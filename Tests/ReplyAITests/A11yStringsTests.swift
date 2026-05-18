import XCTest
@testable import ReplyAICore

/// Pins for `A11yStrings`. Icon-only tappable elements rely on these
/// strings being announced verbatim by VoiceOver — drift here silently
/// regresses the accessibility surface. Pin the literal values so a
/// future "consistency" refactor (e.g. renaming "Clear search" to
/// "Clear field") surfaces as a deliberate change rather than a silent
/// announcement shift.
final class A11yStringsTests: XCTestCase {

    /// SidebarView's trailing clear button (xmark.circle.fill). Without
    /// the label, VoiceOver speaks the SF Symbol's component-by-component
    /// name verbatim ("xmark dot circle dot fill"), which is unusable.
    func testClearSearchLiteral() {
        XCTAssertEqual(A11yStrings.clearSearch, "Clear search")
    }

    /// ThreadListView's bulk-actions "checkmark.circle" button. The
    /// `.help()` tooltip and `.accessibilityLabel()` must announce the
    /// same string — drift here means sighted users hover one phrase
    /// while VoiceOver users hear another.
    func testMarkAllReadLiteral() {
        XCTAssertEqual(A11yStrings.markAllRead, "Mark all read")
    }

    /// ThreadListView's bulk-actions "archivebox" button — same dual-use
    /// (help tooltip + a11y label) rationale as `markAllRead`.
    func testArchiveReadLiteral() {
        XCTAssertEqual(A11yStrings.archiveRead, "Archive read")
    }

    /// Style invariant: imperative verb-phrase, sentence-case first
    /// word, no trailing punctuation, ≤ 24 chars. Catches a future
    /// regression where a label drifts into a sentence ("Click to clear
    /// the search field.") and overflows the announcement budget.
    func testAllLabelsAreShortAndUnpunctuated() {
        let labels = [
            A11yStrings.clearSearch,
            A11yStrings.markAllRead,
            A11yStrings.archiveRead,
        ]
        for label in labels {
            XCTAssertFalse(label.isEmpty, "\(label) must not be empty")
            XCTAssertLessThanOrEqual(label.count, 24,
                "\(label) must be ≤ 24 chars; VoiceOver announces it verbatim")
            XCTAssertFalse(label.hasSuffix("."),
                "\(label) must not end in a period — labels aren't sentences")
            XCTAssertFalse(label.hasSuffix("…"),
                "\(label) must not end in an ellipsis")
            let first = label.first!
            XCTAssertTrue(first.isUppercase,
                "\(label) must begin with an uppercase letter")
        }
    }

    /// Channel-filter label, active state — tap toggles the filter OFF,
    /// so the announcement is "Show all channels" regardless of which
    /// channel is currently filtered (the channel name is implicit in
    /// the visible Text element next to the row's ChannelDot).
    func testChannelFilterActiveLiteral() {
        XCTAssertEqual(
            A11yStrings.channelFilter(active: true, channelLabel: "Slack"),
            "Show all channels",
            "active state ignores the channel name — the user's intent is to clear the filter")
    }

    /// Channel-filter label, inactive state — tap turns the filter ON,
    /// so the announcement is "Filter <channelLabel>" verbatim.
    func testChannelFilterInactiveLiteral() {
        XCTAssertEqual(
            A11yStrings.channelFilter(active: false, channelLabel: "Slack"),
            "Filter Slack")
        XCTAssertEqual(
            A11yStrings.channelFilter(active: false, channelLabel: "Telegram"),
            "Filter Telegram")
        XCTAssertEqual(
            A11yStrings.channelFilter(active: false, channelLabel: "iMessage"),
            "Filter iMessage",
            "lowercase i in iMessage must NOT trigger a re-capitalization — channel name is taken verbatim")
    }

    /// `.help()` and `.accessibilityLabel()` MUST stay in lock-step —
    /// `SidebarView.channelRow` uses `A11yStrings.channelFilter` for
    /// both. Pin that the function is deterministic for identical
    /// inputs so a future "let's vary the tooltip" refactor surfaces here.
    func testChannelFilterIsDeterministic() {
        let labelA = A11yStrings.channelFilter(active: true, channelLabel: "Slack")
        let labelB = A11yStrings.channelFilter(active: true, channelLabel: "Slack")
        XCTAssertEqual(labelA, labelB,
            "function must be deterministic — drift here would desync .help() from .accessibilityLabel()")
    }
}
