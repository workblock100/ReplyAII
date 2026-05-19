import XCTest
@testable import ReplyAICore

/// Pin the user-visible copy on `WelcomeGate` — the first screen every new
/// user sees. View 3 of 5 under REP-UI-STR-HOIST-001. The hero subtitle
/// is the product's brand promise, so a copy edit there should land in
/// PR review with a named test rather than as a silent SwiftUI-body diff.
final class WelcomeGateStringsTests: XCTestCase {

    // MARK: - Frozen literals

    func testHeroTitleIsFrozen() {
        XCTAssertEqual(WelcomeGate.Strings.heroTitle, "Welcome to ReplyAI",
            "hero title must remain `Welcome to ReplyAI` — three words, brand-name terminal; rephrasing to `Hello`, `Hi there`, etc. drops the brand from the first impression")
    }

    func testHeroSubtitleIsFrozen() {
        XCTAssertEqual(WelcomeGate.Strings.heroSubtitle,
                       "A unified, keyboard-first inbox for every channel you message in. Drafts in your voice, on-device. Your messages never leave this Mac.",
            "hero subtitle is the brand promise — three sentences (scope, control surface, trust). Drift here means a marketing copy edit landed without review; restore the original literal or update this test deliberately")
    }

    func testFooterSettingsHintIsFrozen() {
        XCTAssertEqual(WelcomeGate.Strings.footerSettingsHint,
                       "You can revisit any of this in Settings later.",
            "footer reassurance must remain `You can revisit any of this in Settings later.` — period-terminated; signals that this screen isn't a forced-decision gate")
    }

    func testGetStartedLabelIsFrozen() {
        XCTAssertEqual(WelcomeGate.Strings.getStartedLabel, "Get started",
            "primary CTA must remain `Get started` — sentence case, two words; matches the rest of the onboarding flow's CTA grammar")
    }

    // MARK: - Shape invariants

    /// The hero subtitle is intentionally three sentences. Pinning the
    /// sentence count catches an over-zealous edit that consolidates them
    /// into one (loses the rhythm) or splits them into more.
    func testHeroSubtitleHasThreeSentences() {
        let sentences = WelcomeGate.Strings.heroSubtitle
            .components(separatedBy: ". ")
            .filter { !$0.isEmpty }
        XCTAssertEqual(sentences.count, 3,
            "hero subtitle must remain three sentences for cadence; got \(sentences.count)")
    }

    /// The hero subtitle wraps inside a 1180-pt min-width window's hero
    /// block (which uses 64-pt horizontal padding, leaving ~1052pt for
    /// the text column). Inter Tight at 14pt averages ~6.5 chars/inch ≈
    /// 220 chars per line; this subtitle is 175 chars so it fits within
    /// one to two lines depending on font metrics. Cap at 220 to flag
    /// any future edit that would push it to three lines.
    func testHeroSubtitleFitsTwoLines() {
        XCTAssertLessThanOrEqual(WelcomeGate.Strings.heroSubtitle.count, 220,
            "hero subtitle must stay ≤ 220 chars to render in two lines max")
    }

    /// All terminal-punctuation strings on this screen end with a period.
    /// The CTA does not — buttons aren't sentences.
    func testTerminalPunctuationInvariants() {
        XCTAssertTrue(WelcomeGate.Strings.heroSubtitle.hasSuffix("."),
            "hero subtitle must end with a period")
        XCTAssertTrue(WelcomeGate.Strings.footerSettingsHint.hasSuffix("."),
            "footer hint must end with a period")
        XCTAssertFalse(WelcomeGate.Strings.heroTitle.hasSuffix("."),
            "hero title must not end with a period — it's a greeting, not a sentence")
        XCTAssertFalse(WelcomeGate.Strings.getStartedLabel.hasSuffix("."),
            "CTA button label must not end with a period")
    }
}
