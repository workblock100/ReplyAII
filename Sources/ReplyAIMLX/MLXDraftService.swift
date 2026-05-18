import Foundation
import ReplyAICore       // LLMService protocol, DraftChunk, PromptBuilder, Tone, etc.
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
    /// Default Hugging Face model ID. Drift here re-downloads ~2 GB of
    /// weights on next launch for every shipped user — pinned so a casual
    /// "let's try a different default" lands in code review instead of as
    /// a silent storage hit during the next OTA update.
    static let defaultModelID = "mlx-community/Llama-3.2-3B-Instruct-4bit"

    /// Confidence value yielded as the first `DraftChunk` for every MLX
    /// draft. The composer routes drafts with confidence < `lowConfidenceThreshold`
    /// through the `cmp-lowconf` screen, so dropping this below that threshold
    /// silently flips the UX into "we're not sure" mode for every MLX-generated
    /// draft; drift to 1.0 would hide any future real low-confidence signal.
    /// Pinned by `MLXDraftServiceTests.testDefaultDraftConfidenceIsZeroPointEightFive`.
    static let defaultDraftConfidence: Double = 0.85

    /// User-visible progress copy emitted before the download starts so
    /// the composer banner reads as "we know we're slow, we're working
    /// on it" rather than as a frozen UI. Hoisted from the inline yield
    /// site so the wording lives next to the other loadProgress strings
    /// instead of buried in a continuation closure. Pinned by
    /// `MLXDraftServiceTests`'s `*PreparingMessage*` cluster — drift
    /// here is the only signal a user has during the 0%-progress window.
    static let preparingMessage = "Preparing on-device model…"

    /// User-visible progress copy emitted *after* download completes,
    /// while MLX maps weights into memory. Distinct from the prepare
    /// message so the user sees forward progress (download ✓ → warm)
    /// rather than a stale "preparing" banner during the ~3-5s warmup.
    /// Pinned by `MLXDraftServiceTests`'s `*WarmingMessage*` cluster.
    static let warmingMessage = "Warming weights…"

    /// Format the user-visible "Downloading model · X of Y" copy. The
    /// inline interpolation it replaced lived inside a `progressHandler`
    /// closure that fires on a background queue at high frequency —
    /// hoisting moves the format to a single source of truth so a future
    /// "let's localize this" / "let's add a checksum" edit lands once.
    /// Pinned by `MLXDraftServiceTests`'s `*DownloadingMessage*` cluster.
    static func downloadingMessage(completedBytes: Int64, totalBytes: Int64) -> String {
        "Downloading model · \(formatBytes(completedBytes)) of \(formatBytes(totalBytes))"
    }

    /// Fallback download copy when the server doesn't advertise a
    /// `Content-Length` (Hugging Face does, but the macro-generated
    /// `Progress` can briefly report `totalUnitCount == 0` before the
    /// first chunk lands). The percentage form keeps the banner
    /// changing — silent banners look hung. Pinned by
    /// `MLXDraftServiceTests`'s `*DownloadingMessageFraction*` cluster.
    static func downloadingMessage(fraction: Double) -> String {
        "Downloading model · \(Int(fraction * 100))%"
    }

    /// Apple-style byte formatter for `downloadingMessage`. Threshold
    /// at 1024 MiB matches the human convention "anything over 1 GB
    /// reads in GB"; the `%.1f` precision for GB and `%.0f` for MB is
    /// the same shape the system Storage settings use. Drift here
    /// either makes the banner read "1023 MB" instead of "1.0 GB"
    /// (jumpy) or "0.5 GB" instead of "512 MB" (over-precise for small
    /// downloads). Pinned by `MLXDraftServiceTests`'s `*FormatBytes*`
    /// cluster.
    static func formatBytes(_ bytes: Int64) -> String {
        let mib = Double(bytes) / (1024 * 1024)
        return mib > 1024
            ? String(format: "%.1f GB", mib / 1024)
            : String(format: "%.0f MB", mib)
    }

    /// Package-internal so tests can pin the production default after a
    /// no-arg init (see `MLXDraftServiceTests.testDefaultModelIDIsLlama32_3BInstruct4bit`).
    let modelID: String
    private let lock = NSLock()
    private var cachedContainer: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    init(modelID: String = MLXDraftService.defaultModelID) {
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
                    continuation.yield(DraftChunk(kind: .confidence(MLXDraftService.defaultDraftConfidence)))

                    // If we don't already have a container, announce the
                    // load immediately so the UI shows "preparing…" rather
                    // than staring at an empty composer for 30s.
                    if !hasCachedContainer {
                        continuation.yield(DraftChunk(
                            kind: .loadProgress(fraction: 0, message: MLXDraftService.preparingMessage)
                        ))
                    }

                    let container = try await ensureContainer { progress in
                        let fraction = progress.fractionCompleted
                        let msg: String = progress.totalUnitCount > 0
                            ? MLXDraftService.downloadingMessage(
                                completedBytes: progress.completedUnitCount,
                                totalBytes: progress.totalUnitCount
                              )
                            : MLXDraftService.downloadingMessage(fraction: fraction)
                        continuation.yield(DraftChunk(kind: .loadProgress(fraction: fraction, message: msg)))
                    }
                    if Task.isCancelled { continuation.finish(); return }

                    continuation.yield(DraftChunk(
                        kind: .loadProgress(fraction: 1, message: MLXDraftService.warmingMessage)
                    ))

                    let session = ChatSession(container, instructions: PromptBuilder.systemPrompt(tone: tone))
                    // REP-222 wiring (2026-05-09): pull the user's voice
                    // examples from UserDefaults and pass them as few-shot
                    // exemplars in the prompt. PromptBuilder.build accepts
                    // these via the `voiceExamples:` parameter — without
                    // this read, the field defaults to [] and every draft
                    // is generated against tone alone, ignoring the user's
                    // voice profile entirely.
                    let voiceExamples = UserDefaults.standard.voiceExampleMessages()
                    let prompt = PromptBuilder.build(
                        thread: thread,
                        tone: tone,
                        history: history,
                        voiceExamples: voiceExamples
                    )

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

}
