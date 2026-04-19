import Foundation

// MARK: - Public surface

struct DraftChunk: Sendable {
    enum Kind: Sendable {
        case text(String)
        case confidence(Double)
        /// Long-running model load — the service is downloading or loading
        /// weights into memory and hasn't started generating yet. `fraction`
        /// is [0, 1]; `message` is a short user-visible description like
        /// "Downloading Llama 3.2 3B · 47%".
        case loadProgress(fraction: Double, message: String)
        case done
    }
    let kind: Kind
}

/// Drop-in swap target for MLX later. Stream-first so the UI renders as tokens arrive.
protocol LLMService: Sendable {
    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error>
}

// MARK: - Stub implementation

/// Hard-coded drafts from Fixtures, emitted as a token stream with realistic pacing.
/// Used by the UI exactly the way MLX will be wired.
struct StubLLMService: LLMService {
    var tokenDelay: ClosedRange<UInt64> = 22_000_000 ... 58_000_000   // 22–58ms per token
    var initialDelay: UInt64 = 180_000_000                              // 180ms "thinking"

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let confidence = Fixtures.seedConfidence(threadID: thread.id, tone: tone)
                continuation.yield(DraftChunk(kind: .confidence(confidence)))

                // Cold-start wait.
                try? await Task.sleep(nanoseconds: initialDelay)
                if Task.isCancelled { continuation.finish(); return }

                let seed = Fixtures.seedDraft(threadID: thread.id, tone: tone)
                for token in Self.tokenize(seed) {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: UInt64.random(in: tokenDelay))
                    continuation.yield(DraftChunk(kind: .text(token)))
                }

                continuation.yield(DraftChunk(kind: .done))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Word-boundary tokenizer that preserves inter-word spacing so we can
    /// append chunks directly without rebuilding the string.
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == " " || ch == "\n" {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
