import XCTest
@testable import ReplyAICore

/// Pins the durable accessibility identifiers that UI automation targets.
/// These strings are not user-facing copy; changing them silently breaks
/// XCUITest selectors and any external smoke harness that drives the app.
final class ReplyAIUITestIDTests: XCTestCase {
    func testAppIdentifiersAreStable() {
        XCTAssertEqual(ReplyAIUITestID.App.openInboxButton, "replyai.app.prototype.open-inbox")
    }

    func testOnboardingIdentifiersAreStable() {
        XCTAssertEqual(ReplyAIUITestID.Onboarding.getStartedButton, "replyai.onboarding.get-started")
        XCTAssertEqual(
            ReplyAIUITestID.Onboarding.welcomeGateGetStartedButton,
            "replyai.onboarding.welcome-gate.get-started")
        XCTAssertEqual(ReplyAIUITestID.Onboarding.continueButton, "replyai.onboarding.permissions.continue")
        XCTAssertEqual(ReplyAIUITestID.Onboarding.skipButton, "replyai.onboarding.permissions.skip")
        XCTAssertEqual(
            ReplyAIUITestID.Onboarding.permissionButton("full-disk-access"),
            "replyai.onboarding.permissions.button.full-disk-access")
    }

    func testInboxIdentifiersAreStable() {
        XCTAssertEqual(ReplyAIUITestID.Inbox.composerEditor, "replyai.inbox.composer.editor")
        XCTAssertEqual(
            ReplyAIUITestID.Inbox.threadRow(id: "thread-123"),
            "replyai.inbox.thread-row.thread-123")
    }

    func testTonePillIdentifiersTrackToneRawValues() {
        XCTAssertEqual(ReplyAIUITestID.Inbox.tonePill(.warm), "replyai.inbox.tone-pill.warm")
        XCTAssertEqual(ReplyAIUITestID.Inbox.tonePill(.direct), "replyai.inbox.tone-pill.direct")
        XCTAssertEqual(ReplyAIUITestID.Inbox.tonePill(.playful), "replyai.inbox.tone-pill.playful")
    }

    func testIdentifiersDoNotContainWhitespace() {
        let identifiers = [
            ReplyAIUITestID.App.openInboxButton,
            ReplyAIUITestID.Onboarding.getStartedButton,
            ReplyAIUITestID.Onboarding.welcomeGateGetStartedButton,
            ReplyAIUITestID.Onboarding.continueButton,
            ReplyAIUITestID.Onboarding.skipButton,
            ReplyAIUITestID.Onboarding.permissionButton("accessibility"),
            ReplyAIUITestID.Inbox.composerEditor,
            ReplyAIUITestID.Inbox.threadRow(id: "demo-thread"),
            ReplyAIUITestID.Inbox.tonePill(.warm),
        ]

        for identifier in identifiers {
            XCTAssertFalse(identifier.contains(" "), "\(identifier) must be selector-safe")
            XCTAssertTrue(identifier.hasPrefix("replyai."), "\(identifier) must stay app-scoped")
        }
    }
}
