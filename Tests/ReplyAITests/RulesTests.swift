import XCTest
@testable import ReplyAI

final class RulesTests: XCTestCase {
    // MARK: - Codable round-trips

    func testPredicateJSONRoundtrip_simple() throws {
        let cases: [RulePredicate] = [
            .senderIs("Maya"),
            .senderContains("maya"),
            .channelIs(.slack),
            .textContains("deck"),
            .textMatchesRegex(#"\d{6}"#),
            .isUnread,
            .senderUnknown,
        ]
        for p in cases {
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
            XCTAssertEqual(p, decoded, "round-trip mismatch for \(p)")
        }
    }

    func testPredicateJSONRoundtrip_nested() throws {
        let p: RulePredicate = .and([
            .channelIs(.slack),
            .or([.senderContains("maya"), .senderContains("ravi")]),
            .not(.isUnread),
        ])
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
        XCTAssertEqual(p, decoded)
    }

    func testActionJSONRoundtrip() throws {
        let cases: [RuleAction] = [.archive, .pin, .markDone, .silentlyIgnore, .setDefaultTone(.direct)]
        for a in cases {
            let data = try JSONEncoder().encode(a)
            let decoded = try JSONDecoder().decode(RuleAction.self, from: data)
            XCTAssertEqual(a, decoded)
        }
    }

    func testSmartRuleJSONRoundtrip() throws {
        let rule = SmartRule(
            name: "Slack deck pings",
            when: .and([.channelIs(.slack), .textContains("deck")]),
            then: .setDefaultTone(.direct)
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(SmartRule.self, from: data)
        XCTAssertEqual(rule, decoded)
    }

    // MARK: - Evaluation

    func testSimpleEvaluationMatches() {
        let ctx = RuleContext(
            senderName: "Maya Chen",
            senderHandle: "maya",
            channel: .slack,
            lastMessageText: "can you review the deck?",
            isUnread: true,
            senderKnown: true
        )
        XCTAssertTrue(RuleEvaluator.matches(.channelIs(.slack), in: ctx))
        XCTAssertTrue(RuleEvaluator.matches(.senderContains("maya"), in: ctx))
        XCTAssertTrue(RuleEvaluator.matches(.textContains("deck"), in: ctx))
        XCTAssertTrue(RuleEvaluator.matches(.isUnread, in: ctx))
        XCTAssertFalse(RuleEvaluator.matches(.channelIs(.whatsapp), in: ctx))
    }

    func testCompoundEvaluation() {
        let ctx = RuleContext(
            senderName: "Maya Chen",
            senderHandle: "maya",
            channel: .slack,
            lastMessageText: "can you review the deck before 4?",
            isUnread: true,
            senderKnown: true
        )
        let predicate: RulePredicate = .and([
            .channelIs(.slack),
            .senderContains("maya"),
            .textContains("deck"),
        ])
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx))

        let notPredicate: RulePredicate = .not(.isUnread)
        XCTAssertFalse(RuleEvaluator.matches(notPredicate, in: ctx))
    }

    func testRegexPredicateMatches2FA() {
        let ctx = RuleContext(
            senderName: "+15551234567",
            senderHandle: "+15551234567",
            channel: .sms,
            lastMessageText: "Your verification code is 820193",
            isUnread: true,
            senderKnown: false
        )
        XCTAssertTrue(RuleEvaluator.matches(.textMatchesRegex(#"(?i)\bverification code\b"#), in: ctx))
        XCTAssertTrue(RuleEvaluator.matches(.textMatchesRegex(#"\b\d{6}\b"#), in: ctx))
    }

    func testInactiveRuleSkipped() {
        var rule = SmartRule(
            name: "test", when: .channelIs(.slack), then: .archive, active: false
        )
        let ctx = RuleContext(
            senderName: "x", senderHandle: "x", channel: .slack,
            lastMessageText: "", isUnread: false, senderKnown: true
        )
        XCTAssertTrue(RuleEvaluator.matching([rule], in: ctx).isEmpty)
        rule.active = true
        XCTAssertEqual(RuleEvaluator.matching([rule], in: ctx).count, 1)
    }

    func testDefaultToneFromRules() {
        let rules = [
            SmartRule(name: "a", when: .channelIs(.imessage), then: .pin),
            SmartRule(name: "b", when: .channelIs(.slack),    then: .setDefaultTone(.direct)),
        ]
        let ctx = RuleContext(
            senderName: "x", senderHandle: "x", channel: .slack,
            lastMessageText: "", isUnread: false, senderKnown: true
        )
        XCTAssertEqual(RuleEvaluator.defaultTone(for: rules, in: ctx), .direct)
    }

    // MARK: - Store

    @MainActor
    func testStoreSeedsOnEmptyFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = RulesStore(fileURL: tmp)
        XCTAssertEqual(store.rules.count, SmartRule.seedRules.count)
    }

    @MainActor
    func testStoreRoundTripsAddedRule() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let store = RulesStore(fileURL: tmp)
        let custom = SmartRule(
            name: "my custom", when: .channelIs(.teams), then: .pin
        )
        store.add(custom)

        let reopened = RulesStore(fileURL: tmp)
        XCTAssertTrue(reopened.rules.contains(custom))
    }

    // MARK: - Integration with InboxViewModel

    @MainActor
    func testSelectThreadAppliesDefaultToneRule() throws {
        // Build a store with a single rule: when channel is slack AND
        // sender contains "Maya", set default tone to .direct. Feed it
        // into an InboxViewModel seeded with Maya's fixture thread.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = RulesStore(fileURL: tmp)
        // Reset to a known single rule.
        for r in store.rules { store.remove(r.id) }
        store.add(SmartRule(
            name: "test · Maya → direct",
            when: .and([.channelIs(.slack), .senderContains("Maya")]),
            then: .setDefaultTone(.direct)
        ))

        let model = InboxViewModel(
            threads: Fixtures.threads,
            imessage: nil,        // unused for this test
            rules: store
        )
        XCTAssertEqual(model.activeTone, .warm, "sanity: default tone before rule fires")

        model.selectThread("t1")  // Maya Chen, Slack
        XCTAssertEqual(model.activeTone, .direct, "rule should flip tone to direct")
    }

    @MainActor
    func testSelectThreadAppliesPinRule() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = RulesStore(fileURL: tmp)
        for r in store.rules { store.remove(r.id) }
        store.add(SmartRule(
            name: "pin anything Slack",
            when: .channelIs(.slack),
            then: .pin
        ))

        let model = InboxViewModel(
            threads: Fixtures.threads,
            imessage: nil,
            rules: store
        )
        // t3 is Ravi (Linear) — slack, NOT pre-pinned in Fixtures.
        XCTAssertFalse(
            model.threads.first(where: { $0.id == "t3" })?.pinned ?? true,
            "sanity: t3 starts unpinned"
        )

        model.selectThread("t3")
        XCTAssertTrue(
            model.threads.first(where: { $0.id == "t3" })?.pinned ?? false,
            "pin rule should flip pinned to true"
        )
    }

    @MainActor
    func testSelectThreadSkipsRulesWhenNoMatch() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = RulesStore(fileURL: tmp)
        for r in store.rules { store.remove(r.id) }
        store.add(SmartRule(
            name: "only whatsapp",
            when: .channelIs(.whatsapp),
            then: .setDefaultTone(.playful)
        ))

        let model = InboxViewModel(
            threads: Fixtures.threads,
            imessage: nil,
            rules: store
        )
        model.selectThread("t1")  // Slack thread — rule should NOT fire
        XCTAssertEqual(model.activeTone, .warm, "tone should stay at default when no rule matches")
    }

    // MARK: - Incoming-message rule actions

    /// Minimal ChannelService double: serves a fixed thread list and
    /// returns preconfigured incoming messages keyed by thread id,
    /// filtered by the sinceRowID watermark.
    private struct MockChannel: ChannelService {
        let fixedThreads: [MessageThread]
        let incoming: [String: [Message]]
        func recentThreads(limit: Int) async throws -> [MessageThread] { fixedThreads }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
            incoming[id] ?? []
        }
        func newIncomingMessages(forThreadID id: String, sinceRowID: Int64) async throws -> [Message] {
            (incoming[id] ?? [])
                .filter { $0.rowID > sinceRowID }
                .sorted { $0.rowID < $1.rowID }
        }
    }

    @MainActor
    private func makeModelWithRules(
        _ rules: [SmartRule],
        threads: [MessageThread],
        incoming: [String: [Message]]
    ) -> InboxViewModel {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = RulesStore(fileURL: tmp)
        for r in store.rules { store.remove(r.id) }
        for r in rules { store.add(r) }

        // Clear any archived state left behind by a previous test run.
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")

        return InboxViewModel(
            threads: threads,
            imessage: MockChannel(fixedThreads: threads, incoming: incoming),
            rules: store
        )
    }

    @MainActor
    func testIncomingArchiveRuleFires() async throws {
        let thread = MessageThread(
            id: "spam-1", channel: .sms, name: "Promo Alerts",
            avatar: "P", preview: "weekly sale ends soon",
            time: "now", unread: 2
        )
        let rule = SmartRule(
            name: "archive promos",
            when: .senderContains("Promo"),
            then: .archive
        )
        let model = makeModelWithRules(
            [rule],
            threads: [thread],
            incoming: ["spam-1": [
                Message(from: .them, text: "weekly sale", time: "now", rowID: 100)
            ]]
        )

        XCTAssertFalse(model.archivedThreadIDs.contains("spam-1"))
        await model.processIncomingForRules(model.threads)
        XCTAssertTrue(model.archivedThreadIDs.contains("spam-1"))
    }

    @MainActor
    func testIncomingMarkDoneClearsUnread() async throws {
        let thread = MessageThread(
            id: "2fa-1", channel: .sms, name: "+18885551234",
            avatar: "☎", preview: "verification code 820193",
            time: "now", unread: 3
        )
        let rule = SmartRule(
            name: "mark 2fa done",
            when: .textMatchesRegex(#"(?i)verification code"#),
            then: .markDone
        )
        let model = makeModelWithRules(
            [rule],
            threads: [thread],
            incoming: ["2fa-1": [
                Message(from: .them, text: "your verification code is 820193", time: "now", rowID: 1)
            ]]
        )

        await model.processIncomingForRules(model.threads)
        XCTAssertEqual(
            model.threads.first(where: { $0.id == "2fa-1" })?.unread, 0,
            "markDone should zero unread"
        )
    }

    @MainActor
    func testIncomingWatermarkPreventsDoubleFire() async throws {
        // If we process twice with the same data, an action should fire
        // only once. We can't observe "did the side effect run twice?"
        // for archive (it's idempotent set insertion), so use a counter
        // indirectly: after the first pass, changing the rule and doing
        // a second pass with no NEW messages should NOT reapply.
        let thread = MessageThread(
            id: "t", channel: .imessage, name: "Mom",
            avatar: "M", preview: "hi", time: "now", unread: 1
        )
        let rule = SmartRule(
            name: "pretend-archive",
            when: .channelIs(.imessage),
            then: .archive
        )
        let model = makeModelWithRules(
            [rule],
            threads: [thread],
            incoming: ["t": [
                Message(from: .them, text: "hi", time: "now", rowID: 5)
            ]]
        )

        await model.processIncomingForRules(model.threads)
        XCTAssertTrue(model.archivedThreadIDs.contains("t"))

        // Unarchive manually, run again with no NEW messages (rowID 5
        // already seen). Archive rule should NOT reapply.
        model.unarchive("t")
        await model.processIncomingForRules(model.threads)
        XCTAssertFalse(
            model.archivedThreadIDs.contains("t"),
            "watermark should have stopped the rule from re-firing on the same message"
        )
    }

    @MainActor
    func testArchivedIDsPersistAcrossInstances() async throws {
        let thread = MessageThread(
            id: "s", channel: .sms, name: "Bot",
            avatar: "B", preview: "", time: "", unread: 0
        )
        let rule = SmartRule(name: "arc", when: .channelIs(.sms), then: .archive)
        let model = makeModelWithRules(
            [rule],
            threads: [thread],
            incoming: ["s": [
                Message(from: .them, text: "x", time: "", rowID: 1)
            ]]
        )
        await model.processIncomingForRules(model.threads)
        XCTAssertTrue(model.archivedThreadIDs.contains("s"))

        // New InboxViewModel instance pulls archived state from UserDefaults.
        let second = InboxViewModel(threads: [thread])
        XCTAssertTrue(second.archivedThreadIDs.contains("s"))

        // Clean up for subsequent tests.
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")
    }

    @MainActor
    func testStoreTogglePersists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let store = RulesStore(fileURL: tmp)
        let id = store.rules[0].id
        let wasActive = store.rules[0].active
        store.toggle(id)

        let reopened = RulesStore(fileURL: tmp)
        XCTAssertEqual(reopened.rules.first(where: { $0.id == id })?.active, !wasActive)
    }
}
