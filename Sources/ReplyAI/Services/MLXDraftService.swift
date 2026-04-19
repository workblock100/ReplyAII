import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace    // provides #huggingFaceLoadModelContainer macro
import HuggingFace       // provides HubClient (macro expansion target)
import Tokenizers        // provides AutoTokenizer (macro expansion target)

/// MLX-backed draft generator. First call triggers a model download
/// into `~/Library/Caches/huggingface/hub/`; subsequent calls reuse
/// the cached container.
///
/// Model: `mlx-community/Llama-3.2-3B-Instruct-4bit` by default — small
/// enough to load on any Apple Silicon, fast enough to feel streaming,
/// 4-bit quantized for ~2 GB weights.
final class MLXDraftService: @unchecked Sendable, LLMService {
    private let modelID: String
    private let lock = NSLock()
    private var cachedContainer: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    init(modelID: String = "mlx-community/Llama-3.2-3B-Instruct-4bit") {
        self.modelID = modelID
    }

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    continuation.yield(DraftChunk(kind: .confidence(0.85)))

                    // If we don't already have a container, announce the
                    // load immediately so the UI shows "preparing…" rather
                    // than staring at an empty composer for 30s.
                    if !hasCachedContainer {
                        continuation.yield(DraftChunk(
                            kind: .loadProgress(fraction: 0, message: "Preparing on-device model…")
                        ))
                    }

                    let container = try await ensureContainer { progress in
                        let fraction = progress.fractionCompleted
                        let mb: (Int64) -> String = { bytes in
                            let mib = Double(bytes) / (1024 * 1024)
                            return mib > 1024
                                ? String(format: "%.1f GB", mib / 1024)
                                : String(format: "%.0f MB", mib)
                        }
                        let msg: String
                        if progress.totalUnitCount > 0 {
                            msg = "Downloading model · \(mb(progress.completedUnitCount)) of \(mb(progress.totalUnitCount))"
                        } else {
                            msg = "Downloading model · \(Int(fraction * 100))%"
                        }
                        continuation.yield(DraftChunk(kind: .loadProgress(fraction: fraction, message: msg)))
                    }
                    if Task.isCancelled { continuation.finish(); return }

                    continuation.yield(DraftChunk(
                        kind: .loadProgress(fraction: 1, message: "Warming weights…")
                    ))

                    let session = ChatSession(container, instructions: Self.systemPrompt(tone: tone))
                    let prompt  = Self.buildPrompt(thread: thread, tone: tone, history: history)

                    for try await chunk in session.streamResponse(to: prompt, role: .user, images: [], videos: []) {
                        if Task.isCancelled { break }
                        continuation.yield(DraftChunk(kind: .text(chunk)))
                    }

                    continuation.yield(DraftChunk(kind: .done))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var hasCachedContainer: Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedContainer != nil
    }

    // MARK: - Container caching

    private func ensureContainer(
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> ModelContainer {
        lock.lock()
        if let cached = cachedContainer { lock.unlock(); return cached }
        if let existing = loadTask {
            // A concurrent draft is already loading — just wait. We lose
            // progress events for the second caller; acceptable since the
            // UI only shows one banner at a time.
            lock.unlock()
            return try await existing.value
        }

        let modelID = self.modelID
        let task = Task<ModelContainer, Error> {
            let config = ModelConfiguration(id: modelID)
            return try await #huggingFaceLoadModelContainer(
                configuration: config,
                progressHandler: progressHandler
            )
        }
        loadTask = task
        lock.unlock()

        do {
            let container = try await task.value
            lock.lock()
            cachedContainer = container
            loadTask = nil
            lock.unlock()
            return container
        } catch {
            lock.lock()
            loadTask = nil
            lock.unlock()
            throw error
        }
    }

    // MARK: - Prompt construction

    private static func systemPrompt(tone: Tone) -> String {
        let base = """
        You are ReplyAI, a drafting assistant embedded in the user's messaging inbox. \
        You write the user's next reply in their own voice. Output ONLY the reply text \
        itself — no preamble, no apology, no meta-commentary. Keep replies concise and \
        conversational; these are text messages, not essays.
        """
        switch tone {
        case .warm:
            return base + " Use a warm, friendly tone. Light emoji are fine. Avoid sounding corporate."
        case .direct:
            return base + " Be direct. Short. Lowercase. Get to the point. No filler."
        case .playful:
            return base + " Be playful and witty with dry humor; occasional emoji are welcome."
        }
    }

    private static func buildPrompt(thread: MessageThread, tone: Tone, history: [Message]) -> String {
        var lines: [String] = []
        lines.append("Conversation with \(thread.name) via \(thread.channel.label).")
        lines.append("")
        lines.append("Recent messages (oldest first):")
        for m in history.suffix(20) {
            let speaker = m.from == .me ? "me" : thread.name
            lines.append("\(speaker): \(m.text)")
        }
        lines.append("")
        lines.append("Write my next reply in a \(tone.rawValue.lowercased()) tone. Reply text only.")
        return lines.joined(separator: "\n")
    }
}
