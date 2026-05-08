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
                UNNotificationContentParser.UserInfoKey.ckSenderID: "+15551234567",
                UNNotificationContentParser.UserInfoKey.sender: "alice@example.com",
                UNNotificationContentParser.UserInfoKey.ckChatIdentifier: "iMessage;-;+15551234567"
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
            userInfo: [UNNotificationContentParser.UserInfoKey.sender: "bob@example.com"]
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
                UNNotificationContentParser.UserInfoKey.ckSenderID: "+15559876543",
                UNNotificationContentParser.UserInfoKey.ckChatIdentifier: "iMessage;+;chat9876543210"
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
                UNNotificationContentParser.UserInfoKey.ckSenderID: "+15559876543",
                UNNotificationContentParser.UserInfoKey.ckChatGUID: "iMessage;-;+15559876543"
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
            userInfo: [UNNotificationContentParser.UserInfoKey.ckSenderID: "+15550001111"]
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
                UNNotificationContentParser.UserInfoKey.ckSenderID: "",
                UNNotificationContentParser.UserInfoKey.sender: "real-sender@example.com"
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
            userInfo: [UNNotificationContentParser.UserInfoKey.sender: ""]
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
                UNNotificationContentParser.UserInfoKey.ckSenderID: "+15550000000",
                UNNotificationContentParser.UserInfoKey.ckChatIdentifier: "",
                UNNotificationContentParser.UserInfoKey.ckChatGUID: "iMessage;-;+15550000000"
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
                UNNotificationContentParser.UserInfoKey.ckSenderID: NSNumber(value: 15551234567),  // numeric handle, not String
                UNNotificationContentParser.UserInfoKey.sender:     NSNull()                       // explicit null, not String
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
                UNNotificationContentParser.UserInfoKey.ckChatIdentifier: NSNumber(value: 42),  // not a String
                UNNotificationContentParser.UserInfoKey.ckChatGUID:       NSNull()              // not a String
            ]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.chatGUID,
            "non-String chat identifiers must produce nil chatGUID, never `String(describing:)` of a number")
    }

    /// `UNNotificationContentParser.UserInfoKey.*` are the four iMessage /
    /// CallKit `userInfo` keys this parser AND the inline divergent path
    /// in `NotificationCoordinator.willPresent` resolve against. They were
    /// previously inline literals in both files. Drift on any key silently
    /// breaks that key's resolution leg without throwing — sender
    /// attribution falls through to `title`, chatGUID resolution returns
    /// nil and creates a duplicate thread per notification (instead of
    /// refreshing the existing thread). Pin the literal values so a
    /// "let's modernize the keys" edit lands in code review.
    func testUserInfoKeysAreFrozen() {
        XCTAssertEqual(UNNotificationContentParser.UserInfoKey.ckSenderID, "CKSenderID",
            "ckSenderID drift breaks the primary sender-handle resolution leg — sender attribution silently falls through to `content.title`")
        XCTAssertEqual(UNNotificationContentParser.UserInfoKey.sender, "sender",
            "sender drift breaks the fallback sender-handle resolution leg — older payloads with only `sender` set silently fall through to `content.title`")
        XCTAssertEqual(UNNotificationContentParser.UserInfoKey.ckChatIdentifier, "CKChatIdentifier",
            "ckChatIdentifier drift breaks chatGUID resolution — every notification creates a duplicate thread instead of refreshing the existing one")
        XCTAssertEqual(UNNotificationContentParser.UserInfoKey.ckChatGUID, "CKChatGUID",
            "ckChatGUID drift breaks the fallback chatGUID resolution leg — older payloads only carry `CKChatGUID` and would silently lose thread identity")
    }

    /// Pin that whitespace-only `content.title` is treated as a VALID
    /// sender handle (NOT filtered to the nil-return path), as long as
    /// it is non-empty by `String.isEmpty`. The parser checks
    /// `!content.title.isEmpty` — a single space passes, but a zero-
    /// length string falls through to nil. Surprising-but-safe: a
    /// malformed iMessage notification with `title: " "` (single space)
    /// and absent userInfo keys produces a thread whose senderHandle
    /// is `" "`, which then matches an existing whitespace-keyed
    /// thread or creates a fresh one. Drift toward
    /// `.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` would
    /// silently change the resolution: that single-space title would
    /// flip from "valid" to "fall through and return nil". The
    /// present-but-empty empty-string case (already pinned by
    /// `testEmptyCKSenderIDFallsBackToSenderKey` via the sender keys)
    /// matches the senderHandle/sender code path, but the
    /// title-fallback empty-string check has no separate test today.
    /// Pin both legs together so a future "trim before isEmpty"
    /// refactor surfaces here as a deliberate change.
    func testWhitespaceOnlyTitleIsTreatedAsValidSender() {
        let content = makeContent(
            title: " ",  // single ASCII space
            body: "body",
            userInfo: [:]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNotNil(result,
            "whitespace-only title is non-empty by `isEmpty`; parse should NOT return nil — drift toward `.trimmingCharacters(.whitespacesAndNewlines).isEmpty` would silently change this to nil")
        XCTAssertEqual(result?.senderHandle, " ",
            "whitespace-only title must round-trip verbatim as senderHandle — drift toward trimming would either drop the whitespace (changing thread keying) or produce an empty handle that bypasses the InboxViewModel handle-match path")
    }

    /// Pin that an exactly-empty `content.title` (zero-length string)
    /// AND absent sender keys causes `parse` to return nil. The body
    /// of the resolution-order chain is `else if !content.title.isEmpty`
    /// — drift toward `else if true` (always-true fallback) would
    /// produce a parsed result with `senderHandle = ""` for every
    /// malformed notification, silently bypassing the InboxViewModel's
    /// handle-match path. The current `testBothSenderKeysMissingReturnsNil`
    /// test sends `title: ""` together with absent keys, but doesn't
    /// pin the empty-title contract specifically (it asserts the
    /// negative result without distinguishing "title was empty" from
    /// "title path skipped"). Add an assertion that doubles down on
    /// the empty-title leg.
    func testExactlyEmptyTitleWithNoSenderKeysReturnsNil() {
        let content = makeContent(
            title: "",
            body: "body",
            userInfo: [:]
        )
        let result = UNNotificationContentParser.parse(content)
        XCTAssertNil(result,
            "empty title (zero-length) AND absent sender keys must return nil — drift toward `else { senderHandle = title }` (no isEmpty guard) would silently propagate empty handles into InboxViewModel")
        // Sanity contrast vs the whitespace-only case above: that one
        // returns a non-nil result, this one returns nil. Pinning both
        // sides of the empty-vs-whitespace distinction.
        let withSpace = makeContent(title: " ", body: "body", userInfo: [:])
        XCTAssertNotNil(UNNotificationContentParser.parse(withSpace),
            "control: a single-space title (non-empty by isEmpty) must not return nil — pinned by testWhitespaceOnlyTitleIsTreatedAsValidSender; mirrored here so both legs of the comparison live in one file")
    }
}
