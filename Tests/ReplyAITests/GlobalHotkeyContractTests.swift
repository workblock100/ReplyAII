import XCTest
import AppKit
@testable import ReplyAI

/// GlobalHotkey itself can't be unit-tested without a running NSApp +
/// Carbon event pump, but its public *contract* — the notification name
/// and channel-agnostic constants used by other modules — must stay
/// stable. Renaming the notification name silently breaks the IPC
/// between GlobalHotkey and AppPrototypeView (the hotkey would still
/// fire but the inbox window would never surface).
final class GlobalHotkeyContractTests: XCTestCase {

    func testSummonInboxNotificationNameIsStable() {
        // AppPrototypeView observes this exact name via `.onReceive` and
        // calls `openWindow(id: "inbox")`. Any rename here without a
        // matching update on the observer side would silently regress
        // the ⌘⇧R "summon" affordance.
        XCTAssertEqual(
            Notification.Name.replyAIRequestSummonInbox.rawValue,
            "co.replyai.summon.inbox",
            "summon-inbox notification name is part of the in-process IPC contract"
        )
    }

    /// `ReplyAIWindowSummoner.summon()` falls back to posting the summon
    /// notification when no NSWindow with title "Inbox" exists. That fallback
    /// is the path SwiftUI uses to call `openWindow(id: "inbox")` and the
    /// ⌘⇧R affordance has zero observable behavior without it. Verify
    /// `summon()` runs without crashing in a headless test (no NSApp running)
    /// AND fires the notification exactly once. This also pins that
    /// `summon()` is `@MainActor`-callable from a main-actor-isolated test.
    @MainActor
    func testSummonPostsNotificationWhenNoInboxWindowExists() {
        let exp = expectation(description: "summon notification fires")
        let token = NotificationCenter.default.addObserver(
            forName: .replyAIRequestSummonInbox,
            object: nil,
            queue: .main
        ) { _ in exp.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        // No inbox window exists in the headless test runner — the fast path
        // (NSApp.windows.first { $0.title == "Inbox" }) returns nil, so the
        // fallback notification path is exercised.
        ReplyAIWindowSummoner.summon()
        wait(for: [exp], timeout: 1.0)
    }

    /// Pin the window-title literal `"Inbox"` that the summoner's fast path
    /// matches against. The match must stay in sync with `ReplyAIApp`'s
    /// `WindowGroup("Inbox", id: "inbox")`. If either side drifts (e.g. the
    /// scene is renamed to "Reply" but the summoner still searches for
    /// "Inbox") the fast path silently degrades to the notification-fallback
    /// path on every summon — slower and observable as a one-frame stutter.
    /// This test runs `summon()` with a synthetic NSWindow titled "Inbox" in
    /// scope (added to NSApp.windows by the AppKit runtime) and verifies the
    /// notification does NOT fire — proving the fast path matched.
    @MainActor
    func testSummonFastPathMatchesWindowTitledInbox() {
        // Listen for the fallback notification. If the fast path fires, the
        // summoner returns early and this notification never posts.
        var fallbackFired = false
        let token = NotificationCenter.default.addObserver(
            forName: .replyAIRequestSummonInbox,
            object: nil,
            queue: .main
        ) { _ in fallbackFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Inbox"
        // Adding to NSApp.windows happens automatically when the window is
        // created; close-on-deinit is fine for this test scope.
        defer { window.close() }

        ReplyAIWindowSummoner.summon()
        // Drain the run loop so any same-tick notification post would have
        // been observed; without this a missing fast path could still appear
        // to pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(fallbackFired,
            "fast path must match the window titled `Inbox` and skip the fallback — drift in either side breaks ⌘⇧R surfacing")
    }
}
