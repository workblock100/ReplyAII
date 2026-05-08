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

    /// `ReplyAIWindowSummoner.inboxWindowID` is the scene id used by
    /// `WindowGroup(_, id:)` in ReplyAIApp and every `openWindow(id:)`
    /// call site (MenuBarContent, AppPrototypeView, ObDoneView). Drift on
    /// the WindowGroup side leaves `openWindow` callers spinning up a
    /// no-such-id scene (silent no-op); drift on any caller routes that
    /// one button to a stale id (button no-ops while the others continue
    /// to work). Pin the literal so a "let's namespace it" edit lands
    /// once with deliberate review.
    @MainActor
    func testInboxWindowIDConstantIsInbox() {
        XCTAssertEqual(ReplyAIWindowSummoner.inboxWindowID, "inbox",
            "inboxWindowID drift partially breaks SwiftUI scene routing — buttons routed through stale ids silently no-op while siblings continue to work")
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

    /// Pin the GlobalHotkey NSLog prefix used at three sites
    /// (RegisterEventHotKey-failed, InstallEventHandler-failed,
    /// successful-register confirmation). Drift between any two sites
    /// would have one filterable by `[ReplyAI] GlobalHotkey:` while
    /// another is invisible to that grep.
    func testLogPrefixIsFrozen() {
        XCTAssertEqual(GlobalHotkey.logPrefix, "[ReplyAI] GlobalHotkey: ")
        XCTAssertTrue(GlobalHotkey.logPrefix.hasPrefix("[ReplyAI]"),
            "log prefix must start with `[ReplyAI]` so process-wide log filtering catches it")
        XCTAssertTrue(GlobalHotkey.logPrefix.hasSuffix(": "),
            "log prefix must end with `: ` so subsequent message text reads naturally without an extra separator")
    }

    // MARK: - Diagnostic NSLog body pins

    /// `registerFailedLog(status:)` is the line a triage engineer
    /// greps for after a "⌘⇧R doesn't open ReplyAI" report. The body
    /// must read "RegisterEventHotKey failed" verbatim — drift to a
    /// different verb (e.g. "errored") or an alternate keyword (e.g.
    /// `code=` instead of `status=`) silently breaks the runbook
    /// grep. Pins both the prefix composition (logPrefix is reused)
    /// and the body shape.
    func testRegisterFailedLogFormatIncludesStatusAndKeyword() {
        let line = GlobalHotkey.registerFailedLog(status: -50)
        XCTAssertEqual(line, "[ReplyAI] GlobalHotkey: RegisterEventHotKey failed (status=-50)",
            "registerFailedLog must produce the exact triage-greppable line — drift breaks the runbook")
        XCTAssertTrue(line.hasPrefix(GlobalHotkey.logPrefix),
            "registerFailedLog must compose with logPrefix so process-wide filtering catches it")
    }

    func testRegisterFailedLogFormatHandlesPositiveStatus() {
        // Carbon hot-key statuses are usually negative, but pin a
        // positive value too so the format works regardless of sign.
        XCTAssertEqual(GlobalHotkey.registerFailedLog(status: 7),
                       "[ReplyAI] GlobalHotkey: RegisterEventHotKey failed (status=7)",
                       "format must handle non-negative OSStatus values without prepending a sign or padding")
    }

    /// `installFailedLog(status:)` is the second-leg failure line —
    /// `RegisterEventHotKey` succeeded but `InstallEventHandler` did
    /// not. Triage relies on these reading distinctly so the runbook
    /// can localize the failing leg.
    func testInstallFailedLogFormatIncludesStatusAndKeyword() {
        XCTAssertEqual(GlobalHotkey.installFailedLog(status: -25291),
                       "[ReplyAI] GlobalHotkey: InstallEventHandler failed (status=-25291)",
                       "installFailedLog must produce the exact triage-greppable line for the second-leg failure mode")
    }

    func testRegisterAndInstallFailedLogsReadDistinctly() {
        let r = GlobalHotkey.registerFailedLog(status: -50)
        let i = GlobalHotkey.installFailedLog(status: -50)
        XCTAssertNotEqual(r, i,
            "register- and install-failed lines must read distinctly so a triage engineer can localize which Carbon leg failed without inspecting code")
        XCTAssertTrue(r.contains("RegisterEventHotKey"),
            "registerFailedLog must call out `RegisterEventHotKey` by name — drift breaks the runbook grep")
        XCTAssertTrue(i.contains("InstallEventHandler"),
            "installFailedLog must call out `InstallEventHandler` by name — drift breaks the runbook grep")
    }

    /// `registeredLog` is the success-path confirmation a triage
    /// engineer greps for to verify `⌘⇧R` registered at app launch.
    /// Drift would silently break the runbook check that confirms
    /// the global hotkey is active in production builds.
    func testRegisteredLogIsExact() {
        XCTAssertEqual(GlobalHotkey.registeredLog,
                       "[ReplyAI] GlobalHotkey: ⌘⇧R registered",
                       "registeredLog must read exactly — runbook grep on `⌘⇧R registered` confirms hotkey installed at launch")
        XCTAssertTrue(GlobalHotkey.registeredLog.hasPrefix(GlobalHotkey.logPrefix),
            "registeredLog must compose with logPrefix so process-wide filtering catches the success line")
    }
}
