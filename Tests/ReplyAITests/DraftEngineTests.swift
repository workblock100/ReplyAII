import XCTest
@testable import ReplyAI

@MainActor
final class DraftEngineTests: XCTestCase {
    func testPrimeProducesDraftFromStub() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]
        engine.prime(thread: thread, tone: .warm, history: [])

        // Wait up to 2s for the stream to drain.
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertEqual(state.text, Fixtures.seedDraft(threadID: thread.id, tone: .warm))
        XCTAssertTrue(state.isDone)
        XCTAssertFalse(state.isStreaming)
    }

    func testRegenerateReplaysStream() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .direct, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .direct).isDone
        }

        engine.regenerate(thread: thread, tone: .direct, history: [])
        // After regenerate kicks off, state resets — isDone flips to false.
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .direct).isDone)

        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .direct).isDone
        }
        XCTAssertEqual(
            engine.state(threadID: thread.id, tone: .direct).text,
            Fixtures.seedDraft(threadID: thread.id, tone: .direct)
        )
    }

    func testDismissClearsEntry() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]
        engine.prime(thread: thread, tone: .playful, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .playful).isDone
        }
        engine.dismiss(threadID: thread.id, tone: .playful)
        XCTAssertEqual(engine.state(threadID: thread.id, tone: .playful).text, "")
    }

    func testToneCyclingWalksEveryCase() {
        var t = Tone.warm
        var seen: [Tone] = [t]
        for _ in 0..<Tone.allCases.count {
            t = t.cycled()
            seen.append(t)
        }
        // After N cycles we should land back on the starting tone.
        XCTAssertEqual(seen.last, .warm)
        XCTAssertEqual(Set(seen).count, Tone.allCases.count)
    }

    // MARK: - Concurrent prime guard (REP-049)

    func testDoublePrimeCancelsFirst() async throws {
        // Both prime() calls happen synchronously — the second cancels the
        // first task via primingTasks before it emits any text.
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        engine.prime(thread: thread, tone: .warm, history: [])

        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertTrue(state.isDone)
        XCTAssertFalse(state.isStreaming)
        // No error from the cancelled first task's CancellationError propagating.
        XCTAssertNil(state.error)
        // Text equals exactly one draft — no doubling from two concurrent streams.
        XCTAssertEqual(state.text, Fixtures.seedDraft(threadID: thread.id, tone: .warm))
    }

    func testDoublePrimeResultReflectsSecond() async throws {
        // After rapid double-prime, the engine settles on a single coherent
        // draft — no partial text from the cancelled first task bleeds in.
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .playful, history: [])
        engine.prime(thread: thread, tone: .playful, history: [])

        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .playful).isDone
        }

        let state = engine.state(threadID: thread.id, tone: .playful)
        XCTAssertFalse(state.isStreaming)
        XCTAssertNil(state.error)
        XCTAssertEqual(state.text, Fixtures.seedDraft(threadID: thread.id, tone: .playful))
    }

    // MARK: - Draft invalidation (REP-054)

    func testInvalidateResetsToIdle() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .warm).text.isEmpty,
                       "draft must have content before invalidation")

        engine.invalidate(threadID: thread.id)

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertEqual(state.text, "", "invalidated draft must have empty text")
        XCTAssertFalse(state.isStreaming, "invalidated draft must not be streaming")
        XCTAssertFalse(state.isDone, "invalidated draft must not be marked done")
        XCTAssertNil(state.error, "invalidated draft must not have an error")
        // Cache entry is kept (not evicted), so cacheSize is unchanged.
        XCTAssertGreaterThan(engine.cacheSize, 0,
                             "invalidate must preserve the cache slot for follow-up re-prime")
    }

    func testInvalidateSkipsNonSelectedThread() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let threadA = Fixtures.threads[0]
        let threadB = Fixtures.threads[1]

        engine.prime(thread: threadA, tone: .warm, history: [])
        engine.prime(thread: threadB, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: threadA.id, tone: .warm).isDone &&
            engine.state(threadID: threadB.id, tone: .warm).isDone
        }

        // Only invalidate threadA (the "selected" thread).
        engine.invalidate(threadID: threadA.id)

        let stateA = engine.state(threadID: threadA.id, tone: .warm)
        XCTAssertEqual(stateA.text, "", "threadA's draft must be cleared by invalidation")
        XCTAssertFalse(stateA.isDone, "threadA must be reset to idle")

        let stateB = engine.state(threadID: threadB.id, tone: .warm)
        XCTAssertFalse(stateB.text.isEmpty, "threadB's draft must survive threadA's invalidation")
        XCTAssertTrue(stateB.isDone, "threadB must remain done")
    }

    // MARK: - REP-153: invalidate() on uncached thread is idempotent

    func testInvalidateOnUncachedThreadIsNoOp() {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        XCTAssertEqual(engine.cacheSize, 0, "engine must start with empty cache")

        // Call invalidate on a thread that was never primed — must not crash
        engine.invalidate(threadID: "never-primed-thread")

        XCTAssertEqual(engine.cacheSize, 0, "cache size must remain 0 after invalidating uncached thread")
        // Verify state for the uncached thread is still idle (default)
        let state = engine.state(threadID: "never-primed-thread", tone: .warm)
        XCTAssertEqual(state.text, "", "uncached thread state must be idle with empty text")
        XCTAssertFalse(state.isStreaming, "uncached thread must not show as streaming")
        XCTAssertFalse(state.isDone, "uncached thread must not show as done")
    }

    func testInvalidateOnUncachedThreadDoesNotAffectCachedThread() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        let textBefore = engine.state(threadID: thread.id, tone: .warm).text
        XCTAssertFalse(textBefore.isEmpty, "primed thread must have content")

        // Invalidating a different (uncached) thread must leave the primed thread intact
        engine.invalidate(threadID: "other-thread-id")

        let stateAfter = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertEqual(stateAfter.text, textBefore, "cached thread draft must be unaffected by invalidating an uncached thread")
    }

    // MARK: - REP-250: invalidate() during in-flight prime cancels the task

    // Calling invalidate while the prime task is still in its initialDelay
    // ("thinking") must immediately reset state to idle — not priming.
    func testInvalidateMidPrimeTransitionsToIdle() async throws {
        // Use a 5-second initial delay so the prime task is definitely still
        // running when we call invalidate() right after prime().
        let longDelay: UInt64 = 5_000_000_000  // 5s
        let engine = DraftEngine(
            service: StubLLMService(tokenDelay: 0...0, initialDelay: longDelay)
        )
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        // Invalidate immediately — task is in initial-delay sleep.
        engine.invalidate(threadID: thread.id)

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertEqual(state.text, "", "invalidated mid-prime must have empty text")
        XCTAssertFalse(state.isStreaming, "invalidated mid-prime must not show as streaming")
        XCTAssertFalse(state.isDone, "invalidated mid-prime must not show as done")
        XCTAssertNil(state.error, "invalidated mid-prime must not surface an error")
    }

    // After invalidate() cancels a mid-prime task, isDone must never flip to
    // true — the cancelled task must not complete and overwrite the reset state.
    func testInvalidateMidPrimeCancelsPrimingTask() async throws {
        let longDelay: UInt64 = 5_000_000_000  // 5s
        let engine = DraftEngine(
            service: StubLLMService(tokenDelay: 0...0, initialDelay: longDelay)
        )
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        engine.invalidate(threadID: thread.id)

        // Wait 200ms — well under the 5s initialDelay. If the task were not
        // cancelled, it would NOT have finished yet. Either way isDone must be
        // false because the state was reset to idle and the task was cancelled.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(engine.state(threadID: thread.id, tone: .warm).isDone,
                       "cancelled prime task must not flip isDone to true after invalidation")
    }

    // MARK: - Cache eviction (REP-034)

    func testEvictClearsSingleThread() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertGreaterThan(engine.cacheSize, 0)

        engine.evict(threadID: thread.id)
        XCTAssertEqual(engine.cacheSize, 0, "all tone entries for the thread must be removed")
        XCTAssertEqual(engine.state(threadID: thread.id, tone: .warm).text, "",
                       "evicted state returns the default empty state")
    }

    func testEvictLeavesOtherThreadsIntact() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let threadA = Fixtures.threads[0]
        let threadB = Fixtures.threads[1]

        engine.prime(thread: threadA, tone: .warm, history: [])
        engine.prime(thread: threadB, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: threadA.id, tone: .warm).isDone &&
            engine.state(threadID: threadB.id, tone: .warm).isDone
        }
        XCTAssertEqual(engine.cacheSize, 2)

        engine.evict(threadID: threadA.id)
        XCTAssertEqual(engine.cacheSize, 1, "only threadA's entry must be removed")
        XCTAssertFalse(engine.state(threadID: threadB.id, tone: .warm).text.isEmpty,
                       "threadB's draft must survive eviction of threadA")
    }

    // MARK: - load-progress state transitions (REP-038)

    func testLoadProgressTransitionsState() async throws {
        let engine = DraftEngine(service: LoadProgressThenTextService(progressSteps: 3))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])

        // modelLoadStatus should be set while progress chunks arrive.
        try await waitUntil(timeout: 2.0) {
            engine.modelLoadStatus != nil
        }
        XCTAssertNotNil(engine.modelLoadStatus)
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .warm).isDone)

        // After text chunk + done, modelLoadStatus must clear.
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertNil(engine.modelLoadStatus, "modelLoadStatus must be nil after streaming completes")
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .warm).text.isEmpty)
    }

    /// The composer renders `modelLoadStatus.message` directly under the
    /// progress bar (e.g. "Downloading Llama 3.2 3B · 47%"), so each
    /// loadProgress chunk must replace the prior status — not append, not
    /// linger. Pin that the latest fraction + message reach observers
    /// verbatim, and that the status is held while the stream pauses
    /// after the final progress chunk.
    func testLoadProgressLatestChunkReplacesPriorStatus() async throws {
        let engine = DraftEngine(service: PausingProgressService(
            stages: [
                (0.10, "Downloading · 10%"),
                (0.55, "Downloading · 55%"),
                (0.95, "Warming · 95%"),
            ]
        ))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])

        try await waitUntil(timeout: 2.0) {
            engine.modelLoadStatus?.message == "Warming · 95%"
        }
        XCTAssertEqual(engine.modelLoadStatus,
                       DraftEngine.ModelLoadStatus(fraction: 0.95, message: "Warming · 95%"),
                       "modelLoadStatus must reflect the LATEST loadProgress chunk verbatim, not an aggregate or stale earlier value")
    }

    /// `DraftEngine.apply(.text)` clears `modelLoadStatus` immediately —
    /// not on `.done`. The composer relies on this so the progress bar
    /// disappears the moment the first token streams in, and the user
    /// sees the draft instead of "Warming · 100%" lingering during
    /// generation. A regression that delayed the clear to `.done` would
    /// keep the spinner up for the whole stream.
    func testLoadProgressClearedOnFirstTextChunkBeforeDone() async throws {
        let engine = DraftEngine(service: ProgressThenHoldingTextService())
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])

        // Wait until at least one text chunk has been applied (text non-empty)
        // BUT before .done arrives (isDone still false).
        try await waitUntil(timeout: 2.0) {
            !engine.state(threadID: thread.id, tone: .warm).text.isEmpty
        }
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .warm).isDone,
                       "test setup precondition: stream must still be live after first text chunk")
        XCTAssertNil(engine.modelLoadStatus,
                     "modelLoadStatus must clear on the first .text chunk — not delayed until .done")
    }

    /// `ModelLoadStatus` is `Equatable` so SwiftUI views can `.onChange`
    /// or `.equatable()` against it without falling back to reference
    /// identity. Pin the value-equality contract here — a future struct
    /// change that drops Equatable (or adds a non-Equatable field) would
    /// silently regress the composer's progress-bar update path.
    func testModelLoadStatusEqualityIsValueBased() {
        let a = DraftEngine.ModelLoadStatus(fraction: 0.5, message: "Loading")
        let b = DraftEngine.ModelLoadStatus(fraction: 0.5, message: "Loading")
        let cFraction = DraftEngine.ModelLoadStatus(fraction: 0.5001, message: "Loading")
        let cMessage = DraftEngine.ModelLoadStatus(fraction: 0.5, message: "Loading…")
        XCTAssertEqual(a, b, "identical fraction+message must compare equal")
        XCTAssertNotEqual(a, cFraction, "fraction differences must surface as inequality")
        XCTAssertNotEqual(a, cMessage, "message differences must surface as inequality")
    }

    func testCancellationTransitionsToIdle() async throws {
        let engine = DraftEngine(service: CancellableLongService())
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .direct, history: [])

        // Wait for streaming to begin.
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .direct).isStreaming
        }

        engine.dismiss(threadID: thread.id, tone: .direct)

        // State must return to idle (no text, not streaming, no error).
        let state = engine.state(threadID: thread.id, tone: .direct)
        XCTAssertEqual(state.text, "", "dismissed draft must have no text")
        XCTAssertFalse(state.isStreaming, "dismissed draft must not be streaming")
        XCTAssertFalse(state.isDone, "dismissed draft must not be marked done")
        XCTAssertNil(state.error, "dismiss must not produce an error")
    }

    // MARK: - dismiss() state-transition tests (REP-107)

    func testDismissAfterReadyTransitionsToIdle() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }

        engine.dismiss(threadID: thread.id, tone: .warm)

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertEqual(state.text, "", "dismiss after ready must clear text")
        XCTAssertFalse(state.isDone, "dismiss after ready must clear isDone")
        XCTAssertFalse(state.isStreaming, "dismiss after ready must clear isStreaming")
        XCTAssertNil(state.error)
    }

    func testDismissOfUnknownEntryIsNoop() {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        // Dismiss an entry that was never primed — must not crash and state stays idle.
        engine.dismiss(threadID: "never-primed-thread", tone: .direct)
        let state = engine.state(threadID: "never-primed-thread", tone: .direct)
        XCTAssertEqual(state.text, "", "dismiss of unknown entry must be a noop")
        XCTAssertFalse(state.isDone)
        XCTAssertFalse(state.isStreaming)
    }

    func testDismissDoesNotInvalidateOtherEntries() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let t1 = Fixtures.threads[0]
        let t2 = Fixtures.threads[1]

        engine.prime(thread: t1, tone: .warm, history: [])
        engine.prime(thread: t2, tone: .direct, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: t1.id, tone: .warm).isDone &&
            engine.state(threadID: t2.id, tone: .direct).isDone
        }

        // Dismiss only t1/warm.
        engine.dismiss(threadID: t1.id, tone: .warm)

        XCTAssertEqual(engine.state(threadID: t1.id, tone: .warm).text, "",
                       "dismissed entry must be cleared")
        XCTAssertTrue(engine.state(threadID: t2.id, tone: .direct).isDone,
                      "other entry must remain intact after dismiss")
        XCTAssertFalse(engine.state(threadID: t2.id, tone: .direct).text.isEmpty,
                       "other entry must retain its draft text")
    }

    // MARK: - Cache isolation (REP-098)

    func testCacheIsolationAcrossThreadIDs() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let tA = Fixtures.threads[0]
        let tB = Fixtures.threads[1]

        engine.prime(thread: tA, tone: .warm, history: [])
        engine.prime(thread: tB, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: tA.id, tone: .warm).isDone &&
            engine.state(threadID: tB.id, tone: .warm).isDone
        }

        let draftA = engine.state(threadID: tA.id, tone: .warm).text
        let draftB = engine.state(threadID: tB.id, tone: .warm).text
        XCTAssertFalse(draftA.isEmpty, "thread A must have a draft")
        XCTAssertFalse(draftB.isEmpty, "thread B must have a draft")
        XCTAssertNotEqual(draftA, draftB, "thread A and B must have independent cache entries")
        XCTAssertEqual(draftA, Fixtures.seedDraft(threadID: tA.id, tone: .warm))
        XCTAssertEqual(draftB, Fixtures.seedDraft(threadID: tB.id, tone: .warm))
    }

    func testCacheIsolationAcrossTones() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        engine.prime(thread: thread, tone: .direct, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone &&
            engine.state(threadID: thread.id, tone: .direct).isDone
        }

        let warmText = engine.state(threadID: thread.id, tone: .warm).text
        let directText = engine.state(threadID: thread.id, tone: .direct).text
        XCTAssertFalse(warmText.isEmpty, "warm tone must have a draft")
        XCTAssertFalse(directText.isEmpty, "direct tone must have a draft")
        XCTAssertNotEqual(warmText, directText, "different tones must have independent cache entries")
        XCTAssertEqual(warmText, Fixtures.seedDraft(threadID: thread.id, tone: .warm))
        XCTAssertEqual(directText, Fixtures.seedDraft(threadID: thread.id, tone: .direct))
    }

    // MARK: - LLM error path (REP-114)

    func testLLMErrorTransitionsToDraftStateError() async throws {
        let engine = DraftEngine(service: ThrowingStubLLMService())
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).error != nil
        }

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertNotNil(state.error, "LLM throw must transition state to error")
        XCTAssertFalse(state.isStreaming, "error state must not be streaming")
        XCTAssertFalse(state.isDone, "error state must not be done")
        XCTAssertEqual(state.text, "", "error state must have no text")
    }

    func testRegenerateAfterErrorRetries() async throws {
        let engine = DraftEngine(service: FailOnceThenSucceedService())
        let thread = Fixtures.threads[0]

        // First prime — service throws.
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).error != nil
        }
        XCTAssertNotNil(engine.state(threadID: thread.id, tone: .warm).error)

        // Regenerate — service succeeds on second call.
        engine.regenerate(thread: thread, tone: .warm, history: [])
        // State resets to streaming immediately; error must be cleared.
        try await waitUntil(timeout: 2.0) {
            let s = engine.state(threadID: thread.id, tone: .warm)
            return s.isDone || s.error != nil
        }
        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertTrue(state.isDone, "regenerate must eventually produce a ready draft")
        XCTAssertNil(state.error, "recovered draft must have no error")
        XCTAssertFalse(state.text.isEmpty, "recovered draft must have text")
    }

    // MARK: - Whitespace trimming on done (REP-127)

    func testDraftLeadingNewlinesTrimmed() async throws {
        let engine = DraftEngine(service: FixedTextService(text: "\n\nHello there"))
        let thread = Fixtures.threads[0]
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertEqual(engine.state(threadID: thread.id, tone: .warm).text, "Hello there",
                       "leading newlines must be stripped on done transition")
    }

    func testDraftTrailingWhitespaceTrimmed() async throws {
        let engine = DraftEngine(service: FixedTextService(text: "Hello   \n"))
        let thread = Fixtures.threads[0]
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertEqual(engine.state(threadID: thread.id, tone: .warm).text, "Hello",
                       "trailing whitespace must be stripped on done transition")
    }

    func testWhitespaceOnlyDraftReturnsEmptyString() async throws {
        let engine = DraftEngine(service: FixedTextService(text: "   \n\n  "))
        let thread = Fixtures.threads[0]
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertEqual(state.text, "", "all-whitespace draft must trim to empty string")
        XCTAssertTrue(state.isDone, "engine must still reach done state for whitespace-only draft")
    }

    // MARK: - Rapid regenerate serialization (REP-132)

    func testRapidRegenerateProducesOneDraftState() async throws {
        // SlowFixedTextService emits tokens slowly so both calls overlap.
        let engine = DraftEngine(service: SlowFixedTextService(text: "settled draft"))
        let thread = Fixtures.threads[0]

        // Prime once so there's a key in the cache, then regenerate twice quickly.
        engine.prime(thread: thread, tone: .warm, history: [])
        engine.regenerate(thread: thread, tone: .warm, history: [])
        engine.regenerate(thread: thread, tone: .warm, history: [])

        try await waitUntil(timeout: 3.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertTrue(state.isDone, "engine must reach done state after rapid regenerates")
        XCTAssertNil(state.error, "rapid regenerate must not leave an error state")
        // Text must equal exactly one draft — no double-concatenation from two live streams.
        XCTAssertEqual(state.text, "settled draft",
                       "final text must be from exactly one completed stream")
    }

    func testRapidRegenerateDoesNotDoubleDraftCount() async throws {
        // After rapid double-regenerate only one entry exists per (threadID, tone) key.
        let engine = DraftEngine(service: SlowFixedTextService(text: "one"))
        let thread = Fixtures.threads[0]

        engine.regenerate(thread: thread, tone: .warm, history: [])
        engine.regenerate(thread: thread, tone: .warm, history: [])

        try await waitUntil(timeout: 3.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }

        // cacheSize == 1 confirms only one entry was created for this (threadID, tone).
        XCTAssertEqual(engine.cacheSize, 1,
                       "rapid regenerate must not create duplicate cache entries")
        XCTAssertEqual(engine.state(threadID: thread.id, tone: .warm).text, "one",
                       "final text must come from one stream, not two concatenated")
    }

    // MARK: - REP-138: dismiss() deletes corresponding DraftStore entry

    func testDismissClearsStoredDraft() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = DraftStore(draftsDirectory: tmpDir)
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0),
                                 store: store)
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertNotNil(store.read(threadID: thread.id), "draft must be stored after prime+ready")

        engine.dismiss(threadID: thread.id, tone: .warm)

        XCTAssertNil(store.read(threadID: thread.id),
                     "dismiss must delete the stored draft entry")
    }

    func testDismissWithNoStoredDraftIsNoop() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = DraftStore(draftsDirectory: tmpDir)
        let engine = DraftEngine(service: StubLLMService(), store: store)
        let thread = Fixtures.threads[0]

        // No prime — no stored draft. dismiss must not crash.
        engine.dismiss(threadID: thread.id, tone: .warm)
        XCTAssertNil(store.read(threadID: thread.id), "no crash and no draft for a thread never primed")
    }

    func testReprimingAfterDismissWritesNewEntry() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = DraftStore(draftsDirectory: tmpDir)
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0),
                                 store: store)
        let thread = Fixtures.threads[0]

        // Prime → dismiss → prime again.
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        engine.dismiss(threadID: thread.id, tone: .warm)
        XCTAssertNil(store.read(threadID: thread.id), "store must be empty after dismiss")

        engine.regenerate(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertNotNil(store.read(threadID: thread.id),
                        "re-prime after dismiss must write a new store entry")
    }

    // MARK: - REP-182: empty LLM stream

    func testEmptyLLMStreamTransitionsToIdle() async throws {
        let engine = DraftEngine(service: EmptyStreamService())
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])

        // Wait for the stream task to finish (isStreaming returns to false).
        try await waitUntil(timeout: 2.0) {
            !engine.state(threadID: thread.id, tone: .warm).isStreaming
        }

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertFalse(state.isStreaming, "empty stream must clear isStreaming flag")
        XCTAssertFalse(state.isDone, "empty stream must not set isDone (no content)")
        XCTAssertEqual(state.text, "", "empty stream must leave text empty")
        XCTAssertNil(state.error, "empty stream must not record an error")
    }

    func testEmptyLLMStreamDoesNotCrash() async throws {
        let engine = DraftEngine(service: EmptyStreamService())
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .direct, history: [])

        try await waitUntil(timeout: 2.0) {
            !engine.state(threadID: thread.id, tone: .direct).isStreaming
        }
        // Reaching here without a crash or assertion failure = pass.
    }

    // MARK: - REP-169: N concurrent primes on distinct threads

    func testConcurrentPrimesOnDistinctThreadsAllReachReady() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let threads = (0..<10).map { i in
            MessageThread(id: "concurrent-thread-\(i)", channel: .imessage, name: "T\(i)",
                          avatar: "T", preview: "", time: "", unread: 0)
        }

        // Prime 10 distinct threads concurrently — each gets its own task slot.
        await withTaskGroup(of: Void.self) { group in
            for thread in threads {
                let t = thread
                group.addTask { @MainActor in
                    engine.prime(thread: t, tone: .warm, history: [])
                }
            }
        }

        for thread in threads {
            try await waitUntil(timeout: 5.0) {
                engine.state(threadID: thread.id, tone: .warm).isDone
            }
        }

        for thread in threads {
            let state = engine.state(threadID: thread.id, tone: .warm)
            XCTAssertTrue(state.isDone,
                          "thread \(thread.id) must reach ready after concurrent prime")
            XCTAssertFalse(state.isStreaming,
                           "thread \(thread.id) must not remain in streaming state")
        }
    }

    func testNoPrimingStateLeaksAfterConcurrentPrimes() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let threads = (0..<10).map { i in
            MessageThread(id: "leak-thread-\(i)", channel: .imessage, name: "L\(i)",
                          avatar: "L", preview: "", time: "", unread: 0)
        }

        await withTaskGroup(of: Void.self) { group in
            for thread in threads {
                let t = thread
                group.addTask { @MainActor in
                    engine.prime(thread: t, tone: .warm, history: [])
                }
            }
        }

        for thread in threads {
            try await waitUntil(timeout: 5.0) {
                !engine.state(threadID: thread.id, tone: .warm).isStreaming
            }
        }

        let leaking = threads.filter {
            engine.state(threadID: $0.id, tone: .warm).isStreaming
        }
        XCTAssertEqual(leaking.count, 0,
                       "no thread must remain stuck in streaming/priming after concurrent primes complete")
    }

    // MARK: - REP-189: error state must not block re-priming

    func testPrimeErrorLeavesEngineInIdleNotErrorState() async throws {
        // FailOnceThenSucceedService throws on first call, succeeds on second.
        let engine = DraftEngine(service: FailOnceThenSucceedService())
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).error != nil
        }

        // Engine must not be stuck — a second prime() call must clear the error
        // and eventually reach ready.
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }

        let state = engine.state(threadID: thread.id, tone: .warm)
        XCTAssertNil(state.error,
                     "error must be cleared after second prime succeeds — not stuck in error state")
        XCTAssertTrue(state.isDone, "engine must reach ready after recovering from error via prime()")
    }

    func testPrimeSucceedsAfterPreviousError() async throws {
        let engine = DraftEngine(service: FailOnceThenSucceedService())
        let thread = Fixtures.threads[1]

        engine.prime(thread: thread, tone: .direct, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .direct).error != nil
        }
        XCTAssertNotNil(engine.state(threadID: thread.id, tone: .direct).error,
                        "pre-condition: first prime must have errored")

        engine.prime(thread: thread, tone: .direct, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .direct).isDone
        }
        XCTAssertTrue(engine.state(threadID: thread.id, tone: .direct).isDone,
                      "prime() must succeed after prior error on the same (thread, tone) key")
        XCTAssertNil(engine.state(threadID: thread.id, tone: .direct).error)
    }

    // MARK: - helper

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition did not become true within \(timeout)s", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - REP-195: dismiss on unprimed thread is a no-op

    func testDismissOnUnprimedThreadIsNoOp() {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        // Dismiss a thread that was never primed — must not crash.
        engine.dismiss(threadID: "never-primed", tone: .warm)
        // State must still be default (idle) and cache must be empty.
        let state = engine.state(threadID: "never-primed", tone: .warm)
        XCTAssertEqual(state.text, "",
                       "unprimed thread must have empty text after dismiss")
        XCTAssertFalse(state.isStreaming,
                       "unprimed thread must not be streaming after dismiss")
        XCTAssertEqual(engine.cacheSize, 0,
                       "cache must remain empty after dismiss on unprimed thread")
    }

    // MARK: - REP-203: regenerate on different tone evicts original tone's cache

    func testRegenerateOnDifferentToneEvictsOriginalTone() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        // Prime with .warm tone and wait for completion.
        engine.prime(thread: thread, tone: .warm, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .warm).isDone
        }
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .warm).text.isEmpty,
                       "precondition: .warm draft must be populated")

        // Regenerate using a different tone (.direct). This must evict .warm.
        engine.regenerate(thread: thread, tone: .direct, history: [])

        // Wait for .direct to be ready.
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .direct).isDone
        }

        // .warm must have been evicted — its entry was cleared when generate() ran.
        // After evict, state returns the default (empty text, not streaming).
        let warmState = engine.state(threadID: thread.id, tone: .warm)
        // The original .warm key was removed from the cache during regenerate →
        // state() for that missing key returns a zero-value DraftState.
        XCTAssertFalse(warmState.isStreaming,
                       ".warm cache entry must not be streaming after tone switch")

        let directState = engine.state(threadID: thread.id, tone: .direct)
        XCTAssertTrue(directState.isDone, ".direct draft must be done")
        XCTAssertFalse(directState.text.isEmpty, ".direct draft must have content")
    }

    // MARK: - REP-216: regenerate for same tone must not no-op

    // After priming completes, regenerate with the identical tone must enter
    // a non-done (priming) state immediately — guards against a shortcut that
    // skips work when the tone hasn't changed.
    func testRegenerateSameToneTransitionsThroughPriming() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .playful, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .playful).isDone
        }

        engine.regenerate(thread: thread, tone: .playful, history: [])

        // Immediately after regenerate the entry must be non-done (streaming started).
        XCTAssertFalse(engine.state(threadID: thread.id, tone: .playful).isDone,
                       "engine must enter priming (not done) immediately after regenerate")
    }

    // After priming with the same tone, regenerate must reach .ready again.
    func testRegenerateSameToneReachesReady() async throws {
        let engine = DraftEngine(service: StubLLMService(tokenDelay: 0...0, initialDelay: 0))
        let thread = Fixtures.threads[0]

        engine.prime(thread: thread, tone: .playful, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .playful).isDone
        }

        engine.regenerate(thread: thread, tone: .playful, history: [])
        try await waitUntil(timeout: 2.0) {
            engine.state(threadID: thread.id, tone: .playful).isDone
        }

        let state = engine.state(threadID: thread.id, tone: .playful)
        XCTAssertTrue(state.isDone, "engine must reach ready after same-tone regenerate")
        XCTAssertFalse(state.text.isEmpty, "regenerated draft must have content")
    }

    // MARK: - DraftState.isLowConfidence threshold pin
    //
    // ComposerView shows the low-confidence affordance when
    // `state.isLowConfidence`. The threshold (0.4) is the boundary
    // between "show the warning" and "stay quiet"; drifting it would
    // silently change when the warning appears for users.

    func testIsLowConfidenceTrueJustBelowThreshold() {
        var s = DraftEngine.DraftState()
        s.confidence = 0.39
        XCTAssertTrue(s.isLowConfidence,
            "0.39 must be flagged low — threshold is 0.4 (strict less-than)")
    }

    func testIsLowConfidenceFalseAtThreshold() {
        var s = DraftEngine.DraftState()
        s.confidence = 0.4
        XCTAssertFalse(s.isLowConfidence,
            "0.4 must NOT be flagged low — threshold is strict less-than 0.4")
    }

    func testIsLowConfidenceFalseAboveThreshold() {
        var s = DraftEngine.DraftState()
        s.confidence = 0.85
        XCTAssertFalse(s.isLowConfidence)
    }

    func testIsLowConfidenceTrueAtZero() {
        var s = DraftEngine.DraftState()
        s.confidence = 0.0
        XCTAssertTrue(s.isLowConfidence,
            "zero confidence must be flagged low")
    }

    func testDefaultDraftStateIsHighConfidence() {
        let s = DraftEngine.DraftState()
        // The default confidence (1.0) must NOT trigger the warning so
        // a freshly-instantiated state doesn't render the affordance
        // before any chunk has arrived.
        XCTAssertFalse(s.isLowConfidence,
            "default confidence (1.0) must not be low — would render warning before any chunk arrives")
    }

    /// Pin every field-level default on `DraftState()` together. Each
    /// default carries a distinct UX promise that's only obvious from
    /// the call site:
    ///   * `text == ""` — composer renders a clean empty state before any
    ///     chunk arrives. Drift to a placeholder string ("Loading…", "—")
    ///     would silently show that copy through the actual text field.
    ///   * `confidence == 1.0` — the high-confidence test above pins the
    ///     boundary, but the literal value also matters: a future drift to
    ///     `0.5` would still pass `isLowConfidence == false` while
    ///     misreporting confidence to any future consumer that reads
    ///     `confidence` directly (Settings stats, telemetry, etc.).
    ///   * `isStreaming == false` — composer's streaming spinner is gated
    ///     on this. Drift to `true` would render the spinner on every
    ///     fresh state before the first token has actually started.
    ///   * `isDone == false` — composer's "draft ready" affordances and
    ///     the `cmp-tones` enabled state both gate on this. Drift to
    ///     `true` would mark every fresh state as completed-and-ready,
    ///     which lets the user "send" a blank draft.
    ///   * `error == nil` — error banner gates on non-nil. Drift to a
    ///     non-nil string would render an error toast on every fresh
    ///     state before any LLM call has run.
    /// One test pinning all five fields together so a refactor to
    /// `DraftState`'s field defaults can't silently flip any of them
    /// without a deliberate test edit.
    func testDefaultDraftStateFieldDefaultsAreFrozen() {
        let s = DraftEngine.DraftState()
        XCTAssertEqual(s.text, "",
            "default text must be empty — drift to a placeholder string would render that copy in every fresh composer")
        XCTAssertEqual(s.confidence, 1.0, accuracy: 1e-9,
            "default confidence must be 1.0 — drift would misreport confidence to telemetry / stats consumers even when isLowConfidence stays false")
        XCTAssertFalse(s.isStreaming,
            "default isStreaming must be false — drift to true would render the streaming spinner before any token arrives")
        XCTAssertFalse(s.isDone,
            "default isDone must be false — drift to true would let the user send a blank draft from a fresh state")
        XCTAssertNil(s.error,
            "default error must be nil — drift to a non-nil string would render an error banner on every fresh composer")
    }

    /// Pin the literal value of `DraftState.lowConfidenceThreshold`.
    /// The behavioral tests above lock the boundary via 0.39/0.4/0.85
    /// confidence inputs, but a refactor that moved the literal cutoff
    /// from `isLowConfidence` into the constant could silently change the
    /// constant's value without those tests noticing (they'd just shift
    /// boundary-by-input). This test asserts the constant directly.
    /// Drift up routes more MLX drafts through the cmp-lowconf composer
    /// (`MLXDraftService.defaultDraftConfidence = 0.85` would route low
    /// at any threshold ≥ 0.86); drift down hides genuinely uncertain
    /// drafts behind the normal three-tone UX. The constant must stay
    /// strictly less than MLX's confidence default so today's MLX path
    /// continues to render in the high-confidence composer.
    func testLowConfidenceThresholdLiteralIsZeroPointFour() {
        XCTAssertEqual(DraftEngine.DraftState.lowConfidenceThreshold, 0.4, accuracy: 1e-9,
            "DraftState.lowConfidenceThreshold drift either over-warns (too high) or hides uncertain drafts (too low)")
        XCTAssertLessThan(DraftEngine.DraftState.lowConfidenceThreshold,
                          MLXDraftService.defaultDraftConfidence,
            "lowConfidenceThreshold must stay strictly less than MLXDraftService.defaultDraftConfidence — otherwise every MLX draft routes through cmp-lowconf")
    }

    // MARK: - primingKey format pin

    /// Pin the priming-task dictionary key format. Used at FOUR call
    /// sites (`prime`, `evict`, `invalidate`, `dismiss`) to look up
    /// the in-flight prime task for a (threadID, tone) pair. Drift
    /// between any two sites silently leaks tasks because the
    /// cancel-side lookup misses the entry the prime-side stored.
    func testPrimingKeyFormatRoundTripsAndIsStable() {
        // Format roundtrip: `<threadID>:<tone-rawValue>` byte-for-byte.
        XCTAssertEqual(DraftEngine.primingKey(threadID: "t1", tone: .warm),
                       "t1:Warm")
        XCTAssertEqual(DraftEngine.primingKey(threadID: "t1", tone: .direct),
                       "t1:Direct")
        XCTAssertEqual(DraftEngine.primingKey(threadID: "t1", tone: .playful),
                       "t1:Playful")

        // Pairwise distinct across (threadID, tone) — collision would
        // mean one entry's cancel hits the other's task.
        let keys = [
            DraftEngine.primingKey(threadID: "t1", tone: .warm),
            DraftEngine.primingKey(threadID: "t1", tone: .direct),
            DraftEngine.primingKey(threadID: "t2", tone: .warm),
        ]
        XCTAssertEqual(Set(keys).count, keys.count,
            "primingKey must produce distinct strings for each (thread, tone) pair — collision merges tasks")
    }

}

// MARK: - Test-only mock LLM services (REP-038)

/// Emits `progressSteps` loadProgress chunks followed by one text chunk and done.
/// Lets tests verify that DraftEngine transitions through the loading state correctly.
private struct LoadProgressThenTextService: LLMService {
    let progressSteps: Int

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for i in 1...max(1, progressSteps) {
                    if Task.isCancelled { continuation.finish(); return }
                    let fraction = Double(i) / Double(progressSteps)
                    continuation.yield(DraftChunk(kind: .loadProgress(
                        fraction: fraction,
                        message: "Loading · \(Int(fraction * 100))%"
                    )))
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                if Task.isCancelled { continuation.finish(); return }
                continuation.yield(DraftChunk(kind: .text("ok")))
                continuation.yield(DraftChunk(kind: .done))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Emits text chunks slowly so callers can cancel mid-stream.
private struct CancellableLongService: LLMService {
    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(DraftChunk(kind: .confidence(0.9)))
                // Signal streaming has started with a first token.
                continuation.yield(DraftChunk(kind: .text("word ")))
                // Then emit slowly so the test has time to call dismiss.
                for _ in 0..<20 {
                    if Task.isCancelled { continuation.finish(); return }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continuation.yield(DraftChunk(kind: .text("more ")))
                }
                continuation.yield(DraftChunk(kind: .done))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Error-path test doubles (REP-114)

/// Always throws immediately — lets tests verify the error state transition.
private struct ThrowingStubLLMService: LLMService {
    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NSError(domain: "test.llm", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "stub error"]))
        }
    }
}

/// Throws on the first call, succeeds on the second — lets tests verify that
/// regenerate() after an error eventually reaches the ready state.
private final class FailOnceThenSucceedService: LLMService, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        lock.lock()
        let n = callCount
        callCount += 1
        lock.unlock()
        return AsyncThrowingStream { continuation in
            if n == 0 {
                continuation.finish(throwing: NSError(domain: "test.llm", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "first call fails"]))
            } else {
                continuation.yield(DraftChunk(kind: .text("retry-ok")))
                continuation.yield(DraftChunk(kind: .done))
                continuation.finish()
            }
        }
    }
}

/// Emits a single fixed text string then done — useful for testing trimming behavior
/// where the exact text content matters and Fixtures.seedDraft is not appropriate.
private struct FixedTextService: LLMService {
    let text: String

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(DraftChunk(kind: .text(text)))
            continuation.yield(DraftChunk(kind: .done))
            continuation.finish()
        }
    }
}

/// Emits a fixed text string with a delay between tokens so callers can overlap
/// two calls before the first completes. Used to test rapid-regenerate serialization.
private struct SlowFixedTextService: LLMService {
    let text: String

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Initial delay so a second regenerate() call can land while we're still streaming.
                try? await Task.sleep(nanoseconds: 80_000_000)
                if Task.isCancelled { continuation.finish(); return }
                continuation.yield(DraftChunk(kind: .text(text)))
                if Task.isCancelled { continuation.finish(); return }
                continuation.yield(DraftChunk(kind: .done))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Immediately closes the stream without yielding any chunks — no .text, no .done.
/// Used to test that DraftEngine transitions to idle rather than staying in .priming.
private struct EmptyStreamService: LLMService {
    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

/// Emits a fixed list of (fraction, message) loadProgress chunks then pauses
/// indefinitely without yielding text or done. Lets tests assert the LATEST
/// emitted progress is what `modelLoadStatus` exposes — the existing
/// `LoadProgressThenTextService` proceeds to text + done immediately, which
/// would race the assertion against the load-status clear in `apply(.text)`.
private struct PausingProgressService: LLMService {
    let stages: [(Double, String)]

    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for (fraction, message) in stages {
                    if Task.isCancelled { continuation.finish(); return }
                    continuation.yield(DraftChunk(kind: .loadProgress(
                        fraction: fraction, message: message
                    )))
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                // Hold open — never yield text or done — so the test can
                // observe the final progress chunk before any clear path
                // (text/done) fires.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Emits one loadProgress chunk, then one text chunk, then holds open
/// without ever sending `.done`. Lets the test observe `modelLoadStatus`
/// being cleared mid-stream by the first text chunk specifically — not
/// indirectly by the `.done` path which also clears it.
private struct ProgressThenHoldingTextService: LLMService {
    func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(DraftChunk(kind: .loadProgress(
                    fraction: 0.5, message: "Loading"
                )))
                try? await Task.sleep(nanoseconds: 5_000_000)
                if Task.isCancelled { continuation.finish(); return }
                continuation.yield(DraftChunk(kind: .text("first ")))
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
