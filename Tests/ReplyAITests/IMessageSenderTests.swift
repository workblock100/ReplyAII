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

    // MARK: - REP-158: chatGUID format for 1:1 vs group thread

    func testChatGUIDForOneToOneThreadSynthesized() {
        // 1:1 thread with no pre-populated chatGUID → synthesized from channel + id
        let t = MessageThread(
            id: "alice@example.com", channel: .imessage, name: "Alice",
            avatar: "A", preview: "", time: "",
            chatGUID: nil
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;-;alice@example.com",
                       "1:1 thread with nil chatGUID must synthesize iMessage;-;<id>")
    }

    func testChatGUIDForGroupThreadUsedVerbatim() {
        // Group thread with a pre-populated chatGUID → returned unchanged
        let t = MessageThread(
            id: "chat123", channel: .imessage, name: "Launch Crew",
            avatar: "L", preview: "", time: "",
            chatGUID: "iMessage;+;chat123"
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;+;chat123",
                       "group thread with non-nil chatGUID must return it verbatim without synthesis")
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

    // MARK: - Send timeout (REP-025)

    func testSendTimeoutReturnsError() {
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook = IMessageSender.executeHook
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
        }
        IMessageSender.sendTimeout = 0.1
        // Executor that outlasts the timeout window — simulates a hung Messages.app.
        IMessageSender.executeHook = { _ in Thread.sleep(forTimeInterval: 1.0) }

        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        let start = Date()
        XCTAssertThrowsError(try IMessageSender.send("hello", to: thread)) { error in
            guard let sendError = error as? IMessageSender.SendError,
                  case .timedOut = sendError else {
                XCTFail("Expected timedOut, got \(error)")
                return
            }
        }
        // Must resolve near the injected timeout, not block for the full 1 s.
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testNormalSendCompletesBeforeTimeout() {
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook = IMessageSender.executeHook
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
        }
        IMessageSender.sendTimeout = 1.0
        // Instant no-op executor — simulates a fast successful AppleScript send.
        IMessageSender.executeHook = { _ in /* success */ }

        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertNoThrow(try IMessageSender.send("hello", to: thread))
    }

    // MARK: - Dry-run hook (REP-093)

    func testDryRunHookReturnsSuccessWithoutScript() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertNoThrow(try IMessageSender.send("hello dry-run", to: thread))
    }

    func testCustomHookIsInvokedOnSend() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        var scriptExecuted = false
        IMessageSender.executeHook = { _ in scriptExecuted = true }

        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertNoThrow(try IMessageSender.send("hello live", to: thread))
        XCTAssertTrue(scriptExecuted, "custom executeHook must be invoked on send")
    }

    // MARK: - Message length guard (REP-064)

    func testTooLongMessageReturnsError() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        var scriptExecuted = false
        IMessageSender.executeHook = { _ in scriptExecuted = true }

        let overLimit = String(repeating: "x", count: IMessageSender.maxMessageLength + 1)
        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertThrowsError(try IMessageSender.send(overLimit, to: thread)) { error in
            guard let sendError = error as? IMessageSender.SendError,
                  case .messageTooLong = sendError else {
                XCTFail("Expected messageTooLong, got \(error)")
                return
            }
        }
        XCTAssertFalse(scriptExecuted, "AppleScript must not execute when message exceeds limit")
    }

    func testExactLimitMessageProceeds() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        let atLimit = String(repeating: "a", count: IMessageSender.maxMessageLength)
        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        // Exactly at the limit must succeed (dryRunHook so no real AppleScript).
        XCTAssertNoThrow(try IMessageSender.send(atLimit, to: thread))
    }

    // MARK: - -1708 retry (REP-059)

    func testRetriableErrorSucceedsOnSecondAttempt() {
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook    = IMessageSender.executeHook
        let prevDelay   = IMessageSender.retryDelay
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
            IMessageSender.retryDelay  = prevDelay
        }
        IMessageSender.sendTimeout = 3.0
        IMessageSender.retryDelay  = 0   // no sleep in tests
        var callCount = 0
        // First call throws -1708; second call succeeds.
        IMessageSender.executeHook = { _ in
            callCount += 1
            if callCount == 1 {
                throw IMessageSender.SendError.scriptFailure("AppleScript error -1708: Event not handled")
            }
        }
        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertNoThrow(try IMessageSender.send("retry me", to: thread))
        XCTAssertEqual(callCount, 2, "executor must be invoked exactly twice on a -1708 retry")
    }

    // MARK: - REP-128: chatGUID format pre-flight validation

    func testValidOneToOneGUIDPasses() {
        XCTAssertTrue(IMessageSender.isValidChatGUID("iMessage;-;+15551234567"),
                      "valid 1:1 iMessage GUID must pass validation")
    }

    func testValidGroupGUIDPasses() {
        XCTAssertTrue(IMessageSender.isValidChatGUID("iMessage;+;chat1234567890"),
                      "valid group iMessage GUID must pass validation")
    }

    func testInvalidGUIDThrowsInvalid() {
        // Empty string is filtered by chatGUID(for:) — use an explicitly invalid GUID
        // so the validation inside sendRaw is exercised.
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        XCTAssertThrowsError(try IMessageSender.send("hello", to:
            MessageThread(id: "x", channel: .imessage, name: "X",
                          avatar: "X", preview: "", time: "", chatGUID: "INVALID_NO_SEPARATORS"))) { error in
            guard case IMessageSender.SendError.invalidChatGUID = error else {
                XCTFail("Expected invalidChatGUID, got \(error)"); return
            }
        }
    }

    func testEmptyGUIDIsValidationFailed() {
        XCTAssertFalse(IMessageSender.isValidChatGUID(""),
                       "empty string must fail GUID validation")
    }

    func testWrongPrefixThrowsInvalid() {
        XCTAssertFalse(IMessageSender.isValidChatGUID("SMS;-;4155551234"),
                       "SMS GUID must fail iMessage prefix check")
    }

    func testMissingSeparatorThrowsInvalid() {
        XCTAssertFalse(IMessageSender.isValidChatGUID("iMessageNoseparator"),
                       "GUID without semicolons must fail validation")
    }

    func testNonRetriableErrorFailsImmediately() {
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook = IMessageSender.executeHook
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
        }
        IMessageSender.sendTimeout = 3.0
        var callCount = 0
        // A non-retriable error (-1743 NotAuthorized) must not trigger a retry.
        IMessageSender.executeHook = { _ in
            callCount += 1
            throw IMessageSender.SendError.notAuthorized
        }
        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertThrowsError(try IMessageSender.send("no retry", to: thread)) { error in
            guard let sendError = error as? IMessageSender.SendError,
                  case .notAuthorized = sendError else {
                XCTFail("Expected notAuthorized, got \(error)")
                return
            }
        }
        XCTAssertEqual(callCount, 1, "non-retriable error must not trigger a second attempt")
    }

    // MARK: - REP-181: -1708 retry cap

    func testRetryCapReachedThrowsError() {
        // When every attempt throws -1708, the sender must eventually give up and
        // throw an error. The hook is called at most maxRetry+1 = 2 times.
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook    = IMessageSender.executeHook
        let prevDelay   = IMessageSender.retryDelay
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
            IMessageSender.retryDelay  = prevDelay
        }
        IMessageSender.sendTimeout = 3.0
        IMessageSender.retryDelay  = 0   // no sleep in tests
        var callCount = 0
        IMessageSender.executeHook = { _ in
            callCount += 1
            throw IMessageSender.SendError.scriptFailure("AppleScript error -1708: Event not handled")
        }
        let thread = MessageThread(
            id: "+15559876543", channel: .imessage, name: "RetryTest",
            avatar: "R", preview: "", time: "",
            chatGUID: "iMessage;-;+15559876543"
        )
        XCTAssertThrowsError(try IMessageSender.send("cap test", to: thread),
                             "all-failing -1708 hook must throw after retry cap is reached")
        XCTAssertLessThanOrEqual(callCount, 3,
            "hook must be called at most maxRetry+1 times, got \(callCount)")
        XCTAssertGreaterThanOrEqual(callCount, 1, "hook must be called at least once")
    }

    func testRetrySucceedsOnSecondAttempt() {
        // One -1708 failure then success: send must succeed and hook is called exactly twice.
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook    = IMessageSender.executeHook
        let prevDelay   = IMessageSender.retryDelay
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
            IMessageSender.retryDelay  = prevDelay
        }
        IMessageSender.sendTimeout = 3.0
        IMessageSender.retryDelay  = 0   // no sleep in tests
        var callCount = 0
        IMessageSender.executeHook = { _ in
            callCount += 1
            if callCount == 1 {
                throw IMessageSender.SendError.scriptFailure("AppleScript error -1708: Event not handled")
            }
        }
        let thread = MessageThread(
            id: "+15557654321", channel: .imessage, name: "RetryOK",
            avatar: "R", preview: "", time: "",
            chatGUID: "iMessage;-;+15557654321"
        )
        XCTAssertNoThrow(try IMessageSender.send("retry success", to: thread),
                         "single -1708 followed by success must not throw")
        XCTAssertEqual(callCount, 2, "hook must be called exactly twice: initial + one retry")
    }

    // MARK: - REP-269: retryDelay injectable

    func testRetryDelayZeroCompletesInstantly() {
        // With retryDelay=0, a -1708 retry cycle must complete well under 100ms.
        let prevTimeout = IMessageSender.sendTimeout
        let prevHook    = IMessageSender.executeHook
        let prevDelay   = IMessageSender.retryDelay
        defer {
            IMessageSender.sendTimeout = prevTimeout
            IMessageSender.executeHook = prevHook
            IMessageSender.retryDelay  = prevDelay
        }
        IMessageSender.sendTimeout = 3.0
        IMessageSender.retryDelay  = 0
        var callCount = 0
        IMessageSender.executeHook = { _ in
            callCount += 1
            if callCount == 1 {
                throw IMessageSender.SendError.scriptFailure("AppleScript error -1708: Event not handled")
            }
        }
        let thread = MessageThread(
            id: "+15550000001", channel: .imessage, name: "Speed",
            avatar: "S", preview: "", time: "",
            chatGUID: "iMessage;-;+15550000001"
        )
        let start = Date()
        XCTAssertNoThrow(try IMessageSender.send("fast retry", to: thread))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1,
                          "retryDelay=0 must not add wall-clock time (got \(elapsed)s)")
        XCTAssertEqual(callCount, 2, "hook must be called twice: initial attempt + one retry")
    }
}

// MARK: - REP-174: escapeForAppleScriptLiteral completeness

final class IMessageSenderEscapeTests: XCTestCase {

    func testDoubleQuoteEscapedInAppleScript() {
        let result = IMessageSender.escapeForAppleScriptLiteral(#"say "hi""#)
        // Input: say "hi"  →  Output: say \"hi\"
        XCTAssertEqual(result, #"say \"hi\""#,
                       "double-quote must be escaped to \\\" in the AppleScript literal")
    }

    func testNewlineEscapedInAppleScript() {
        let result = IMessageSender.escapeForAppleScriptLiteral("line one\nline two")
        XCTAssertEqual(result, "line one\\nline two",
                       "newline must become the two-char \\n literal so the tell block stays single-line")
        XCTAssertFalse(result.contains("\n"), "no literal newline must remain after escaping")
    }

    func testBackslashEscapedInAppleScript() {
        let result = IMessageSender.escapeForAppleScriptLiteral("path\\file")
        XCTAssertEqual(result, "path\\\\file",
                       "backslash must be doubled so it does not escape the following character in AppleScript")
    }

    func testEmojiPassesThroughUnchanged() {
        let input = "🐢 shell vibes"
        XCTAssertEqual(IMessageSender.escapeForAppleScriptLiteral(input), input,
                       "emoji must pass through escaping without modification")
    }

    // MARK: - REP-193: 4096-char boundary with multi-byte Unicode

    func testExactLimitWithEmoji() {
        // Swift String.count uses grapheme clusters. A 4096-emoji string has
        // .count == 4096 even though it is far more than 4096 bytes. The guard
        // must pass because it checks .count (grapheme clusters), not byte length.
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        // Each "😀" is one grapheme cluster; 4096 of them = .count == 4096.
        let emojiAtLimit = String(repeating: "😀", count: IMessageSender.maxMessageLength)
        XCTAssertEqual(emojiAtLimit.count, IMessageSender.maxMessageLength,
                       "precondition: emoji string must have exactly maxMessageLength grapheme clusters")

        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertNoThrow(try IMessageSender.send(emojiAtLimit, to: thread),
                         "4096-grapheme emoji string must not throw — limit is cluster-based not byte-based")
    }

    func testOneOverLimitWithEmojiThrows() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        let emojiOverLimit = String(repeating: "😀", count: IMessageSender.maxMessageLength + 1)
        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertThrowsError(try IMessageSender.send(emojiOverLimit, to: thread)) { error in
            guard let sendError = error as? IMessageSender.SendError,
                  case .messageTooLong = sendError else {
                XCTFail("Expected messageTooLong, got \(error)")
                return
            }
        }
    }

}

// MARK: - REP-210: combined newline + backslash escaping boundary cases

final class IMessageSenderCombinedEscapeTests: XCTestCase {

    // REP-210: a message containing both \n and \\ must have both escaped
    // correctly in the same pass.  Escaping is applied left-to-right:
    // first \\ → \\\\, then \n → \\n, so the two substitutions don't
    // interfere with each other.
    func testNewlineAndBackslashBothEscapedInAppleScript() {
        let input = "line one\nline two\nbackslash: \\"
        let result = IMessageSender.escapeForAppleScriptLiteral(input)
        XCTAssertEqual(result, "line one\\nline two\\nbackslash: \\\\",
                       "\\n must become \\\\n and \\\\ must become \\\\\\\\ in the same escape pass")
        XCTAssertFalse(result.contains("\n"),
                       "no literal newline must survive after escaping")
    }

    // Tab characters are legal in AppleScript string literals and must
    // pass through unchanged (escaping only touches \, " and \n).
    func testTabCharacterPassesThroughUnescaped() {
        let input = "column\there"
        let result = IMessageSender.escapeForAppleScriptLiteral(input)
        XCTAssertEqual(result, "column\there",
                       "tab is a legal AppleScript literal character and must not be escaped")
    }
}
