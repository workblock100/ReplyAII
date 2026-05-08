import XCTest
@testable import ReplyAI

// Bundle ID extractor that reads a "bundleID" key from userInfo, so tests
// can post fake activation notifications without needing real NSRunningApplication.
private let testExtractor: (Notification) -> String? = { $0.userInfo?["bundleID"] as? String }

@MainActor
final class MessagesAppActivationObserverTests: XCTestCase {

    // MARK: - REP-239: callback fires for Messages, silent for others

    func testActivationCallbackFiresForMessages() async throws {
        let center = NotificationCenter()
        var fired = false
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        observer.onMessagesActivated = { fired = true }

        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: ["bundleID": "com.apple.MobileSMS"]
        )

        // Give the debounce queue a moment to drain (debounce: 0.0 → dispatches async)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(fired, "callback must fire when Messages.app is activated")
    }

    func testActivationCallbackSilentForOtherApps() async throws {
        let center = NotificationCenter()
        var fired = false
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        observer.onMessagesActivated = { fired = true }

        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: ["bundleID": "com.apple.Safari"]
        )

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired, "callback must not fire when a non-Messages app is activated")
    }

    // MARK: - REP-239: 600ms debounce coalesces rapid activations

    func testRapidActivationsDebounced() async throws {
        let center = NotificationCenter()
        var callCount = 0
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.05  // 50ms — fast enough for tests, long enough to coalesce
        )
        observer.onMessagesActivated = { callCount += 1 }

        // Two activations before the debounce window elapses.
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])

        // Wait for the debounce window to close.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(callCount, 1,
            "two rapid activations within the debounce window must coalesce to one callback")
    }

    // MARK: - stop() cancels pending callback

    func testStopCancelsPendingDebouncedCallback() async throws {
        let center = NotificationCenter()
        var fired = false
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.1
        )
        observer.onMessagesActivated = { fired = true }

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])

        // Stop before the debounce fires.
        observer.stop()

        // Wait past the original debounce window.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(fired,
            "stop() before debounce expiry must cancel the pending callback")
    }

    func testActivationAfterStopDoesNotFire() async throws {
        let center = NotificationCenter()
        var fired = false
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        observer.onMessagesActivated = { fired = true }

        observer.stop()

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired,
            "activation notifications posted after stop() must not be observed")
    }

    func testNilBundleIDExtractorDoesNotFire() async throws {
        let center = NotificationCenter()
        var fired = false
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: { _ in nil },
            debounce: 0.0
        )
        observer.onMessagesActivated = { fired = true }

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired,
            "extractor returning nil must short-circuit before scheduling the callback")
    }

    // MARK: - Defensive paths

    /// `stop()` is invoked from `deinit` and is safe to call from app teardown
    /// after the observer has already been stopped (e.g. window-close + app
    /// quit). Calling it twice must not crash, double-remove, or leave the
    /// notification center in a broken state.
    func testDoubleStopDoesNotCrash() async throws {
        let center = NotificationCenter()
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        observer.stop()
        observer.stop()  // must be a no-op, not a crash

        // After two stops, posting a Messages activation must not fire the callback.
        var fired = false
        observer.onMessagesActivated = { fired = true }
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired,
            "after two stop() calls the observer must remain detached")
    }

    /// A notification posted with no `userInfo` (the default behavior of some
    /// AppKit-internal call sites and unit tests) must be tolerated — the
    /// extractor will return nil, and the observer must not crash on the
    /// optional chain or schedule a spurious callback.
    func testNotificationWithoutUserInfoIsIgnored() async throws {
        let center = NotificationCenter()
        var fired = false
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        observer.onMessagesActivated = { fired = true }

        center.post(name: NSWorkspace.didActivateApplicationNotification,
                    object: nil, userInfo: nil)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired,
            "missing userInfo must short-circuit cleanly without firing")
    }

    /// Activations from non-Messages apps within the debounce window must not
    /// reset the trailing-edge timer — non-Messages activations are filtered
    /// before scheduleCallback() so they don't perturb a pending Messages fire.
    func testNonMessagesActivationDoesNotInfluenceDebounce() async throws {
        let center = NotificationCenter()
        var callCount = 0
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.05
        )
        observer.onMessagesActivated = { callCount += 1 }

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.Safari"])
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.Terminal"])

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(callCount, 1,
            "non-Messages activations must not perturb the Messages debounce timer")
    }

    /// `onMessagesActivated` is a `var` closure — a caller can clear it after
    /// install (e.g. a view model resetting on tab change). When it's nil at
    /// fire-time the dispatched work item must not crash; the optional-chain
    /// inside the closure is the only safety net.
    func testNilCallbackAfterScheduleDoesNotCrash() async throws {
        let center = NotificationCenter()
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.05
        )
        observer.onMessagesActivated = { /* will be cleared */ }

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])

        // Clear the callback before the debounce window closes.
        observer.onMessagesActivated = nil

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(observer.onMessagesActivated,
            "callback cleared after schedule must remain nil and the dispatched fire must be tolerant of it")
    }

    /// After `stop()`, the observer's debounce queue should not retain a
    /// pending fire that could surface after a new callback is reattached.
    /// Guards against the failure mode where a stopped observer is reused
    /// (not supported, but historically possible) and would deliver a stale
    /// callback to the new owner.
    func testStopThenReattachCallbackDoesNotFireFromStaleSchedule() async throws {
        let center = NotificationCenter()
        let observer = MessagesAppActivationObserver(
            notificationCenter: center,
            bundleIDExtractor: testExtractor,
            debounce: 0.1
        )
        observer.onMessagesActivated = { XCTFail("original callback must not fire after stop") }

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: ["bundleID": "com.apple.MobileSMS"])

        observer.stop()

        var newFired = false
        observer.onMessagesActivated = { newFired = true }

        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(newFired,
            "stop() must not allow a stale-schedule callback to surface to a re-attached handler")
    }

    // MARK: - default-debounce pin

    /// `MessagesAppActivationObserver(notificationCenter:bundleIDExtractor:)`
    /// with no explicit `debounce` is the production call site at
    /// `InboxViewModel.activationObserver` init. If a future refactor tightens
    /// the default below the visible 600ms window, every shipped user will
    /// see extra sync triggers as they thumb between Messages threads —
    /// this pin catches that drift.
    func testDefaultDebounceIsSixHundredMilliseconds() {
        XCTAssertEqual(MessagesAppActivationObserver.defaultDebounce, 0.6,
            "defaultDebounce drift changes how many sync triggers fire per user visit to Messages.app")

        let observer = MessagesAppActivationObserver(
            notificationCenter: NotificationCenter(),
            bundleIDExtractor: testExtractor
        )
        XCTAssertEqual(observer.debounce, MessagesAppActivationObserver.defaultDebounce,
            "the no-debounce-arg init must route through Self.defaultDebounce — otherwise the static constant becomes dead code while the literal 0.6 lives on in the init signature")
    }

    /// Pin the Messages.app bundle ID — `com.apple.MobileSMS`. Apple's
    /// publicly-documented identifier; a rename here would silently
    /// break both this observer (no activation callbacks ever fire) and
    /// the AccessibilityAPIReader's PID lookup (no AX tree ever
    /// materializes). Both files now reference this single constant; pin
    /// the literal so the cross-file invariant lands in code review.
    func testMessagesAppBundleIDIsAppleMobileSMS() {
        XCTAssertEqual(MessagesAppActivationObserver.messagesAppBundleID,
                       "com.apple.MobileSMS",
                       "drift here breaks both activation callbacks AND AccessibilityAPIReader PID lookup — the bundle ID is published by Apple and must match exactly")
    }

    /// Pin the dispatch-queue label. Visible in Instruments / sample
    /// traces as the only signal distinguishing this observer's
    /// debounce queue from any other dispatch queue. Sibling to
    /// `ChatDBWatcher.dispatchQueueLabel` — both share the
    /// `co.replyai.` reverse-DNS prefix.
    func testDispatchQueueLabelIsFrozen() {
        XCTAssertEqual(MessagesAppActivationObserver.dispatchQueueLabel,
                       "co.replyai.messages-activation")
        XCTAssertTrue(MessagesAppActivationObserver.dispatchQueueLabel.hasPrefix("co.replyai."),
            "queue label must use the `co.replyai.` reverse-DNS prefix shared with sibling queues")
    }
}
