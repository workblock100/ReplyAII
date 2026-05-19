import XCTest
@testable import ReplyAICore

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

    /// Edge: thread with BOTH empty chatGUID AND empty id synthesizes
    /// `"iMessage;-;"` which `validateChatGUID` rejects (parts[2] is
    /// empty), so the send fails fast with `.invalidChatGUID` rather
    /// than firing a malformed AppleScript at Messages.app. Same shape
    /// as the legacy by-identifier empty-id pin — different code path.
    func testChatGUIDForThreadWithBothFieldsEmpty() {
        let t = MessageThread(
            id: "", channel: .imessage, name: "?",
            avatar: "?", preview: "", time: "",
            chatGUID: nil
        )
        // Synthesis still runs (no defensive empty guard at this layer);
        // the validation that catches the resulting empty parts[2] lives
        // in sendRaw → validateChatGUID, which the next assertion exercises.
        XCTAssertEqual(IMessageSender.chatGUID(for: t), "iMessage;-;",
            "synthesis falls through verbatim — empty id appears as empty parts[2]")

        // And the send path rejects it before AppleScript runs.
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        XCTAssertThrowsError(try IMessageSender.send("hi", to: t)) { err in
            guard case IMessageSender.SendError.invalidChatGUID = err else {
                return XCTFail("expected .invalidChatGUID, got \(err)")
            }
        }
    }

    /// Pin: `chatGUID(for:)` synthesis falls back to the `iMessage`
    /// service prefix for every non-SMS channel. The synthesized
    /// string is intentionally still iMessage-shaped for Slack /
    /// Teams / WhatsApp / Telegram threads (since none of those
    /// channels go through `IMessageSender` to send) — but
    /// `validateChatGUID(_:for:)` then refuses to send through the
    /// AppleScript path. Pinning the synthesis output here means a
    /// future "let's also handle Slack here" refactor can't silently
    /// flip the prefix to "Slack;-;..." (which would still fail
    /// validation but produce a different invalid-GUID error string)
    /// without surfacing in CI.
    func testChatGUIDSynthesisPrefixIsIMessageForNonSMSChannels() {
        for channel in [Channel.slack, .teams, .whatsapp, .telegram] {
            let t = MessageThread(
                id: "abc",
                channel: channel,
                name: "X",
                avatar: "X",
                preview: "",
                time: "",
                chatGUID: nil
            )
            XCTAssertEqual(
                IMessageSender.chatGUID(for: t),
                "iMessage;-;abc",
                "synthesis for \(channel.rawValue) must keep the iMessage prefix; non-iMessage channels never reach the AppleScript send path so this is the documented fallback shape (validateChatGUID then rejects it)"
            )
        }
    }

    /// Pin: the SMS branch of `chatGUID(for:)`. When `thread.channel ==
    /// .sms` and `chatGUID` is nil/empty, synthesis routes through
    /// `Self.smsServiceID` ("SMS"), NOT the iMessage fallback. The
    /// existing testChatGUIDSynthesisPrefixIsIMessageForNonSMSChannels
    /// covers the four non-iMessage non-SMS channels, but skips the
    /// SMS leg because the production code intentionally treats SMS
    /// differently. The legacy `send(_:toChatIdentifier:channel:)` path
    /// has its own SMS pin (search "SMS;-;+15551234567") but that's a
    /// different code path. Pin the `chatGUID(for: thread)` SMS-branch
    /// synthesis explicitly so a future "merge SMS into iMessage
    /// fallback" refactor surfaces here as a deliberate edit.
    func testChatGUIDSynthesisPrefixIsSMSForSMSChannelWhenGUIDAbsent() {
        let smsThread = MessageThread(
            id: "+15551234567", channel: .sms, name: "Phone",
            avatar: "P", preview: "", time: "", chatGUID: nil
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: smsThread),
            "SMS;-;+15551234567",
            "SMS-channel synthesis must use the `SMS;-;` prefix, not the iMessage fallback — drift would silently mis-address the AppleScript send to the wrong service"
        )

        // Sibling: empty-string chatGUID also routes through the SMS
        // branch (filtered by `!guid.isEmpty`).
        let smsThreadEmpty = MessageThread(
            id: "+15559998888", channel: .sms, name: "Phone",
            avatar: "P", preview: "", time: "", chatGUID: ""
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: smsThreadEmpty),
            "SMS;-;+15559998888",
            "empty chatGUID on an SMS channel must still pick the SMS prefix — the channel decides the prefix, not the (filtered) chatGUID"
        )
    }

    /// Pin that `chatGUID(for:)` returns the thread's stored chatGUID
    /// VERBATIM when present, regardless of whether the GUID's service
    /// prefix matches the thread's channel. Realistic scenario: chat.db
    /// emits `iMessage;-;+15551234567` for a chat that the inbox classifies
    /// as `.sms` (e.g. SMS-relay where chat.service_name disagrees with
    /// our channel mapping), or vice versa. The non-synthesis path does
    /// NOT rewrite the prefix to match the channel — the stored GUID
    /// wins. Drift toward "let's coerce the prefix to the channel's
    /// service to be safe" would silently route AppleScript sends through
    /// the wrong Messages.app service for every chat.db row whose
    /// channel-classification disagreed with its service_name. Pin both
    /// directions of mismatch so a future channel-prefix-coercion
    /// refactor surfaces here.
    func testChatGUIDForReturnsStoredGUIDVerbatimRegardlessOfChannelPrefixMismatch() {
        // SMS thread with an iMessage-shaped GUID — verbatim, no rewrite.
        let smsThreadWithIMessageGUID = MessageThread(
            id: "+15551234567", channel: .sms, name: "Phone",
            avatar: "P", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: smsThreadWithIMessageGUID),
            "iMessage;-;+15551234567",
            "stored chatGUID must round-trip verbatim regardless of channel — coercing the prefix to the channel's service would silently route AppleScript sends through the wrong Messages.app service for chat.db rows whose service_name disagreed with our channel mapping"
        )

        // iMessage thread with an SMS-shaped GUID — same verbatim policy.
        let imessageThreadWithSMSGUID = MessageThread(
            id: "+15558881111", channel: .imessage, name: "Phone",
            avatar: "P", preview: "", time: "",
            chatGUID: "SMS;-;+15558881111"
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: imessageThreadWithSMSGUID),
            "SMS;-;+15558881111",
            "iMessage-channel thread with an SMS-shaped stored chatGUID must also round-trip verbatim — the thread.channel is NOT the source of truth for the GUID prefix when the GUID is non-nil"
        )
    }

    /// 2026-05-19 regression: chat.db on modern macOS surfaces 3-field
    /// GUIDs with non-iMessage/SMS service prefixes on short codes and
    /// merged-canonical rows (`any;-;29196`, hypothetically `RCS;-;<id>`,
    /// etc.). Messages.app's AppleScript `send` verb rejects those
    /// prefixes with `Invalid chat GUID 'any;-;29196': must match
    /// iMessage;[+-];<identifier>.` Discovered when Elijah tried to
    /// reply to a short code (5-digit SMS sender 29196) and got the
    /// validation error toast instead of an actual send.
    ///
    /// Fix: `chatGUID(for:)` now drops chat.db GUIDs whose service prefix
    /// isn't a known one (`iMessage` / `SMS`) and synthesizes from
    /// `thread.channel + thread.id` instead — same path used when chat.db
    /// returns no GUID at all. The pin asserts the new shape produces a
    /// valid GUID that round-trips through `validateChatGUID`.
    func testUnknownServicePrefixSynthesizesFromChannelAndID() {
        // The exact case Elijah hit — short code "29196" on .sms.
        let smsShortCode = MessageThread(
            id: "29196", channel: .sms, name: "29196",
            avatar: "2", preview: "", time: "",
            chatGUID: "any;-;29196"   // chat.db's weird short-code shape
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: smsShortCode),
            "SMS;-;29196",
            "any-prefix GUID on a .sms thread must synthesize to SMS;-;<id> — preserving the chat.db GUID verbatim would surface the Invalid chat GUID validation error Elijah hit on 2026-05-19"
        )
        XCTAssertNoThrow(
            try IMessageSender.validateChatGUID("SMS;-;29196", for: .sms),
            "synthesized GUID must pass the same validation Messages.app expects"
        )

        // Same shape, .imessage channel — synthesizes with iMessage prefix.
        let imessageWeird = MessageThread(
            id: "abc123", channel: .imessage, name: "Weird Row",
            avatar: "W", preview: "", time: "",
            chatGUID: "rcs;-;abc123"   // hypothetical RCS row
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: imessageWeird),
            "iMessage;-;abc123",
            "non-iMessage/SMS prefix on a .imessage thread must synthesize with iMessage prefix"
        )

        // Boundary: a partial 2-field GUID is malformed and should pass
        // through verbatim (failing validation downstream), NOT silently
        // synthesize — that would mask a real chat.db corruption.
        let partialGUID = MessageThread(
            id: "handle", channel: .imessage, name: "X",
            avatar: "X", preview: "", time: "",
            chatGUID: "any;29196"   // missing the middle field
        )
        XCTAssertEqual(
            IMessageSender.chatGUID(for: partialGUID),
            "any;29196",
            "malformed 2-field GUID must pass verbatim — only well-formed (3-field) GUIDs with unknown service prefixes synthesize"
        )
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

    /// Pin that a whitespace-only `thread.chatGUID` is treated as
    /// PRESENT (not nil) by `chatGUID(for:)`'s `!guid.isEmpty` check —
    /// a single space passes through verbatim into the sender path,
    /// then fails `validateChatGUID` because `" ".split(separator: ";")
    /// .count == 1`. Surprising-but-safe: a malformed or hostile
    /// chat.db row with a whitespace-only chatGUID surfaces a clear
    /// `invalidChatGUID(" ")` error instead of silently synthesizing
    /// a 1:1 GUID from the (probably-incorrect) thread.id. Drift
    /// toward `(guid?.isEmpty == false && guid.trimmingCharacters(...)
    /// .isEmpty == false)` would silently flip whitespace-only into
    /// the synthesis path, where the synthesized GUID `iMessage;-;
    /// <thread.id>` would be sent against — but that's only correct if
    /// thread.id IS the right route, which for a row with a malformed
    /// chatGUID is exactly the thing in doubt. Pin the surfacing-as-
    /// validation-error contract so a future "isEmpty also rejects
    /// whitespace" refactor lands deliberately. This pin sits next to
    /// `testEmptyChatGUIDStringTreatedAsNil` (which pins the OPPOSITE
    /// shape — empty string DOES route to synthesis) so the two
    /// boundary cases live together.
    func testWhitespaceOnlyChatGUIDPassesThroughVerbatimNotSynthesized() {
        let t = MessageThread(
            id: "handle", channel: .imessage, name: "X",
            avatar: "X", preview: "", time: "",
            chatGUID: " "  // single ASCII space — non-empty but malformed
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: t), " ",
            "whitespace-only chatGUID must pass through verbatim — drift toward `.trimmingCharacters().isEmpty` would silently route to the synthesis path, where the synthesized GUID would target whatever thread.id happens to be (potentially the wrong route)")
        // Sanity contrast: empty string DOES route to synthesis.
        let empty = MessageThread(
            id: "handle", channel: .imessage, name: "X",
            avatar: "X", preview: "", time: "",
            chatGUID: ""
        )
        XCTAssertEqual(IMessageSender.chatGUID(for: empty), "iMessage;-;handle",
            "control: empty chatGUID still synthesizes — pinning whitespace-only and empty together makes the boundary explicit")
        // The whitespace-only case fails validation, so a real send() call would throw.
        XCTAssertThrowsError(try IMessageSender.validateChatGUID(" ", for: .imessage)) { err in
            guard case IMessageSender.SendError.invalidChatGUID(let guid) = err else {
                return XCTFail("expected invalidChatGUID, got: \(err)")
            }
            XCTAssertEqual(guid, " ",
                "the surfaced invalidChatGUID payload must be the offending whitespace verbatim — pin so a future trim-before-validate refactor is visible at the error site, not just at the chatGUID(for:) site")
        }
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

    // MARK: - REP-128: chatGUID format pre-flight validation (migrated to validateChatGUID)

    func testValidOneToOneGUIDPasses() {
        XCTAssertNoThrow(try IMessageSender.validateChatGUID("iMessage;-;+15551234567", for: .imessage),
                         "valid 1:1 iMessage GUID must pass validation")
    }

    func testValidGroupGUIDPasses() {
        XCTAssertNoThrow(try IMessageSender.validateChatGUID("iMessage;+;chat1234567890", for: .imessage),
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
        XCTAssertThrowsError(try IMessageSender.validateChatGUID("", for: .imessage),
                             "empty string must fail GUID validation")
    }

    func testWrongPrefixThrowsInvalid() {
        // SMS GUID is not valid for the iMessage channel.
        XCTAssertThrowsError(try IMessageSender.validateChatGUID("SMS;-;4155551234", for: .imessage),
                             "SMS GUID must fail iMessage prefix check")
    }

    func testMissingSeparatorThrowsInvalid() {
        XCTAssertThrowsError(try IMessageSender.validateChatGUID("iMessageNoseparator", for: .imessage),
                             "GUID without semicolons must fail validation")
    }

    /// `split(separator:";", maxSplits: 3, omittingEmptySubsequences: false)`
    /// can return up to 4 parts. The validator's `parts.count == 3` check
    /// must reject 4-part GUIDs (an extra `;<chunk>` slipped in by a
    /// malformed AppleScript fixture or a future iMessage schema bump). Pin
    /// so a future loosening to `>= 3` is a deliberate change.
    func testExtraSeparatorThrowsInvalid() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;-;+15551234567;extra", for: .imessage),
            "4-part GUID (extra trailing `;<chunk>`) must fail the strict 3-part validator")
    }

    /// The prefix check (`parts[0] == "iMessage"`) is case-sensitive: lowercase
    /// `"imessage"` or `"IMESSAGE"` must fail. iMessage's own AppleScript dictionary
    /// emits camelCase verbatim, so a different case implies a corrupted source.
    /// Pin so a future "lowercase normalize" refactor surfaces rather than silently
    /// widening the accepted set.
    func testIMessagePrefixIsCaseSensitive() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("imessage;-;+15551234567", for: .imessage),
            "lowercase `imessage` prefix must fail — chat.db emits camelCase `iMessage` verbatim")
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("IMESSAGE;-;+15551234567", for: .imessage),
            "uppercase `IMESSAGE` prefix must fail")
    }

    // MARK: - REP-162: cross-channel GUID validation

    func testSMSGUIDFormatRecognized() {
        // Well-formed SMS GUIDs must pass SMS channel validation.
        XCTAssertNoThrow(try IMessageSender.validateChatGUID("SMS;-;+14155551234", for: .sms),
                         "well-formed SMS;-;<identifier> must pass SMS channel validation")
        XCTAssertNoThrow(try IMessageSender.validateChatGUID("SMS;+;groupChat99", for: .sms),
                         "well-formed SMS;+;<identifier> must pass SMS channel validation")
    }

    func testWrongChannelGUIDThrows() {
        // An iMessage GUID is not valid for the Slack channel.
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;-;+15551234567", for: .slack),
            "iMessage GUID must throw invalidChatGUID when validated against .slack channel"
        ) { error in
            guard case IMessageSender.SendError.invalidChatGUID = error else {
                XCTFail("Expected invalidChatGUID, got \(error)"); return
            }
        }
    }

    /// Trailing-semicolon GUID: `"iMessage;-;"` splits with
    /// `omittingEmptySubsequences: false` into three parts where the
    /// final element is empty. The validator's `!parts[2].isEmpty`
    /// guard rejects it. Pin so a future "trim trailing separators"
    /// shortcut doesn't quietly accept a chat-id-less GUID that
    /// AppleScript would then fail on with errAEEventNotHandled.
    func testTrailingSemicolonGUIDFailsValidation() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;-;", for: .imessage),
            "trailing-semicolon GUID has empty chat-id; must fail the !parts[2].isEmpty guard")
    }

    /// Empty middle separator: `"iMessage;;chat"` splits to three parts
    /// where `parts[1] == ""` — neither "+" nor "-", so validation
    /// fails. Pin because a future "tolerate any non-empty middle"
    /// loosening would silently accept this corrupted shape and route
    /// it to AppleScript with no useful error.
    func testEmptyMiddleSeparatorFailsValidation() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;;+15551234567", for: .imessage),
            "empty middle separator (`iMessage;;…`) must fail — only `+` or `-` are accepted there")
    }

    /// Invalid middle separator: `"iMessage;X;chat"` has the right
    /// shape but `parts[1] == "X"`, not `+` or `-`. The validator's
    /// strict `parts[1] == "+" || parts[1] == "-"` clause rejects it.
    /// Pin the closed set against a future "any single character"
    /// widening; chat.db only ever emits + or - here.
    func testNonPlusOrMinusSeparatorFailsValidation() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;X;+15551234567", for: .imessage),
            "middle separator must be exactly `+` or `-`; `X` is not a valid alternative")
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;~;+15551234567", for: .imessage),
            "middle separator `~` must also fail — closed set of `+`/`-` only")
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;0;+15551234567", for: .imessage),
            "digit `0` as middle separator must fail — closed set, not `\\d`")
    }

    /// Whitespace-padded middle separator like `"+ "` (plus + space).
    /// `split` preserves the trailing space, so `parts[1] == "+ "`
    /// (length 2) fails the literal `==` check. Pin so a future
    /// relaxation that trims whitespace from the middle component
    /// (well-meaning, chat.db never emits this) doesn't silently widen
    /// the accepted set.
    func testWhitespacePaddedMiddleSeparatorFailsValidation() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage;+ ;chat1", for: .imessage),
            "middle separator with trailing space (`+ `) must fail — no trim happens, literal == check")
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("iMessage; -;chat1", for: .imessage),
            "middle separator with leading space (` -`) must also fail")
    }

    /// Non-iMessage / non-SMS channels currently have no GUID write path —
    /// the validator's `default:` arm throws unconditionally so that a
    /// future caller who reuses GUID-based send routing for WhatsApp /
    /// Teams / Telegram has to wire per-channel format rules first. Pin
    /// the contract for each currently-unsupported channel so a refactor
    /// that accidentally widens the supported-channel set surfaces here.
    func testValidateChatGUIDForWhatsAppAlwaysThrows() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("whatsapp:+15551234567", for: .whatsapp),
            ".whatsapp must hit the default arm and throw — no write path defined yet"
        ) { error in
            guard case IMessageSender.SendError.invalidChatGUID = error else {
                XCTFail("Expected invalidChatGUID, got \(error)"); return
            }
        }
    }

    func testValidateChatGUIDForTeamsAlwaysThrows() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("teams:thread/abc", for: .teams),
            ".teams must hit the default arm and throw — no write path defined yet"
        ) { error in
            guard case IMessageSender.SendError.invalidChatGUID = error else {
                XCTFail("Expected invalidChatGUID, got \(error)"); return
            }
        }
    }

    func testValidateChatGUIDForTelegramAlwaysThrows() {
        XCTAssertThrowsError(
            try IMessageSender.validateChatGUID("tg://chat/12345", for: .telegram),
            ".telegram must hit the default arm and throw — no write path defined yet"
        ) { error in
            guard case IMessageSender.SendError.invalidChatGUID = error else {
                XCTFail("Expected invalidChatGUID, got \(error)"); return
            }
        }
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

    // MARK: - Legacy send(_:toChatIdentifier:channel:) overload (autopilot 2026-05-07)

    /// The legacy by-identifier overload had zero direct test coverage.
    /// It synthesizes a 1:1-shaped GUID and forwards to sendRaw, which
    /// means group sends from this path can't work — but that's an
    /// intentional contract documented in the source. Pin the four
    /// observable behaviors:

    func testLegacyByIdentifierThrowsUnsupportedForSlackChannel() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        XCTAssertThrowsError(
            try IMessageSender.send("hi", toChatIdentifier: "C123", channel: .slack)
        ) { err in
            guard case IMessageSender.SendError.unsupported = err else {
                return XCTFail("expected .unsupported, got \(err)")
            }
        }
    }

    func testLegacyByIdentifierThrowsUnsupportedForWhatsAppChannel() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        XCTAssertThrowsError(
            try IMessageSender.send("hi", toChatIdentifier: "+15550009999", channel: .whatsapp)
        ) { err in
            guard case IMessageSender.SendError.unsupported = err else {
                return XCTFail("expected .unsupported, got \(err)")
            }
        }
    }

    func testLegacyByIdentifierBuildsIMessageGUIDForIMessageChannel() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        var capturedScript: String?
        IMessageSender.executeHook = { src in capturedScript = src }

        XCTAssertNoThrow(
            try IMessageSender.send("hi", toChatIdentifier: "+15551234567", channel: .imessage)
        )

        let script = capturedScript ?? ""
        XCTAssertTrue(script.contains("iMessage;-;+15551234567"),
                      "legacy iMessage send must synthesize 1:1 GUID 'iMessage;-;<id>'; got: \(script)")
    }

    func testLegacyByIdentifierBuildsSMSGUIDForSMSChannel() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        var capturedScript: String?
        IMessageSender.executeHook = { src in capturedScript = src }

        XCTAssertNoThrow(
            try IMessageSender.send("hi", toChatIdentifier: "+15551234567", channel: .sms)
        )

        let script = capturedScript ?? ""
        XCTAssertTrue(script.contains("SMS;-;+15551234567"),
                      "legacy SMS send must synthesize 1:1 GUID 'SMS;-;<id>'; got: \(script)")
    }

    /// All-cases pin: every Channel except .imessage and .sms must throw
    /// `.unsupported` from the legacy by-identifier overload. Catches a
    /// future refactor that adds a new Channel case (e.g. .discord, .signal)
    /// without updating the IMessageSender guard — the new channel would
    /// silently fall through to AppleScript send-by-identifier semantics,
    /// which only Messages.app understands.
    func testLegacyByIdentifierUnsupportedForEveryNonAppleChannel() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        for ch in Channel.allCases where ch != .imessage && ch != .sms {
            XCTAssertThrowsError(
                try IMessageSender.send("hi", toChatIdentifier: "anything", channel: ch),
                "channel \(ch) must throw unsupported from legacy by-identifier path"
            ) { err in
                guard case IMessageSender.SendError.unsupported = err else {
                    return XCTFail("channel \(ch) must throw .unsupported, got \(err)")
                }
            }
        }
    }

    /// Pin: the legacy by-identifier path correctly rejects an empty id.
    /// `send(text, toChatIdentifier: "", channel: .imessage)` synthesizes
    /// `"iMessage;-;"` which `isValidIMessageGUID` rejects (parts[2] is
    /// empty), so SendError.invalidChatGUID fires before AppleScript runs.
    /// Pinned because an empty id reaching AppleScript would surface as an
    /// opaque errOSAScriptError rather than ReplyAI's own actionable copy.
    func testLegacyByIdentifierWithEmptyIDThrowsInvalidChatGUID() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        XCTAssertThrowsError(
            try IMessageSender.send("hi", toChatIdentifier: "", channel: .imessage)
        ) { err in
            guard case IMessageSender.SendError.invalidChatGUID(let guid) = err else {
                return XCTFail("expected .invalidChatGUID, got \(err)")
            }
            XCTAssertEqual(guid, "iMessage;-;",
                "synthesized GUID surfaces in the error so logs identify the bad input")
        }
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

    // Carriage return (U+000D) is NOT in the escape replacement list —
    // only `\\`, `"`, and `\n` get rewritten. A bare CR therefore reaches
    // the AppleScript double-quoted literal verbatim. AppleScript treats
    // CR inside `"..."` as a string-internal newline (it doesn't terminate
    // the literal the way an unescaped `"` would). Pin both legs:
    //   1. CR-only payload: byte-for-byte identity (no `\\r` substitution).
    //   2. CR mixed with `\n`: the `\n` is rewritten to the two-byte
    //      escape sequence; the surrounding CR survives untouched.
    // A future "harden control-character escaping" edit that adds
    // `\r → \\r` (or strips CR entirely) flips this contract — the test
    // forces the change to be deliberate rather than a silent
    // ambient-quoting tweak.
    func testEscapeCarriageReturnPassesThroughVerbatim() {
        let crOnly = "alpha\rbeta"
        XCTAssertEqual(
            IMessageSender.escapeForAppleScriptLiteral(crOnly),
            "alpha\rbeta",
            "carriage return is not in the escape list and must reach the AppleScript literal verbatim"
        )

        let crLF = "before\r\nafter"
        // `\n` becomes the two-character `\\n` AppleScript escape; the
        // leading CR survives in the same position.
        XCTAssertEqual(
            IMessageSender.escapeForAppleScriptLiteral(crLF),
            "before\r\\nafter",
            "CRLF input emits a verbatim CR followed by the AppleScript `\\n` escape — order and bytes pinned"
        )
    }

    // MARK: - maxMessageLength constant pin
    //
    // The 4096 cap is shipped as the user-visible "too long" boundary —
    // existing tests use `IMessageSender.maxMessageLength` symbolically, so
    // a future tweak from 4096 → 8192 (or down to 2048) would let every
    // existing test re-pass while changing real-world behaviour: shorter
    // messages would start failing, longer ones would either truncate or
    // round-trip through Messages.app at risk. The 4096 number is also
    // baked into the messageTooLong copy via interpolation, so users see
    // it directly. Pin the literal value here.

    func testMaxMessageLengthIsExactly4096() {
        XCTAssertEqual(IMessageSender.maxMessageLength, 4096,
                       "maxMessageLength is shipped UX — a silent change shifts the 'too long' boundary that every send call relies on")
    }

    func testMaxMessageLengthAppearsInMessageTooLongCopy() {
        // The error string interpolates IMessageSender.maxMessageLength at
        // its tail — pin that the literal numeric value reaches the user
        // verbatim, not via a separate magic constant in the format string.
        let copy = IMessageSender.SendError.messageTooLong(99).errorDescription ?? ""
        XCTAssertTrue(copy.contains("4096"),
                      "messageTooLong copy must reference 4096 directly so the user sees the actual boundary; got: \(copy)")
    }

    // MARK: - Production timing default contracts
    //
    // `sendTimeout` and `retryDelay` are mutable `static var`s so tests
    // can override them. That same mutability means the runtime value
    // can drift away from the production literal silently (a test that
    // forgets to restore in tearDown leaks state into later tests; a
    // future refactor that "tunes" the wait could land without anyone
    // noticing). Pin against the immutable `defaultSendTimeout` /
    // `defaultRetryDelay` constants — those are what the production
    // initializer references, so they survive any test-mutation noise.

    /// 10s is the AppleScript send budget. Drop it and Messages.app's
    /// busy-with-iCloud-sync window starts producing spurious `.timedOut`
    /// errors that look like Messages.app rejecting our chat — a real
    /// production telemetry signal would get drowned in test-induced noise.
    /// Raise it past ~15s and the user perceives the Send button as hung.
    func testDefaultSendTimeoutIsTenSeconds() {
        XCTAssertEqual(IMessageSender.defaultSendTimeout, 10,
                       "production sendTimeout default is shipped UX — see test rationale")
    }

    /// 0.5s is the gap between a `-1708` AppleScript failure (Messages.app
    /// hadn't finished compositing) and the retry. Drop to 0 and the
    /// retry hits the same not-ready Messages.app surface; raise above
    /// ~1s and the user sees a multi-second hang on every transient
    /// failure. The retry path is what masks that flake from users —
    /// tuning the delay is a real product call, pinned here.
    func testDefaultRetryDelayIsHalfSecond() {
        XCTAssertEqual(IMessageSender.defaultRetryDelay, 0.5,
                       "production retryDelay default is shipped UX — see test rationale")
    }
}

/// Pin the AppleScript template that `IMessageSender.sendRaw` emits. The
/// template is what reaches Messages.app — drift in either the
/// `tell application "Messages"` opener, the `chat id "<guid>"` reference,
/// the `send "..." to targetChat` call, or the `end tell` closer would
/// break sends silently (Messages would compile-error or address a
/// different chat). Capture the source via `executeHook` and pin the
/// substring contract.
final class IMessageSenderAppleScriptTemplateTests: XCTestCase {

    func testAppleScriptSourceMatchesExpectedTemplate() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }

        // Capture box — executeHook runs synchronously on the calling
        // thread inside `sendRaw`, so a lock-free shared variable is fine
        // here as long as we read after the send returns.
        final class Captured: @unchecked Sendable {
            var source: String = ""
        }
        let captured = Captured()
        IMessageSender.executeHook = { src in captured.source = src }

        let thread = MessageThread(
            id: "+15551234567", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15551234567"
        )
        XCTAssertNoThrow(try IMessageSender.send("hello", to: thread))

        let src = captured.source
        XCTAssertTrue(src.contains("tell application \"Messages\""),
            "AppleScript must address Messages.app via `tell application \"Messages\"` — got: \(src)")
        XCTAssertTrue(src.contains("end tell"),
            "AppleScript must close the tell block — got: \(src)")
        XCTAssertTrue(src.contains("chat id \"iMessage;-;+15551234567\""),
            "AppleScript must reference the GUID via `chat id \"<guid>\"` — got: \(src)")
        XCTAssertTrue(src.contains("send \"hello\" to targetChat"),
            "AppleScript must send the (escaped) text to the resolved targetChat — got: \(src)")
    }

    /// Empty-text sends must still produce a structurally valid script.
    /// The `send ""` form is legal AppleScript and Messages.app accepts
    /// it (silently no-ops the send). Pin so a "guard against empty
    /// text" refactor doesn't accidentally drop the send call entirely.
    func testEmptyTextStillProducesValidSendBlock() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        final class Captured: @unchecked Sendable { var source: String = "" }
        let captured = Captured()
        IMessageSender.executeHook = { src in captured.source = src }

        let thread = MessageThread(
            id: "+15550009999", channel: .imessage, name: "Test",
            avatar: "T", preview: "", time: "",
            chatGUID: "iMessage;-;+15550009999"
        )
        XCTAssertNoThrow(try IMessageSender.send("", to: thread))

        XCTAssertTrue(captured.source.contains("send \"\" to targetChat"),
            "empty text must still emit a `send \"\" to targetChat` line — drift drops the send call entirely; got: \(captured.source)")
    }

    /// `IMessageSender.iMessageServiceID` and `smsServiceID` are the AppleScript
    /// service-identifier strings used by both the 1:1 GUID synthesis path
    /// (`chatGUID(for:)` and the `toChatIdentifier` overload) AND the GUID
    /// validators (`isValidIMessageGUID`, `isValidSMSGUID`). Drift on either
    /// is double-edged: synthesis emits a GUID Messages.app rejects, and
    /// validation rejects every legitimate GUID. The literals previously
    /// lived inline at four call sites — pinning the constants here surfaces
    /// "let's normalize to lowercase" or "let's add MMS" in code review.
    func testServiceIDLiteralsAreIMessageAndSMS() {
        XCTAssertEqual(IMessageSender.iMessageServiceID, "iMessage",
            "iMessageServiceID drift breaks the synthesized 1:1 GUID format AND the GUID validator simultaneously")
        XCTAssertEqual(IMessageSender.smsServiceID, "SMS",
            "smsServiceID drift breaks the synthesized SMS-relay GUID format AND the SMS GUID validator simultaneously")
    }

    // MARK: - chat-GUID format pin
    //
    // The chat-GUID wire format is `<service>;<style>;<identifier>` —
    // semicolons at fixed positions, with a single-char style marker
    // (`-` for 1:1, `+` for group). The synthesis path joins those
    // fields back into a string; the validator splits an incoming GUID
    // and checks each field. Drift between synthesis and validation
    // means the validator no longer accepts what synthesis produces —
    // every send fails `invalidChatGUID` immediately. Hoisted to
    // `chatGUIDFieldSeparator`, `chatGUID1to1Marker`, `chatGUIDGroupMarker`,
    // and the convenience `chatGUID1to1Separator` (`";-;"`) used by
    // both synthesis sites. Pin the literals so a future "let's
    // normalize to / instead of ;" lands deliberately.

    func testChatGUIDDelimitersAreFrozen() {
        XCTAssertEqual(IMessageSender.chatGUIDFieldSeparator, ";",
            "chatGUIDFieldSeparator must remain `;` — it's the field delimiter Messages.app and chat.db both project")
        XCTAssertEqual(IMessageSender.chatGUID1to1Separator, ";-;",
            "chatGUID1to1Separator must equal `;-;` — drift desyncs synthesis from validation and rejects every send")
    }

    func testChatGUIDStyleMarkersAreFrozen() {
        XCTAssertEqual(IMessageSender.chatGUID1to1Marker, "-",
            "chatGUID1to1Marker must remain `-` — Messages.app encodes 1:1 chats with this marker, group chats with `+`")
        XCTAssertEqual(IMessageSender.chatGUIDGroupMarker, "+",
            "chatGUIDGroupMarker must remain `+` — drift desyncs the validator from real chat.db-projected GUIDs for group threads")
    }

    /// Round-trip pin: a GUID synthesized via the constants must validate
    /// via the constants. Catches drift where synthesis changes shape but
    /// validation doesn't (or vice versa).
    func testSynthesisRoundTripsThroughValidation() throws {
        let synth = "\(IMessageSender.iMessageServiceID)\(IMessageSender.chatGUID1to1Separator)+15551234567"
        XCTAssertNoThrow(
            try IMessageSender.validateChatGUID(synth, for: .imessage),
            "synthesizing via the hoisted constants and re-validating via the same constants must round-trip"
        )
    }

    /// Composition pin: `chatGUID1to1Separator` MUST equal
    /// `<chatGUIDFieldSeparator><chatGUID1to1Marker><chatGUIDFieldSeparator>`.
    /// Today both sides happen to be `";-;"` but that's an emergent
    /// property — if a future refactor changes `chatGUID1to1Marker`
    /// from `-` to (say) `_` to support a new chat-style, the
    /// separator must follow or the synthesis path emits malformed
    /// GUIDs while the validator still accepts the old shape. Pin
    /// asserts the composition relationship so a one-side rename
    /// surfaces as a deliberate change rather than a silent
    /// desync. Mirrors the pattern of pinning emergent equalities
    /// on top of individual frozen-literal pins.
    func testChatGUID1to1SeparatorComposesFromFieldSeparatorAndMarker() {
        let composed = "\(IMessageSender.chatGUIDFieldSeparator)\(IMessageSender.chatGUID1to1Marker)\(IMessageSender.chatGUIDFieldSeparator)"
        XCTAssertEqual(IMessageSender.chatGUID1to1Separator, composed,
            "chatGUID1to1Separator must equal <chatGUIDFieldSeparator><chatGUID1to1Marker><chatGUIDFieldSeparator>; if any of the three components is renamed independently of the others, the synthesis path emits a GUID the validator rejects")
    }

    /// `appleScriptErrorPrefix` is the format prefix used at BOTH the
    /// emit site (`SendError.scriptFailure("\(prefix)\(code): \(msg)")`)
    /// AND the retry-detection site
    /// (`msg.contains("\(prefix)\(eventNotHandledErrorCode)")`). Drift
    /// between the two would silently disable the retry path for
    /// `errAEEventNotHandled` (-1708) which fires transiently during
    /// iCloud sync — every send during sync would fail to the user
    /// instead of retrying after `retryDelay`. Pin the literal so a
    /// future refactor that touches one site without the other trips
    /// here.
    func testAppleScriptErrorPrefixIsFrozen() {
        XCTAssertEqual(IMessageSender.appleScriptErrorPrefix, "AppleScript error ",
            "appleScriptErrorPrefix drift between emit-site and retry-detection silently disables the -1708 retry path during iCloud sync")
    }

    /// The retry-detection contains-check uses `prefix + code` as one
    /// haystack-needle. Pin the composite string so a future
    /// constant-defined-but-not-used drift trips here too.
    func testRetryDetectionNeedleComposesPrefixAndEventNotHandledCode() {
        let needle = "\(IMessageSender.appleScriptErrorPrefix)\(IMessageSender.eventNotHandledErrorCode)"
        XCTAssertEqual(needle, "AppleScript error -1708",
            "retry-detection needle must compose `appleScriptErrorPrefix + eventNotHandledErrorCode` byte-for-byte — drift in either silently disables retry")
    }

    /// `scriptParseFailureCopy` is the failure string emitted when
    /// `NSAppleScript(source:)` returns nil — pre-execution syntax
    /// failure. Hoisted from the inline literal so support-engineer
    /// log grep stays stable. Pin the literal byte-for-byte.
    func testScriptParseFailureCopyIsFrozen() {
        XCTAssertEqual(IMessageSender.scriptParseFailureCopy,
                       "NSAppleScript failed to parse",
            "scriptParseFailureCopy drift breaks support-engineer log grep on the pre-execution-syntax-failure path")
    }

    /// `appleScriptApplicationTarget` is the `tell application "<X>"`
    /// process name. Drift to anything other than "Messages" addresses
    /// either a non-existent application (compile error) or a different
    /// process (silent send to the wrong place). Pin the literal so a
    /// "let's quote with single ticks" or "Messages.app" rewrite is
    /// surfaced in code review.
    func testAppleScriptApplicationTargetIsFrozen() {
        XCTAssertEqual(IMessageSender.appleScriptApplicationTarget, "Messages",
            "AppleScript application target drift breaks every send — Messages.app is the only process that exposes `chat id` + `send`")
    }

    /// `appleScriptChatBindingName` is the local-variable name shared
    /// between the assignment line (`set <name> to a reference to chat
    /// id "..."`) and the send line (`send "..." to <name>`). Drift on
    /// only one site emits AppleScript that fails at runtime with
    /// "undefined identifier"; pinning the constant routes both sites
    /// through one source of truth so any rename touches both.
    func testAppleScriptChatBindingNameIsFrozen() {
        XCTAssertEqual(IMessageSender.appleScriptChatBindingName, "targetChat",
            "binding-name drift between the set-site and send-site silently breaks every send with an undefined-identifier error")
    }

    /// Render-equality pin: `appleScriptSendSource` for a fixed
    /// (text, guid) pair must match the expected four-line literal
    /// byte-for-byte. Complements the per-substring `contains` pins in
    /// `IMessageSenderAppleScriptTemplateTests` — those assert each
    /// line is present, this asserts no extra lines crept in (e.g. a
    /// stray `delay 1` or `display notification` line) and the leading
    /// indentation matches what AppleScript compiles cleanly.
    func testAppleScriptSendSourceMatchesExpectedTemplate() {
        let rendered = IMessageSender.appleScriptSendSource(
            escapedText: "hello",
            escapedGUID: "iMessage;-;+15551234567"
        )
        let expected = """
        tell application "Messages"
            set targetChat to a reference to chat id "iMessage;-;+15551234567"
            send "hello" to targetChat
        end tell
        """
        XCTAssertEqual(rendered, expected,
            "AppleScript send template drift — extra/missing lines or indent change would break script compilation or change the send semantics")
    }

    /// Round-trip pin: the rendered template must thread the inputs
    /// through the assignment site and the send site verbatim, AND
    /// must use the hoisted constants (not inline duplicates) at both
    /// the application-target and binding-name positions. Catches a
    /// refactor that rewrites the builder to bypass `appleScriptApplicationTarget`
    /// or `appleScriptChatBindingName` — the literal-pins above would
    /// still pass on the constants while the builder silently used
    /// hardcoded strings.
    func testAppleScriptSendSourceUsesHoistedConstants() {
        let rendered = IMessageSender.appleScriptSendSource(
            escapedText: "body",
            escapedGUID: "iMessage;+;chatX"
        )
        // application target appears inside `tell application "..."`
        XCTAssertTrue(rendered.contains("tell application \"\(IMessageSender.appleScriptApplicationTarget)\""),
            "builder must thread `appleScriptApplicationTarget` constant into the tell-opener — got: \(rendered)")
        // binding name appears in both the set site and the send site
        XCTAssertTrue(rendered.contains("set \(IMessageSender.appleScriptChatBindingName) to a reference to chat id"),
            "builder must thread `appleScriptChatBindingName` into the set-site — got: \(rendered)")
        XCTAssertTrue(rendered.contains("to \(IMessageSender.appleScriptChatBindingName)"),
            "builder must thread `appleScriptChatBindingName` into the send-site — got: \(rendered)")
        // input arguments must round-trip through the rendered string.
        XCTAssertTrue(rendered.contains("\"iMessage;+;chatX\""),
            "escapedGUID must appear quoted in the rendered template — got: \(rendered)")
        XCTAssertTrue(rendered.contains("send \"body\""),
            "escapedText must appear quoted after `send` in the rendered template — got: \(rendered)")
    }

    /// Pin the `send(_:to:)` thread-channel guard. The new MessageThread-
    /// based send entrypoint must throw `.unsupported` for every
    /// channel that isn't `.imessage` or `.sms` — same contract as the
    /// legacy `send(_:toChatIdentifier:channel:)` path
    /// (testLegacyByIdentifierUnsupportedForEveryNonAppleChannel) but
    /// covering the newer entry point. Drift toward "let's let Slack
    /// fall through to AppleScript" would silently route Slack sends
    /// through Messages.app, which would either compile-error inside
    /// AppleScript (no `chat id` matching the Slack ID format) or
    /// post the text into a misidentified chat. Pin every non-Apple
    /// channel so a partial-fix regression that only protected one
    /// channel still surfaces.
    func testSendByThreadUnsupportedForEveryNonAppleChannel() {
        let prevHook = IMessageSender.executeHook
        defer { IMessageSender.executeHook = prevHook }
        IMessageSender.executeHook = IMessageSender.dryRunHook()

        for ch in Channel.allCases where ch != .imessage && ch != .sms {
            let thread = MessageThread(
                id: "anything", channel: ch, name: "X",
                avatar: "X", preview: "", time: ""
            )
            XCTAssertThrowsError(
                try IMessageSender.send("hi", to: thread),
                "channel \(ch) must throw .unsupported from send(_:to:)"
            ) { err in
                guard case IMessageSender.SendError.unsupported = err else {
                    return XCTFail("channel \(ch) must throw .unsupported from send(_:to:), got \(err)")
                }
            }
        }
    }
}
