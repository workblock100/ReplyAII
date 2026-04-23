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

    // MARK: - senderIs case-insensitive (REP-065)

    func testSenderIsCaseInsensitiveMatch() {
        let ctx = RuleContext(
            senderName: "Alice Smith",
            senderHandle: "alice",
            channel: .imessage,
            lastMessageText: "hey",
            isUnread: true,
            senderKnown: true,
            chatIdentifier: ""
        )
        XCTAssertTrue(RuleEvaluator.matches(.senderIs("alice smith"), in: ctx),
                      "lowercase rule must match mixed-case display name")
        XCTAssertTrue(RuleEvaluator.matches(.senderIs("ALICE SMITH"), in: ctx),
                      "uppercase rule must also match")
        XCTAssertTrue(RuleEvaluator.matches(.senderIs("Alice Smith"), in: ctx),
                      "exact-case match must still work")
    }

    func testSenderIsCaseInsensitiveMismatch() {
        let ctx = RuleContext(
            senderName: "Alice Smith",
            senderHandle: "alice",
            channel: .imessage,
            lastMessageText: "hey",
            isUnread: true,
            senderKnown: true,
            chatIdentifier: ""
        )
        XCTAssertFalse(RuleEvaluator.matches(.senderIs("bob"), in: ctx),
                       "different name must not match regardless of case")
        XCTAssertFalse(RuleEvaluator.matches(.senderIs("Alice"), in: ctx),
                       "partial name match must not match (senderIs is full-string)")
    }

    // MARK: - Evaluation

    func testSimpleEvaluationMatches() {
        let ctx = RuleContext(
            senderName: "Maya Chen",
            senderHandle: "maya",
            channel: .slack,
            lastMessageText: "can you review the deck?",
            isUnread: true,
            senderKnown: true,
            chatIdentifier: ""
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
            senderKnown: true,
            chatIdentifier: ""
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
            senderKnown: false,
            chatIdentifier: ""
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
            lastMessageText: "", isUnread: false, senderKnown: true,
            chatIdentifier: ""
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
            lastMessageText: "", isUnread: false, senderKnown: true,
            chatIdentifier: ""
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
        try store.add(custom)

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
        try store.add(SmartRule(
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
        try store.add(SmartRule(
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
        try store.add(SmartRule(
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
        for r in rules { try? store.add(r) }

        // Clear any archived/silenced state left behind by a previous test run.
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")
        UserDefaults.standard.removeObject(forKey: "pref.inbox.silentlyIgnoredThreadIDs")

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

    // MARK: - REP-004: silentlyIgnore vs archive parity

    @MainActor
    func testSilentlyIgnoreAndArchiveAreDistinct() async throws {
        let threadA = MessageThread(
            id: "thread-archive", channel: .sms, name: "Archive Bot",
            avatar: "A", preview: "", time: "", unread: 1
        )
        let threadB = MessageThread(
            id: "thread-silent", channel: .sms, name: "Silent Bot",
            avatar: "S", preview: "", time: "", unread: 1
        )
        let archiveRule = SmartRule(name: "archive-a", when: .senderContains("Archive"), then: .archive)
        let silentRule  = SmartRule(name: "silent-b",  when: .senderContains("Silent"),  then: .silentlyIgnore)

        let model = makeModelWithRules(
            [archiveRule, silentRule],
            threads: [threadA, threadB],
            incoming: [
                "thread-archive": [Message(from: .them, text: "sale!", time: "", rowID: 1)],
                "thread-silent":  [Message(from: .them, text: "newsletter", time: "", rowID: 2)],
            ]
        )

        await model.processIncomingForRules(model.threads)

        // archive lands only in archivedThreadIDs
        XCTAssertTrue(model.archivedThreadIDs.contains("thread-archive"), "archive rule → archivedThreadIDs")
        XCTAssertFalse(model.silentlyIgnoredThreadIDs.contains("thread-archive"), "archive must not leak into silentlyIgnoredThreadIDs")

        // silentlyIgnore lands only in silentlyIgnoredThreadIDs
        XCTAssertTrue(model.silentlyIgnoredThreadIDs.contains("thread-silent"), "silentlyIgnore → silentlyIgnoredThreadIDs")
        XCTAssertFalse(model.archivedThreadIDs.contains("thread-silent"), "silentlyIgnore must not leak into archivedThreadIDs")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")
        UserDefaults.standard.removeObject(forKey: "pref.inbox.silentlyIgnoredThreadIDs")
    }

    @MainActor
    func testMenuBarHidesSilentlyIgnored() async throws {
        let visible = MessageThread(
            id: "visible", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hey", time: "", unread: 2
        )
        let silenced = MessageThread(
            id: "silenced", channel: .sms, name: "Newsletter Co",
            avatar: "N", preview: "weekly deals", time: "", unread: 1
        )
        let silentRule = SmartRule(name: "hush newsletter", when: .senderContains("Newsletter"), then: .silentlyIgnore)

        let model = makeModelWithRules(
            [silentRule],
            threads: [visible, silenced],
            incoming: [
                "silenced": [Message(from: .them, text: "deals", time: "", rowID: 1)]
            ]
        )

        // Before rules fire both threads are unread → both would be waiting.
        XCTAssertEqual(model.menuBarWaitingThreads.count, 2, "precondition: both unread before rule fires")

        await model.processIncomingForRules(model.threads)

        // After the rule fires, silenced thread must vanish from the menu-bar list.
        let ids = model.menuBarWaitingThreads.map(\.id)
        XCTAssertTrue(ids.contains("visible"),   "visible thread must remain in menu-bar list")
        XCTAssertFalse(ids.contains("silenced"), "silently-ignored thread must not appear in menu-bar list")

        // Archived threads (not silenced) must still appear in the menu-bar list.
        // Add an archived thread to confirm the distinction.
        model.archivedThreadIDs.insert("visible")   // simulate archive action on `visible`
        XCTAssertTrue(
            model.menuBarWaitingThreads.map(\.id).contains("visible"),
            "archived thread is still unread → must remain in menu-bar count"
        )

        // Clean up
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")
        UserDefaults.standard.removeObject(forKey: "pref.inbox.silentlyIgnoredThreadIDs")
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
        UserDefaults.standard.removeObject(forKey: "pref.inbox.silentlyIgnoredThreadIDs")
    }

    // MARK: - REP-001: lastSeenRowID persistence

    @MainActor
    func testLastSeenRowIDPersistsAcrossInstances() async throws {
        // Start with a clean slate.
        UserDefaults.standard.removeObject(forKey: "pref.inbox.lastSeenRowID")
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")

        let thread = MessageThread(
            id: "watermark-thread", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hey", time: "now", unread: 1
        )
        let rule = SmartRule(name: "no-op", when: .channelIs(.imessage), then: .markDone)
        let model = makeModelWithRules(
            [rule],
            threads: [thread],
            incoming: ["watermark-thread": [
                Message(from: .them, text: "hey", time: "now", rowID: 42)
            ]]
        )

        // Process once so the watermark for "watermark-thread" advances to 42.
        await model.processIncomingForRules(model.threads)

        // A new InboxViewModel instance should hydrate the watermark from UserDefaults
        // and NOT re-fire the rule against the same rowID.
        let second = makeModelWithRules(
            [SmartRule(name: "archive-check", when: .channelIs(.imessage), then: .archive)],
            threads: [thread],
            incoming: ["watermark-thread": [
                Message(from: .them, text: "hey", time: "now", rowID: 42)
            ]]
        )
        // The archive rule would normally fire against rowID 42, but the watermark
        // persisted from the first instance already marks it as seen.
        await second.processIncomingForRules(second.threads)
        XCTAssertFalse(
            second.archivedThreadIDs.contains("watermark-thread"),
            "persisted watermark should prevent re-firing on already-seen rowID"
        )

        // Clean up.
        UserDefaults.standard.removeObject(forKey: "pref.inbox.lastSeenRowID")
        UserDefaults.standard.removeObject(forKey: "pref.inbox.archivedThreadIDs")
        UserDefaults.standard.removeObject(forKey: "pref.inbox.silentlyIgnoredThreadIDs")
    }

    // MARK: - REP-002: SmartRule priority + conflict resolution

    func testHigherPrioritySetDefaultToneWins() {
        // Two rules both match, both set tone. Higher priority should win.
        let lowPriority = SmartRule(
            name: "low",
            when: .channelIs(.imessage),
            then: .setDefaultTone(.warm),
            priority: 0
        )
        let highPriority = SmartRule(
            name: "high",
            when: .channelIs(.imessage),
            then: .setDefaultTone(.direct),
            priority: 10
        )
        let ctx = RuleContext(
            senderName: "x", senderHandle: "x", channel: .imessage,
            lastMessageText: "", isUnread: false, senderKnown: true,
            chatIdentifier: ""
        )
        // Low-priority rule is first in the array; high-priority must still win.
        let tone = RuleEvaluator.defaultTone(for: [lowPriority, highPriority], in: ctx)
        XCTAssertEqual(tone, .direct, "higher priority rule should override lower")
    }

    func testPriorityFieldMissingDefaultsToZero() throws {
        // JSON without a "priority" key should decode with priority == 0.
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "name": "legacy",
          "when": {"kind": "is_unread"},
          "then": {"kind": "archive"},
          "active": true
        }
        """.data(using: .utf8)!
        let rule = try JSONDecoder().decode(SmartRule.self, from: json)
        XCTAssertEqual(rule.priority, 0, "missing priority field should decode as 0")
    }

    func testPriorityRoundTripsThroughJSON() throws {
        let rule = SmartRule(
            name: "urgent",
            when: .channelIs(.slack),
            then: .setDefaultTone(.direct),
            priority: 5
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(SmartRule.self, from: data)
        XCTAssertEqual(decoded.priority, 5)
        XCTAssertEqual(decoded, rule)
    }

    func testPriorityTiebreakerPreservesInsertionOrder() {
        // When priorities are equal, the first rule in the input array wins.
        let first = SmartRule(
            name: "first",
            when: .channelIs(.imessage),
            then: .setDefaultTone(.warm),
            priority: 0
        )
        let second = SmartRule(
            name: "second",
            when: .channelIs(.imessage),
            then: .setDefaultTone(.direct),
            priority: 0
        )
        let ctx = RuleContext(
            senderName: "x", senderHandle: "x", channel: .imessage,
            lastMessageText: "", isUnread: false, senderKnown: true,
            chatIdentifier: ""
        )
        let matched = RuleEvaluator.matching([first, second], in: ctx)
        XCTAssertEqual(matched.first?.name, "first", "equal priority: insertion order is tiebreaker")
        let tone = RuleEvaluator.defaultTone(for: [first, second], in: ctx)
        XCTAssertEqual(tone, .warm)
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

    // MARK: - REP-012: remove / update / resetToSeeds coverage

    @MainActor
    func testRemoveRulePersistsToDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let store = RulesStore(fileURL: tmp)
        let rule = SmartRule(name: "to remove", when: .channelIs(.slack), then: .archive)
        try store.add(rule)
        XCTAssertTrue(store.rules.contains(rule), "precondition: rule present before remove")

        store.remove(rule.id)

        let reopened = RulesStore(fileURL: tmp)
        XCTAssertFalse(
            reopened.rules.contains(where: { $0.id == rule.id }),
            "removed rule must not appear in a freshly loaded store"
        )
    }

    @MainActor
    func testUpdateRulePersists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let store = RulesStore(fileURL: tmp)
        var rule = SmartRule(name: "original", when: .channelIs(.sms), then: .markDone)
        try store.add(rule)

        rule = SmartRule(id: rule.id, name: "updated", when: .channelIs(.teams), then: .pin, active: rule.active, priority: rule.priority)
        store.update(rule)

        let reopened = RulesStore(fileURL: tmp)
        let found = reopened.rules.first(where: { $0.id == rule.id })
        XCTAssertEqual(found?.name, "updated", "updated name should persist")
        XCTAssertEqual(found?.then, .pin, "updated action should persist")
        XCTAssertEqual(found?.when, .channelIs(.teams), "updated predicate should persist")
    }

    @MainActor
    func testResetToSeedsRestoresDefaults() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let store = RulesStore(fileURL: tmp)
        // Remove all seeds and add a custom rule so the state differs from seed.
        for r in store.rules { store.remove(r.id) }
        try store.add(SmartRule(name: "custom", when: .channelIs(.whatsapp), then: .archive))

        store.resetToSeeds()

        let reopened = RulesStore(fileURL: tmp)
        XCTAssertEqual(
            reopened.rules.map(\.id).sorted(),
            SmartRule.seedRules.map(\.id).sorted(),
            "resetToSeeds should restore exactly the seed rule IDs"
        )
        XCTAssertFalse(
            reopened.rules.contains(where: { $0.name == "custom" }),
            "custom rule must be gone after reset"
        )
    }

    @MainActor
    func testRemoveNonExistentUUIDIsNoOp() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let store = RulesStore(fileURL: tmp)
        let countBefore = store.rules.count

        // Remove a UUID that was never added.
        store.remove(UUID())

        XCTAssertEqual(store.rules.count, countBefore, "rule count must not change on phantom remove")
        let reopened = RulesStore(fileURL: tmp)
        XCTAssertEqual(reopened.rules.count, countBefore, "persisted count must not change either")
    }

    // MARK: - REP-018: isGroupChat + hasAttachment predicates

    func testIsGroupChatPredicateTrue() {
        let ctx = RuleContext(
            senderName: "Launch Crew",
            senderHandle: "chat1234567890",
            channel: .imessage,
            lastMessageText: "hey",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "chat1234567890"
        )
        XCTAssertTrue(RuleEvaluator.matches(.isGroupChat, in: ctx))
    }

    func testIsGroupChatPredicateFalse() {
        let ctx = RuleContext(
            senderName: "Alice",
            senderHandle: "+14155551234",
            channel: .imessage,
            lastMessageText: "hey",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "+14155551234"
        )
        XCTAssertFalse(RuleEvaluator.matches(.isGroupChat, in: ctx))
    }

    func testHasAttachmentPredicateTrue() {
        // hasAttachment is now driven by cache_has_attachments from chat.db,
        // not the "📎 Attachment" sentinel — RuleContext.hasAttachment must be true.
        var ctx = RuleContext(
            senderName: "Alice",
            senderHandle: "+14155551234",
            channel: .imessage,
            lastMessageText: "📎 Attachment",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "+14155551234"
        )
        ctx.hasAttachment = true
        XCTAssertTrue(RuleEvaluator.matches(.hasAttachment, in: ctx))
    }

    func testHasAttachmentPredicateFalse() {
        let ctx = RuleContext(
            senderName: "Alice",
            senderHandle: "+14155551234",
            channel: .imessage,
            lastMessageText: "just a text",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "+14155551234"
        )
        // hasAttachment defaults to false — sentinel text alone must not fire.
        XCTAssertFalse(RuleEvaluator.matches(.hasAttachment, in: ctx))
    }

    func testNewPredicatesCodableRoundTrip() throws {
        let rules: [SmartRule] = [
            SmartRule(name: "group", when: .isGroupChat, then: .pin),
            SmartRule(name: "attachment", when: .hasAttachment, then: .archive),
        ]
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([SmartRule].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].when, .isGroupChat)
        XCTAssertEqual(decoded[1].when, .hasAttachment)
    }

    // MARK: - RulesStore: malformed-rule skipping (REP-024)

    private func tempRulesURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAIRulesTests-\(UUID().uuidString).json")
    }

    private func validRuleJSON() throws -> String {
        let rule = SmartRule(name: "valid", when: .isUnread, then: .archive)
        let data = try JSONEncoder().encode(rule)
        return String(data: data, encoding: .utf8)!
    }

    @MainActor
    func testMalformedRuleIsSkipped() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let valid = try validRuleJSON()
        // Embed one valid rule and one clearly malformed object.
        let json = "[\(valid), {\"broken\": true}]"
        try json.data(using: .utf8)!.write(to: url)

        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        XCTAssertEqual(store.rules.count, 1, "malformed entry must be skipped")
        XCTAssertEqual(store.rules.first?.name, "valid")
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 1)
    }

    @MainActor
    func testPartiallyCorruptRulesFileLoadsValidRules() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let valid = try validRuleJSON()
        // Three valid, two malformed interleaved.
        let json = """
        [
          \(valid),
          {"kind": "unknown_kind"},
          \(valid),
          {},
          \(valid)
        ]
        """
        try json.data(using: .utf8)!.write(to: url)

        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        XCTAssertEqual(store.rules.count, 3, "three valid rules must load")
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 2)
    }

    @MainActor
    func testFullyCorruptJSONFallsBackToSeeds() throws {
        let url = tempRulesURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("broken"))
        }

        try "not json at all %%%".data(using: .utf8)!.write(to: url)

        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        // Invalid JSON → seeds, no skips recorded (treated as fully corrupt).
        XCTAssertFalse(store.rules.isEmpty, "seeds must be loaded when file is invalid JSON")
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 0)
    }

    @MainActor
    func testEmptyArrayLoadsZeroRules() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try "[]".data(using: .utf8)!.write(to: url)

        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        XCTAssertEqual(store.rules.count, 0)
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 0)
    }

    // MARK: - Regex validation (REP-031)

    func testValidRegexPasses() {
        XCTAssertNoThrow(try SmartRule.validateRegex(#"\d{6}"#))
        XCTAssertNoThrow(try SmartRule.validateRegex(#"(?i)hello"#))
        XCTAssertNoThrow(try SmartRule.validateRegex(#"[a-z]+"#))
    }

    func testInvalidRegexThrows() {
        XCTAssertThrowsError(try SmartRule.validateRegex("[unclosed")) { error in
            guard let ve = error as? RuleValidationError,
                  case .invalidRegex(let pattern, _) = ve else {
                XCTFail("Expected RuleValidationError.invalidRegex, got \(error)")
                return
            }
            XCTAssertEqual(pattern, "[unclosed")
        }
    }

    func testErrorMessageContainsPattern() {
        do {
            try SmartRule.validateRegex("[unclosed")
            XCTFail("Should have thrown")
        } catch let error as RuleValidationError {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains("[unclosed"),
                          "error description must embed the offending pattern: \(description)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func testAddValidatingRejectsInvalidRegex() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        let badRule = SmartRule(
            name: "Bad regex rule",
            when: .textMatchesRegex("[unclosed"),
            then: .pin
        )
        XCTAssertThrowsError(try store.addValidating(badRule))
        XCTAssertTrue(store.rules.allSatisfy { $0.id != badRule.id },
                      "invalid rule must not be stored")
    }

    @MainActor
    func testAddValidatingAcceptsValidRegex() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        let goodRule = SmartRule(
            name: "Good regex rule",
            when: .textMatchesRegex(#"\d{6}"#),
            then: .archive
        )
        let before = store.rules.count
        XCTAssertNoThrow(try store.addValidating(goodRule))
        XCTAssertEqual(store.rules.count, before + 1)
    }

    @MainActor
    func testAddValidatingNestedRegex() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let stats = Stats(fileURL: tempRulesURL())
        let store = RulesStore(fileURL: url, stats: stats)
        let nestedBad = SmartRule(
            name: "Nested bad regex",
            when: .and([.textContains("hi"), .textMatchesRegex("[bad")]),
            then: .pin
        )
        XCTAssertThrowsError(try store.addValidating(nestedBad),
                             "validation must walk nested predicates")
    }

    // MARK: - 100-rule cap (REP-069)

    @MainActor
    func testAddUpToCapSucceeds() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RulesStore(fileURL: url)
        // Start from zero rules.
        store.rules.forEach { store.remove($0.id) }
        XCTAssertEqual(RulesStore.maxRules, 100)
        for i in 0..<RulesStore.maxRules {
            let rule = SmartRule(name: "rule-\(i)", when: .isUnread, then: .archive)
            XCTAssertNoThrow(try store.add(rule), "add at \(i) must not throw before cap")
        }
        XCTAssertEqual(store.rules.count, RulesStore.maxRules)
    }

    @MainActor
    func testAddBeyondCapThrows() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }
        for i in 0..<RulesStore.maxRules {
            try? store.add(SmartRule(name: "r\(i)", when: .isUnread, then: .archive))
        }
        XCTAssertEqual(store.rules.count, RulesStore.maxRules,
            "precondition: store is exactly at cap")
        XCTAssertThrowsError(
            try store.add(SmartRule(name: "overflow", when: .isUnread, then: .pin))
        ) { error in
            guard let ve = error as? RuleValidationError,
                  case .tooManyRules(let limit) = ve else {
                XCTFail("Expected tooManyRules, got \(error)")
                return
            }
            XCTAssertEqual(limit, RulesStore.maxRules)
        }
        XCTAssertEqual(store.rules.count, RulesStore.maxRules,
            "count must not change after a rejected add")
    }

    // MARK: - lastFiredActions debug surface (REP-058)

    @MainActor
    func testLastFiredActionsPopulatedOnMatch() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }

        let rule = SmartRule(name: "unread pin", when: .isUnread, then: .pin, active: true)
        try store.add(rule)

        let ctx = RuleContext(
            senderName: "Alice",
            senderHandle: "+14155551234",
            channel: .imessage,
            lastMessageText: "hey",
            isUnread: true,
            senderKnown: true,
            chatIdentifier: "+14155551234"
        )

        store.evaluate(for: ctx)

        XCTAssertEqual(store.lastFiredActions.count, 1, "one matching rule must produce one entry")
        XCTAssertEqual(store.lastFiredActions[0].ruleID, rule.id)
        if case .pin = store.lastFiredActions[0].action { /* expected */ } else {
            XCTFail("expected .pin action, got \(store.lastFiredActions[0].action)")
        }
    }

    @MainActor
    func testLastFiredActionsEmptyOnNoMatch() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }

        // Rule only fires when isUnread; the context below is read.
        let rule = SmartRule(name: "unread archive", when: .isUnread, then: .archive, active: true)
        try store.add(rule)

        let ctx = RuleContext(
            senderName: "Bob",
            senderHandle: "+15555550101",
            channel: .imessage,
            lastMessageText: "hello",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "+15555550101"
        )

        store.evaluate(for: ctx)

        XCTAssertTrue(store.lastFiredActions.isEmpty,
                      "no matching rule must leave lastFiredActions empty")
    }

    // MARK: - RulesStore: export + import (REP-035)

    private func tmpURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RulesTests-\(name)-\(UUID().uuidString).json")
    }

    @MainActor
    func testExportRoundTrips() throws {
        let storeURL = tmpURL("export-store")
        let exportURL = tmpURL("export-out")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        let rule = SmartRule(name: "export test", when: .senderIs("Alice"), then: .pin)
        try store.add(rule)

        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: tmpURL("export-reimport"))
        try importStore.import(from: exportURL)
        XCTAssertTrue(importStore.rules.contains(where: { $0.id == rule.id }),
                      "exported rule must be importable by UUID")
        XCTAssertEqual(importStore.rules.first(where: { $0.id == rule.id })?.name,
                       "export test")
    }

    @MainActor
    func testImportMergesNewRules() throws {
        let storeURL = tmpURL("merge-store")
        let exportURL = tmpURL("merge-export")
        let targetURL = tmpURL("merge-target")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
            try? FileManager.default.removeItem(at: targetURL)
        }
        let source = RulesStore(fileURL: storeURL)
        let newRule = SmartRule(name: "incoming", when: .textContains("meeting"), then: .archive)
        try source.add(newRule)
        try source.export(to: exportURL)

        let target = RulesStore(fileURL: targetURL)
        let preCount = target.rules.count
        try target.import(from: exportURL)

        XCTAssertEqual(target.rules.count, preCount + 1,
                       "import must append rules with new UUIDs")
        XCTAssertTrue(target.rules.contains(where: { $0.id == newRule.id }))
    }

    @MainActor
    func testImportUpdatesExistingRule() throws {
        let storeURL = tmpURL("update-store")
        let exportURL = tmpURL("update-export")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        let original = SmartRule(name: "original name", when: .senderIs("Bob"), then: .pin)
        try store.add(original)

        // Mutate a copy with the same UUID and export it from a separate store.
        let updated = SmartRule(id: original.id, name: "updated name",
                                when: original.when, then: original.then,
                                active: original.active, priority: original.priority)
        let tempStore = RulesStore(fileURL: tmpURL("update-temp"))
        try tempStore.add(updated)
        try tempStore.export(to: exportURL)

        try store.import(from: exportURL)
        XCTAssertEqual(store.rules.first(where: { $0.id == original.id })?.name,
                       "updated name", "import must update the rule in place when UUID matches")
    }

    @MainActor
    func testImportSkipsMalformed() throws {
        let targetURL = tmpURL("malformed-target")
        let malformedURL = tmpURL("malformed-src")
        defer {
            try? FileManager.default.removeItem(at: targetURL)
            try? FileManager.default.removeItem(at: malformedURL)
        }
        // Write a versioned envelope with one valid rule and one corrupt object.
        let validRule = SmartRule(name: "valid", when: .senderIs("Carol"), then: .archive)
        let validData = try JSONEncoder().encode(validRule)
        let validObj = try JSONSerialization.jsonObject(with: validData)
        let envelope: [String: Any] = [
            "version": 1,
            "rules": [validObj, ["bad_key": "no kind field"]]
        ]
        let mixedData = try JSONSerialization.data(withJSONObject: envelope)
        try mixedData.write(to: malformedURL)

        let target = RulesStore(fileURL: targetURL)
        let before = target.rules.count
        XCTAssertNoThrow(try target.import(from: malformedURL),
                         "import must not throw on malformed entries")
        XCTAssertEqual(target.rules.count, before + 1,
                       "only the valid rule must be appended; malformed entry skipped")
        XCTAssertTrue(target.rules.contains(where: { $0.id == validRule.id }))
    }

    // MARK: - RulesStore: export version field (REP-110)

    @MainActor
    func testExportIncludesVersionField() throws {
        let storeURL = tmpURL("ver-store")
        let exportURL = tmpURL("ver-out")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        try store.add(SmartRule(name: "v1 rule", when: .senderIs("Dave"), then: .pin))
        try store.export(to: exportURL)

        let data = try Data(contentsOf: exportURL)
        let obj = try XCTUnwrap(try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                "export must produce a JSON object, not a bare array")
        XCTAssertEqual(obj["version"] as? Int, 1, "export must include version: 1")
        XCTAssertNotNil(obj["rules"], "export must include a rules key")
    }

    @MainActor
    func testImportRoundTripWithVersionField() throws {
        let storeURL = tmpURL("ver-rt-store")
        let exportURL = tmpURL("ver-rt-out")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        let rule = SmartRule(name: "roundtrip", when: .senderIs("Eve"), then: .archive)
        try store.add(rule)
        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: tmpURL("ver-rt-reimport"))
        try importStore.import(from: exportURL)
        XCTAssertTrue(importStore.rules.contains(where: { $0.id == rule.id }),
                      "versioned export must round-trip correctly via import")
    }

    @MainActor
    func testImportUnknownVersionThrows() throws {
        let targetURL = tmpURL("ver-unknown-target")
        let badURL = tmpURL("ver-unknown-src")
        defer {
            try? FileManager.default.removeItem(at: targetURL)
            try? FileManager.default.removeItem(at: badURL)
        }
        let envelope: [String: Any] = ["version": 99, "rules": []]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        try data.write(to: badURL)

        let target = RulesStore(fileURL: targetURL)
        do {
            try target.import(from: badURL)
            XCTFail("import of unknown version must throw")
        } catch RulesStoreError.unsupportedExportVersion(let v) {
            XCTAssertEqual(v, 99, "thrown error must carry the actual version number")
        }
    }

    // MARK: - `not` predicate (REP-100)

    func testNotPredicateNegatesMatch() {
        let aliceCtx = RuleContext(
            senderName: "Alice", senderHandle: "alice",
            channel: .imessage, lastMessageText: "hey",
            isUnread: false, senderKnown: true, chatIdentifier: ""
        )
        let bobCtx = RuleContext(
            senderName: "Bob", senderHandle: "bob",
            channel: .imessage, lastMessageText: "yo",
            isUnread: false, senderKnown: true, chatIdentifier: ""
        )
        XCTAssertFalse(RuleEvaluator.matches(.not(.senderIs("Alice")), in: aliceCtx),
                       "not(senderIs) must return false when sender IS Alice")
        XCTAssertTrue(RuleEvaluator.matches(.not(.senderIs("Alice")), in: bobCtx),
                      "not(senderIs) must return true when sender is NOT Alice")
    }

    func testDoubleNegationEquivalentToOriginal() {
        let ctx = RuleContext(
            senderName: "Alice", senderHandle: "alice",
            channel: .imessage, lastMessageText: "hi",
            isUnread: true, senderKnown: true, chatIdentifier: ""
        )
        let base = RuleEvaluator.matches(.senderIs("Alice"), in: ctx)
        let doubleNot = RuleEvaluator.matches(.not(.not(.senderIs("Alice"))), in: ctx)
        XCTAssertEqual(base, doubleNot,
                       "not(not(p)) must equal p — evaluator must not short-circuit")
    }

    func testNotOrDeMorganEquivalence() {
        // De Morgan: not(A or B) == not(A) and not(B)
        let ctx = RuleContext(
            senderName: "Alice", senderHandle: "alice",
            channel: .slack, lastMessageText: "deck",
            isUnread: false, senderKnown: true, chatIdentifier: ""
        )
        let notOr = RuleEvaluator.matches(.not(.or([.senderIs("Alice"), .senderIs("Bob")])), in: ctx)
        let andNots = RuleEvaluator.matches(.and([.not(.senderIs("Alice")), .not(.senderIs("Bob"))]), in: ctx)
        XCTAssertEqual(notOr, andNots, "De Morgan law: not(A or B) must equal and(not A, not B)")
    }

    // MARK: - `or` predicate with 3+ branches (REP-113)

    func testOr3BranchesMiddleMatchReturnsTrue() {
        let ctx = RuleContext(
            senderName: "Maya", senderHandle: "maya",
            channel: .imessage, lastMessageText: "hi",
            isUnread: false, senderKnown: true, chatIdentifier: ""
        )
        // First and last branches do NOT match; middle one does.
        let pred: RulePredicate = .or([.senderIs("Alice"), .senderIs("Maya"), .senderIs("Bob")])
        XCTAssertTrue(RuleEvaluator.matches(pred, in: ctx),
                      "or([nomatch, match, nomatch]) must return true")
    }

    func testOr3BranchesNoneMatchReturnsFalse() {
        let ctx = RuleContext(
            senderName: "Carol", senderHandle: "carol",
            channel: .imessage, lastMessageText: "hi",
            isUnread: false, senderKnown: true, chatIdentifier: ""
        )
        let pred: RulePredicate = .or([.senderIs("Alice"), .senderIs("Maya"), .senderIs("Bob")])
        XCTAssertFalse(RuleEvaluator.matches(pred, in: ctx),
                       "or([nm, nm, nm]) must return false when no branch matches")
    }

    func testOr3BranchesAllMatchReturnsTrue() {
        let ctx = RuleContext(
            senderName: "Alice", senderHandle: "alice",
            channel: .imessage, lastMessageText: "hi",
            isUnread: true, senderKnown: true, chatIdentifier: ""
        )
        let pred: RulePredicate = .or([.senderIs("Alice"), .isUnread, .textContains("hi")])
        XCTAssertTrue(RuleEvaluator.matches(pred, in: ctx),
                      "or([m, m, m]) must return true when all branches match")
    }

    func testOrEmptyArrayReturnsFalse() {
        let ctx = RuleContext(
            senderName: "Alice", senderHandle: "alice",
            channel: .imessage, lastMessageText: "hi",
            isUnread: false, senderKnown: true, chatIdentifier: ""
        )
        XCTAssertFalse(RuleEvaluator.matches(.or([]), in: ctx),
                       "or([]) must return false — defined behavior for empty disjunction")
    }

    // MARK: - `messageAgeOlderThan` predicate (REP-106)

    func testMessageOlderThanHoursMatches() {
        let now = Date()
        var ctx = RuleContext(
            senderName: "Old Bot", senderHandle: "old",
            channel: .imessage, lastMessageText: "ping",
            isUnread: false, senderKnown: false, chatIdentifier: ""
        )
        ctx.lastMessageDate = now.addingTimeInterval(-25 * 3600) // 25 hours ago
        XCTAssertTrue(
            RuleEvaluator.matches(.messageAgeOlderThan(hours: 24), in: ctx, currentDate: now),
            "Thread last-messaged 25h ago must match messageAgeOlderThan(hours: 24)"
        )
    }

    func testMessageYoungerThanHoursDoesNotMatch() {
        let now = Date()
        var ctx = RuleContext(
            senderName: "Recent Bot", senderHandle: "recent",
            channel: .imessage, lastMessageText: "pong",
            isUnread: false, senderKnown: false, chatIdentifier: ""
        )
        ctx.lastMessageDate = now.addingTimeInterval(-1 * 3600) // 1 hour ago
        XCTAssertFalse(
            RuleEvaluator.matches(.messageAgeOlderThan(hours: 24), in: ctx, currentDate: now),
            "Thread last-messaged 1h ago must NOT match messageAgeOlderThan(hours: 24)"
        )
    }

    func testMessageAgeOlderThanCodableRoundTrip() throws {
        let pred: RulePredicate = .messageAgeOlderThan(hours: 48)
        let data = try JSONEncoder().encode(pred)
        let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
        XCTAssertEqual(pred, decoded, "messageAgeOlderThan must survive JSON encode/decode round-trip")
        if case .messageAgeOlderThan(let hours) = decoded {
            XCTAssertEqual(hours, 48)
        } else {
            XCTFail("decoded predicate has wrong case")
        }
    }
}

// MARK: - RulesStore concurrent add stress test (REP-120)

@MainActor
final class RulesStoreConcurrencyTests: XCTestCase {

    private func tempRulesURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RulesStoreConcurrency-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rules.json")
    }

    func testConcurrentAddNeverLosesRules() async throws {
        // Spawn 30 concurrent tasks each adding a unique rule to an isolated store.
        // RulesStore is @MainActor so all tasks serialize through the main actor —
        // this guards against any future regression that introduces a data race
        // (e.g. making add() actor-free) and verifies no add is silently dropped.
        let store = RulesStore(fileURL: tempRulesURL())
        // Clear seed rules so we start from 0.
        for rule in store.rules { store.remove(rule.id) }

        let taskCount = 30
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<taskCount {
                group.addTask { @MainActor in
                    let rule = SmartRule(
                        name: "concurrent-rule-\(i)",
                        when: .senderIs("bot\(i)"),
                        then: .archive
                    )
                    try? store.add(rule)
                }
            }
        }
        XCTAssertEqual(store.rules.count, taskCount,
                       "All \(taskCount) concurrent adds must land — no rule silently dropped")
    }
}

// MARK: - REP-116: hasUnread predicate

final class HasUnreadPredicateTests: XCTestCase {

    private func ctx(unread: Int) -> RuleContext {
        RuleContext(
            senderName: "Test", senderHandle: "test",
            channel: .imessage, lastMessageText: "hello",
            isUnread: unread > 0, unreadCount: unread, senderKnown: true, chatIdentifier: "chat1"
        )
    }

    func testHasUnreadMatchesPositiveCount() {
        XCTAssertTrue(
            RuleEvaluator.matches(.hasUnread, in: ctx(unread: 3)),
            "hasUnread must match when unreadCount > 0"
        )
    }

    func testHasUnreadDoesNotMatchZeroCount() {
        XCTAssertFalse(
            RuleEvaluator.matches(.hasUnread, in: ctx(unread: 0)),
            "hasUnread must not match when unreadCount == 0"
        )
    }

    func testHasUnreadCodableRoundTrip() throws {
        let pred: RulePredicate = .hasUnread
        let data = try JSONEncoder().encode(pred)
        let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
        XCTAssertEqual(pred, decoded, "hasUnread must survive JSON encode/decode round-trip")
        if case .hasUnread = decoded { } else { XCTFail("decoded predicate has wrong case") }
    }

    func testNotHasUnreadMatchesReadThread() {
        XCTAssertTrue(
            RuleEvaluator.matches(.not(.hasUnread), in: ctx(unread: 0)),
            "not(hasUnread) must match a thread with zero unread messages"
        )
        XCTAssertFalse(
            RuleEvaluator.matches(.not(.hasUnread), in: ctx(unread: 1)),
            "not(hasUnread) must not match a thread with unread messages"
        )
    }
}
