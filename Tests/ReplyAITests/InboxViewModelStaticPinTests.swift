import XCTest
@testable import ReplyAI

/// Static-only pins for InboxViewModel constants that ship to user UX.
/// The full `InboxViewModelTests` suite is environmentally skipped under
/// the autopilot's three-skip workaround (see AGENTS.md gotcha #243),
/// so these pins live in a separately-named class — the
/// `--skip InboxViewModelTests` substring filter won't match
/// `InboxViewModelStaticPinTests` (companion to the existing
/// `InboxViewModelLoadLimitPinTests` and `InboxViewModelMenuBarWaitingTests`
/// files which use the same naming convention to evade the skip).
///
/// Each pin in this file must be an XCTAssertEqual against a class-
/// scoped `static let` — no instantiation of `InboxViewModel`, no
/// async, no chat.db, no Contacts. Anything heavier belongs in the
/// main `InboxViewModelTests` suite (which already pins the same
/// constants — these are duplicates that fire in the skip-gated
/// autopilot run).
@MainActor
final class InboxViewModelStaticPinTests: XCTestCase {

    /// `InboxViewModel.incomingNotificationTimeLabel` is the time-chip
    /// value applied to a thread when a UNNotification updates (or
    /// creates) it on the no-chat.db code path. Drift here changes the
    /// time-chip copy on every notification-driven thread refresh —
    /// users would see e.g. `"just now"` or `""` instead of `"now"`,
    /// which (a) breaks the visual alignment with chat.db's relative-
    /// time column and (b) silently changes the test expectations of
    /// every notification-applies-to-thread suite. Mirrors the
    /// equivalent pin inside the skip-gated InboxViewModelTests so
    /// the autopilot's three-skip workaround still validates this
    /// contract on every fire.
    func testIncomingNotificationTimeLabelIsNow() {
        XCTAssertEqual(InboxViewModel.incomingNotificationTimeLabel, "now",
            "InboxViewModel.incomingNotificationTimeLabel drift changes the time-chip copy on every notification-driven thread refresh; pin must mirror the equivalent pin inside the skip-gated InboxViewModelTests so the contract is validated under the autopilot's three-skip workaround")
        XCTAssertFalse(InboxViewModel.incomingNotificationTimeLabel.isEmpty,
            "incomingNotificationTimeLabel must be a non-empty string — empty would render as a stripped-down ThreadRow with no time chip on every notification refresh")
    }

    /// `InboxViewModel.emptyChatDBSyncFailureMessage` is the user-
    /// visible toast copy when chat.db is reachable + Full Disk Access
    /// is granted but the SQL query returns zero rows (a fresh-install
    /// Mac with no Messages history yet, or an account where the user
    /// signed out of iCloud). Pin the literal so a copy edit lands on
    /// a clear test, not buried inside the channel-fallback code path.
    func testEmptyChatDBSyncFailureMessageIsFrozen() {
        XCTAssertEqual(InboxViewModel.emptyChatDBSyncFailureMessage,
                       "No conversations returned. chat.db may be empty on this account.",
            "emptyChatDBSyncFailureMessage drift changes the toast users see when chat.db is healthy but empty — copy edits should land on this test, not silently inside the fallback path")
    }

    /// `InboxViewModel.perThreadMessageLoadLimit` is also pinned in
    /// `InboxViewModelLoadLimitPinTests`; keep both as belt-and-suspenders.
    /// If the existing pin file is renamed, this duplicate keeps the
    /// contract visible. Drift in either direction (down truncates
    /// PromptBuilder's context window; up makes thread-detail switches
    /// slow on chatty threads) is silent in production.
    func testPerThreadMessageLoadLimitMirroredPin() {
        XCTAssertEqual(InboxViewModel.perThreadMessageLoadLimit, 40,
            "duplicate pin of perThreadMessageLoadLimit — see InboxViewModelLoadLimitPinTests for the canonical reasoning; both files exist to ensure at least one fires under any plausible test-skip configuration")
    }
}
