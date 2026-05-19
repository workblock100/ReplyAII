import XCTest
@testable import ReplyAICore

/// Pin the user-visible copy on `FDABanner` — the macOS Full Disk Access
/// permission prompt that appears above the inbox when chat.db is
/// unreachable. View 4 of 5 under REP-UI-STR-HOIST-001.
///
/// NOTE: `header` currently mentions iMessage, which is pivot-conflicted
/// per the 2026-04-23 channel-agnostic direction. The fix is structural
/// (gate the banner to only-show when iMessage is the active channel),
/// not a copy edit — until that gating ships, the literal stays as-is.
final class FDABannerStringsTests: XCTestCase {

    // MARK: - Frozen literals

    func testHeaderIsFrozen() {
        XCTAssertEqual(FDABanner.Strings.header,
                       "ReplyAI needs Full Disk Access to read iMessage",
            "FDA banner header must remain `ReplyAI needs Full Disk Access to read iMessage` — pivot-conflicted but kept until the banner-gating change ships; rewriting to `... to read your messages` without that gate would surface FDA copy to Slack-only users who don't need it")
    }

    func testOpenSystemSettingsLabelIsFrozen() {
        XCTAssertEqual(FDABanner.Strings.openSystemSettingsLabel,
                       "Open System Settings",
            "FDA primary CTA must remain `Open System Settings` — Apple's official term for the app; rephrasing to `Open Preferences` would be wrong on macOS 13+")
    }

    func testRetryLabelIsFrozen() {
        XCTAssertEqual(FDABanner.Strings.retryLabel, "Retry",
            "FDA secondary CTA must remain `Retry` — single word; expansion to `Try Again` doesn't fit the compact banner layout")
    }

    // MARK: - Shape invariants

    /// FDA banner sits in a horizontal stack at 30pt button height. The
    /// primary CTA needs to stay short enough to fit alongside the Retry
    /// button without the layout overflowing on a 720pt-wide inbox.
    func testCTALabelLengthInvariants() {
        XCTAssertLessThanOrEqual(FDABanner.Strings.openSystemSettingsLabel.count, 21,
            "Open System Settings (20 chars) must stay ≤ 21 chars to fit the 30pt-height button without truncation")
        XCTAssertLessThanOrEqual(FDABanner.Strings.retryLabel.count, 8,
            "Retry must stay ≤ 8 chars — single-word compact-CTA per the design system")
    }

    /// Neither CTA is a sentence, so neither should end with terminal
    /// punctuation. The header is a complete sentence but Apple's HIG
    /// drops the period on banner-style copy — confirmed against the
    /// design's reference.
    func testTerminalPunctuationInvariants() {
        XCTAssertFalse(FDABanner.Strings.header.hasSuffix("."),
            "banner header must not end with a period per Apple HIG for inline banner copy")
        XCTAssertFalse(FDABanner.Strings.openSystemSettingsLabel.hasSuffix("."),
            "primary CTA must not end with a period")
        XCTAssertFalse(FDABanner.Strings.retryLabel.hasSuffix("."),
            "secondary CTA must not end with a period")
    }
}
