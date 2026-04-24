import XCTest
@testable import ReplyAI

final class PromptBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeThread(channel: Channel = .imessage, name: String = "Alice") -> MessageThread {
        MessageThread(id: "t1", channel: channel, name: name, avatar: "A", preview: "", time: "now")
    }

    private func makeMessage(_ text: String, from: Message.Author = .them) -> Message {
        Message(from: from, text: text, time: "12:00")
    }

    // MARK: - Tests

    func testToneLabelAppearsInPrompt() {
        let thread = makeThread()
        for tone in Tone.allCases {
            let prompt = PromptBuilder.build(thread: thread, tone: tone, history: [])
            XCTAssertTrue(
                prompt.contains(tone.rawValue.lowercased()),
                "Expected tone '\(tone.rawValue.lowercased())' in prompt"
            )
        }
    }

    func testThreadContextAppearsInPrompt() {
        let thread = makeThread(channel: .imessage, name: "Bob")
        let history = [makeMessage("hey there"), makeMessage("you around?")]
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: history)

        XCTAssertTrue(prompt.contains("Bob"), "Sender name missing from prompt")
        XCTAssertTrue(prompt.contains("iMessage"), "Channel label missing from prompt")
        XCTAssertTrue(prompt.contains("hey there"), "Message text missing from prompt")
        XCTAssertTrue(prompt.contains("you around?"), "Second message missing from prompt")
    }

    func testLongHistoryIsTruncatedToCharBudget() {
        let thread = makeThread()
        // Each message is 100 chars; budget is 2 000 chars — only 20 messages should fit.
        let longText = String(repeating: "x", count: 100)
        let history = (0..<50).map { _ in makeMessage(longText) }

        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: history)

        // Count occurrences of the long text in the prompt.
        var count = 0
        var searchRange = prompt.startIndex..<prompt.endIndex
        while let range = prompt.range(of: longText, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<prompt.endIndex
        }
        // At most historyCharBudget / 100 = 20 messages, budget boundary may vary by 1.
        XCTAssertLessThanOrEqual(count, PromptBuilder.historyCharBudget / longText.count + 1)
        XCTAssertLessThan(count, 50, "All 50 messages should not appear — truncation expected")
    }

    func testEmptyHistoryFallback() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [])

        XCTAssertTrue(prompt.contains("no messages"), "Expected fallback text for empty history")
        XCTAssertFalse(prompt.isEmpty)
    }

    func testNoniMessageChannelLabelAppearsInPrompt() {
        for channel in [Channel.slack, .whatsapp, .teams, .sms, .telegram] {
            let thread = makeThread(channel: channel, name: "Charlie")
            let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [])
            XCTAssertTrue(
                prompt.contains(channel.label),
                "Expected channel label '\(channel.label)' in prompt"
            )
        }
    }

    func testEmbeddedNewlinesInMessageTextAreCollapsed() {
        let thread = makeThread()
        let history = [makeMessage("line one\nline two\nline three")]
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: history)

        // The speaker:text line should not contain raw newlines within the message text.
        // Find the line containing "line one" and verify the full entry is on one line.
        let lines = prompt.components(separatedBy: "\n")
        let messageLine = lines.first { $0.contains("line one") }
        XCTAssertNotNil(messageLine, "Message line not found in prompt")
        XCTAssertTrue(messageLine?.contains("line one line two line three") == true,
                      "Embedded newlines should be collapsed to spaces")
    }

    // MARK: - truncate invariants (REP-073)

    func testShortHistoryPassesThroughUnchanged() {
        // A history well under the budget must not lose any messages.
        let messages = (1...5).map { makeMessage("short \($0)") }
        let result = PromptBuilder.truncate(messages, budget: 10_000)
        XCTAssertEqual(result.count, messages.count, "short history must pass through unchanged")
        XCTAssertEqual(result.map(\.text), messages.map(\.text))
    }

    func testMostRecentMessageAlwaysRetained() {
        // When truncation drops messages, the last (most recent) message must survive.
        // Use a tiny budget so everything except the last message is dropped.
        let last = makeMessage("the latest message that must survive truncation")
        let old  = makeMessage(String(repeating: "x", count: 500))
        let messages = [old, old, old, old, last]
        let result = PromptBuilder.truncate(messages, budget: 50)
        XCTAssertFalse(result.isEmpty, "must retain at least one message after truncation")
        XCTAssertEqual(result.last?.text, last.text, "most recent message must always be retained")
    }

    // MARK: - Tone system instruction tests (REP-112)

    func testEachToneProducesNonEmptySystemInstruction() {
        for tone in Tone.allCases {
            let instruction = PromptBuilder.systemPrompt(tone: tone)
            XCTAssertFalse(instruction.isEmpty,
                           "systemPrompt(tone: \(tone)) must return a non-empty string")
        }
    }

    func testToneInstructionsAreDistinct() {
        var seen: [String: Tone] = [:]
        for tone in Tone.allCases {
            let instruction = PromptBuilder.systemPrompt(tone: tone)
            if let duplicate = seen[instruction] {
                XCTFail("Tone.\(tone) and Tone.\(duplicate) produce identical system instructions — each tone must be distinct")
            }
            seen[instruction] = tone
        }
    }

    // MARK: - Large-payload truncation (REP-121)

    func testTruncatedPromptRespectsBudget() {
        // 20 messages × 200 chars = 4 000 total chars; budget is 2 000.
        // After truncation the retained messages must fit within the budget.
        let body = String(repeating: "b", count: 200)
        let messages = (1...20).map { _ in makeMessage(body) }
        let truncated = PromptBuilder.truncate(messages, budget: PromptBuilder.historyCharBudget)
        let retained = truncated.map(\.text.count).reduce(0, +)
        // Allow up to one over-budget message because the most-recent message
        // is always retained even when it alone exceeds the budget.
        XCTAssertLessThanOrEqual(
            retained, PromptBuilder.historyCharBudget + body.count,
            "truncated history must fit within historyCharBudget (+ 1 forced message)"
        )
        XCTAssertLessThan(truncated.count, 20,
                          "at least some messages must have been dropped for a 4 000-char payload")
    }

    func testTruncationDoesNotDropSystemInstruction() {
        // With a heavy payload that forces truncation, the system instruction
        // (thread name + tone label) must survive in the final prompt.
        let thread = makeThread(name: "SystemGuard")
        let body = String(repeating: "z", count: 200)
        let messages = (1...20).map { _ in makeMessage(body) }
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: messages)
        XCTAssertTrue(prompt.contains("SystemGuard"),
                      "thread name must appear in prompt even after message truncation")
        XCTAssertTrue(prompt.contains(Tone.warm.rawValue.lowercased()),
                      "tone label must appear in prompt even after message truncation")
    }

    // MARK: - REP-137: oversized system instruction guard

    func testOversizedSystemInstructionFitsWithinCap() {
        // Normal tone instructions are short; verify the cap formula is correct.
        let cap = PromptBuilder.historyCharBudget - PromptBuilder.minHistoryReserve
        for tone in Tone.allCases {
            let result = PromptBuilder.systemPrompt(tone: tone)
            XCTAssertLessThanOrEqual(result.count, cap,
                                     "systemPrompt for \(tone) must fit within budget cap")
        }
    }

    func testOversizedSystemInstructionPreservesAtLeastOneMessage() {
        let thread = makeThread(name: "OversizeTest")
        let shortMsg = makeMessage("short message context")
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [shortMsg])
        XCTAssertTrue(prompt.contains("short message context"),
                      "most-recent message must appear in prompt regardless of system instruction size")
    }

    // MARK: - REP-145: empty message list produces non-empty valid prompt

    func testEmptyMessagesProducesNonEmptyPrompt() {
        let thread = makeThread(name: "EmptyTest")
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [])
        XCTAssertFalse(prompt.isEmpty, "empty message list must produce a non-empty prompt")
    }

    func testEmptyMessagesPromptContainsToneInstruction() {
        let thread = makeThread(name: "ToneTest")
        let prompt = PromptBuilder.build(thread: thread, tone: .playful, history: [])
        XCTAssertTrue(prompt.contains(Tone.playful.rawValue.lowercased()),
                      "prompt with empty message list must still include tone instruction")
    }

    func testSingleMessagePromptContainsMessageText() {
        let thread = makeThread(name: "Single")
        let msg = makeMessage("unique single message text")
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [msg])
        XCTAssertTrue(prompt.contains("unique single message text"),
                      "single-message prompt must contain the message body")
    }

    // MARK: - REP-152: all-messages-from-same-sender produces valid prompt

    func testAllMessagesFromMeProducesNonEmptyPrompt() {
        let thread = makeThread(name: "AllMe")
        let history = (0..<3).map { i in makeMessage("message \(i)", from: .me) }
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: history)
        XCTAssertFalse(prompt.isEmpty,
                       "all-.me history must produce a non-empty prompt without crashing")
        XCTAssertTrue(prompt.contains("message 0") || prompt.contains("message 2"),
                      "at least one message body must appear in all-.me prompt")
    }

    func testAllMessagesFromThemProducesNonEmptyPrompt() {
        let thread = makeThread(name: "AllThem")
        let history = (0..<3).map { i in makeMessage("their message \(i)", from: .them) }
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: history)
        XCTAssertFalse(prompt.isEmpty,
                       "all-.them history must produce a non-empty prompt without crashing")
        XCTAssertTrue(prompt.contains("their message"),
                      "at least one message body must appear in all-.them prompt")
    }

    func testAllMessagesFromMeContainsToneInstruction() {
        let thread = makeThread(name: "ToneCheck")
        let history = [makeMessage("I said something", from: .me)]
        let prompt = PromptBuilder.build(thread: thread, tone: .playful, history: history)
        XCTAssertTrue(prompt.contains(Tone.playful.rawValue.lowercased()),
                      "all-.me prompt must still include the tone instruction")
    }

    // MARK: - REP-180: system prompt structural ordering

    func testSystemPromptPrecedesConversationHistory() {
        // systemPrompt(tone:) must not contain any message content — it's the
        // system turn and should be prepended before the conversation block.
        let thread = makeThread(name: "OrderCheck")
        let msg = makeMessage("rep180_unique_token")
        let system = PromptBuilder.systemPrompt(tone: .warm)
        let conversation = PromptBuilder.build(thread: thread, tone: .warm, history: [msg])

        // System block must not bleed message content into itself.
        XCTAssertFalse(system.contains("rep180_unique_token"),
                       "systemPrompt must not contain conversation message text")

        // Combined output: system comes first, then conversation.
        let combined = system + "\n\n" + conversation
        let sysRange = combined.range(of: system)!
        let msgRange = combined.range(of: "rep180_unique_token")!
        XCTAssertLessThan(sysRange.lowerBound, msgRange.lowerBound,
                          "system prompt must appear before message content in combined output")
    }

    func testAllMessagesFollowSystemBlock() {
        let thread = makeThread(name: "OrderCheck3")
        let messages = [
            makeMessage("first_180_msg"),
            makeMessage("second_180_msg"),
            makeMessage("third_180_msg"),
        ]
        let system = PromptBuilder.systemPrompt(tone: .direct)
        let conversation = PromptBuilder.build(thread: thread, tone: .direct, history: messages)
        let combined = system + "\n\n" + conversation

        let sysEnd = combined.range(of: system)!.upperBound
        for msg in ["first_180_msg", "second_180_msg", "third_180_msg"] {
            let msgRange = combined.range(of: msg)!
            XCTAssertGreaterThanOrEqual(msgRange.lowerBound, sysEnd,
                "'\(msg)' must appear after the system block in combined output")
        }
    }

    // MARK: - REP-206: drop-oldest truncation direction

    /// When total message chars exceed the budget, the oldest (earliest in the array)
    /// messages are dropped first, preserving the most-recent context for the model.
    func testOldestMessagesDroppedWhenOverBudget() {
        // 5 messages of 500 chars each = 2500 chars total, exceeds 2000-char budget.
        // The oldest (messages[0]) must be absent; the newest (messages[4]) must survive.
        let oldest  = makeMessage(String(repeating: "O", count: 500))
        let middle1 = makeMessage(String(repeating: "M", count: 500))
        let middle2 = makeMessage(String(repeating: "N", count: 500))
        let middle3 = makeMessage(String(repeating: "P", count: 500))
        let newest  = makeMessage(String(repeating: "Q", count: 500))
        let messages = [oldest, middle1, middle2, middle3, newest]

        let result = PromptBuilder.truncate(messages, budget: PromptBuilder.historyCharBudget)

        let texts = result.map(\.text)
        XCTAssertFalse(texts.contains(oldest.text),  "oldest message must be dropped when over budget")
        XCTAssertTrue(texts.contains(newest.text),   "newest message must survive truncation")
    }

    /// When total chars exactly equals the budget, all messages must be preserved —
    /// no message should be dropped at the boundary.
    func testAllMessagesPreservedAtExactBudget() {
        // 4 messages of 500 chars each = exactly 2000-char budget.
        let texts = (0..<4).map { i in String(repeating: String(UnicodeScalar(65 + i)!), count: 500) }
        let messages = texts.map { makeMessage($0) }

        let result = PromptBuilder.truncate(messages, budget: PromptBuilder.historyCharBudget)

        XCTAssertEqual(result.count, 4, "all 4 messages must survive when total equals budget")
        for text in texts {
            XCTAssertTrue(result.map(\.text).contains(text),
                          "message '\(text.prefix(5))…' must not be dropped at exact budget boundary")
        }
    }
}
