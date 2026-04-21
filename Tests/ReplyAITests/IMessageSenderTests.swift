import XCTest
@testable import ReplyAI

final class IMessageSenderTests: XCTestCase {
    // MARK: - GUID selection

    func testUsesChatGUIDWhenPresent_OneOnOne() {
        let t = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Pal",
            avatar: "P", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;-;+15551234567")
    }

    func testUsesChatGUIDForGroupThread() {
        // Group chats carry a `;+;` infix — only the DB knows the real
        // GUID. If the sender re-synthesizes with `;-;` the send will
        // silently fail or (worse) address the wrong recipient.
        let t = MessageThread(
            id: "chat1234567890", channel: .imessage, name: "Design Crit",
            avatar: "D", preview: "", time: "",
            chatGUID: "iMessage;+;chat1234567890"
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;+;chat1234567890")
    }

    func testFallsBackToSynthesized_NoGUID() {
        // Legacy rows without chat.guid — synthesize for 1:1 form. Only
        // works for 1:1 chats; group sends without a GUID would error
        // from Messages.app but our API surface doesn't block them.
        let t = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Pal",
            avatar: "P", preview: "", time: "",
            chatGUID: nil
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;-;+15551234567")
    }

    func testFallsBackToSMSService_WhenChannelIsSMS() {
        let t = MessageThread(
            id: "+15551234567", channel: .sms, name: "Number",
            avatar: "N", preview: "", time: "",
            chatGUID: nil
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "SMS;-;+15551234567")
    }

    func testEmptyChatGUIDStringTreatedAsNil() {
        // COALESCE(c.guid, '') in IMessageChannel can surface "" for
        // freak rows; the sender should ignore empties and synthesize.
        let t = MessageThread(
            id: "handle", channel: .imessage, name: "X",
            avatar: "X", preview: "", time: "",
            chatGUID: ""
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;-;handle")
    }

    // MARK: - AppleScript literal escaping (REP-006)

    // Count unescaped double-quotes: a `"` not immediately preceded by `\`.
    private func unescapedQuoteCount(_ s: String) -> Int {
        var count = 0
        var prevWasBackslash = false
        for ch in s {
            if ch == "\"" && !prevWasBackslash { count += 1 }
            prevWasBackslash = (ch == "\\") && !prevWasBackslash
        }
        return count
    }

    private func assertSafe(_ input: String, file: StaticString = #file, line: UInt = #line) {
        let output = IMessageSender.escapeForAppleScriptLiteral(input)
        XCTAssertEqual(
            unescapedQuoteCount(output), 0,
            "unescaped \" in output for input \(input.debugDescription)",
            file: file, line: line
        )
        // A trailing odd backslash would escape the closing `"` in the script.
        var backslashCount = 0
        for ch in output.reversed() {
            guard ch == "\\" else { break }
            backslashCount += 1
        }
        XCTAssertEqual(
            backslashCount % 2, 0,
            "output ends with odd backslash for input \(input.debugDescription)",
            file: file, line: line
        )
    }

    func testEscapePlainTextUnchanged() {
        XCTAssertEqual(IMessageSender.escapeForAppleScriptLiteral("hello"), "hello")
    }

    func testEscapeEmptyString() {
        XCTAssertEqual(IMessageSender.escapeForAppleScriptLiteral(""), "")
    }

    func testEscapeDoubleQuote() {
        let result = IMessageSender.escapeForAppleScriptLiteral("say \"hi\"")
        XCTAssertEqual(result, #"say \"hi\""#)
        assertSafe("say \"hi\"")
    }

    func testEscapeBackslash() {
        let result = IMessageSender.escapeForAppleScriptLiteral("path\\file")
        XCTAssertEqual(result, "path\\\\file")
        assertSafe("path\\file")
    }

    func testEscapeBackslashBeforeQuote() {
        // Input \" must become \\\" (escaped backslash then escaped quote).
        let input = "\\\""
        assertSafe(input)
        let result = IMessageSender.escapeForAppleScriptLiteral(input)
        XCTAssertEqual(result, "\\\\\\\"")
    }

    func testEscapeBackticksUnchanged() {
        // Backticks are not special in AppleScript string literals.
        let input = "run `cmd`"
        XCTAssertEqual(IMessageSender.escapeForAppleScriptLiteral(input), input)
        assertSafe(input)
    }

    func testEscapeShellInterpolationAttempt() {
        let input = "$(rm -rf ~)"
        assertSafe(input)
        XCTAssertEqual(IMessageSender.escapeForAppleScriptLiteral(input), input)
    }

    func testEscapeNewlineInMessage() {
        assertSafe("line one\nline two")
    }

    func testEscapeNullByte() {
        assertSafe("before\0after")
    }

    func testEscapeZeroWidthChars() {
        assertSafe("hello\u{200B}\u{FEFF}world")
    }

    func testEscapeEmojiZWJSequence() {
        assertSafe("👨‍👩‍👧‍👦 check this")
    }

    func testEscapeMixedScripts() {
        assertSafe("مرحباً — こんにちは — héllo — \"quoted\"")
    }

    func testEscapeVeryLongString() {
        // 10 000 chars of alternating quotes and backslashes — worst-case expansion.
        let input = String(repeating: "\"\\", count: 5_000)
        assertSafe(input)
    }

    func testEscapeMultipleConsecutiveQuotes() {
        let input = "\"\"\"triple\"\"\""
        assertSafe(input)
        XCTAssertEqual(
            IMessageSender.escapeForAppleScriptLiteral(input),
            "\\\"\\\"\\\"triple\\\"\\\"\\\""
        )
    }

    func testEscapeControlCharacters() {
        assertSafe("tab:\there\r\n\u{07}bell")
    }
}
