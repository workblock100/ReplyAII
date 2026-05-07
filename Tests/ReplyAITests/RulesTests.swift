import XCTest
@testable import ReplyAI

final class RulesTests: XCTestCase {

    /// testSelectThreadAppliesPinRule instantiates an InboxViewModel that
    /// reads pinnedThreadIDs from UserDefaults.standard (REP-178). Clear
    /// the key before each test so "t3 starts unpinned" stays true after
    /// other test runs have written the key.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "pref.inbox.pinnedThreadIDs")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "pref.inbox.pinnedThreadIDs")
        super.tearDown()
    }

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

    // MARK: - kind discriminator strings — persistence contract
    //
    // Every shipped rules.json is keyed by these exact strings. Round-trip
    // tests above confirm encode→decode is symmetric, but they don't catch
    // a refactor that *renames* a kind value (e.g. "is_unread" → "unread"
    // or "silently_ignore" → "silentlyIgnore"): the symmetric pair would
    // still pass while every existing user's rules.json silently became
    // un-decodable. Pin the literal `kind` string per case here.

    /// Encode a predicate, parse the JSON, and return the value of the
    /// top-level "kind" key. Forces an inspection of the wire format
    /// rather than a round-trip-symmetric value comparison.
    private func encodedKind<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                "encoded predicate/action must be a JSON object")
        return try XCTUnwrap(obj["kind"] as? String,
                             "encoded predicate/action must include a top-level kind discriminator")
    }

    func testPredicateKindDiscriminatorsAreStable() throws {
        // Each pair is (predicate variant, expected kind string in rules.json).
        // Order matches SmartRule.RulePredicate.Kind to make additions easy
        // to spot.
        let cases: [(RulePredicate, String)] = [
            (.senderIs("x"),                   "sender_is"),
            (.senderContains("x"),             "sender_contains"),
            (.channelIs(.slack),               "channel_is"),
            (.textContains("x"),               "text_contains"),
            (.textMatchesRegex("x"),           "text_matches_regex"),
            (.isUnread,                        "is_unread"),
            (.senderUnknown,                   "sender_unknown"),
            (.isGroupChat,                     "is_group_chat"),
            (.hasAttachment,                   "has_attachment"),
            (.and([.isUnread]),                "and"),
            (.or([.isUnread]),                 "or"),
            (.not(.isUnread),                  "not"),
            (.messageAgeOlderThan(hours: 1),   "message_age_older_than"),
            (.hasUnread,                       "has_unread"),
            (.timeOfDay(startHour: 9, endHour: 17), "time_of_day"),
            (.threadNameMatchesRegex(pattern: "x"), "thread_name_matches_regex"),
            (.messageCount(atLeast: 2),             "message_count_at_least"),
            (.contactGroupMatchesName(groupName: "x"), "contact_group_matches_name"),
        ]
        for (predicate, expected) in cases {
            let kind = try encodedKind(predicate)
            XCTAssertEqual(kind, expected,
                "RulePredicate \(predicate) must encode kind=\"\(expected)\" — renaming orphans every rules.json with this clause")
        }
    }

    func testActionKindDiscriminatorsAreStable() throws {
        let cases: [(RuleAction, String)] = [
            (.archive,                  "archive"),
            (.pin,                      "pin"),
            (.silentlyIgnore,           "silently_ignore"),
            (.markDone,                 "mark_done"),
            (.setDefaultTone(.direct),  "set_default_tone"),
        ]
        for (action, expected) in cases {
            let kind = try encodedKind(action)
            XCTAssertEqual(kind, expected,
                "RuleAction \(action) must encode kind=\"\(expected)\" — renaming orphans every rules.json with this action")
        }
    }

    func testPredicateKindDecodesFromCanonicalJSON() throws {
        // Decode-side check for every standalone kind. If a future refactor
        // renames the rawValue, this test fails at the decode call rather
        // than silently treating a previously-valid rules.json as malformed.
        let canonicals: [(String, RulePredicate)] = [
            (#"{"kind":"is_unread"}"#,         .isUnread),
            (#"{"kind":"sender_unknown"}"#,    .senderUnknown),
            (#"{"kind":"is_group_chat"}"#,     .isGroupChat),
            (#"{"kind":"has_attachment"}"#,    .hasAttachment),
            (#"{"kind":"has_unread"}"#,        .hasUnread),
        ]
        for (json, expected) in canonicals {
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
            XCTAssertEqual(decoded, expected,
                "canonical JSON \(json) must decode to \(expected) — kind renames break shipped rules.json")
        }
    }

    // MARK: - CodingKeys field names — wire-format contract
    //
    // The kind-discriminator tests above guarantee `kind` strings stay
    // stable. The associated-value field names (`value`, `hours`,
    // `clauses`, `clause`, `start_hour`, `end_hour`, `at_least`,
    // `group_name`) are equally part of the on-disk contract — a
    // rename in `RulePredicate.CodingKeys` orphans every shipped
    // rules.json with that variant. Pin the literal JSON object shape
    // for each variant so a typo in CodingKeys surfaces here.

    /// Encode a predicate and return the parsed JSON object so individual
    /// field names can be asserted.
    private func encodedJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testValueFieldUsedForStringPredicates() throws {
        // senderIs / senderContains / textContains / textMatchesRegex /
        // threadNameMatchesRegex all use the `value` key — pin literally.
        let cases: [(RulePredicate, String)] = [
            (.senderIs("alice"),                       "alice"),
            (.senderContains("ali"),                   "ali"),
            (.textContains("deck"),                    "deck"),
            (.textMatchesRegex("^urgent"),             "^urgent"),
            (.threadNameMatchesRegex(pattern: "team"), "team"),
        ]
        for (pred, expected) in cases {
            let json = try encodedJSON(pred)
            XCTAssertEqual(json["value"] as? String, expected,
                "\(pred) must encode its string under the `value` key — renaming the CodingKey breaks rules.json")
        }
    }

    func testChannelIsUsesValueKey() throws {
        let json = try encodedJSON(RulePredicate.channelIs(.slack))
        XCTAssertEqual(json["value"] as? String, "slack",
            "channelIs must encode its Channel rawValue under the `value` key")
    }

    func testMessageAgeOlderThanUsesHoursKey() throws {
        let json = try encodedJSON(RulePredicate.messageAgeOlderThan(hours: 48))
        XCTAssertEqual(json["hours"] as? Int, 48,
            "messageAgeOlderThan must encode its hours under the `hours` key")
    }

    func testTimeOfDayUsesStartEndHourKeys() throws {
        let json = try encodedJSON(RulePredicate.timeOfDay(startHour: 22, endHour: 6))
        XCTAssertEqual(json["start_hour"] as? Int, 22,
            "timeOfDay must encode startHour under the `start_hour` key")
        XCTAssertEqual(json["end_hour"] as? Int, 6,
            "timeOfDay must encode endHour under the `end_hour` key")
    }

    func testMessageCountUsesAtLeastKey() throws {
        let json = try encodedJSON(RulePredicate.messageCount(atLeast: 5))
        XCTAssertEqual(json["at_least"] as? Int, 5,
            "messageCount must encode its threshold under the `at_least` key")
    }

    func testContactGroupMatchesNameUsesGroupNameKey() throws {
        let json = try encodedJSON(RulePredicate.contactGroupMatchesName(groupName: "Family"))
        XCTAssertEqual(json["group_name"] as? String, "Family",
            "contactGroupMatchesName must encode its name under the `group_name` key")
    }

    func testAndOrUseClausesKey() throws {
        let andJSON = try encodedJSON(RulePredicate.and([.isUnread, .hasUnread]))
        XCTAssertNotNil(andJSON["clauses"],
            "and(...) must encode its child predicates under the `clauses` key")
        let arr = try XCTUnwrap(andJSON["clauses"] as? [[String: Any]])
        XCTAssertEqual(arr.count, 2)

        let orJSON = try encodedJSON(RulePredicate.or([.isUnread]))
        XCTAssertNotNil(orJSON["clauses"],
            "or(...) must encode its child predicates under the `clauses` key")
    }

    func testNotUsesClauseKey() throws {
        let json = try encodedJSON(RulePredicate.not(.isUnread))
        XCTAssertNotNil(json["clause"],
            "not(...) must encode its inner predicate under the singular `clause` key (not `clauses`)")
        XCTAssertNil(json["clauses"],
            "not(...) must NOT use `clauses` — that key is reserved for and/or")
    }

    func testSetDefaultToneActionUsesValueKey() throws {
        let json = try encodedJSON(RuleAction.setDefaultTone(.direct))
        XCTAssertEqual(json["value"] as? String, "Direct",
            "setDefaultTone must encode its Tone rawValue under the `value` key")
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

    @MainActor
    func testLastSeenRowIDLoadsFromLiteralKey() async throws {
        // The existing persistence test (testLastSeenRowIDPersistsAcrossInstances)
        // verifies behavior across instances using `UserDefaults.standard`, but
        // both save and load go through the same private constant — a silent
        // rename of `pref.inbox.lastSeenRowID` would still pass that test. Pin
        // the literal key here by writing payload directly at the literal,
        // building a fresh model, and observing that the rule engine treats
        // those rowIDs as already-seen. If the key drifts, the watermark won't
        // hydrate and the archive rule will fire.
        let suite = "test.ReplyAI.lastSeenRowID-literal-key.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        let payload = try JSONEncoder().encode(["watermark-literal": Int64(99)])
        d.set(payload, forKey: "pref.inbox.lastSeenRowID")

        let thread = MessageThread(
            id: "watermark-literal", channel: .imessage, name: "Pinner",
            avatar: "P", preview: "x", time: "now", unread: 1
        )
        let rule = SmartRule(name: "would archive", when: .channelIs(.imessage), then: .archive)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAITests-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = RulesStore(fileURL: tmp)
        for r in store.rules { store.remove(r.id) }
        try store.add(rule)

        // Incoming rowID 50 is below the persisted watermark (99) — if the
        // load path read the literal key the rule must not fire. If the key
        // drifted, lastSeenRowID would default to 0 and the rule would archive
        // the thread.
        let model = InboxViewModel(
            threads: [thread],
            imessage: MockChannel(
                fixedThreads: [thread],
                incoming: ["watermark-literal": [
                    Message(from: .them, text: "old", time: "now", rowID: 50)
                ]]
            ),
            rules: store,
            defaults: d
        )

        await model.processIncomingForRules(model.threads)

        XCTAssertFalse(
            model.archivedThreadIDs.contains("watermark-literal"),
            "lastSeenRowID load path must read 'pref.inbox.lastSeenRowID' literally — renaming abandons every shipped user's watermark and re-fires every rule against already-seen messages"
        )
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

    // MARK: - REP-170 contactGroupMatchesName

    private func contactGroupCtx(groups: [String]) -> RuleContext {
        RuleContext(
            senderName: "Maya Chen",
            senderHandle: "+14155551234",
            channel: .imessage,
            lastMessageText: "hi",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "+14155551234",
            contactGroupNames: groups
        )
    }

    func testContactGroupMatchesWhenGroupPresent() {
        let ctx = contactGroupCtx(groups: ["Family", "Coworkers"])
        XCTAssertTrue(RuleEvaluator.matches(.contactGroupMatchesName(groupName: "Family"), in: ctx))
    }

    func testContactGroupNoMatchWhenGroupAbsent() {
        let ctx = contactGroupCtx(groups: ["Coworkers"])
        XCTAssertFalse(RuleEvaluator.matches(.contactGroupMatchesName(groupName: "Family"), in: ctx))
    }

    func testContactGroupCaseInsensitive() {
        let ctx = contactGroupCtx(groups: ["family"])
        XCTAssertTrue(RuleEvaluator.matches(.contactGroupMatchesName(groupName: "FAMILY"), in: ctx),
                      "match must be case-insensitive so users don't have to mirror their Contacts capitalization")
    }

    func testContactGroupMatchesPartialName() {
        // localizedCaseInsensitiveContains — querying "Fam" should hit "Family Group".
        let ctx = contactGroupCtx(groups: ["Family Group"])
        XCTAssertTrue(RuleEvaluator.matches(.contactGroupMatchesName(groupName: "Fam"), in: ctx))
    }

    func testContactGroupEmptyGroupsReturnsFalse() {
        let ctx = contactGroupCtx(groups: [])
        XCTAssertFalse(RuleEvaluator.matches(.contactGroupMatchesName(groupName: "Family"), in: ctx),
                       "no groups resolved → predicate must short-circuit to false (no Contacts permission case)")
    }

    func testContactGroupMatchesCodableRoundTrip() throws {
        let rule = SmartRule(
            name: "Family default tone",
            when: .contactGroupMatchesName(groupName: "Family"),
            then: .setDefaultTone(.warm)
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(SmartRule.self, from: data)
        guard case .contactGroupMatchesName(let g) = decoded.when else {
            XCTFail("expected contactGroupMatchesName, got \(decoded.when)"); return
        }
        XCTAssertEqual(g, "Family")
    }

    /// Empty `groupName` does NOT match any group — Swift's
    /// `localizedCaseInsensitiveContains("")` returns `false` for empty
    /// patterns (unlike `hasPrefix("")` / `hasSuffix("")` which return
    /// true). Pin the safe-by-default behaviour because it's surprising
    /// to anyone who knows the prefix/suffix variants — a future
    /// "consistency fix" that swapped the matcher for one that DID
    /// short-circuit empty as true would silently match every group on
    /// the user's device.
    func testContactGroupMatchesEmptyNameNeverMatches() {
        let ctxWithGroups = contactGroupCtx(groups: ["Coworkers", "Family"])
        XCTAssertFalse(RuleEvaluator.matches(.contactGroupMatchesName(groupName: ""), in: ctxWithGroups),
            "empty groupName must not match any group — Swift's localizedCaseInsensitiveContains returns false on empty pattern, unlike has{Prefix,Suffix}")

        let ctxNoGroups = contactGroupCtx(groups: [])
        XCTAssertFalse(RuleEvaluator.matches(.contactGroupMatchesName(groupName: ""), in: ctxNoGroups),
            "empty groupName + empty groups list also returns false — short-circuits via the empty list")
    }

    // MARK: - REP-016 senderKnown classification

    private func makeThread(name: String) -> MessageThread {
        MessageThread(
            id: name, channel: .imessage, name: name,
            avatar: "?", preview: "hi", time: "now", unread: 0
        )
    }

    func testSenderKnownTrueForContactName() {
        let ctx = RuleContext.from(thread: makeThread(name: "Maya Chen"))
        XCTAssertTrue(ctx.senderKnown,
                      "a real contact name (no @, no leading +, has letters) must classify as known")
    }

    func testSenderKnownFalseForPhoneWithPlusPrefix() {
        let ctx = RuleContext.from(thread: makeThread(name: "+14155551234"))
        XCTAssertFalse(ctx.senderKnown, "+E.164 phone must classify as unknown")
    }

    func testSenderKnownFalseForEmailHandle() {
        // Pre-REP-016 fix: operator precedence parsed `(notPlus && notAt) || !isPhonelike`
        // so emails fell into the `||` branch and were mis-classified as known.
        let ctx = RuleContext.from(thread: makeThread(name: "user@example.com"))
        XCTAssertFalse(ctx.senderKnown, "email-shaped handle must classify as unknown")
    }

    func testSenderKnownFalseForFormattedPhone() {
        // "(415) 555-1234" — all chars are in the phone-charset ("+0123456789 ()-").
        // Pre-REP-016 fix this was classified as known (the inline expression's `||`
        // branch fired); now it correctly falls into the phonelike check.
        let ctx = RuleContext.from(thread: makeThread(name: "(415) 555-1234"))
        XCTAssertFalse(ctx.senderKnown, "US-formatted phone must classify as unknown")
    }

    func testSenderKnownFalseForDigitOnlyHandle() {
        let ctx = RuleContext.from(thread: makeThread(name: "4155551234"))
        XCTAssertFalse(ctx.senderKnown, "digit-only handle must classify as unknown")
    }

    func testSenderUnknownPredicateFiresOnEmail() {
        // End-to-end: the .senderUnknown predicate must now match an email handle.
        let ctx = RuleContext.from(thread: makeThread(name: "user@example.com"))
        XCTAssertTrue(RuleEvaluator.matches(.senderUnknown, in: ctx),
                      ".senderUnknown must fire on email handles after REP-016 fix")
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

    // MARK: - REP-220: concurrent add + remove does not corrupt rules array

    func testConcurrentAddRemoveNoCrash() async throws {
        // Rapidly interleave 50 adds and 50 removes on the same store.
        // RulesStore is @MainActor so tasks serialize through the main actor;
        // this guards against any future regression that removes that isolation
        // and introduces a real race between add() and remove().
        let store = RulesStore(fileURL: tempRulesURL())
        for rule in store.rules { store.remove(rule.id) }

        var addedIDs: [UUID] = []
        for i in 0..<50 {
            let rule = SmartRule(name: "add-remove-\(i)", when: .senderIs("x\(i)"), then: .archive)
            try? store.add(rule)
            addedIDs.append(rule.id)
        }

        await withTaskGroup(of: Void.self) { group in
            for id in addedIDs {
                group.addTask { @MainActor in store.remove(id) }
            }
            for i in 50..<100 {
                group.addTask { @MainActor in
                    let rule = SmartRule(name: "refill-\(i)", when: .senderIs("y\(i)"), then: .pin)
                    try? store.add(rule)
                }
            }
        }
        // Must not crash; final count must be non-negative.
        XCTAssertGreaterThanOrEqual(store.rules.count, 0,
                                    "Rules count must be ≥0 after concurrent add+remove")
    }

    func testConcurrentAddRemoveNoDuplicateIDs() async throws {
        let store = RulesStore(fileURL: tempRulesURL())
        for rule in store.rules { store.remove(rule.id) }

        // Add 50 rules then concurrently remove half and add 25 new ones.
        var firstBatch: [SmartRule] = []
        for i in 0..<50 {
            let rule = SmartRule(name: "batch-\(i)", when: .senderIs("s\(i)"), then: .archive)
            try? store.add(rule)
            firstBatch.append(rule)
        }

        let toRemove = Array(firstBatch.prefix(25))
        await withTaskGroup(of: Void.self) { group in
            for rule in toRemove {
                group.addTask { @MainActor in store.remove(rule.id) }
            }
            for i in 50..<75 {
                group.addTask { @MainActor in
                    let r = SmartRule(name: "new-\(i)", when: .senderIs("n\(i)"), then: .pin)
                    try? store.add(r)
                }
            }
        }

        let ids = store.rules.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count,
                       "No duplicate UUIDs must appear in rules after concurrent add+remove")
    }
}

// MARK: - REP-116: hasUnread predicate

final class HasUnreadPredicateTests: XCTestCase {

    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAIHasUnreadTests-\(UUID().uuidString).json")
    }

    private func validRuleJSON() throws -> String {
        let rule = SmartRule(name: "valid", when: .isUnread, then: .archive)
        let data = try JSONEncoder().encode(rule)
        return String(data: data, encoding: .utf8)!
    }

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

    // MARK: - REP-143: rules array preserves insertion order

    @MainActor
    func testRulesArrayPreservesInsertionOrder() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RulesStore(fileURL: url)
        // Clear seed rules so we start clean.
        for rule in store.rules { store.remove(rule.id) }

        let ruleA = SmartRule(name: "A", when: .isUnread, then: .archive, priority: 0)
        let ruleB = SmartRule(name: "B", when: .isUnread, then: .pin,     priority: 5)
        try store.add(ruleA)
        try store.add(ruleB)

        // Insertion order: A first, then B — regardless of B's higher priority.
        XCTAssertEqual(store.rules.last?.name, "B",
                       "rules array must preserve insertion order, not sort by priority")
        XCTAssertEqual(store.rules.first(where: { $0.name == "A" })?.name, "A")
    }

    @MainActor
    func testLoadFromJSONPreservesFileOrder() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let r1 = SmartRule(name: "first",  when: .isUnread, then: .archive, priority: 0)
        let r2 = SmartRule(name: "second", when: .isUnread, then: .pin,     priority: 10)
        let r3 = SmartRule(name: "third",  when: .isUnread, then: .markDone, priority: 5)
        let json = try JSONEncoder().encode([r1, r2, r3])
        try json.write(to: url)

        let store = RulesStore(fileURL: url)
        let names = store.rules.map(\.name)
        XCTAssertEqual(names, ["first", "second", "third"],
                       "RulesStore must load rules in file order, not sorted by priority")
    }

    @MainActor
    func testUpdateDoesNotReorderRules() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RulesStore(fileURL: url)
        for rule in store.rules { store.remove(rule.id) }

        let ruleA = SmartRule(name: "A", when: .isUnread, then: .archive, priority: 0)
        let ruleB = SmartRule(name: "B", when: .isUnread, then: .pin,     priority: 1)
        try store.add(ruleA)
        try store.add(ruleB)

        // Update A's priority to be higher than B's — must not change position.
        let updated = SmartRule(id: ruleA.id, name: "A", when: .isUnread, then: .archive,
                                priority: 99)
        store.update(updated)

        let firstID = store.rules.first(where: { $0.name == "A" }).map(\.id)
        let secondID = store.rules.first(where: { $0.name == "B" }).map(\.id)
        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertEqual(store.rules.map { $0.name }.filter { $0 == "A" || $0 == "B" },
                       ["A", "B"],
                       "update must not reorder rules even when priority changes")
    }

    // MARK: - REP-144: unknown RuleAction kind decoded gracefully

    func testUnknownRuleActionKindThrowsDecodingError() {
        let json = #"{"kind":"unknown_future_action"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RuleAction.self, from: json),
                             "unknown action kind must throw DecodingError, not crash") { error in
            XCTAssertTrue(error is DecodingError,
                          "expected DecodingError but got \(type(of: error))")
        }
    }

    @MainActor
    func testRulesStoreSkipsRuleWithUnknownAction() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let valid = try validRuleJSON()
        // One valid rule, one with an unknown action kind.
        let unknownActionJSON = """
        {"id":"00000000-0000-0000-0000-000000000000","name":"future","isActive":true,"priority":0,\
        "when":{"kind":"is_unread"},"then":{"kind":"unknown_future_action"}}
        """
        let json = "[\(valid), \(unknownActionJSON)]"
        try json.data(using: String.Encoding.utf8)!.write(to: url)

        let store = RulesStore(fileURL: url)
        XCTAssertEqual(store.rules.count, 1,
                       "rule with unknown action kind must be skipped, valid rule must load")
        XCTAssertEqual(store.rules.first?.name, "valid")
    }

    // MARK: - REP-188: disk round-trip preserves insertion order

    @MainActor
    func testDiskRoundTripPreservesInsertionOrder() throws {
        let storeURL  = tempURL()
        let exportURL = tempURL()
        let importURL = tempURL()
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
            try? FileManager.default.removeItem(at: importURL)
        }

        let store = RulesStore(fileURL: storeURL)
        for rule in store.rules { store.remove(rule.id) }

        let ruleA = SmartRule(name: "A", when: .isUnread, then: .archive, priority: 0)
        let ruleB = SmartRule(name: "B", when: .isUnread, then: .pin,     priority: 5)
        try store.add(ruleA)
        try store.add(ruleB)

        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: importURL)
        for rule in importStore.rules { importStore.remove(rule.id) }
        try importStore.import(from: exportURL)

        let names = importStore.rules.map(\.name)
        let aIndex = names.firstIndex(of: "A")
        let bIndex = names.firstIndex(of: "B")
        XCTAssertNotNil(aIndex, "rule A must survive export+import")
        XCTAssertNotNil(bIndex, "rule B must survive export+import")
        if let a = aIndex, let b = bIndex {
            XCTAssertLessThan(a, b,
                "insertion order must be preserved: A before B even though B has higher priority")
        }
    }
}

// MARK: - TimeOfDay predicate (REP-079)

final class TimeOfDayPredicateTests: XCTestCase {

    // Build a minimal RuleContext sufficient for time-based tests.
    private func makeCtx() -> RuleContext {
        RuleContext(
            senderName: "Test",
            senderHandle: "test",
            channel: .imessage,
            lastMessageText: "",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "test-id"
        )
    }

    // Helper: make a Date whose Calendar hour is exactly `hour`.
    private func date(hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    func testTimeOfDayWithinRangeMatches() {
        let ctx = makeCtx()
        // Range 09–17; inject 14:00 — should match.
        XCTAssertTrue(
            RuleEvaluator.matches(.timeOfDay(startHour: 9, endHour: 17), in: ctx, currentDate: date(hour: 14)),
            "hour 14 must be within 09–17"
        )
        // Boundary: startHour itself matches.
        XCTAssertTrue(
            RuleEvaluator.matches(.timeOfDay(startHour: 9, endHour: 17), in: ctx, currentDate: date(hour: 9)),
            "startHour boundary must match"
        )
        // Boundary: endHour itself matches.
        XCTAssertTrue(
            RuleEvaluator.matches(.timeOfDay(startHour: 9, endHour: 17), in: ctx, currentDate: date(hour: 17)),
            "endHour boundary must match"
        )
    }

    func testTimeOfDayOutsideRangeMismatches() {
        let ctx = makeCtx()
        // Range 09–17; inject 08:00 and 18:00 — neither should match.
        XCTAssertFalse(
            RuleEvaluator.matches(.timeOfDay(startHour: 9, endHour: 17), in: ctx, currentDate: date(hour: 8)),
            "hour 8 must be outside 09–17"
        )
        XCTAssertFalse(
            RuleEvaluator.matches(.timeOfDay(startHour: 9, endHour: 17), in: ctx, currentDate: date(hour: 18)),
            "hour 18 must be outside 09–17"
        )
    }

    func testOvernightWrapAround() {
        let ctx = makeCtx()
        // Overnight range 22–06: hours 22, 23, 0, 3, 6 match; 7, 14 don't.
        let predicate = RulePredicate.timeOfDay(startHour: 22, endHour: 6)
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 22)), "22 matches overnight")
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 23)), "23 matches overnight")
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 0)),  "0 matches overnight")
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 3)),  "3 matches overnight")
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 6)),  "6 matches overnight boundary")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 7)),  "7 does not match overnight")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 14)), "14 does not match overnight")
    }

    func testTimeOfDayCodableRoundTrip() throws {
        let original = RulePredicate.timeOfDay(startHour: 22, endHour: 6)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
        XCTAssertEqual(original, decoded, "timeOfDay must round-trip through JSON")

        // Verify the JSON contains the expected discriminator and fields.
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["kind"] as? String, "time_of_day")
        XCTAssertEqual(json["start_hour"] as? Int, 22)
        XCTAssertEqual(json["end_hour"] as? Int, 6)
    }

    /// `startHour == endHour` is a degenerate single-hour window. The
    /// implementation hits the `startHour <= endHour` branch with both
    /// equal, so the test reduces to `hour >= 14 && hour <= 14` — only
    /// hour 14 matches. Pin both the match and the bracketing non-match
    /// because a future "use < instead of <=" tightening would silently
    /// turn every single-hour rule into a no-op.
    func testTimeOfDaySingleHourWindowMatchesOnlyThatHour() {
        let ctx = makeCtx()
        let predicate = RulePredicate.timeOfDay(startHour: 14, endHour: 14)
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 14)),
            "hour 14 must match a 14–14 single-hour window")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 13)),
            "hour 13 must NOT match a 14–14 single-hour window")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 15)),
            "hour 15 must NOT match a 14–14 single-hour window")
    }

    /// Single-hour window at hour 0 (midnight). Edge case: hour values bottom
    /// out at 0, and a 0–0 window must match exactly midnight. Catches a
    /// future refactor that special-cases the overnight branch and
    /// accidentally consumes the 0-start case.
    func testTimeOfDayMidnightSingleHourMatchesHourZero() {
        let ctx = makeCtx()
        let predicate = RulePredicate.timeOfDay(startHour: 0, endHour: 0)
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 0)),
            "hour 0 must match a 0–0 single-hour window")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 23)),
            "hour 23 must NOT match a 0–0 single-hour window")
    }

    /// Overnight window with `endHour == 0` (e.g. 22–0) is a niche but valid
    /// shape — "match between 22:00 and midnight." The wrap-around branch
    /// fires (startHour > endHour: 22 > 0). Hours 22, 23, 0 match; 1, 12 don't.
    func testTimeOfDayOvernightEndingAtMidnightMatches() {
        let ctx = makeCtx()
        let predicate = RulePredicate.timeOfDay(startHour: 22, endHour: 0)
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 22)))
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 23)))
        XCTAssertTrue(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 0)),
            "midnight must match a 22–0 overnight window — endHour boundary is inclusive")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 1)),
            "hour 1 must NOT match a 22–0 overnight window — it ends at midnight")
        XCTAssertFalse(RuleEvaluator.matches(predicate, in: ctx, currentDate: date(hour: 12)),
            "hour 12 must NOT match a 22–0 overnight window")
    }
}

// MARK: - Export round-trip covers all predicate kinds (REP-133)

final class ExportAllPredicateKindsTests: XCTestCase {

    private func tmpURL(_ label: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ExportAllPredicates-\(label)-\(UUID().uuidString).json")
    }

    @MainActor
    func testExportImportRoundTripAllPredicateKinds() throws {
        let storeURL  = tmpURL("store")
        let exportURL = tmpURL("export")
        let importURL = tmpURL("import-store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
            try? FileManager.default.removeItem(at: importURL)
        }

        let store = RulesStore(fileURL: storeURL)

        // One rule per currently-shipped predicate primitive, plus composites.
        let rules: [SmartRule] = [
            SmartRule(name: "senderIs",            when: .senderIs("Alice"),                            then: .archive),
            SmartRule(name: "senderUnknown",        when: .senderUnknown,                               then: .archive),
            SmartRule(name: "hasAttachment",        when: .hasAttachment,                               then: .archive),
            SmartRule(name: "isGroupChat",          when: .isGroupChat,                                 then: .archive),
            SmartRule(name: "textMatchesRegex",     when: .textMatchesRegex(#"\d{6}"#),                 then: .archive),
            SmartRule(name: "messageAgeOlderThan",  when: .messageAgeOlderThan(hours: 24),              then: .archive),
            SmartRule(name: "hasUnread",               when: .hasUnread,                                          then: .archive),
            SmartRule(name: "timeOfDay",               when: .timeOfDay(startHour: 22, endHour: 6),               then: .archive),
            SmartRule(name: "threadNameMatchesRegex",  when: .threadNameMatchesRegex(pattern: #"(?i)project"#),   then: .archive),
            SmartRule(name: "and-composite",           when: .and([.senderIs("Bob"), .hasUnread]),                then: .pin),
            SmartRule(name: "or-composite",            when: .or([.senderIs("Carol"), .isGroupChat]),             then: .pin),
            SmartRule(name: "not-composite",           when: .not(.hasAttachment),                                then: .silentlyIgnore),
        ]

        for rule in rules { try store.add(rule) }

        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: importURL)
        try importStore.import(from: exportURL)

        for original in rules {
            guard let imported = importStore.rules.first(where: { $0.id == original.id }) else {
                XCTFail("rule '\(original.name)' missing after import")
                continue
            }
            XCTAssertEqual(imported.when, original.when,
                           "predicate for '\(original.name)' must survive export/import unchanged")
        }
    }
}

// MARK: - REP-148: RuleEvaluator.apply() output contract tests

final class RuleEvaluatorApplyTests: XCTestCase {

    private func makeCtx(sender: String = "Alice", text: String = "hello") -> RuleContext {
        RuleContext(
            senderName: sender, senderHandle: sender,
            channel: .imessage, lastMessageText: text,
            isUnread: true, senderKnown: true, chatIdentifier: sender
        )
    }

    func testApplyReturnsEmptyWhenNoRulesMatch() {
        let rule = SmartRule(name: "no-match", when: .senderIs("Bob"), then: .archive)
        let ctx = makeCtx(sender: "Alice")
        let result = RuleEvaluator.apply(rules: [rule], to: ctx)
        XCTAssertTrue(result.isEmpty, "no matching rules must produce an empty apply result")
    }

    func testApplyIncludesAllMatchingRuleIDsAndActions() {
        let r1 = SmartRule(name: "r1", when: .senderIs("Alice"), then: .archive)
        let r2 = SmartRule(name: "r2", when: .isUnread,         then: .pin)
        let ctx = makeCtx(sender: "Alice")
        let result = RuleEvaluator.apply(rules: [r1, r2], to: ctx)
        XCTAssertEqual(result.count, 2, "both matching rules must appear in apply output")
        XCTAssertTrue(result.contains { $0.ruleID == r1.id && $0.action == .archive },
                      "r1 archive action must be present")
        XCTAssertTrue(result.contains { $0.ruleID == r2.id && $0.action == .pin },
                      "r2 pin action must be present")
    }

    func testApplyOrderFollowsPriorityDescending() {
        let low  = SmartRule(name: "low",  when: .isUnread, then: .archive,           priority: 0)
        let high = SmartRule(name: "high", when: .isUnread, then: .setDefaultTone(.warm), priority: 5)
        let ctx = makeCtx()
        let result = RuleEvaluator.apply(rules: [low, high], to: ctx)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.ruleID, high.id, "higher-priority rule must appear first")
    }

    func testApplySkipsInactiveRules() {
        let active   = SmartRule(name: "active",   when: .isUnread, then: .archive,   active: true)
        let inactive = SmartRule(name: "inactive", when: .isUnread, then: .pin,       active: false)
        let ctx = makeCtx()
        let result = RuleEvaluator.apply(rules: [active, inactive], to: ctx)
        XCTAssertEqual(result.count, 1, "inactive rule must be excluded from apply output")
        XCTAssertEqual(result.first?.ruleID, active.id)
    }
}

// MARK: - REP-154: RulesStore.update() with unknown UUID is a no-op

final class RulesStoreUpdateNoOpTests: XCTestCase {

    @MainActor
    func testUpdateWithUnknownUUIDIsNoOp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateNoOp-\(UUID().uuidString)/rules.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = RulesStore(fileURL: url)
        let countBefore = store.rules.count

        let phantom = SmartRule(name: "phantom", when: .isGroupChat, then: .silentlyIgnore)
        store.update(phantom)

        XCTAssertEqual(store.rules.count, countBefore,
                       "rule count must not change after update with unknown UUID")
        XCTAssertNil(store.rules.first(where: { $0.id == phantom.id }),
                     "phantom rule must not appear in store after failed update")

        let reopened = RulesStore(fileURL: url)
        XCTAssertEqual(reopened.rules.count, countBefore,
                       "persisted rule count must not change after update with unknown UUID")
    }
}

// MARK: - REP-157: SmartRule empty and([]) evaluates to vacuous true

final class RulePredicateEmptyAndTests: XCTestCase {

    private func makeCtx() -> RuleContext {
        RuleContext(
            senderName: "Tester", senderHandle: "Tester",
            channel: .imessage, lastMessageText: "test",
            isUnread: false, senderKnown: true, chatIdentifier: "Tester"
        )
    }

    func testAndEmptyArrayEvaluatesToVacuousTrue() {
        let ctx = makeCtx()
        XCTAssertTrue(RuleEvaluator.matches(.and([]), in: ctx),
                      "and([]) must evaluate to vacuous true — no sub-predicates can fail")
    }

    func testAndEmptyVsOrEmptyAreOpposites() {
        // or([]) is already pinned false; and([]) must be the dual (true).
        let ctx = makeCtx()
        let andResult = RuleEvaluator.matches(.and([]), in: ctx)
        let orResult  = RuleEvaluator.matches(.or([]),  in: ctx)
        XCTAssertTrue(andResult,  "and([]) must be true")
        XCTAssertFalse(orResult,  "or([]) must be false")
        XCTAssertNotEqual(andResult, orResult, "empty and/or must be duals")
    }
}

// MARK: - REP-161: SmartRule textMatchesRegex with anchored patterns

final class RulePredicateAnchoredRegexTests: XCTestCase {

    private func ctx(_ text: String) -> RuleContext {
        RuleContext(
            senderName: "Alice", senderHandle: "Alice",
            channel: .imessage, lastMessageText: text,
            isUnread: false, senderKnown: true, chatIdentifier: "Alice"
        )
    }

    func testStartAnchorMatchesAtBeginning() {
        XCTAssertTrue(RuleEvaluator.matches(.textMatchesRegex("^Hello"), in: ctx("Hello world")),
                      "^Hello must match text starting with Hello")
    }

    func testStartAnchorDoesNotMatchMidString() {
        XCTAssertFalse(RuleEvaluator.matches(.textMatchesRegex("^Hello"), in: ctx("Say Hello")),
                       "^Hello must not match when Hello appears mid-string")
    }

    func testEndAnchorMatchesAtEnd() {
        XCTAssertTrue(RuleEvaluator.matches(.textMatchesRegex("world$"), in: ctx("Hello world")),
                      "world$ must match text ending with world")
    }

    func testEndAnchorDoesNotMatchMidString() {
        XCTAssertFalse(RuleEvaluator.matches(.textMatchesRegex("world$"), in: ctx("world is great")),
                       "world$ must not match when world appears at start, not end")
    }

    func testBothAnchorsRequireFullMatch() {
        XCTAssertTrue(RuleEvaluator.matches(.textMatchesRegex("^exact$"), in: ctx("exact")),
                      "^exact$ must match the exact string")
        XCTAssertFalse(RuleEvaluator.matches(.textMatchesRegex("^exact$"), in: ctx("not exact")),
                       "^exact$ must not match a longer string")
    }
}

// MARK: - REP-166: RuleEvaluator with empty rules array

final class RuleEvaluatorEmptyRulesTests: XCTestCase {

    private func makeCtx() -> RuleContext {
        RuleContext(
            senderName: "Alice", senderHandle: "alice@example.com",
            channel: .imessage, lastMessageText: "hello",
            isUnread: true, senderKnown: true, chatIdentifier: "alice@example.com"
        )
    }

    func testMatchingEmptyRulesReturnsEmpty() {
        let result = RuleEvaluator.matching([], in: makeCtx())
        XCTAssertEqual(result.count, 0, "matching([]) must return an empty array")
    }

    func testDefaultToneEmptyRulesReturnsNil() {
        let result = RuleEvaluator.defaultTone(for: [], in: makeCtx())
        XCTAssertNil(result, "defaultTone(for: []) must return nil — no rules, no tone")
    }

    func testApplyEmptyRulesReturnsEmpty() {
        let result = RuleEvaluator.apply(rules: [], to: makeCtx())
        XCTAssertEqual(result.count, 0, "apply(rules: [], to:) must return an empty array")
    }
}

// MARK: - REP-175: RulesStore import() all three merge outcomes in one pass

final class RulesStoreImportMergeTests: XCTestCase {

    private func tmpURL(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportMerge-\(tag)-\(UUID().uuidString)")
            .appendingPathComponent("rules.json")
    }

    /// 2-rule store + import with 1 update + 1 new → net +1 rule, action updated.
    ///
    /// Both stores seed the same static `SmartRule.seedRules` (shared UUIDs). The
    /// export therefore carries the seeds (update-in-place, no delta) + updatedA
    /// (updates A in-place, no delta) + ruleC (new UUID → +1). ruleB is unaffected.
    @MainActor
    func testImportUpdatesExistingAndAppendsNew() throws {
        let storeURL  = tmpURL("main")
        let srcURL    = tmpURL("src")
        let exportURL = tmpURL("export")
        for url in [storeURL, srcURL, exportURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        defer {
            for url in [storeURL, srcURL, exportURL] {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }

        let store = RulesStore(fileURL: storeURL)
        let ruleA = SmartRule(name: "A", when: .senderIs("Alice"), then: .pin)
        let ruleB = SmartRule(name: "B", when: .senderIs("Bob"),   then: .archive)
        try store.add(ruleA)
        try store.add(ruleB)
        let preImportCount = store.rules.count

        // Build an export from a separate store: updated rule A + new rule C.
        let updatedA = SmartRule(id: ruleA.id, name: ruleA.name,
                                 when: ruleA.when, then: .silentlyIgnore,
                                 active: ruleA.active, priority: ruleA.priority)
        let ruleC = SmartRule(name: "C", when: .isGroupChat, then: .markDone)
        let srcStore = RulesStore(fileURL: srcURL)
        try srcStore.add(updatedA)
        try srcStore.add(ruleC)
        try srcStore.export(to: exportURL)

        try store.import(from: exportURL)

        // ruleC is the only genuinely new UUID; everything else update-in-place.
        XCTAssertEqual(store.rules.count, preImportCount + 1,
                       "import must append exactly ruleC — all other UUIDs update in-place")
        let importedA = store.rules.first(where: { $0.id == ruleA.id })
        XCTAssertEqual(importedA?.then, .silentlyIgnore,
                       "rule A's action must be updated to silentlyIgnore")
        XCTAssertTrue(store.rules.contains(where: { $0.id == ruleB.id }),
                      "rule B must survive the import unchanged")
        XCTAssertTrue(store.rules.contains(where: { $0.id == ruleC.id }),
                      "rule C must be appended as a new entry")
    }

    /// Importing a file whose rules are identical to the store produces no change in count or content.
    @MainActor
    func testImportWithNoChangesIsNoop() throws {
        let storeURL  = tmpURL("noop-main")
        let exportURL = tmpURL("noop-export")
        for url in [storeURL, exportURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        defer {
            for url in [storeURL, exportURL] {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }

        let store = RulesStore(fileURL: storeURL)
        let rule = SmartRule(name: "stable", when: .senderIs("Dave"), then: .pin)
        try store.add(rule)
        let before = store.rules.count

        // Export the store's current state and import it back — should be a no-op.
        try store.export(to: exportURL)
        try store.import(from: exportURL)

        XCTAssertEqual(store.rules.count, before, "importing identical rules must not change store count")
        // Use the UUID to locate our rule — seed rules occupy the front of the array.
        XCTAssertEqual(store.rules.first(where: { $0.id == rule.id })?.name, "stable",
                       "our rule must be unchanged after self-import")
    }

    /// Importing an empty rules array leaves the store untouched.
    @MainActor
    func testImportEmptyArrayIsNoop() throws {
        let storeURL = tmpURL("empty-main")
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }

        let store = RulesStore(fileURL: storeURL)
        let rule = SmartRule(name: "existing", when: .senderIs("Eve"), then: .archive)
        try store.add(rule)
        let countBefore = store.rules.count

        // Write an empty versioned envelope and import it.
        let emptyURL = tmpURL("empty-export")
        try FileManager.default.createDirectory(
            at: emptyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyURL.deletingLastPathComponent()) }
        let envelope: [String: Any] = ["version": 1, "rules": [Any]()]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        try data.write(to: emptyURL)

        try store.import(from: emptyURL)
        XCTAssertEqual(store.rules.count, countBefore, "importing [] must leave store count unchanged")
        XCTAssertTrue(store.rules.contains(where: { $0.id == rule.id }), "existing rule must survive empty import")
    }
}

// MARK: - REP-129: threadNameMatchesRegex predicate

final class ThreadNameMatchesRegexTests: XCTestCase {

    private func ctx(threadName: String) -> RuleContext {
        RuleContext(
            senderName: threadName,
            senderHandle: threadName,
            channel: .imessage,
            lastMessageText: "hey",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "chat123",
            threadDisplayName: threadName
        )
    }

    func testThreadNameMatchesRegexWhenMatching() {
        let ctx = ctx(threadName: "Project Alpha Discussion")
        XCTAssertTrue(
            RuleEvaluator.matches(.threadNameMatchesRegex(pattern: #"(?i)project"#), in: ctx),
            "case-insensitive 'project' must match thread named 'Project Alpha Discussion'"
        )
    }

    func testThreadNameMatchesRegexWhenNotMatching() {
        let ctx = ctx(threadName: "Soccer Team 🏆")
        XCTAssertFalse(
            RuleEvaluator.matches(.threadNameMatchesRegex(pattern: #"(?i)project"#), in: ctx),
            "pattern 'project' must not match thread named 'Soccer Team'"
        )
    }

    func testThreadNameInvalidRegexThrows() {
        let rule = SmartRule(
            name: "bad regex",
            when: .threadNameMatchesRegex(pattern: "[invalid"),
            then: .archive
        )
        XCTAssertThrowsError(try SmartRule.validatePredicateRegexes(rule.when)) { error in
            guard case RuleValidationError.invalidRegex(let pattern, _) = error else {
                XCTFail("expected RuleValidationError.invalidRegex, got \(error)")
                return
            }
            XCTAssertEqual(pattern, "[invalid")
        }
    }

    func testThreadNameMatchesRegexCodableRoundTrip() throws {
        let original = RulePredicate.threadNameMatchesRegex(pattern: #"^Work:"#)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
        XCTAssertEqual(decoded, original, "threadNameMatchesRegex must round-trip through JSON unchanged")
    }
}

// MARK: - REP-215: validateRegex boundary cases

final class ValidateRegexBoundaryCasesTests: XCTestCase {

    // An empty pattern matches everything — valid by design for "catch-all" rules.
    func testEmptyPatternAccepted() {
        XCTAssertNoThrow(try SmartRule.validateRegex(""),
                         "empty pattern is valid ICU regex (matches everything) and must not throw")
    }

    // Python named-group syntax (?P<name>...) is not part of ICU regex.
    // NSRegularExpression uses ICU which requires (?<name>...) instead.
    // Passing Python syntax must surface as invalidRegex so the user can correct it.
    func testPythonNamedGroupSyntaxThrows() {
        XCTAssertThrowsError(try SmartRule.validateRegex("(?P<name>x)")) { error in
            guard let ve = error as? RuleValidationError,
                  case .invalidRegex = ve else {
                XCTFail("Expected RuleValidationError.invalidRegex for Python-syntax named group, got \(error)")
                return
            }
        }
    }
}

// MARK: - Predicate double-negation correctness (REP-208)

final class DoubleNegationTests: XCTestCase {

    private func aliceCtx() -> RuleContext {
        RuleContext(
            senderName: "Alice", senderHandle: "Alice",
            channel: .imessage, lastMessageText: "",
            isUnread: false, senderKnown: true, chatIdentifier: "t-alice")
    }

    private func bobCtx() -> RuleContext {
        RuleContext(
            senderName: "Bob", senderHandle: "Bob",
            channel: .imessage, lastMessageText: "",
            isUnread: false, senderKnown: true, chatIdentifier: "t-bob")
    }

    /// `not(not(pred))` must evaluate to the same truth value as `pred` itself.
    func testDoubleNegationMatchesWhenBaseMatches() {
        let pred = RulePredicate.not(.not(.senderIs("Alice")))
        XCTAssertTrue(RuleEvaluator.matches(pred, in: aliceCtx()),
                      "not(not(senderIs(Alice))) must match context where sender is Alice")
    }

    func testDoubleNegationMissesWhenBaseMisses() {
        let pred = RulePredicate.not(.not(.senderIs("Alice")))
        XCTAssertFalse(RuleEvaluator.matches(pred, in: bobCtx()),
                       "not(not(senderIs(Alice))) must not match context where sender is Bob")
    }

    /// `not(not(not(pred)))` must equal `not(pred)` in both matching and non-matching cases.
    func testTripleNegationInvertsBase() {
        let base  = RulePredicate.senderIs("Alice")
        let triple = RulePredicate.not(.not(.not(base)))
        let single = RulePredicate.not(base)

        XCTAssertEqual(
            RuleEvaluator.matches(triple, in: aliceCtx()),
            RuleEvaluator.matches(single, in: aliceCtx()),
            "not(not(not(pred))) must equal not(pred) when predicate matches")
        XCTAssertEqual(
            RuleEvaluator.matches(triple, in: bobCtx()),
            RuleEvaluator.matches(single, in: bobCtx()),
            "not(not(not(pred))) must equal not(pred) when predicate does not match")
    }
}

// MARK: - REP-179: RuleEvaluator equal-priority deterministic order

final class RuleEvaluatorDeterministicOrderTests: XCTestCase {
    private let ctx = RuleContext(
        senderName: "Alice",
        senderHandle: "alice",
        channel: .imessage,
        lastMessageText: "hello",
        isUnread: true,
        senderKnown: true,
        chatIdentifier: "chat123"
    )

    func testEqualPriorityRulesPreserveInsertionOrder() {
        let ruleA = SmartRule(name: "A", when: .senderIs("alice"), then: .pin, priority: 0)
        let ruleB = SmartRule(name: "B", when: .senderIs("alice"), then: .archive, priority: 0)
        let result = RuleEvaluator.matching([ruleA, ruleB], in: ctx)
        XCTAssertEqual(result.map(\.name), ["A", "B"],
            "equal-priority rules must preserve insertion order (A before B)")
    }

    func testEqualPriorityDeterministicOnMultipleCalls() {
        let ruleA = SmartRule(name: "A", when: .senderIs("alice"), then: .pin, priority: 5)
        let ruleB = SmartRule(name: "B", when: .senderIs("alice"), then: .archive, priority: 5)
        let rules = [ruleA, ruleB]
        let first = RuleEvaluator.matching(rules, in: ctx).map(\.name)
        let second = RuleEvaluator.matching(rules, in: ctx).map(\.name)
        XCTAssertEqual(first, second,
            "repeated calls with identical inputs must produce identical order")
    }
}

// MARK: - REP-251: compound predicate export + import round-trip

final class RulesStoreCompoundPredicateTests: XCTestCase {

    private func tmpURL(_ tag: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RulesCompound-\(tag)-\(UUID().uuidString).json")
    }

    // Deeply nested and/or/not tree must survive a full export→import round-trip
    // without losing structure or corrupting the `kind` discriminator.
    @MainActor
    func testCompoundPredicateRoundTrip() throws {
        let storeURL = tmpURL("compound-store")
        let exportURL = tmpURL("compound-export")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        let predicate: RulePredicate = .and([
            .senderIs("A"),
            .or([
                .textMatchesRegex("^hi"),
                .not(.senderUnknown)
            ])
        ])
        let rule = SmartRule(name: "compound", when: predicate, then: .pin)
        try store.add(rule)
        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: tmpURL("compound-reimport"))
        try importStore.import(from: exportURL)

        let imported = importStore.rules.first(where: { $0.id == rule.id })
        XCTAssertNotNil(imported, "compound-predicate rule must survive export+import")
        XCTAssertEqual(imported?.when, predicate,
                       "predicate tree must be identical after round-trip")
    }

    // or([]) encodes and decodes without crash; it's a valid (vacuous-false) predicate.
    @MainActor
    func testOrEmptyPredicateRoundTrip() throws {
        let storeURL = tmpURL("or-empty-store")
        let exportURL = tmpURL("or-empty-export")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        let rule = SmartRule(name: "or-empty", when: .or([]), then: .archive)
        try store.add(rule)
        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: tmpURL("or-empty-reimport"))
        try importStore.import(from: exportURL)

        let imported = importStore.rules.first(where: { $0.id == rule.id })
        XCTAssertNotNil(imported, "or([]) rule must survive export+import")
        XCTAssertEqual(imported?.when, .or([]),
                       "or([]) must decode back to or([])")
    }

    // and([not(hasUnread)]) — single-element and wrapping a not — must round-trip.
    @MainActor
    func testAndNotPredicateRoundTrip() throws {
        let storeURL = tmpURL("and-not-store")
        let exportURL = tmpURL("and-not-export")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: exportURL)
        }
        let store = RulesStore(fileURL: storeURL)
        let predicate: RulePredicate = .and([.not(.hasUnread)])
        let rule = SmartRule(name: "and-not", when: predicate, then: .pin)
        try store.add(rule)
        try store.export(to: exportURL)

        let importStore = RulesStore(fileURL: tmpURL("and-not-reimport"))
        try importStore.import(from: exportURL)

        let imported = importStore.rules.first(where: { $0.id == rule.id })
        XCTAssertNotNil(imported, "and([not(hasUnread)]) rule must survive export+import")
        XCTAssertEqual(imported?.when, predicate,
                       "and([not(hasUnread)]) must decode back to the original tree")
    }
}

// MARK: - REP-226: messageCount(atLeast:) predicate

final class RuleMessageCountPredicateTests: XCTestCase {

    private func ctx(messageCount: Int) -> RuleContext {
        RuleContext(
            senderName: "Alice",
            senderHandle: "alice",
            channel: .imessage,
            lastMessageText: "",
            isUnread: false,
            senderKnown: true,
            chatIdentifier: "t1",
            messageCount: messageCount
        )
    }

    func testMessageCountAtLeastMatchesWhenAboveThreshold() {
        let pred = RulePredicate.messageCount(atLeast: 3)
        XCTAssertTrue(RuleEvaluator.matches(pred, in: ctx(messageCount: 5)),
                      "5 messages ≥ 3: predicate must match")
    }

    func testMessageCountAtLeastMatchesAtExactThreshold() {
        let pred = RulePredicate.messageCount(atLeast: 5)
        XCTAssertTrue(RuleEvaluator.matches(pred, in: ctx(messageCount: 5)),
                      "5 messages == 5: predicate must match (inclusive)")
    }

    func testMessageCountAtLeastMissesWhenBelowThreshold() {
        let pred = RulePredicate.messageCount(atLeast: 6)
        XCTAssertFalse(RuleEvaluator.matches(pred, in: ctx(messageCount: 5)),
                       "5 messages < 6: predicate must not match")
    }

    func testMessageCountAtLeastZeroIsVacuousTrue() {
        let pred = RulePredicate.messageCount(atLeast: 0)
        XCTAssertTrue(RuleEvaluator.matches(pred, in: ctx(messageCount: 0)),
                      "atLeast=0 must match even a thread with 0 messages")
        XCTAssertTrue(RuleEvaluator.matches(pred, in: ctx(messageCount: 100)),
                      "atLeast=0 must match any thread")
    }

    func testMessageCountAtLeastCodableRoundTrip() throws {
        let predicate = RulePredicate.messageCount(atLeast: 7)
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(RulePredicate.self, from: data)
        XCTAssertEqual(decoded, predicate,
                       "messageCount(atLeast:) must survive encode→decode round-trip")
    }
}

// MARK: - RuleValidationError.errorDescription pin
//
// invalidRegex's pattern interpolation is exercised by an existing test
// (~line 1063) but tooManyRules's user-facing copy had no direct test.
// Settings → Rules surfaces this string when the user tries to add a
// 101st rule; pin the limit interpolation + recovery hint so a refactor
// can't silently drop them.

final class RuleValidationErrorDescriptionTests: XCTestCase {

    func testTooManyRulesIncludesActualLimit() {
        // The number is the most actionable piece of the message — users
        // need to know how many rules they're allowed to keep.
        let copy = RuleValidationError.tooManyRules(limit: 100).errorDescription ?? ""
        XCTAssertTrue(copy.contains("100"),
            "tooManyRules must include the actual limit — got: \(copy)")
    }

    func testTooManyRulesGivesRecoveryHint() {
        // The user is blocked from saving; the message must tell them
        // what to do (remove an existing rule) rather than just refusing.
        let copy = RuleValidationError.tooManyRules(limit: 100).errorDescription ?? ""
        XCTAssertTrue(copy.lowercased().contains("remove"),
            "tooManyRules should suggest removing an existing rule — got: \(copy)")
    }

    func testInvalidRegexIncludesReason() {
        // The NSRegularExpression error message ("Invalid escape sequence",
        // "Unmatched parentheses", etc.) is what tells the user what to fix.
        let copy = RuleValidationError.invalidRegex(
            pattern: "[abc",
            reason: "Unbalanced bracket"
        ).errorDescription ?? ""
        XCTAssertTrue(copy.contains("Unbalanced bracket"),
            "invalidRegex must surface the reason — got: \(copy)")
    }

    func testEveryCaseProducesNonEmptyDescription() {
        let cases: [RuleValidationError] = [
            .invalidRegex(pattern: "x", reason: "y"),
            .tooManyRules(limit: 1),
        ]
        for err in cases {
            let desc = err.errorDescription ?? ""
            XCTAssertFalse(desc.isEmpty, "empty description for \(err)")
        }
    }

    func testLocalizedErrorBridgeSurfacesOurCopy() {
        // SwiftUI alerts use `error.localizedDescription` — confirm the
        // bridge returns our text, not the generic CFString fallback.
        let err: Error = RuleValidationError.tooManyRules(limit: 100)
        XCTAssertTrue(err.localizedDescription.contains("100"),
            "LocalizedError bridge must surface our copy — got: \(err.localizedDescription)")
    }
}

// MARK: - RulesStore.defaultFileURL() — persistence path contract
//
// Production init uses `RulesStore(fileURL: RulesStore.defaultFileURL())`
// and the seeded rules.json travels with the user across reinstalls
// (Application Support survives Trash-and-reinstall). A silent path
// change orphans every shipped user's customised rules. Pin the path
// components so a refactor that drops "ReplyAI/" or renames "rules.json"
// trips a test instead of an unnoticed migration.

final class RulesStoreDefaultFileURLTests: XCTestCase {

    func testDefaultFileURLEndsWithRulesJSON() {
        let url = RulesStore.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, "rules.json",
                       "production path must end with rules.json — anything else orphans every user's customised rules")
    }

    func testDefaultFileURLLivesUnderReplyAIDirectory() {
        let url = RulesStore.defaultFileURL()
        let parent = url.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(parent, "ReplyAI",
                       "rules.json must live alongside stats.json in ReplyAI/; factory-reset relies on a single directory sweep")
    }

    func testDefaultFileURLDirectoryExistsAfterCall() {
        // The helper is documented to lazily create the parent directory.
        // Without that side-effect, RulesStore would have to handle an
        // ENOENT on first write — and every test that uses defaultFileURL
        // would race the directory into existence.
        let url = RulesStore.defaultFileURL()
        let dir = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                      "defaultFileURL() must create the parent directory so the first write succeeds")
        XCTAssertTrue(isDirectory.boolValue,
                      "the ReplyAI/ entry must be a directory, not a stray file")
    }

    func testDefaultFileURLIsAbsoluteAndFileScheme() {
        // A relative URL or a non-file scheme would silently break the
        // atomic write path inside RulesStore.writeSync(_:to:); pin the
        // shape so an accidental file:// → http:// drift trips the test.
        let url = RulesStore.defaultFileURL()
        XCTAssertTrue(url.isFileURL,
                      "rules path must be a file:// URL for FileManager + atomic write")
        XCTAssertTrue(url.path.hasPrefix("/"),
                      "rules path must be absolute so behavior doesn't depend on the cwd of the launching process")
    }
}

/// Pins the human-readable seed rule names. Seeds are the first thing a
/// brand-new user sees in `set-rules`; renames silently change that
/// first impression, and product copy review (REP-062) can't catch drift
/// that lands in the same commit. UUIDs are intentionally not asserted —
/// they are randomly generated per-rule and can change freely.
final class SmartRuleSeedNamesTests: XCTestCase {

    func testSeedRulesCountPinned() {
        // The bundle of seeds defines the empty-state look of the rules
        // screen; adding/removing one is a deliberate product call.
        XCTAssertEqual(SmartRule.seedRules.count, 4,
                       "seed rules count must remain stable; add → reflect new shape in this pin")
    }

    func testSeedRulesNamesInOrder() {
        // Order is the display order in set-rules; flipping order shifts
        // which rule a brand-new user reads first.
        let names = SmartRule.seedRules.map(\.name)
        XCTAssertEqual(names, [
            "Any message contains a 2FA code",
            #"Slack DM from @maya-chen with "deck""#,
            "WhatsApp voice memo > 30s",
            "Newsletter from any @*substack.com",
        ])
    }

    func testFirstThreeSeedRulesActiveByDefault() {
        // 2FA, Slack DM, WhatsApp voice memo all fire on install so the
        // user sees the rules engine doing something on day one.
        XCTAssertTrue(SmartRule.seedRules[0].active,
                      "2FA seed must be active so first-impression demos light up")
        XCTAssertTrue(SmartRule.seedRules[1].active,
                      "Slack DM seed must be active by default")
        XCTAssertTrue(SmartRule.seedRules[2].active,
                      "WhatsApp voice memo seed must be active by default")
    }

    func testSubstackSeedDisabledByDefault() {
        // The substack seed is shown as a deliberately *off* example so
        // the user can see what an inactive rule looks like without it
        // accidentally archiving real newsletters.
        XCTAssertFalse(SmartRule.seedRules[3].active,
                       "Substack seed must default to inactive so it doesn't archive real newsletters")
    }

    // MARK: - Seed-rule action pins
    //
    // Pinning the `.then` action for each seed rule guards against an
    // accidental behavior swap. e.g. flipping the 2FA rule from `.archive`
    // to `.silentlyIgnore` would still pass naming tests but materially
    // change what a fresh install does on day one.

    func testTwoFactorSeedRuleActionIsArchive() {
        // 2FA codes auto-archive — the rule shouldn't *hide* the message
        // (silentlyIgnore would suppress notifications too); it should
        // archive so the user can still find it via search.
        guard case .archive = SmartRule.seedRules[0].then else {
            XCTFail("expected .archive for 2FA seed, got \(SmartRule.seedRules[0].then)"); return
        }
    }

    func testSlackMayaSeedRuleActionIsSetDefaultToneDirect() {
        // The Slack-from-Maya seed advertises the "smart tone" feature —
        // flipping it to a different tone (warm, playful) silently changes
        // the demo's first impression.
        guard case .setDefaultTone(let tone) = SmartRule.seedRules[1].then else {
            XCTFail("expected .setDefaultTone(...) for Slack/Maya seed, got \(SmartRule.seedRules[1].then)"); return
        }
        XCTAssertEqual(tone, .direct,
                       "Slack/Maya seed pins to .direct — the tone the design copy demonstrates")
    }

    func testWhatsAppVoiceMemoSeedRuleActionIsPin() {
        // Voice memos are surfaced via pin (top of inbox) rather than
        // archive (out of sight) — drift here would undo the rule's whole
        // point.
        guard case .pin = SmartRule.seedRules[2].then else {
            XCTFail("expected .pin for WhatsApp voice memo seed, got \(SmartRule.seedRules[2].then)"); return
        }
    }

    func testSubstackSeedRuleActionIsSilentlyIgnore() {
        // Newsletters opt for `.silentlyIgnore` (suppress notifications +
        // hide from menu-bar count) rather than `.archive` so the user
        // can still browse them in the inbox if they want to.
        guard case .silentlyIgnore = SmartRule.seedRules[3].then else {
            XCTFail("expected .silentlyIgnore for Substack seed, got \(SmartRule.seedRules[3].then)"); return
        }
    }
}
