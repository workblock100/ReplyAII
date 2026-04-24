import XCTest
import UserNotifications
@testable import ReplyAI

final class UNNotificationContentParserTests: XCTestCase {

    // MARK: - Helpers

    /// Build a UNMutableNotificationContent with the supplied userInfo and body/title.
    private func makeContent(
        title: String = "",
        body: String = "",
        userInfo: [String: Any] = [:]
    ) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        return content.copy() as! UNNotificationContent
    }

    // MARK: - REP-241: testFullPayloadParsesAllFields

    func testFullPayloadParsesAllFields() {
        let content = makeContent(
            title: "Alice",
            body: "Hey, what time is the meeting?",
            userInfo: [
                "CKSenderID": "+15551234567",
                "sender": "alice@example.com",
                "CKChatIdentifier": "iMessage;-;+15551234567"
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result)
        // CKSenderID takes priority over sender and title
        XCTAssertEqual(result?.senderHandle, "+15551234567")
        XCTAssertEqual(result?.preview, "Hey, what time is the meeting?")
        XCTAssertEqual(result?.chatGUID, "iMessage;-;+15551234567")
    }

    // MARK: - REP-241: testMissingCKSenderIDFallsBackToSenderKey

    func testMissingCKSenderIDFallsBackToSenderKey() {
        let content = makeContent(
            title: "Fallback Title",
            body: "See you tomorrow",
            userInfo: ["sender": "bob@example.com"]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.senderHandle, "bob@example.com",
            "Should fall back to 'sender' key when CKSenderID is absent")
        XCTAssertEqual(result?.preview, "See you tomorrow")
    }

    // MARK: - REP-241: testTitleFallbackWhenBothSenderKeysMissing

    func testTitleFallbackWhenBothSenderKeysMissing() {
        let content = makeContent(
            title: "Carol Smith",
            body: "Running a bit late",
            userInfo: [:]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.senderHandle, "Carol Smith",
            "Should fall back to content.title when both userInfo sender keys are absent")
    }

    // MARK: - REP-241: testBothSenderKeysMissingReturnsNil

    func testBothSenderKeysMissingReturnsNil() {
        // No userInfo keys and empty title — no sender recoverable.
        let content = makeContent(title: "", body: "Some body text", userInfo: [:])
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNil(result,
            "Should return nil when CKSenderID, sender, and title are all absent/empty")
    }

    // MARK: - REP-241: testChatGUIDPresentAndAbsent

    func testChatGUIDPresentInCKChatIdentifier() {
        let content = makeContent(
            title: "",
            body: "Test",
            userInfo: [
                "CKSenderID": "+15559876543",
                "CKChatIdentifier": "iMessage;+;chat9876543210"
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertEqual(result?.chatGUID, "iMessage;+;chat9876543210")
    }

    func testChatGUIDFallsBackToCKChatGUID() {
        let content = makeContent(
            title: "",
            body: "Test",
            userInfo: [
                "CKSenderID": "+15559876543",
                "CKChatGUID": "iMessage;-;+15559876543"
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertEqual(result?.chatGUID, "iMessage;-;+15559876543",
            "Should fall back to CKChatGUID when CKChatIdentifier is absent")
    }

    func testChatGUIDAbsentProducesNilField() {
        let content = makeContent(
            title: "",
            body: "Test",
            userInfo: ["CKSenderID": "+15550001111"]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.chatGUID,
            "chatGUID should be nil when neither CKChatIdentifier nor CKChatGUID is present")
    }
}
