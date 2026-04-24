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
}
