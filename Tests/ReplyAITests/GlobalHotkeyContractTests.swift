import XCTest
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
}
