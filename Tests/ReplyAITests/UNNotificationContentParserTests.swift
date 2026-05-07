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

    // MARK: - empty-string fallback semantics

    func testEmptyCKSenderIDFallsBackToSenderKey() {
        // CFNotificationCenter sometimes delivers CKSenderID as an empty
        // string rather than omitting it. The parser checks `!isEmpty`, so
        // the next-tier `sender` key must surface — not an empty handle.
        let content = makeContent(
            title: "Title",
            body: "body",
            userInfo: [
                "CKSenderID": "",
                "sender": "real-sender@example.com"
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertEqual(result?.senderHandle, "real-sender@example.com",
                       "empty CKSenderID must fall through to sender, not yield an empty handle")
    }

    func testEmptySenderFallsBackToTitle() {
        // Same isEmpty rule on the second tier — empty `sender` falls
        // through to `content.title`. Otherwise we'd publish an empty
        // sender handle to the inbox UI.
        let content = makeContent(
            title: "Real Title",
            body: "body",
            userInfo: ["sender": ""]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertEqual(result?.senderHandle, "Real Title")
    }

    func testEmptyCKChatIdentifierIsNotFalledBack() {
        // Behavior pin: the chatGUID resolution uses `??`, which only
        // triggers fallback on nil — not on empty string. So an empty-
        // string CKChatIdentifier currently produces an empty chatGUID
        // instead of falling through to CKChatGUID. If a future change
        // wants to treat empty as missing, this test will fail and force
        // a deliberate decision.
        let content = makeContent(
            title: "",
            body: "Test",
            userInfo: [
                "CKSenderID": "+15550000000",
                "CKChatIdentifier": "",
                "CKChatGUID": "iMessage;-;+15550000000"
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertEqual(result?.chatGUID, "",
                       "empty CKChatIdentifier currently wins over CKChatGUID — `??` falls back on nil only")
    }

    func testPreviewMatchesContentBodyVerbatim() {
        // Body is propagated as-is. No trimming, no normalisation —
        // important because the rule engine does substring matches on
        // the preview and any whitespace mutation here would silently
        // change rule semantics.
        let body = "  Hello  world  \n"
        let content = makeContent(
            title: "Sender",
            body: body,
            userInfo: [:]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertEqual(result?.preview, body,
                       "preview must equal content.body byte-for-byte — no trimming")
    }

    /// `userInfo` arrives as `[AnyHashable: Any]` from the OS — keys we treat
    /// as Strings (`CKSenderID`, `sender`, `CKChatIdentifier`, `CKChatGUID`)
    /// can hold non-String values when the source notification is malformed
    /// (e.g. a wrapper that posts NSNumber for a numeric handle, or NSNull).
    /// The parser's `as? String` cast must safely fail and fall through the
    /// resolution order, NOT crash and not surface the raw value via
    /// `String(describing:)`. Pin both the sender-key cascade and the
    /// chatGUID nil result for a non-String value.
    func testNonStringSenderValuesFallThroughResolutionOrder() {
        let content = makeContent(
            title: "TitleFallback",
            body: "msg",
            userInfo: [
                "CKSenderID": NSNumber(value: 15551234567),  // numeric handle, not String
                "sender":     NSNull()                       // explicit null, not String
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result, "non-String sender values must not crash; cascade lands on title")
        XCTAssertEqual(result?.senderHandle, "TitleFallback",
            "non-String CKSenderID + non-String sender must fall through to content.title")
    }

    func testNonStringChatIdentifierProducesNilChatGUID() {
        let content = makeContent(
            title: "Alice",
            body: "msg",
            userInfo: [
                "CKChatIdentifier": NSNumber(value: 42),  // not a String
                "CKChatGUID":       NSNull()              // not a String
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.chatGUID,
            "non-String chat identifiers must produce nil chatGUID, never `String(describing:)` of a number")
    }
}
