import XCTest
@testable import ReplyAICore

/// Pin the user-visible strings for the Limited Mode banner (REP-259).
/// The banner is the entry point from the inbox into the "grant
/// permissions" flow, so copy drift here changes the user's path back
/// out of demo mode. Drift on `Strings.openCTA` in particular is
/// load-bearing — it's the only affordance pointing to Settings from
/// the inbox shell.
final class LimitedModeBannerStringsTests: XCTestCase {

    func testBannerTitleIsLimitedMode() {
        XCTAssertEqual(LimitedModeBanner.Strings.title, "You're in Limited Mode",
                       "Banner title drift changes how the user understands the demo-data state — must read like a status, not a warning")
    }

    func testBannerBodyExplainsDemoAndCTA() {
        XCTAssertEqual(LimitedModeBanner.Strings.body,
                       "These are demo conversations. Grant permissions to see your real messages.",
                       "Body must (1) explain that the threads are demo, (2) hint at the resolution path")
    }

    func testBannerOpenCTAIsOpenSettings() {
        XCTAssertEqual(LimitedModeBanner.Strings.openCTA, "Open Settings",
                       "Primary CTA must read 'Open Settings' — the System Settings deep-link target is the privacy pane")
    }

    func testBannerDismissHintIsDismiss() {
        XCTAssertEqual(LimitedModeBanner.Strings.dismissHint, "Dismiss",
                       "Dismiss accessibility label drives VoiceOver readout — must stay 'Dismiss' for parity with native banner patterns")
    }
}

/// Pin the user-visible strings for the Limited Mode variant of
/// `ObDoneView` (REP-259). The user sees these the first time they
/// finish onboarding without granting any channel permissions; the
/// copy needs to (a) acknowledge their state, (b) not panic them,
/// (c) point at the next action (Settings later, demo now).
final class ObDoneViewLimitedModeStringsTests: XCTestCase {

    func testLimitedEyebrowSetsExpectation() {
        XCTAssertEqual(ObDoneView.Strings.limitedEyebrow, "You're set up — for now",
                       "Eyebrow must convey both 'completed' (good) and 'partial' (with a path forward)")
    }

    func testLimitedCTAOffersContinueNotSetup() {
        XCTAssertEqual(ObDoneView.Strings.limitedCTA, "Continue in Limited Mode",
                       "CTA verb must be 'Continue' — the user already chose to skip permissions, so don't surface 'Set up' again here")
    }

    func testLimitedSecondaryHintsAtFutureUpgrade() {
        XCTAssertEqual(ObDoneView.Strings.limitedSecondary,
                       "You can grant permissions later in Settings.",
                       "Secondary line must reassure that the choice is reversible without re-running onboarding")
    }

    func testLimitedReadyDetailDoesNotClaimFalseSetup() {
        let detail = ObDoneView.Strings.limitedReadyDetail
        XCTAssertFalse(detail.contains("Voice profile trained"),
                       "Limited-mode detail must not claim a trained voice profile — that copy lives on the default-mode path only")
        XCTAssertFalse(detail.contains("4 channels connected"),
                       "Limited-mode detail must not claim channels connected — the whole point is the user skipped channel setup")
        XCTAssertTrue(detail.contains("Limited Mode") || detail.contains("sample threads") || detail.contains("Settings"),
                      "Limited-mode detail must mention Limited Mode / sample threads / Settings so the state is unambiguous")
    }
}
