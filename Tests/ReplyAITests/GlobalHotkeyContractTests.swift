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

    /// `ReplyAIWindowSummoner.inboxWindowTitle` is the title both
    /// `WindowGroup("Inbox", id: "inbox")` in ReplyAIApp and the AppKit
    /// fast-path window lookup in `summon()` route through. Drift on
    /// either side silently degrades `⌘⇧R` from the fast `makeKey` path
    /// to the slower `openWindow` notification-fallback path on every
    /// summon — a one-frame stutter users notice over time. The AppKit-
    /// touching fast-path test is gated behind `RUN_APPKIT_TOUCHING_TESTS`;
    /// this pin is unconditional so the constant value is locked even in
    /// the headless run.
    @MainActor
    func testInboxWindowTitleConstantIsInbox() {
        XCTAssertEqual(ReplyAIWindowSummoner.inboxWindowTitle, "Inbox",
            "inboxWindowTitle drift desyncs the WindowGroup label and the AppKit fast-path lookup — every ⌘⇧R falls back to the slower notification path")
    }

    /// `ReplyAIWindowSummoner.summon()` falls back to posting the summon
    /// notification when no NSWindow with title "Inbox" exists. That fallback
    /// is the path SwiftUI uses to call `openWindow(id: "inbox")` and the
    /// ⌘⇧R affordance has zero observable behavior without it.
    ///
    /// SUSPECTED SIGSEGV TRIGGER (2026-05-06): when this test runs in the
    /// full `swift test` suite, the runner segfaults later during teardown
    /// of an unrelated suite — strong hypothesis is that AppKit objects
    /// touched here (NotificationCenter + a NSApp-ish run-loop interaction
    /// inside `summon()`) leak state into the headless xctest process.
    /// Gating on an opt-in env var so CI / autopilot runs the rest of the
    /// suite cleanly while keeping the test available locally with
    /// `RUN_APPKIT_TOUCHING_TESTS=1 swift test`.
    @MainActor
    func testSummonPostsNotificationWhenNoInboxWindowExists() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_APPKIT_TOUCHING_TESTS"] != "1",
            "AppKit-touching test gated to avoid SIGSEGV in headless xctest; opt in with RUN_APPKIT_TOUCHING_TESTS=1"
        )
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
    ///
    /// SUSPECTED SIGSEGV TRIGGER (2026-05-06): this test constructs a real
    /// NSWindow inside the test body. Lingering NSWindow refs in
    /// `NSApp.windows` after teardown are a known crash source in headless
    /// xctest. Gated on the same opt-in env var as the sibling test.
    @MainActor
    func testSummonFastPathMatchesWindowTitledInbox() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RUN_APPKIT_TOUCHING_TESTS"] != "1",
            "AppKit-touching test gated to avoid SIGSEGV in headless xctest; opt in with RUN_APPKIT_TOUCHING_TESTS=1"
        )
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
