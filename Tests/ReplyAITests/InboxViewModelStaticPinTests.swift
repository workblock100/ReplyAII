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

    /// `InboxViewModel.{archivedKey, silentlyIgnoredKey, pinnedKey,
    /// snoozedUntilKey, lastSeenRowIDKey}` are the persistence keys
    /// that back the inbox's per-user state (which threads are
    /// archived/ignored/pinned, when each is snoozed-until, and the
    /// rule-engine high-water-mark for each thread). They share the
    /// `pref.inbox.*` namespace prefix so `wipeReplyAIDefaults` sweeps
    /// them on factory reset.
    ///
    /// These keys are also pinned in `InboxViewModelTests.swift`, but
    /// that file is in the autopilot's three-skip workaround (see
    /// AGENTS.md gotcha #243), so the canonical pins don't fire under
    /// the standard autopilot merge gate. Mirror them here so a
    /// rename of any persistence key surfaces under the three-skip
    /// run too — drift in any of these would silently orphan user
    /// data (the new key reads as empty on every launch while the old
    /// key's data sits in UserDefaults forever, until factory reset).
    /// One test pinning all five together because the keys form a
    /// coherent contract — they MUST all start with the
    /// `wipeNamespacePrefix` so the wipe logic finds them.
    func testInboxPersistenceKeysAreFrozen() {
        XCTAssertEqual(InboxViewModel.archivedKey, "pref.inbox.archivedThreadIDs",
            "archivedKey drift orphans archived-thread state on every shipped user — they keep seeing rows they thought they archived")
        XCTAssertEqual(InboxViewModel.silentlyIgnoredKey, "pref.inbox.silentlyIgnoredThreadIDs",
            "silentlyIgnoredKey drift orphans silentlyIgnore rule-action state — `silentlyIgnore` rules silently stop being respected on next launch")
        XCTAssertEqual(InboxViewModel.pinnedKey, "pref.inbox.pinnedThreadIDs",
            "pinnedKey drift orphans pinned-thread ordering — every pinned thread appears unpinned on next launch")
        XCTAssertEqual(InboxViewModel.snoozedUntilKey, "pref.inbox.snoozedUntil",
            "snoozedUntilKey drift orphans snooze state — every snoozed thread reappears immediately on next launch (the worst possible UX for snooze)")
        XCTAssertEqual(InboxViewModel.lastSeenRowIDKey, "pref.inbox.lastSeenRowID",
            "lastSeenRowIDKey drift makes the rule engine re-evaluate every historical message on next launch (rules fire as if every shipped message just arrived)")

        // All five keys must share the wipe-namespace prefix so factory
        // reset finds them. Drift here would leak per-user state past
        // a wipe — exactly the scenario the wipe contract exists to prevent.
        for key in [InboxViewModel.archivedKey, InboxViewModel.silentlyIgnoredKey,
                    InboxViewModel.pinnedKey, InboxViewModel.snoozedUntilKey,
                    InboxViewModel.lastSeenRowIDKey] {
            XCTAssertTrue(key.hasPrefix(PreferenceKey.wipeNamespacePrefix),
                "every InboxViewModel persistence key must share the wipe-namespace prefix (`\(PreferenceKey.wipeNamespacePrefix)`) — `\(key)` doesn't, which means factory reset will leave its data behind")
        }
    }
}
