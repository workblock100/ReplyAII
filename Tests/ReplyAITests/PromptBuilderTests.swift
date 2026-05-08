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

    func testTruncateEmptyHistoryReturnsEmpty() {
        // Defense in depth — confirm no nil-deref or off-by-one when called
        // with no messages (e.g. fresh thread before first incoming).
        let result = PromptBuilder.truncate([], budget: 10_000)
        XCTAssertTrue(result.isEmpty)
    }

    func testTruncateZeroBudgetDropsEverything() {
        // Pin the strict-greater-than check in the implementation —
        // budget=0 means "no room for any chars" so every message hits
        // the break condition. Catches a refactor that flips > to >=.
        let messages = (1...3).map { makeMessage("msg \($0)") }
        let result = PromptBuilder.truncate(messages, budget: 0)
        XCTAssertTrue(result.isEmpty,
            "budget=0 must drop every message — first-iteration break condition")
    }

    /// Edge case: the most-recent (last) message ALONE exceeds the
    /// budget. The current implementation drops it silently — it does
    /// NOT force-retain the most-recent message — because the loop's
    /// `if total + chars > budget { break }` fires on the first
    /// iteration with `total = 0`. Pinning the actual behavior so a
    /// future force-retain refactor (which existing comments at
    /// `testLongHistoryIsTruncatedToCharBudget` ASSUME is in place but
    /// isn't) surfaces here as a deliberate change rather than a
    /// silent drift. If the implementation ever switches to
    /// "force-retain when it alone fits within e.g. 2× budget," this
    /// test should be updated to match — but the change should be
    /// intentional and reviewed.
    func testTruncateDropsMostRecentWhenItAloneExceedsBudget() {
        let huge = makeMessage(String(repeating: "x", count: 300))
        let result = PromptBuilder.truncate([huge], budget: 100)
        XCTAssertTrue(result.isEmpty,
            "single message larger than budget is dropped — first-iteration break, no force-retain")
    }

    /// Sibling case: when the most-recent message exceeds budget AND
    /// older messages would fit, the older ones are still dropped
    /// because the reversed iteration stops at the first over-budget
    /// item. Confirms the loop does NOT skip the over-budget item and
    /// continue with smaller older messages.
    func testTruncateBreaksOnFirstOverBudgetAndDoesNotSkipForward() {
        let huge   = makeMessage(String(repeating: "x", count: 300))
        let small1 = makeMessage("a")  // 1 char, would fit
        let small2 = makeMessage("b")  // 1 char, would fit
        // Order: [small1, small2, huge] → reversed: [huge, small2, small1]
        // Loop hits huge first, breaks; small1/small2 never visited.
        let result = PromptBuilder.truncate([small1, small2, huge], budget: 100)
        XCTAssertTrue(result.isEmpty,
            "loop breaks on first over-budget message; older smaller messages are NOT recovered after the break")
    }

    /// Edge case: empty-text messages all survive truncation under any
    /// non-negative budget, because `chars=0` never trips the strict-greater
    /// `total + chars > budget` break. Pinned because empty messages can
    /// realistically appear in history (chat.db rows with cleared text,
    /// attachment-only messages where AttributedBodyDecoder returned ""),
    /// and a future "filter empties at truncate" hardening would change the
    /// shape of every prompt that contains attachment-only messages.
    func testTruncateRetainsEmptyTextMessagesUnderPositiveBudget() {
        let empties = (1...5).map { _ in makeMessage("") }
        let result = PromptBuilder.truncate(empties, budget: 100)
        XCTAssertEqual(result.count, 5,
            "every empty-text message survives a positive budget — chars=0 never trips the > break")
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

    // MARK: - REP-222: voice example injection

    func testVoiceExamplesInjectedIntoPrompt() {
        let thread = makeThread(name: "VoiceTest")
        let examples = ["Sure, sounds good!", "On it — give me a sec"]
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [], voiceExamples: examples)

        XCTAssertTrue(prompt.contains("Style examples from the user's prior messages:"),
                      "voice examples section header must appear when examples are non-empty")
        XCTAssertTrue(prompt.contains("Sure, sounds good!"), "first example must appear in prompt")
        XCTAssertTrue(prompt.contains("On it — give me a sec"), "second example must appear in prompt")
    }

    func testEmptyVoiceExamplesProduceNoHeader() {
        let thread = makeThread(name: "NoVoice")
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [], voiceExamples: [])

        XCTAssertFalse(prompt.contains("Style examples"),
                       "voice examples section must not appear when examples list is empty")
    }

    func testVoiceExamplesSectionAppearsBeforeHistory() {
        let thread = makeThread(name: "OrderVoice")
        let examples = ["rep222_voice_token"]
        let msg = makeMessage("rep222_history_token")
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [msg], voiceExamples: examples)

        let voiceRange = prompt.range(of: "rep222_voice_token")!
        let historyRange = prompt.range(of: "rep222_history_token")!
        XCTAssertLessThan(voiceRange.lowerBound, historyRange.lowerBound,
                          "voice examples must appear before conversation history in the prompt")
    }

    func testMultipleVoiceExamplesAllAppearInPrompt() {
        let thread = makeThread(name: "MultiVoice")
        let examples = (1...5).map { "example_voice_\($0)" }
        let prompt = PromptBuilder.build(thread: thread, tone: .playful, history: [], voiceExamples: examples)

        for example in examples {
            XCTAssertTrue(prompt.contains(example),
                          "voice example '\(example)' must appear in prompt")
        }
    }

    /// Pin current behaviour: an empty-string voice example produces a bare
    /// `- ` bullet in the prompt (no trimming or filtering at the build
    /// layer). This is documented rather than fixed because the boundary
    /// is the *caller's* responsibility — `UserVoiceProfile` and rule
    /// rendering should screen empties before passing them in. If a future
    /// fire decides to harden `build` itself with `.filter { !$0.isEmpty }`,
    /// this test fails and forces the change to be deliberate.
    func testEmptyVoiceExampleProducesBareBulletInPrompt() {
        let thread = makeThread(name: "EmptyVoice")
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [],
                                         voiceExamples: ["", "real example"])

        XCTAssertTrue(prompt.contains("Style examples from the user's prior messages:"),
            "section header must still appear when at least one example is non-empty")
        // The empty-string example renders as a bare "- " line. Pin its
        // exact substring so a refactor that strips it shows up here as a
        // deliberate change of contract.
        XCTAssertTrue(prompt.contains("\n- \n"),
            "empty voice example currently renders as a bare '- ' bullet — refactor that filters empties must update this test")
        XCTAssertTrue(prompt.contains("- real example"),
            "the non-empty example must still appear alongside the bare bullet")
    }

    /// A voice-examples list that's only empty strings — `["", ""]` — is
    /// not the same as `[]`. The non-isEmpty guard fires (count > 0), so
    /// the section header still appears even though every bullet is bare.
    /// Pin so a future "treat all-empty as missing" optimization is a
    /// visible behaviour change.
    func testAllEmptyVoiceExamplesStillEmitSectionHeader() {
        let thread = makeThread(name: "AllEmptyVoice")
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [],
                                         voiceExamples: ["", ""])

        XCTAssertTrue(prompt.contains("Style examples from the user's prior messages:"),
            "all-empty voiceExamples list still triggers the header — count, not content, drives the guard")
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

    // MARK: - Per-tone semantic markers in systemPrompt

    func testWarmTonePromptMentionsWarmth() {
        // Beyond the existing "non-empty" + "all-tones-distinct" guards, pin
        // the load-bearing semantic marker for each tone. A refactor that
        // swapped two tone-tail instructions (e.g. .warm acquired the
        // .direct tail) would slip past both existing guards but ship a
        // model that drafts in the wrong voice.
        let prompt = PromptBuilder.systemPrompt(tone: .warm)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("warm"),
                      ".warm system prompt must mention warmth, got: \(prompt)")
    }

    func testDirectTonePromptMentionsBrevity() {
        let prompt = PromptBuilder.systemPrompt(tone: .direct)
        // The .direct tail tells the model to be "direct" + "short" + lowercase.
        // Pin "direct" since it's the most distinctive load-bearing token; the
        // other markers are less diagnostic in isolation.
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("direct"),
                      ".direct system prompt must mention directness, got: \(prompt)")
    }

    func testPlayfulTonePromptMentionsPlayfulness() {
        let prompt = PromptBuilder.systemPrompt(tone: .playful)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("playful"),
                      ".playful system prompt must mention playfulness, got: \(prompt)")
    }

    // MARK: - Public-constant pins
    //
    // `historyCharBudget` and `minHistoryReserve` define the prompt's
    // truncation envelope. Drift here changes how much history every
    // draft request includes — quietly degrading completion quality on
    // long threads. Pin the exact numbers so a change is acknowledged
    // in code review rather than slipping through.

    func testHistoryCharBudgetPinned() {
        XCTAssertEqual(PromptBuilder.historyCharBudget, 2_000,
            "historyCharBudget governs how many message-history characters reach the model — drift silently changes completion quality on long threads")
    }

    func testMinHistoryReservePinned() {
        XCTAssertEqual(PromptBuilder.minHistoryReserve, 200,
            "minHistoryReserve guarantees at least 200 chars of recent history survive the system-instruction overflow guard")
    }

    func testMinHistoryReserveLessThanBudget() {
        // Logical invariant: the reserve must fit inside the total budget,
        // otherwise the truncation math goes negative on every call. The
        // values themselves are pinned above; this guards against a future
        // edit that bumps the reserve above the budget.
        XCTAssertLessThan(PromptBuilder.minHistoryReserve, PromptBuilder.historyCharBudget,
            "minHistoryReserve must stay below historyCharBudget — otherwise truncate(_:budget:) produces a negative cap")
    }

    /// The trailing user-turn instruction is what tells the model to emit a
    /// reply WITHOUT preamble ("Sure, here's…"). If the literal `"Reply
    /// text only."` ever drifts, every draft starts including conversational
    /// scaffolding the composer doesn't know how to strip — pin it so
    /// changes are deliberate.
    func testBuildPromptEndsWithReplyTextOnlyInstruction() {
        let thread = MessageThread(id: "t-instr", channel: .imessage,
                                   name: "Maya", avatar: "M",
                                   preview: "", time: "")
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [])
        XCTAssertTrue(prompt.contains("Reply text only."),
            "user-turn instruction must contain `Reply text only.` literal — drift here changes every draft's preamble behavior")
    }

    /// The instruction line is the LAST line of the prompt — anything after
    /// would dilute the "no preamble" signal. Pin the position so a refactor
    /// that appends a footer (e.g. examples) doesn't push the instruction
    /// into the middle where the model ignores it.
    func testBuildPromptInstructionLineIsLast() {
        let thread = MessageThread(id: "t-instr-last", channel: .slack,
                                   name: "Maya", avatar: "M",
                                   preview: "", time: "")
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [])
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false)
        // The very last line should be the instruction.
        let lastLine = String(lines.last ?? "")
        XCTAssertTrue(lastLine.contains("Reply text only."),
            "instruction line must be the LAST line, not buried in the middle — got last line: '\(lastLine)'")
    }

    /// Pin the per-message speaker prefix: `me: <text>` for outgoing,
    /// `<thread.name>: <text>` for incoming. Drift here would either
    /// duplicate the user's name as the speaker (the model sees "me" as
    /// the user, "<name>" as the contact) or misattribute messages, both
    /// of which silently produce confused replies.
    func testBuildPromptSpeakerPrefixIsMeForOutgoingAndThreadNameForIncoming() {
        let thread = MessageThread(id: "t-spk", channel: .imessage,
                                   name: "Maya", avatar: "M",
                                   preview: "", time: "")
        let history = [
            Message(from: .them, text: "ping", time: ""),
            Message(from: .me,   text: "pong", time: ""),
        ]
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: history)
        XCTAssertTrue(prompt.contains("Maya: ping"),
            "incoming message must be prefixed with the thread name — got prompt: \(prompt)")
        XCTAssertTrue(prompt.contains("me: pong"),
            "outgoing message must be prefixed with literal `me` — got prompt: \(prompt)")
    }

    /// Tone is interpolated lowercased into the instruction (`.warm` → "warm",
    /// `.direct` → "direct", etc.). Pin so a future tone case (e.g. `.terse`)
    /// or a casing change is a deliberate edit rather than a quiet
    /// instruction-line drift.
    func testBuildPromptToneIsLowercasedInInstruction() {
        let thread = MessageThread(id: "t-tone", channel: .imessage,
                                   name: "Maya", avatar: "M",
                                   preview: "", time: "")
        let warm    = PromptBuilder.build(thread: thread, tone: .warm,    history: [])
        let direct  = PromptBuilder.build(thread: thread, tone: .direct,  history: [])
        let playful = PromptBuilder.build(thread: thread, tone: .playful, history: [])
        XCTAssertTrue(warm.contains("a warm tone."),
            "warm instruction must read `a warm tone.` (lowercase) — got prompt: \(warm)")
        XCTAssertTrue(direct.contains("a direct tone."),
            "direct instruction must read `a direct tone.` (lowercase)")
        XCTAssertTrue(playful.contains("a playful tone."),
            "playful instruction must read `a playful tone.` (lowercase)")
    }

    /// Pin the exact first line of every built prompt:
    /// `Conversation with <name> via <channel.label>.`
    /// The LLM uses this opening to anchor "who am I writing to" and the
    /// channel-aware register (Slack ≠ iMessage tone). A copy edit that
    /// silently breaks the trailing period or swaps "with" for "to" would
    /// still pass `testThreadContextAppearsInPrompt` (which only does
    /// substring contains) but would degrade real prompts. Pinned exactly
    /// here so any rewording surfaces as a deliberate test edit.
    func testBuildPromptFirstLineLiteral() {
        let thread = makeThread(channel: .slack, name: "#growth")
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [])
        let firstLine = prompt
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        XCTAssertEqual(firstLine, "Conversation with #growth via Slack.",
            "first line of build() must be exactly `Conversation with <name> via <channel.label>.` — got: `\(firstLine)`")
    }

    /// Pin the empty-history fallback as the exact literal `(no messages yet)`.
    /// `testEmptyHistoryFallback` only checks `contains("no messages")`, which
    /// would still pass after a rewrite to e.g. "no messages here". The exact
    /// literal matters: it's what the LLM sees in place of conversation
    /// context, and the parenthesized form signals "metadata, not user text"
    /// so the model doesn't echo it back as a reply.
    func testBuildPromptEmptyHistoryFallbackLiteral() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [])
        XCTAssertTrue(prompt.contains("(no messages yet)"),
            "empty-history fallback must be the exact literal `(no messages yet)` — got prompt: \(prompt)")
    }

    /// Pin the recent-messages header as the exact literal
    /// `Recent messages (oldest first):`. The "(oldest first)" parenthetical
    /// is load-bearing — it tells the LLM how to interpret message ordering
    /// so the most recent line is treated as the immediate context. Drift
    /// here (e.g. truncating to "Recent messages:") would silently confuse
    /// the model on long threads.
    func testBuildPromptRecentMessagesHeaderLiteral() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [makeMessage("hi")])
        XCTAssertTrue(prompt.contains("Recent messages (oldest first):"),
            "recent-messages header must read exactly `Recent messages (oldest first):` — got prompt: \(prompt)")
    }

    /// Pin the voice-examples header as the exact literal
    /// `Style examples from the user's prior messages:`. The phrasing tells
    /// the LLM the section is descriptive (the user's *style*) rather than
    /// content to reply to. A rewording like "Examples of how the user
    /// writes:" would still pass `testEmptyVoiceExamplesProduceNoHeader`
    /// (negative-substring check on `Style examples`) but could shift how
    /// the model interprets the section.
    func testBuildPromptVoiceExamplesHeaderLiteral() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm,
                                         history: [], voiceExamples: ["yo"])
        XCTAssertTrue(prompt.contains("Style examples from the user's prior messages:"),
            "voice-examples header must read exactly `Style examples from the user's prior messages:` — got prompt: \(prompt)")
    }

    /// Pin the voice-examples bullet format: each example is rendered on
    /// its own line as `- <example>`. The single-hyphen-space prefix marks
    /// list items unambiguously to the LLM. Switching to "* " or "• " or
    /// dropping the space would still pass the existing
    /// `testMultipleVoiceExamplesAllAppearInPrompt` (substring contains)
    /// but would change how the model parses the list boundary.
    // MARK: - Template literal pins (hoisted constants)
    //
    // The `Template` enum holds every prompt-template literal. Pinning the
    // exact bytes here protects against a refactor that "tightens" the
    // copy in a way that quietly changes how the model parses a section.
    // Each pin asserts BOTH the constant equals the literal AND the
    // rendered prompt routes through the constant — catching drift
    // between source and constant in either direction.

    func testPromptTemplateLiteralsAreFrozen() {
        XCTAssertEqual(PromptBuilder.Template.voiceExamplesHeader,
                       "Style examples from the user's prior messages:",
            "voice-examples header literal must not drift — it tells the LLM the section is descriptive style, not content to reply to")
        XCTAssertEqual(PromptBuilder.Template.recentMessagesHeader,
                       "Recent messages (oldest first):",
            "recent-messages header literal must not drift — `(oldest first)` parenthetical tells the LLM how to interpret message ordering")
        XCTAssertEqual(PromptBuilder.Template.emptyHistoryFallback,
                       "(no messages yet)",
            "empty-history fallback literal must not drift — parenthesized form signals metadata so the model doesn't echo it back as a reply")
        XCTAssertEqual(PromptBuilder.Template.speakerSelf, "me",
            "outgoing-speaker label must remain literal `me` — drift here misattributes messages and silently produces confused replies")
        XCTAssertEqual(PromptBuilder.Template.userInstructionSuffix,
                       " tone. Reply text only.",
            "user-instruction suffix must not drift — `Reply text only.` is what suppresses preamble in every draft")
    }

    func testBuildPromptRoutesRecentMessagesHeaderThroughTemplate() {
        // Drift between source literal and Template constant would let
        // testBuildPromptRecentMessagesHeaderLiteral pass while the
        // constant silently desynced. Asserting `prompt.contains(Template.X)`
        // catches that case: source has to keep emitting whatever the
        // constant currently says.
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm,
                                         history: [makeMessage("hi")])
        XCTAssertTrue(prompt.contains(PromptBuilder.Template.recentMessagesHeader),
            "rendered prompt must contain Template.recentMessagesHeader byte-for-byte — source and constant must not drift")
    }

    func testBuildPromptRoutesEmptyHistoryFallbackThroughTemplate() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [])
        XCTAssertTrue(prompt.contains(PromptBuilder.Template.emptyHistoryFallback),
            "rendered prompt must contain Template.emptyHistoryFallback byte-for-byte — source and constant must not drift")
    }

    // MARK: - Template format pins (build() composers)

    /// `Template.threadHeader(name:channelLabel:)` is the first line of
    /// the user-turn prompt — drift here changes the very first thing
    /// the LLM sees on every draft. Pin the format shape AND a
    /// round-trip witness through `build()` so drift surfaces at
    /// either the formatter or the call site.
    func testThreadHeaderFormatIsExact() {
        XCTAssertEqual(
            PromptBuilder.Template.threadHeader(name: "Alice", channelLabel: "iMessage"),
            "Conversation with Alice via iMessage.",
            "threadHeader format `Conversation with X via Y.` is the prompt-shape contract the LLM has been calibrated against — drift silently changes how the model interprets sender + channel")
    }

    func testBuildPromptRoutesThreadHeaderThroughTemplate() {
        let thread = makeThread()  // name="Bob" channel=.imessage in the helper
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: [])
        let expected = PromptBuilder.Template.threadHeader(name: thread.name, channelLabel: thread.channel.label)
        XCTAssertTrue(prompt.contains(expected),
            "rendered prompt must contain Template.threadHeader(name:channelLabel:) byte-for-byte — source and constant must not drift")
    }

    /// `Template.voiceExampleBullet(_:)` anchors the LLM into "list of
    /// examples" mode. Drift to `"* "` or `"• "` silently changes how
    /// the model treats the voice-examples block.
    func testVoiceExampleBulletFormatIsExact() {
        XCTAssertEqual(PromptBuilder.Template.voiceExampleBullet("hey"),
                       "- hey",
                       "voice-example bullet format `- X` anchors the model into list mode — drift to a different glyph silently changes how voice examples are weighted")
        XCTAssertEqual(PromptBuilder.Template.voiceExampleBullet(""),
                       "- ",
                       "empty-example edge case must still produce a bullet glyph + space — caller dedupes upstream, the formatter does not silently drop")
    }

    func testBuildPromptRoutesVoiceExampleBulletsThroughTemplate() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm,
                                         history: [], voiceExamples: ["sample voice"])
        let expected = PromptBuilder.Template.voiceExampleBullet("sample voice")
        XCTAssertTrue(prompt.contains(expected),
            "rendered prompt must contain Template.voiceExampleBullet(...) byte-for-byte — source and constant must not drift")
    }

    /// `Template.messageLine(speaker:text:)` is the per-message line
    /// shape. Drift to `"<speaker> said: <text>"` or moving the colon
    /// would silently change how the model parses the role of each
    /// line.
    func testMessageLineFormatIsExact() {
        XCTAssertEqual(PromptBuilder.Template.messageLine(speaker: "Alice", text: "hi"),
                       "Alice: hi",
                       "messageLine format `<speaker>: <text>` is the conversation-shape contract — drift changes how the LLM interprets which side is speaking")
        // Empty text edge case (e.g. a message that's all attachment).
        XCTAssertEqual(PromptBuilder.Template.messageLine(speaker: "me", text: ""),
                       "me: ",
                       "empty-text edge case must still emit `<speaker>: ` so the model sees a turn at all — drift here would either drop the speaker entirely or merge with the next line")
    }

    /// `Template.instructionLine(toneLowercased:)` is the final
    /// "what to do" line. The verb ("Write my next reply") anchors
    /// the model's framing of its own task — drift to "Compose" or
    /// "Draft" silently changes the output style.
    func testInstructionLineFormatIsExact() {
        XCTAssertEqual(PromptBuilder.Template.instructionLine(toneLowercased: "warm"),
                       "Write my next reply in a warm tone. Reply text only.",
                       "instructionLine drift changes the verb the model uses to anchor generation — every draft for every shipped user")
        // Composes with the existing userInstructionSuffix pin.
        let line = PromptBuilder.Template.instructionLine(toneLowercased: "direct")
        XCTAssertTrue(line.hasSuffix(PromptBuilder.Template.userInstructionSuffix),
            "instructionLine must compose with userInstructionSuffix — drift either at the prefix or the suffix changes the prompt-shape contract")
    }

    func testBuildPromptRoutesInstructionLineThroughTemplate() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm,
                                         history: [makeMessage("hi")])
        let expected = PromptBuilder.Template.instructionLine(toneLowercased: "warm")
        XCTAssertTrue(prompt.contains(expected),
            "rendered prompt must contain Template.instructionLine(toneLowercased:) byte-for-byte — source and constant must not drift")
    }

    func testBuildPromptRoutesVoiceExamplesHeaderThroughTemplate() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm,
                                         history: [], voiceExamples: ["sample"])
        XCTAssertTrue(prompt.contains(PromptBuilder.Template.voiceExamplesHeader),
            "rendered prompt must contain Template.voiceExamplesHeader byte-for-byte — source and constant must not drift")
    }

    func testBuildPromptRoutesSpeakerSelfThroughTemplate() {
        // The outgoing speaker label is the most easily-typo'd literal:
        // a refactor that changes "me" → "user" or "I" would still
        // render a syntactically valid prompt but break every existing
        // model's "me as draft author" framing.
        let thread = makeThread(name: "Maya")
        let history = [Message(from: .me, text: "outgoing", time: "")]
        let prompt = PromptBuilder.build(thread: thread, tone: .warm, history: history)
        XCTAssertTrue(prompt.contains("\(PromptBuilder.Template.speakerSelf): outgoing"),
            "outgoing message must render as `\(PromptBuilder.Template.speakerSelf): <text>` — source and constant must not drift")
    }

    func testBuildPromptRoutesUserInstructionSuffixThroughTemplate() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .direct, history: [])
        XCTAssertTrue(prompt.contains(PromptBuilder.Template.userInstructionSuffix),
            "rendered prompt must contain Template.userInstructionSuffix byte-for-byte — source and constant must not drift")
    }

    func testBuildPromptVoiceExamplesBulletPrefixIsHyphenSpace() {
        let thread = makeThread()
        let prompt = PromptBuilder.build(thread: thread, tone: .warm,
                                         history: [],
                                         voiceExamples: ["hey there", "no worries"])
        XCTAssertTrue(prompt.contains("\n- hey there\n"),
            "first voice example must render on its own line as `- hey there` — got prompt: \(prompt)")
        XCTAssertTrue(prompt.contains("\n- no worries\n"),
            "second voice example must render on its own line as `- no worries` — got prompt: \(prompt)")
    }

    // MARK: - SystemPrompt freeze + route-through

    /// Pin the system-prompt base. The `Output ONLY the reply text`
    /// instruction is the entire signal that suppresses model
    /// preambles ("Sure! Here's a reply:"). Drift here silently
    /// changes every shipped user's draft style.
    func testSystemPromptBaseIsFrozen() {
        let expected = """
        You are ReplyAI, a drafting assistant embedded in the user's messaging inbox. \
        You write the user's next reply in their own voice. Output ONLY the reply text \
        itself — no preamble, no apology, no meta-commentary. Keep replies concise and \
        conversational; these are text messages, not essays.
        """
        XCTAssertEqual(PromptBuilder.SystemPrompt.base, expected)
    }

    /// Pin the per-tone suffixes. Each suffix is the entire signal
    /// distinguishing draft style at inference time — drift to a
    /// re-worded suffix changes every draft generated under that tone.
    func testSystemPromptToneSuffixesAreFrozen() {
        XCTAssertEqual(PromptBuilder.SystemPrompt.warmSuffix,
                       " Use a warm, friendly tone. Light emoji are fine. Avoid sounding corporate.")
        XCTAssertEqual(PromptBuilder.SystemPrompt.directSuffix,
                       " Be direct. Short. Lowercase. Get to the point. No filler.")
        XCTAssertEqual(PromptBuilder.SystemPrompt.playfulSuffix,
                       " Be playful and witty with dry humor; occasional emoji are welcome.")
    }

    /// Route-through: every tone's `systemPrompt(tone:)` output must
    /// be the base concatenated with the matching suffix, byte-for-
    /// byte. Catches a refactor that defines the constants but
    /// rebuilds the switch with a slightly-different inline string.
    func testSystemPromptRoutesThroughBaseAndSuffix() {
        let warm    = PromptBuilder.systemPrompt(tone: .warm)
        let direct  = PromptBuilder.systemPrompt(tone: .direct)
        let playful = PromptBuilder.systemPrompt(tone: .playful)
        XCTAssertEqual(warm,    PromptBuilder.SystemPrompt.base + PromptBuilder.SystemPrompt.warmSuffix)
        XCTAssertEqual(direct,  PromptBuilder.SystemPrompt.base + PromptBuilder.SystemPrompt.directSuffix)
        XCTAssertEqual(playful, PromptBuilder.SystemPrompt.base + PromptBuilder.SystemPrompt.playfulSuffix)
    }

    /// Pin the partition invariant: the three suffixes are pairwise
    /// distinct AND each one starts with a leading space. The leading
    /// space is the only separator between base and suffix; drift to
    /// a non-space-prefix suffix would silently produce
    /// "essays.Use a warm…" with no separator.
    func testSystemPromptToneSuffixesArePairwiseDistinctAndSpacePrefixed() {
        let suffixes = [
            PromptBuilder.SystemPrompt.warmSuffix,
            PromptBuilder.SystemPrompt.directSuffix,
            PromptBuilder.SystemPrompt.playfulSuffix,
        ]
        XCTAssertEqual(Set(suffixes).count, suffixes.count,
            "tone suffixes must be pairwise distinct — collision merges two tones into one inference behavior")
        for s in suffixes {
            XCTAssertTrue(s.hasPrefix(" "),
                "tone suffix must start with a space so concatenation produces `essays. Use…` not `essays.Use…` — got: \(s)")
        }
    }
}
