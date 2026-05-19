import Foundation

// MARK: - Public surface

/// One step of the streaming draft. The composer renders `text` chunks
/// as tokens arrive, exposes `confidence` for the bottom-of-composer
/// indicator, surfaces `loadProgress` while MLX weights download/load,
/// and treats `done` as the cue to enable the Send button. Stream-first
/// so the UI doesn't block waiting for the full draft.
///
/// `public` so `ReplyAIMLX.MLXDraftService` can yield instances across
/// the module boundary (REP-500 SPM split).
public struct DraftChunk: Sendable {
    public enum Kind: Sendable {
        case text(String)
        case confidence(Double)
        /// Long-running model load — the service is downloading or loading
        /// weights into memory and hasn't started generating yet. `fraction`
        /// is [0, 1]; `message` is a short user-visible description like
        /// "Downloading Llama 3.2 3B · 47%".
        case loadProgress(fraction: Double, message: String)
        case done
    }
    public let kind: Kind
    public init(kind: Kind) { self.kind = kind }
}

/// Drop-in swap target for MLX later. Stream-first so the UI renders as tokens arrive.
/// `public` so `ReplyAIMLX.MLXDraftService` can conform to it (REP-500).
public protocol LLMService: Sendable {
    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error>
}

/// Factory boundary between `ReplyAICore` (which knows the protocol) and
/// `ReplyAIMLX` (which provides the heavy concrete impl). `InboxScreen`
/// calls `LLMServiceProvider.make(useMLX:)` instead of constructing
/// `MLXDraftService()` directly — that direct construction would force
/// `ReplyAICore` to import `ReplyAIMLX`, which would force every
/// dependent (including the test target) to pull in MLX's 45–90 min
/// cold C++ compile. With this indirection, `ReplyAICore` and
/// `ReplyAITests` build in seconds; only the `ReplyAI` executable
/// target pays the cold-MLX-build cost, and at @main launch it
/// installs the MLX-aware factory by overriding `.make`.
///
/// Default behavior: returns `StubLLMService()` regardless of `useMLX`.
/// `ReplyAIApp.init` overrides this to a closure that returns
/// `MLXDraftService()` when `useMLX` is true. If the override is never
/// installed (e.g. a test that constructs `InboxScreen` without running
/// the @main entry point), the user gets stub drafts — safe and fast.
public enum LLMServiceProvider {
    /// Closure that constructs the right concrete LLMService for a
    /// `useMLX` preference value. Default returns `StubLLMService()`;
    /// `ReplyAIApp.init` swaps in the MLX-aware closure at launch.
    nonisolated(unsafe) public static var make: @Sendable (Bool) -> LLMService = { _ in
        StubLLMService()
    }
}

// MARK: - Stub implementation

/// Hard-coded drafts from Fixtures, emitted as a token stream with realistic pacing.
/// Used by the UI exactly the way MLX will be wired.
public struct StubLLMService: LLMService {
    public init(
        tokenDelay: ClosedRange<UInt64> = StubLLMService.defaultTokenDelay,
        initialDelay: UInt64 = StubLLMService.defaultInitialDelay
    ) {
        self.tokenDelay = tokenDelay
        self.initialDelay = initialDelay
    }

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
    /// `LLMServiceTests.testDefaultTokenDelayConstantIs22To58Ms`.
    static let tokenDelayLowerBoundNanoseconds: UInt64 = 22_000_000
    static let tokenDelayUpperBoundNanoseconds: UInt64 = 58_000_000
    public static let defaultTokenDelay: ClosedRange<UInt64> =
        tokenDelayLowerBoundNanoseconds ... tokenDelayUpperBoundNanoseconds

    /// Production default for the cold-start "thinking" pause before
    /// the first token streams (nanoseconds). 180 ms is calibrated so
    /// the composer's "Generating…" indicator has time to render
    /// before the first token lands — without it, the cursor flickers
    /// and the user can't tell whether the model started. Drift to 0
    /// produces a jarring instant-first-token; drift up makes every
    /// stub draft feel slow. Pinned by
    /// `LLMServiceTests.testDefaultInitialDelayConstantIs180Ms`.
    public static let defaultInitialDelay: UInt64 = 180_000_000

    var tokenDelay: ClosedRange<UInt64> = StubLLMService.defaultTokenDelay
    var initialDelay: UInt64 = StubLLMService.defaultInitialDelay

    public func draft(
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
