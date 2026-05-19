import XCTest
@testable import ReplyAICore

/// Pin the user-visible copy on `ObDoneView` — the final onboarding
/// screen. Covers the default "ready" variant and the REP-259 Limited
/// Mode variant for users who skipped permissions. View 5 of 5 under
/// REP-UI-STR-HOIST-001; closes the success_criteria threshold.
final class ObDoneViewStringsTests: XCTestCase {

    // MARK: - Default-variant literals

    func testDefaultEyebrowIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.defaultEyebrow, "You're ready",
            "default eyebrow must remain `You're ready` — affirming, brand-aligned, no period")
    }

    func testDefaultTitleLeadIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.defaultTitleLead, "That's it.\n",
            "default title lead must remain `That's it.\\n` — period-terminated, newline before the italic tail")
    }

    func testDefaultTitleTailIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.defaultTitleTail, "Your inbox is waiting.",
            "default title tail must remain `Your inbox is waiting.`")
    }

    func testDefaultReadyDetailIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.defaultReadyDetail,
                       "Voice profile trained on 2,000 of your messages. 4 channels connected. 9 shortcuts in your fingers.",
            "default ready detail must remain three-sentence rhythm (voice / channels / shortcuts) — drift here loses the parallel-form cadence the design depends on")
    }

    func testDefaultCTAIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.defaultCTA, "Open ReplyAI",
            "default CTA must remain `Open ReplyAI` — verb + brand; matches the menu-bar `Open inbox` cadence")
    }

    func testDefaultSecondaryIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.defaultSecondary, "⌘⇧R works from anywhere now.",
            "default secondary must remain `⌘⇧R works from anywhere now.` — glyph-form shortcut, not the words")
    }

    // MARK: - Limited-variant literals

    func testLimitedEyebrowIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedEyebrow, "You're set up — for now",
            "limited eyebrow must remain `You're set up — for now` (em dash U+2014); softer counterpart to default's `You're ready`")
    }

    func testLimitedTitleLeadIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedTitleLead, "Try it on ",
            "limited title lead must remain `Try it on ` (trailing space) — concatenated with italic tail")
    }

    func testLimitedTitleTailIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedTitleTail, "demo conversations.",
            "limited title tail must remain `demo conversations.` — italicized in render via `serifItalic`")
    }

    func testLimitedReadyDetailIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedReadyDetail,
                       "You skipped some permissions, so ReplyAI will start in Limited Mode with sample threads. Grant access from Settings any time to see your real messages.",
            "limited ready detail must remain its two-sentence form (situation / remedy); drift here removes the explicit Settings-path the REP-259 spec calls for")
    }

    func testLimitedCTAIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedCTA, "Continue in Limited Mode",
            "limited CTA must remain `Continue in Limited Mode` — sentence-cased; matches the variant title's lowercase italic body")
    }

    func testLimitedSecondaryIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedSecondary, "You can grant permissions later in Settings.",
            "limited secondary must remain `You can grant permissions later in Settings.` — period-terminated reassurance")
    }

    // MARK: - Badge + TIP literals (hoisted in this fire)

    func testReadyBadgeIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.readyBadge, "READY",
            "default card badge must remain `READY` — uppercase, ≤ 8 chars, mono-spaced status-badge convention")
    }

    func testLimitedBadgeIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.limitedBadge, "LIMITED",
            "limited card badge must remain `LIMITED` — same shape as READY; rendered with Theme.Color.warn instead of accent so the degraded state reads at a glance")
    }

    func testTipBadgeIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.tipBadge, "TIP",
            "second-card eyebrow must remain `TIP` (uppercase, ≤ 8 chars)")
    }

    func testTipBodyIsFrozen() {
        XCTAssertEqual(ObDoneView.Strings.tipBody,
                       "Try it on one real reply first. The first time ⌘↵ sends what you would've typed, you'll feel it.",
            "TIP body must remain its two-sentence load-bearing onboarding sentence; `⌘↵` is glyph-form not `Command+Return`")
    }

    // MARK: - Shape invariants

    /// Status badges share an uppercase + length-cap shape so the row of
    /// (READY/LIMITED) + TIP cards stays visually balanced.
    func testBadgeShapeInvariants() {
        for badge in [ObDoneView.Strings.readyBadge,
                      ObDoneView.Strings.limitedBadge,
                      ObDoneView.Strings.tipBadge] {
            XCTAssertEqual(badge, badge.uppercased(),
                "card badge `\(badge)` must be uppercase to match the mono-spaced status-badge style")
            XCTAssertLessThanOrEqual(badge.count, 8,
                "card badge `\(badge)` must be ≤ 8 chars to fit the 20-pt card padding without wrapping")
        }
    }

    /// All long-form body strings on this screen end with a period.
    /// CTAs and badges do not.
    func testTerminalPunctuationInvariants() {
        for sentence in [ObDoneView.Strings.defaultReadyDetail,
                         ObDoneView.Strings.defaultSecondary,
                         ObDoneView.Strings.limitedReadyDetail,
                         ObDoneView.Strings.limitedSecondary,
                         ObDoneView.Strings.tipBody,
                         ObDoneView.Strings.defaultTitleTail,
                         ObDoneView.Strings.limitedTitleTail] {
            XCTAssertTrue(sentence.hasSuffix("."),
                "body string must end with a period: `\(sentence)`")
        }
        for label in [ObDoneView.Strings.defaultCTA,
                      ObDoneView.Strings.limitedCTA,
                      ObDoneView.Strings.defaultEyebrow,
                      ObDoneView.Strings.limitedEyebrow,
                      ObDoneView.Strings.readyBadge,
                      ObDoneView.Strings.limitedBadge,
                      ObDoneView.Strings.tipBadge] {
            XCTAssertFalse(label.hasSuffix("."),
                "label / CTA / badge must not end with a period: `\(label)`")
        }
    }
}
