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
