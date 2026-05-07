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

    /// Repeated system cancels must each increment the restart counter so the
    /// exponential-backoff schedule walks forward; without this, every cancel
    /// after the first would silently retry at the initial delay.
    func testRepeatedSystemCancelsAccumulateRestartCount() {
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            restartDelay: 0.05,
            onChange: {}
        )
        watcher.simulateSystemCancel()
        watcher.simulateSystemCancel()
        watcher.simulateSystemCancel()
        XCTAssertEqual(watcher.restartCount.withLock { $0 }, 3,
            "each system cancel must increment restartCount independently")
    }

    /// `stop()` is documented as an alias for `stopWatching()`. Both must block
    /// subsequent restarts identically — the alias was added for callers
    /// pre-dating the rename and a regression to "stop is a no-op" would
    /// silently break shutdown for any caller still using the old name.
    func testStopAliasBlocksRestartLikeStopWatching() {
        let watcher = ChatDBWatcher(
            paths: [],
            debounce: debounce,
            restartDelay: 0.05,
            onChange: {}
        )
        watcher.stop()                 // alias path
        watcher.simulateSystemCancel()
        XCTAssertEqual(watcher.restartCount.withLock { $0 }, 0,
            "stop() alias must set the stopped flag like stopWatching()")
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

    // MARK: - Default-argument contract pins
    //
    // `InboxViewModel.swift:~1041` instantiates the watcher with only the
    // trailing closure: `ChatDBWatcher { [weak self] in ... }`. That call
    // site silently inherits every `init` default — paths, debounce,
    // restartDelay. Pin the production defaults so a "tighten the timing"
    // refactor lands in code review rather than as a silent change to
    // every shipped user's iMessage reactivity / restart-storm behavior.

    /// `restartDelay` is the seed of the exponential backoff curve
    /// (`min(restartDelay * pow(2, count), 60)`). Halving it would double
    /// the restart-storm rate when the system cancels our DispatchSource
    /// during iCloud sync; doubling it would make the inbox appear dead
    /// for ~10s after a cancel. Pin the production default.
    func testDefaultRestartDelayMatchesProductionValue() {
        let watcher = ChatDBWatcher(paths: [], onChange: {})
        XCTAssertEqual(watcher.restartDelay, 5.0,
            "restartDelay default seeds the exponential-backoff curve — drift here changes recovery cadence for every shipped user")
        watcher.stop()
    }

    /// `ChatDBWatcher.defaultDebounce` is the only knob between "feels live"
    /// and "re-syncs 10x per inbound iMessage". A tighter default (say 0.3s)
    /// would make a bulk iMessage import re-sync mid-flight, hammering
    /// `chat.db` reads; a looser default (>1s) would make new messages
    /// visibly slow to surface. The static pin guards both directions in
    /// addition to enforcing that the no-arg init plumbs through the
    /// constant rather than re-introducing a literal `0.6`.
    func testDefaultDebounceIsSixHundredMilliseconds() {
        XCTAssertEqual(ChatDBWatcher.defaultDebounce, 0.6,
            "ChatDBWatcher.defaultDebounce drift changes how reactive the inbox feels for every shipped user — tighten and we re-sync mid-burst, loosen and new messages lag")

        let watcher = ChatDBWatcher(paths: [], onChange: {})
        XCTAssertEqual(watcher.debounce, ChatDBWatcher.defaultDebounce,
            "the no-debounce-arg init must route through ChatDBWatcher.defaultDebounce — otherwise the static constant becomes dead code while the literal 0.6 lives on in the init signature")
        watcher.stop()
    }

    /// Companion to the restart-delay pin: `defaultRestartDelay` should
    /// match the production literal so the no-arg init matches the
    /// `restartDelay` already pinned above.
    func testDefaultRestartDelayConstantMatchesNoArgInit() {
        XCTAssertEqual(ChatDBWatcher.defaultRestartDelay, 5.0,
            "ChatDBWatcher.defaultRestartDelay is the seed of the exponential-backoff curve")

        let watcher = ChatDBWatcher(paths: [], onChange: {})
        XCTAssertEqual(watcher.restartDelay, ChatDBWatcher.defaultRestartDelay,
            "no-restartDelay-arg init must route through the static constant; the existing `testDefaultRestartDelayMatchesProductionValue` only catches drift in the literal value")
        watcher.stop()
    }

    /// Constructing with only the trailing closure must succeed (i.e.
    /// every init parameter besides `onChange` has a default). The
    /// production call site relies on this; if `paths` ever loses its
    /// default, callers must thread the chat.db path through manually.
    func testTrailingClosureInitMatchesProductionCallSite() {
        var fired = false
        let watcher = ChatDBWatcher { fired = true }
        // No paths can resolve in a headless test env — but we just
        // need the construction to compile and the callback shape to
        // round-trip. Drive it directly via the package-level shim.
        watcher.scheduleFire()
        // Default debounce is 0.6s; settle past it to confirm onChange
        // runs without touching real fsevents.
        waitPast(0.6 + 0.2)
        XCTAssertTrue(fired,
            "trailing-closure init must wire `onChange` via the default-args path used at the production call site")
        watcher.stop()
        _ = fired // silence unused-mutation warning when test trims later
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
