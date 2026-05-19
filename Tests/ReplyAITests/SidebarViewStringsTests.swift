import XCTest
@testable import ReplyAICore

/// Pin the user-visible copy in `SidebarView` so a copy edit lands in
/// code review with named tests rather than as a silent SwiftUI-body diff.
/// View 2 of 5 under REP-UI-STR-HOIST-001. See sibling
/// `MenuBarContentStringsTests` for the pattern; brand strings ("R",
/// "ReplyAI") and demo profile strings ("JS", "Jordan Song", "pro · mac")
/// stay inline — brand strings get a `BrandStrings.swift` consolidation
/// pass after every per-view hoist settles; demo profile strings get
/// replaced with real user data when the account layer ships.
final class SidebarViewStringsTests: XCTestCase {

    // MARK: - Frozen literals

    func testSearchShortcutHintIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.searchShortcutHint, "⌘K",
            "search shortcut hint must match the global keyboard map (Services/GlobalHotkey.swift); drift here means the rendered chip silently diverges from the actual shortcut")
    }

    func testSearchPlaceholderIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.searchPlaceholder, "Search anyone, anything",
            "search placeholder must remain `Search anyone, anything` — the verb-less, comma-separated noun phrase the design system calls for; rephrasing to a verb-led prompt (\"Find a thread…\") breaks the placeholder rhythm across the app")
    }

    func testFoldersSectionLabelIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.foldersSection, "Inboxes",
            "folder-list section header must remain `Inboxes` (plural) — singular `Inbox` would conflict with the window title")
    }

    func testChannelsSectionLabelIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.channelsSection, "Channels",
            "channel-filter section header must remain `Channels` (plural)")
    }

    func testSyncIdleLabelIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.syncIdle, "fixtures · ⌘R to sync",
            "idle-sync chip must remain `fixtures · ⌘R to sync` — the `fixtures` token signals the inbox is showing demo data; the `⌘R` matches the actual keyboard shortcut; the middle character is U+00B7 (·), not a hyphen")
    }

    func testSyncingLabelIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.syncing, "syncing…",
            "in-flight sync chip must remain `syncing…` — trailing horizontal ellipsis U+2026, lowercase per the design system's transient-state convention")
    }

    func testSyncDeniedLabelIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.syncDenied, "needs full disk access",
            "denied-sync chip must remain `needs full disk access` — channel-agnostic per the 2026-04-23 pivot; rephrasing to `chat.db blocked` would re-leak the iMessage-only assumption")
    }

    func testSyncLivePrefixIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.syncLivePrefix, "live · ",
            "live-sync prefix must remain `live · ` (trailing space; middle dot U+00B7) — composed with relativeString to produce `live · 5s ago`")
    }

    func testSyncFailedPrefixIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.syncFailedPrefix, "error · ",
            "failed-sync prefix must remain `error · ` (trailing space; middle dot U+00B7) — composed with the truncated message to produce `error · <24-char snippet>`")
    }

    func testSyncFailedMessageMaxLengthIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.syncFailedMessageMaxLength, 24,
            "failed-sync message max-length must remain 24 — empirical fit for the 220-pt sidebar without wrapping")
    }

    func testRelativeJustNowIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.relativeJustNow, "just now",
            "<5s relative-time string must remain `just now` — two words, lowercase, no punctuation")
    }

    func testRelativeSecondsAgoSuffixIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.secondsAgoSuffix, "s ago",
            "seconds-ago suffix must remain `s ago` (with a leading space) — produces `12s ago` when concatenated with the count")
    }

    func testRelativeMinutesAgoSuffixIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.minutesAgoSuffix, "m ago",
            "minutes-ago suffix must remain `m ago` (with a leading space)")
    }

    func testRelativeHoursAgoSuffixIsFrozen() {
        XCTAssertEqual(SidebarView.Strings.hoursAgoSuffix, "h ago",
            "hours-ago suffix must remain `h ago` (with a leading space)")
    }

    // MARK: - Shape invariants

    /// The sync-chip prefixes need a trailing space so the rendered
    /// composed string reads `live · 5s ago`, not `live ·5s ago`.
    func testSyncPrefixesHaveTrailingSpace() {
        XCTAssertTrue(SidebarView.Strings.syncLivePrefix.hasSuffix(" "),
            "syncLivePrefix must end with a space")
        XCTAssertTrue(SidebarView.Strings.syncFailedPrefix.hasSuffix(" "),
            "syncFailedPrefix must end with a space")
    }

    /// Relative-time suffixes need a leading space so the composed string
    /// reads `12s ago`, not `12sago`. The seconds suffix is `s ago`
    /// (space-s-space-ago), where the leading `s` is the unit letter and
    /// the leading character of the suffix string is a regular space.
    func testRelativeSuffixesHaveLeadingSpace() {
        // Suffix structure is `<unit> ago`; the actual leading character is
        // the unit letter, not a space. Verify the leading character is a
        // single-letter unit and the second character is a space.
        for suffix in [SidebarView.Strings.secondsAgoSuffix,
                       SidebarView.Strings.minutesAgoSuffix,
                       SidebarView.Strings.hoursAgoSuffix] {
            XCTAssertEqual(suffix.count, "s ago".count,
                "all relative-time suffixes must be the same length so the chip width stays stable")
            XCTAssertEqual(String(suffix.dropFirst().first ?? Character(" ")), " ",
                "relative-time suffix must have a space after the unit letter — got \(suffix)")
            XCTAssertTrue(suffix.hasSuffix("ago"),
                "relative-time suffix must end with `ago` — got \(suffix)")
        }
    }

    /// All sidebar UI strings should fit within the 220-pt sidebar width
    /// without wrapping. The right shape invariant is character count;
    /// the design uses Inter Tight at 11–13pt, so ~28 chars fits.
    func testStringsFitInSidebarWidth() {
        let strings: [String] = [
            SidebarView.Strings.searchShortcutHint,
            SidebarView.Strings.searchPlaceholder,
            SidebarView.Strings.foldersSection,
            SidebarView.Strings.channelsSection,
            SidebarView.Strings.syncIdle,
            SidebarView.Strings.syncing,
            SidebarView.Strings.syncDenied,
            SidebarView.Strings.syncLivePrefix,
            SidebarView.Strings.syncFailedPrefix,
            SidebarView.Strings.relativeJustNow,
            SidebarView.Strings.secondsAgoSuffix,
            SidebarView.Strings.minutesAgoSuffix,
            SidebarView.Strings.hoursAgoSuffix,
        ]
        for s in strings {
            XCTAssertLessThanOrEqual(s.count, 28,
                "sidebar string `\(s)` must be ≤ 28 chars to fit the 220-pt sidebar without wrapping")
        }
    }
}
