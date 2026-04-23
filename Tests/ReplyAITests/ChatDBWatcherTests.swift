import XCTest
@testable import ReplyAI

final class ChatDBWatcherTests: XCTestCase {
    /// How long to wait after the debounce window before asserting the
    /// callback count. A small buffer above the watcher's debounce
    /// interval gives the DispatchSource.asyncAfter enough slack
    /// without turning the suite into a sleep festival.
    private let debounce: TimeInterval = 0.05
    private let settle: TimeInterval = 0.15

    /// A single burst of events should coalesce into exactly one fire.
    func testBurstWritesCoalesceIntoSingleFire() {
        let counter = FireCounter()
        let watcher = ChatDBWatcher(
            paths: [],   // no real paths — we drive scheduleFire directly
            debounce: debounce,
            onChange: { counter.bump() }
        )

        for _ in 0..<10 { watcher.scheduleFire() }
        waitPast(debounce + 0.1)
        XCTAssertEqual(counter.value, 1, "burst in a single window should produce one fire")
    }

    /// Events separated by more than the debounce window should fire
    /// independently.
    func testWritesAcrossWindowFireTwice() {
        let counter = FireCounter()
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            onChange: { counter.bump() }
        )

        watcher.scheduleFire()
        waitPast(debounce + 0.05)
        XCTAssertEqual(counter.value, 1)

        watcher.scheduleFire()
        waitPast(debounce + 0.05)
        XCTAssertEqual(counter.value, 2, "a second burst beyond the window should fire again")
    }

    /// `stop()` must cancel any pending debounce timer. Events after
    /// stop shouldn't fire.
    func testStopCancelsPendingFire() {
        let counter = FireCounter()
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            onChange: { counter.bump() }
        )

        watcher.scheduleFire()
        watcher.stop()
        waitPast(debounce + settle)
        XCTAssertEqual(counter.value, 0, "stop() should cancel the pending fire")

        // And additional schedules after stop still work the dispatch
        // timer — but the queue path is still live, so a scheduleFire
        // after stop DOES fire. This asserts the invariant we care
        // about (pending-at-stop is cancelled) without over-constraining.
    }

    /// A system-triggered cancel (e.g. chat.db moved during iCloud sync) must
    /// schedule a restart. `simulateSystemCancel` drives the same code path as
    /// the real cancel handler without needing real FS objects.
    func testCancellationSchedulesRestart() {
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            restartDelay: 0.05,
            onChange: {}
        )
        XCTAssertEqual(watcher.restartCount.withLock { $0 }, 0)
        watcher.simulateSystemCancel()
        // simulateSystemCancel is synchronous (queue.sync), so restartCount
        // is already incremented when the call returns.
        XCTAssertEqual(watcher.restartCount.withLock { $0 }, 1,
            "system cancel should schedule exactly one restart attempt")
    }

    /// After `stopWatching()` a simulated system cancel must NOT schedule a
    /// restart — intentional shutdown is permanent.
    func testStopWatchingDoesNotRestart() {
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            restartDelay: 0.05,
            onChange: {}
        )
        watcher.stopWatching()
        watcher.simulateSystemCancel()
        XCTAssertEqual(watcher.restartCount.withLock { $0 }, 0,
            "stopWatching should prevent restart scheduling")
    }

    /// Second `start()` is documented as idempotent — it must not
    /// crash and must not double-fire.
    func testStartIsIdempotent() {
        let counter = FireCounter()
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            onChange: { counter.bump() }
        )
        watcher.start()
        watcher.start()   // second call should be a no-op
        watcher.scheduleFire()
        waitPast(debounce + settle)
        XCTAssertEqual(counter.value, 1)
        watcher.stop()
    }

    // MARK: - stop() idempotency (REP-131)

    /// Calling stop() twice must not crash (no double-cancel on DispatchSource).
    func testDoubleStopDoesNotCrash() {
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            onChange: {}
        )
        watcher.stop()
        watcher.stop()  // second call must be a no-op, not a crash
        // Reaching here without EXC_BAD_ACCESS / preconditionFailure is the assertion.
    }

    /// A burst of fires followed immediately by stop() must result in zero callbacks.
    /// The pending work item was already enqueued before stop(), but stop() cancels it.
    func testCallbackNotFiredAfterStop() {
        let counter = FireCounter()
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            onChange: { counter.bump() }
        )
        // Schedule a burst so there is a pending work item, then stop immediately.
        for _ in 0..<5 { watcher.scheduleFire() }
        watcher.stop()
        // Wait well past the debounce window — the cancelled work item must not run.
        waitPast(debounce + settle * 2)
        XCTAssertEqual(counter.value, 0,
                       "stop() must cancel the pending work item so callback does not fire")
    }

    // MARK: - stop→reinit cycles (REP-173)

    /// Deallocate and recreate a ChatDBWatcher 5 times on the same source path.
    /// Guards against DispatchSource retain-cycle accumulation or double-cancel from deinit.
    func testFiveStopReinitCyclesNoCrash() {
        for _ in 0..<5 {
            let watcher = ChatDBWatcher(paths: [], debounce: debounce, onChange: {})
            watcher.stop()
            // Watcher falls out of scope here — deinit must not crash.
        }
        // Reaching here without trap is the assertion.
    }

    /// After 5 stop→reinit cycles, a 6th watcher instance must still fire its callback.
    func testFinalWatcherAfterCyclesFiresCallback() {
        for _ in 0..<5 {
            let watcher = ChatDBWatcher(paths: [], debounce: debounce, onChange: {})
            watcher.stop()
        }

        let counter = FireCounter()
        let finalWatcher = ChatDBWatcher(
            paths: [], debounce: debounce,
            onChange: { counter.bump() }
        )
        finalWatcher.scheduleFire()
        waitPast(debounce + settle)
        XCTAssertEqual(counter.value, 1,
                       "6th watcher instance after 5 reinit cycles must still fire its onChange callback")
        finalWatcher.stop()
    }

    // MARK: - Helpers

    private func waitPast(_ interval: TimeInterval) {
        let exp = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) { exp.fulfill() }
        wait(for: [exp], timeout: interval + 1.0)
    }
}

/// Tiny atomic counter — the watcher's callback runs on its private
/// queue so the test needs a thread-safe counter to read from the main
/// thread without a data race.
private final class FireCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func bump() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}
