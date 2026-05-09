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
    /// `InboxViewModel.sentToToast(recipient:)` is the
    /// success-path toast copy after a real send. Format is `"Sent
    /// to <recipient>"` — drift to e.g. `"Sent: <recipient>"` or
    /// `"Sent (<recipient>)"` would silently change the toast users
    /// see on every successful send. Pinned in
    /// `InboxViewModelTests.swift` via `testSentToToastFormatRoundTrips`,
    /// but that file is in the three-skip workaround so the
    /// canonical pin doesn't fire under the autopilot's standard merge
    /// gate. Mirror here so toast-copy drift surfaces under the
    /// three-skip run too.
    func testSentToToastFormatMirroredPin() {
        XCTAssertEqual(InboxViewModel.sentToToast(recipient: "Maya"),
                       "Sent to Maya",
            "sentToToast format must round-trip — `Sent to <name>` is what users see on every successful send; drift would silently change toast copy on every shipped install")
        XCTAssertEqual(InboxViewModel.sentToToast(recipient: ""),
                       "Sent to ",
            "empty recipient still produces the prefix verbatim — pin so a future `guard !recipient.isEmpty` shim that suppresses the toast lands as a deliberate change, not a silent UX drop")
    }

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

    /// Mirror pin: `InboxViewModel.ViewState`'s custom `==` operator
    /// has a `default: return false` arm that fires when lhs and rhs
    /// are different cases. The canonical cross-case inequality test
    /// (`testViewStateEqualityCrossCaseAlwaysUnequal` in
    /// `InboxViewModelTests.swift`) covers .loading vs .populated,
    /// .populated vs .demo, .demo vs .empty, .empty vs .empty,
    /// .loading vs .empty, .populated vs .empty — but every pair
    /// involving `.error` is unrepresented there. Since
    /// `InboxViewModelTests` is in the autopilot's three-skip
    /// workaround (gotcha #243), even that existing cross-case test
    /// doesn't fire under the standard merge gate either.
    ///
    /// Pin .error vs every other case here so the `default: false`
    /// arm has coverage in the non-skipped class. Drift would surface
    /// as a SwiftUI re-render failure when the inbox transitions
    /// from .loading/.populated/.empty/.demo INTO .error (or back) —
    /// the @Observable diffing would treat the two states as equal
    /// and skip the redraw, leaving the previous UI on screen with
    /// stale content.
    func testViewStateErrorIsUnequalToEveryOtherCase() {
        struct StubError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }
        let err: InboxViewModel.ViewState = .error(StubError(message: "x"))
        let others: [InboxViewModel.ViewState] = [
            .loading,
            .populated,
            .demo,
            .empty(.noMessages),
            .empty(.noPermissions),
        ]
        for other in others {
            XCTAssertNotEqual(err, other,
                ".error must compare unequal to \(other) — drift would mute a SwiftUI re-render on the transition from non-error → error and leave stale UI on screen")
            XCTAssertNotEqual(other, err,
                "\(other) must compare unequal to .error — symmetry: drift would mute the redraw on the recovery transition (error → idle)")
        }
    }

    /// Mirror pin: the `.empty(EmptyReason)` case has TWO associated
    /// values (`.noMessages` and `.noPermissions`). The canonical
    /// `InboxViewModelTests` cross-case test covers
    /// `.empty(.noMessages) != .empty(.noPermissions)` already, but
    /// only inside the skipped suite. Re-pin here so the EmptyReason
    /// diff is exercised under the autopilot's three-skip merge
    /// gate. The two reasons drive different inbox banners (FDABanner
    /// vs the Limited-Mode CTA), so a silent "they're equal" diff
    /// would route a permission-denied state through the
    /// no-messages copy.
    func testViewStateEmptyReasonsAreUnequal() {
        let noMessages: InboxViewModel.ViewState = .empty(.noMessages)
        let noPermissions: InboxViewModel.ViewState = .empty(.noPermissions)
        XCTAssertNotEqual(noMessages, noPermissions,
            ".empty(.noMessages) and .empty(.noPermissions) must compare unequal — they drive different inbox banners (FDABanner vs Limited-Mode CTA), so drift here would route a permission-denied state through the no-messages copy")
        XCTAssertEqual(noMessages, .empty(.noMessages),
            "same EmptyReason must compare equal — otherwise every sync that lands on .empty(.noMessages) re-renders the banner from scratch on each refresh")
        XCTAssertEqual(noPermissions, .empty(.noPermissions),
            "same EmptyReason must compare equal — otherwise every sync that lands on .empty(.noPermissions) re-renders the banner from scratch on each refresh")
    }
}
