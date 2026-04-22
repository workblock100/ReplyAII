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
}
