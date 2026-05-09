import XCTest
@testable import ReplyAI

/// Pure-logic pins for `SetVoiceView`'s static copy + math helpers.
/// SwiftUI view rendering itself is not unit-testable in XCTest, but the
/// static helpers below all derive user-visible copy from the example
/// count — they're the only thing that distinguishes a working voice
/// profile UI from "Fine-tuned on 2,014 messages" prototype text. Every
/// pin here is a copy edit some future refactor could silently regress.
final class SetVoiceViewTests: XCTestCase {

    // MARK: headerCopy

    func testHeaderCopyZeroExamplesPromptsAction() {
        let copy = SetVoiceView.headerCopy(exampleCount: 0)
        XCTAssertTrue(copy.contains("Send a few replies"),
                      "zero state must invite the user to start sending — empty profile would otherwise look broken")
    }

    func testHeaderCopyOneExampleUsesSingular() {
        let copy = SetVoiceView.headerCopy(exampleCount: 1)
        XCTAssertTrue(copy.contains("1 message"),
                      "singular grammar — '1 messages' would look broken")
        XCTAssertFalse(copy.contains("1 messages"),
                       "no accidental plural")
    }

    func testHeaderCopyManyExamplesUsesPlural() {
        let copy = SetVoiceView.headerCopy(exampleCount: 7)
        XCTAssertTrue(copy.contains("7 messages"),
                      "plural grammar for >1 examples")
    }

    func testHeaderCopyNeverContainsStaticPrototypeNumber() {
        // The original prototype hardcoded "2,014" — a future refactor that
        // accidentally re-pastes the prototype string would break this pin.
        for n in [0, 1, 5, 20, 99] {
            let copy = SetVoiceView.headerCopy(exampleCount: n)
            XCTAssertFalse(copy.contains("2,014"),
                           "header must NOT contain the static '2,014' prototype number — regression to the unwired UI")
        }
    }

    // MARK: strengthPercent

    func testStrengthPercentZero() {
        XCTAssertEqual(SetVoiceView.strengthPercent(exampleCount: 0), 0)
    }

    func testStrengthPercentAtCap() {
        XCTAssertEqual(
            SetVoiceView.strengthPercent(exampleCount: PreferenceRange.maxVoiceExamples),
            100,
            "exactly at cap should read 100%")
    }

    func testStrengthPercentHalfway() {
        let half = PreferenceRange.maxVoiceExamples / 2
        let pct = SetVoiceView.strengthPercent(exampleCount: half)
        XCTAssertEqual(pct, 50,
            "with maxVoiceExamples = 20, 10 examples = 50%")
    }

    func testStrengthPercentClampsAboveCap() {
        // Defense-in-depth: if a future cap migration leaves ghost entries
        // above the cap, the gauge must still read 100% (not 110%).
        let over = PreferenceRange.maxVoiceExamples + 5
        XCTAssertEqual(SetVoiceView.strengthPercent(exampleCount: over), 100)
    }

    func testStrengthPercentClampsNegative() {
        // exampleCount can't realistically be negative, but guard against
        // a future call site that subtracts before passing in.
        XCTAssertEqual(SetVoiceView.strengthPercent(exampleCount: -3), 0)
    }

    // MARK: strengthHint

    func testStrengthHintZero() {
        let hint = SetVoiceView.strengthHint(exampleCount: 0)
        XCTAssertTrue(hint.contains("\(PreferenceRange.maxVoiceExamples)"),
                      "zero state should show how many sends remain to fill")
    }

    func testStrengthHintOneRemainingUsesSingular() {
        let almostFull = PreferenceRange.maxVoiceExamples - 1
        let hint = SetVoiceView.strengthHint(exampleCount: almostFull)
        XCTAssertTrue(hint.contains("1 more send"),
                      "singular: '1 more send' not '1 more sends'")
        XCTAssertFalse(hint.contains("1 more sends"))
    }

    func testStrengthHintAtCapMentionsFifo() {
        let hint = SetVoiceView.strengthHint(exampleCount: PreferenceRange.maxVoiceExamples)
        XCTAssertTrue(hint.localizedCaseInsensitiveContains("FIFO") ||
                      hint.localizedCaseInsensitiveContains("oldest"),
                      "at cap, user should understand new sends evict old ones, not block")
    }

    // MARK: examplePreview

    func testExamplePreviewKeepsShortStringAsIs() {
        let s = "See you Tuesday at the cafe"
        XCTAssertEqual(SetVoiceView.examplePreview(s, displayLength: 80), s)
    }

    func testExamplePreviewTrimsWhitespace() {
        let s = "  Sounds great!  "
        XCTAssertEqual(SetVoiceView.examplePreview(s, displayLength: 80),
                       "Sounds great!",
                       "preview must trim leading/trailing whitespace BEFORE length checks")
    }

    func testExamplePreviewTruncatesLongStrings() {
        let long = String(repeating: "a", count: 200)
        let preview = SetVoiceView.examplePreview(long, displayLength: 80)
        // 80 chars + "…" sentinel
        XCTAssertEqual(preview.count, 81)
        XCTAssertTrue(preview.hasSuffix("…"),
                      "truncated previews must end with ellipsis sentinel — otherwise the UI looks like a clipped sentence")
    }

    func testExamplePreviewHandlesEmpty() {
        XCTAssertEqual(SetVoiceView.examplePreview("", displayLength: 80), "")
    }
}
