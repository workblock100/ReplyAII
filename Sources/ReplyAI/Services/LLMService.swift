import Foundation

// MARK: - Public surface

/// One step of the streaming draft. The composer renders `text` chunks
/// as tokens arrive, exposes `confidence` for the bottom-of-composer
/// indicator, surfaces `loadProgress` while MLX weights download/load,
/// and treats `done` as the cue to enable the Send button. Stream-first
/// so the UI doesn't block waiting for the full draft.
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
    /// Production default for the per-token streaming delay range
    /// (nanoseconds). 22–58 ms is the cadence shipped to demo users
    /// — fast enough to feel like a live model, slow enough that the
    /// composer renders streaming tokens visibly rather than landing
    /// in a single frame. Drift up makes the stub feel laggy
    /// (eroding the demo's "real LLM" illusion); drift down makes
    /// the stream finish before the composer's first redraw, which
    /// flashes the entire draft into place and ruins the streaming
    /// feel. The lower-bound (`tokenDelayLowerBoundNanoseconds`) and
    /// upper-bound (`tokenDelayUpperBoundNanoseconds`) constants are
    /// what the production default range is built from. Pinned by
    /// `LLMServiceTests.testDefaultTokenDelayRangeIsTwentyTwoToFiftyEightMilliseconds`.
    static let tokenDelayLowerBoundNanoseconds: UInt64 = 22_000_000
    static let tokenDelayUpperBoundNanoseconds: UInt64 = 58_000_000
    static let defaultTokenDelay: ClosedRange<UInt64> =
        tokenDelayLowerBoundNanoseconds ... tokenDelayUpperBoundNanoseconds

    /// Production default for the cold-start "thinking" pause before
    /// the first token streams (nanoseconds). 180 ms is calibrated so
    /// the composer's "Generating…" indicator has time to render
    /// before the first token lands — without it, the cursor flickers
    /// and the user can't tell whether the model started. Drift to 0
    /// produces a jarring instant-first-token; drift up makes every
    /// stub draft feel slow. Pinned by
    /// `LLMServiceTests.testDefaultInitialDelayIsOneEightyMilliseconds`.
    static let defaultInitialDelay: UInt64 = 180_000_000

    var tokenDelay: ClosedRange<UInt64> = StubLLMService.defaultTokenDelay
    var initialDelay: UInt64 = StubLLMService.defaultInitialDelay

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
