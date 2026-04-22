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
