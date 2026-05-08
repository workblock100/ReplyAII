import XCTest
@testable import ReplyAI

final class StatsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAIStatsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func tempURL(_ name: String = "stats.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    // MARK: - Counter math

    func testCountersIncrement() {
        let stats = Stats(fileURL: tempURL())
        XCTAssertEqual(stats.snapshot(), Stats.Snapshot())

        stats.recordRuleFired(action: "archive")
        stats.recordRuleFired(action: "archive")
        stats.recordRuleFired(action: "silentlyIgnore")
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        stats.recordDraftSent()
        stats.recordMessagesIndexed(42)
        stats.recordMessagesIndexed(8)

        let snap = stats.snapshot()
        XCTAssertEqual(snap.rulesFiredByAction["archive"], 2)
        XCTAssertEqual(snap.rulesFiredByAction["silentlyIgnore"], 1)
        XCTAssertNil(snap.rulesFiredByAction["markDone"])
        XCTAssertEqual(snap.draftsGenerated, 3)
        XCTAssertEqual(snap.draftsSent, 1)
        XCTAssertEqual(snap.messagesIndexed, 50)
    }

    func testMessagesIndexedIgnoresNonPositive() {
        let stats = Stats(fileURL: tempURL())
        stats.recordMessagesIndexed(0)
        stats.recordMessagesIndexed(-5)
        XCTAssertEqual(stats.snapshot().messagesIndexed, 0)
    }

    /// Parallel guard pin for the per-channel counter — `incrementIndexed`
    /// also no-ops on `count <= 0`. Pinned because the per-channel breakdown
    /// is what feeds the planner-style "which channel drives index growth"
    /// observability; a refactor that dropped the guard would let a
    /// degenerate caller (e.g. SearchIndex.upsert with an empty batch)
    /// pollute the per-channel buckets with zero-count entries.
    func testIncrementIndexedIgnoresNonPositive() {
        let stats = Stats(fileURL: tempURL())
        stats.incrementIndexed(channel: .imessage, count: 0)
        stats.incrementIndexed(channel: .slack, count: -3)
        XCTAssertNil(stats.snapshot().messagesIndexedByChannel[Channel.imessage.rawValue],
            "count=0 must not insert a zero-value bucket for the channel")
        XCTAssertNil(stats.snapshot().messagesIndexedByChannel[Channel.slack.rawValue],
            "negative count must not insert a bucket either")
        XCTAssertEqual(stats.snapshot().messagesIndexed, 0,
            "the aggregate counter is untouched by per-channel non-positive calls")
    }

    /// Companion behavior pin: `recordRuleFired` tracks an empty action
    /// string verbatim as a key (per the docstring's "unknown strings are
    /// tracked verbatim — a typo shows up in the stats rather than silently
    /// disappearing"). Pinned because empty action would mean a degenerate
    /// caller passed `""` for the discriminator — the verbatim policy makes
    /// that visible in the rulesFiredByAction map rather than dropping it.
    func testRecordRuleFiredAcceptsEmptyActionVerbatim() {
        let stats = Stats(fileURL: tempURL())
        stats.recordRuleFired(action: "")
        XCTAssertEqual(stats.snapshot().rulesFiredByAction[""], 1,
            "empty action string is tracked verbatim per the verbatim-discriminator policy")
    }

    /// Parallel guard pin for `recordRuleLoadSkips` — also no-ops on
    /// `count <= 0`. Pinned because rules.json load is one of the few
    /// paths that calls this counter, and a guard regression would
    /// confuse the planner's "ruleLoadSkips: 0" output with "we never
    /// called it" by silently ticking the counter on every successful
    /// load.
    func testRecordRuleLoadSkipsIgnoresNonPositive() {
        let stats = Stats(fileURL: tempURL())
        stats.recordRuleLoadSkips(0)
        stats.recordRuleLoadSkips(-1)
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 0,
            "non-positive recordRuleLoadSkips must be a no-op")
    }

    // MARK: - Persistence

    /// `persist()` schedules the on-disk flush at `now + debounceWriteWindow`.
    /// 2 seconds is the deliberate trade-off: short enough that a crash
    /// shortly after a session loses ≤2s of counters; long enough that a
    /// burst of rule fires + draft increments coalesces into one write
    /// instead of thrashing app-support disk on every event. Drift in
    /// either direction shifts that trade-off invisibly. Pin the literal
    /// against the hoisted constant rather than reaching into the
    /// inline arithmetic in `persist()`.
    func testDebounceWriteWindowDefaultIsTwoSeconds() {
        XCTAssertEqual(Stats.debounceWriteWindow, 2,
                       "debounce window is shipped UX — see test rationale")
    }

    func testStatsRoundTripThroughJSON() throws {
        let url = tempURL()

        let first = Stats(fileURL: url)
        first.recordRuleFired(action: "archive")
        first.recordRuleFired(action: "archive")
        first.recordRuleFired(action: "pin")
        first.recordDraftGenerated()
        first.recordDraftSent()
        first.recordMessagesIndexed(17)

        // Writes are debounced; flushNow() bypasses the delay for the test.
        first.flushNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "stats.json should be written after flushNow()")

        // Reload through a fresh instance — everything should survive.
        let second = Stats(fileURL: url)
        let reloaded = second.snapshot()
        XCTAssertEqual(reloaded.rulesFiredByAction["archive"], 2)
        XCTAssertEqual(reloaded.rulesFiredByAction["pin"], 1)
        XCTAssertEqual(reloaded.draftsGenerated, 1)
        XCTAssertEqual(reloaded.draftsSent, 1)
        XCTAssertEqual(reloaded.messagesIndexed, 17)

        // And the reload lets us keep counting without resetting.
        second.recordDraftGenerated()
        XCTAssertEqual(second.snapshot().draftsGenerated, 2)
    }

    func testEmptyFileReturnsFreshSnapshot() {
        let stats = Stats(fileURL: tempURL("does-not-exist.json"))
        XCTAssertEqual(stats.snapshot(), Stats.Snapshot())
    }

    func testMalformedFileFallsBackToFreshSnapshot() throws {
        let url = tempURL()
        try Data("{not valid json".utf8).write(to: url)
        let stats = Stats(fileURL: url)
        XCTAssertEqual(stats.snapshot(), Stats.Snapshot())
    }

    // MARK: - Thread-safety

    func testIncrementsFromMultipleThreadsAreSerialized() {
        let stats = Stats(fileURL: tempURL())
        let iterations = 500
        let threads = 8

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stats.test", attributes: .concurrent)
        for _ in 0..<threads {
            group.enter()
            queue.async {
                for _ in 0..<iterations {
                    stats.recordDraftGenerated()
                    stats.recordRuleFired(action: "archive")
                    stats.recordMessagesIndexed(1)
                }
                group.leave()
            }
        }
        let expectation = expectation(description: "concurrent writes finish")
        group.notify(queue: .main) { expectation.fulfill() }
        wait(for: [expectation], timeout: 30)

        let snap = stats.snapshot()
        XCTAssertEqual(snap.draftsGenerated, iterations * threads)
        XCTAssertEqual(snap.rulesFiredByAction["archive"], iterations * threads)
        XCTAssertEqual(snap.messagesIndexed, iterations * threads)
    }

    // MARK: - Weekly log (REP-056)

    func testWeeklyLogContainsAllCounters() throws {
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftGenerated()
        stats.recordDraftSent()
        stats.recordRuleFired(action: "archive")
        stats.recordMessagesIndexed(10)
        stats.recordRuleLoadSkips(2)

        let logURL = tempURL("weekly.md")
        try stats.writeWeeklyLog(to: logURL)
        let content = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(content.contains("# Stats week of"), "must include date heading")
        XCTAssertTrue(content.contains("rulesFiredByAction"), "must include rules fired")
        XCTAssertTrue(content.contains("draftsGenerated: 1"), "must include draftsGenerated counter")
        XCTAssertTrue(content.contains("draftsSent: 1"), "must include draftsSent counter")
        XCTAssertTrue(content.contains("messagesIndexed: 10"), "must include messagesIndexed counter")
        XCTAssertTrue(content.contains("ruleLoadSkips: 2"), "must include ruleLoadSkips counter")
    }

    func testWeeklyLogZeroValuesNotOmitted() throws {
        let stats = Stats(fileURL: tempURL())

        let logURL = tempURL("weekly-zeros.md")
        try stats.writeWeeklyLog(to: logURL)
        let content = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(content.contains("draftsGenerated: 0"), "zero counters must appear in log")
        XCTAssertTrue(content.contains("draftsSent: 0"))
        XCTAssertTrue(content.contains("messagesIndexed: 0"))
        XCTAssertTrue(content.contains("ruleLoadSkips: 0"))
    }

    func testWeeklyLogEmptyRulesFiredByActionEmitsBraceLiteral() throws {
        // The else-branch in writeWeeklyLog explicitly emits
        // `- rulesFiredByAction: {}` when no rules have fired, so weekly
        // archives stay column-aligned and a parser scanning for the field
        // never sees a missing line. Removing the placeholder would silently
        // break automation that diffs week-over-week stats.
        let stats = Stats(fileURL: tempURL())

        let logURL = tempURL("weekly-empty-rules.md")
        try stats.writeWeeklyLog(to: logURL)
        let content = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(content.contains("- rulesFiredByAction: {}"),
                      "empty rulesFiredByAction must serialize as the literal `{}` placeholder, not be omitted")
    }

    func testWeeklyLogRulesFiredByActionSortedByKey() throws {
        // The actionsSorted line in writeWeeklyLog sorts alphabetically by
        // action key so the file is stable across runs — week-over-week
        // diffs would otherwise be polluted by Dictionary's hash-order churn.
        let stats = Stats(fileURL: tempURL())
        stats.recordRuleFired(action: "snooze")
        stats.recordRuleFired(action: "archive")
        stats.recordRuleFired(action: "mark-read")

        let logURL = tempURL("weekly-sorted-rules.md")
        try stats.writeWeeklyLog(to: logURL)
        let content = try String(contentsOf: logURL, encoding: .utf8)

        // The triple appears on one line, joined by ", ", in alphabetical
        // order. Pin both the order and the join separator.
        XCTAssertTrue(content.contains("archive: 1, mark-read: 1, snooze: 1"),
                      "rulesFiredByAction entries must be sorted by key and joined with ', '")
    }

    func testWeeklyLogWritesToFile() throws {
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftGenerated()

        let logURL = tempURL("weekly-write.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
        try stats.writeWeeklyLog(to: logURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path), "file must be created")
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 0, "file must not be empty")
    }

    // MARK: - Per-channel indexed counter (REP-070)

    func testPerChannelCountersIncrement() {
        let stats = Stats(fileURL: tempURL())
        stats.incrementIndexed(channel: .imessage, count: 5)
        stats.incrementIndexed(channel: .slack, count: 3)
        stats.incrementIndexed(channel: .imessage, count: 2)

        let snap = stats.snapshot()
        XCTAssertEqual(snap.messagesIndexedByChannel["imessage"], 7)
        XCTAssertEqual(snap.messagesIndexedByChannel["slack"], 3)
        XCTAssertNil(snap.messagesIndexedByChannel["whatsapp"])
    }

    func testPerChannelCountersRoundTrip() throws {
        let url = tempURL()
        let first = Stats(fileURL: url)
        first.incrementIndexed(channel: .imessage, count: 10)
        first.incrementIndexed(channel: .teams, count: 4)
        first.flushNow()

        let second = Stats(fileURL: url)
        let snap = second.snapshot()
        XCTAssertEqual(snap.messagesIndexedByChannel["imessage"], 10)
        XCTAssertEqual(snap.messagesIndexedByChannel["teams"], 4)
    }

    // MARK: - Per-tone draft counters (REP-032)

    func testPerToneCountersIncrement() {
        let stats = Stats(fileURL: tempURL())

        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .direct)
        stats.recordDraftSent(tone: .warm)

        let snap = stats.snapshot()
        // Aggregate counters must also advance
        XCTAssertEqual(snap.draftsGenerated, 3)
        XCTAssertEqual(snap.draftsSent, 1)
        // Per-tone breakdown
        XCTAssertEqual(snap.draftsGeneratedByTone["Warm"], 2)
        XCTAssertEqual(snap.draftsGeneratedByTone["Direct"], 1)
        XCTAssertNil(snap.draftsGeneratedByTone["Playful"])
        XCTAssertEqual(snap.draftsSentByTone["Warm"], 1)
        XCTAssertNil(snap.draftsSentByTone["Direct"])
    }

    func testPerToneCountersRoundTrip() throws {
        let url = tempURL()
        let first = Stats(fileURL: url)
        first.recordDraftGenerated(tone: .playful)
        first.recordDraftGenerated(tone: .playful)
        first.recordDraftSent(tone: .playful)
        first.recordDraftGenerated(tone: .direct)
        first.flushNow()

        let second = Stats(fileURL: url)
        let snap = second.snapshot()
        XCTAssertEqual(snap.draftsGeneratedByTone["Playful"], 2)
        XCTAssertEqual(snap.draftsSentByTone["Playful"], 1)
        XCTAssertEqual(snap.draftsGeneratedByTone["Direct"], 1)
        XCTAssertNil(snap.draftsSentByTone["Direct"])
        // Aggregate counters survive the round-trip
        XCTAssertEqual(snap.draftsGenerated, 3)
        XCTAssertEqual(snap.draftsSent, 1)
    }

    func testAcceptanceRateCalculation() {
        let stats = Stats(fileURL: tempURL())

        // No data yet → nil
        XCTAssertNil(stats.acceptanceRate(for: .warm))

        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftSent(tone: .warm)

        // 1 sent / 4 generated = 0.25
        let rate = stats.acceptanceRate(for: .warm)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate!, 0.25, accuracy: 1e-9)

        // Tone with generates but no sends
        stats.recordDraftGenerated(tone: .direct)
        XCTAssertEqual(stats.acceptanceRate(for: .direct)!, 0.0, accuracy: 1e-9)

        // Tone never touched → nil
        XCTAssertNil(stats.acceptanceRate(for: .playful))
    }

    // MARK: - rulesMatchedCount (REP-094)

    func testMatchedCountIncrementsOnMatch() {
        let stats = Stats(fileURL: tempURL())
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 0)
        stats.incrementRulesMatched()
        stats.incrementRulesMatched()
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 2,
                       "rulesMatchedCount must increment once per matching evaluation")
    }

    func testMatchedCountNotIncrementedOnNoMatch() {
        let stats = Stats(fileURL: tempURL())
        // Simulate two evaluations with no matches — incrementRulesMatched is never called.
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 0,
                       "rulesMatchedCount must remain zero when no rules matched")
    }

    func testMatchedCountRoundTrip() throws {
        let url = tempURL()
        let first = Stats(fileURL: url)
        first.incrementRulesMatched()
        first.incrementRulesMatched()
        first.incrementRulesMatched()
        first.flushNow()

        let second = Stats(fileURL: url)
        XCTAssertEqual(second.snapshot().rulesMatchedCount, 3,
                       "rulesMatchedCount must survive JSON persistence round-trip")
    }

    // MARK: - Concurrent increment stress test (REP-097)

    func testConcurrentIncrementNeverLosesUpdates() async {
        let stats = Stats(fileURL: tempURL("concurrent-test"))
        let taskCount = 200
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    stats.incrementRulesMatched()
                }
            }
        }
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, taskCount,
                       "All \(taskCount) concurrent increments must be reflected — no lost updates under concurrent access")
    }

    // MARK: - rulesMatchedCount ≤ evaluationCount invariant (REP-123)

    func testRulesMatchedNeverExceedsEvaluated() {
        // Simulate 10 rule evaluations of which 3 had at least one match.
        // The caller is responsible for only calling incrementRulesMatched()
        // when a rule actually fires. This test guards against accidentally
        // swapping the counters or double-incrementing.
        let stats = Stats(fileURL: tempURL())
        let evaluationCount = 10
        let matchCount = 3
        for _ in 0..<matchCount { stats.incrementRulesMatched() }
        XCTAssertLessThanOrEqual(
            stats.snapshot().rulesMatchedCount, evaluationCount,
            "matched count (\(matchCount)) must not exceed evaluation count (\(evaluationCount))"
        )
    }

    func testZeroMatchesLeavesMatchedCountAtZero() {
        // After any number of evaluations with no matches,
        // rulesMatchedCount must remain zero because incrementRulesMatched
        // is simply never called.
        let stats = Stats(fileURL: tempURL())
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 0,
                       "zero rule matches must leave rulesMatchedCount at 0")
    }

    // MARK: - WeeklyLogFormat field-name pins

    /// `Stats.WeeklyLogFormat.*` is the markdown vocabulary the
    /// planner/reviewer scripts in `.automation/` parse out of the
    /// weekly log. Drift on a field name (e.g.
    /// `draftsGenerated` → `draftsCreated`) silently breaks the
    /// downstream aggregator without raising a build error or
    /// unit-test failure — the tests above use substring matching
    /// (`content.contains("draftsGenerated")`), which would also fall
    /// through silently if the source emitted the wrong name. This
    /// pin asserts each field name independently so a single rename
    /// surfaces both at the constant and at the tests that match
    /// against it.
    func testWeeklyLogFormatFieldNamesAreFrozen() {
        XCTAssertEqual(Stats.WeeklyLogFormat.headingPrefix, "# Stats week of ",
            "weekly-log heading prefix is what `.automation/` scripts grep for to identify a stats archive — drift breaks the aggregator's file-discovery pass")
        XCTAssertEqual(Stats.WeeklyLogFormat.rulesFiredEmpty, "- rulesFiredByAction: {}",
            "empty-state line drift either changes the parser shape (`{}` is JSON-empty) or moves the dash bullet — both break the planner's line filter")
        XCTAssertEqual(Stats.WeeklyLogFormat.rulesFiredFieldName, "rulesFiredByAction",
            "rulesFiredByAction field-name drift orphans the downstream aggregator's per-action breakdown")
        XCTAssertEqual(Stats.WeeklyLogFormat.draftsGeneratedField, "draftsGenerated",
            "draftsGenerated field-name drift breaks the cumulative draft-counter roll-up")
        XCTAssertEqual(Stats.WeeklyLogFormat.draftsSentField, "draftsSent",
            "draftsSent field-name drift breaks the acceptance-rate computation in the aggregator")
        XCTAssertEqual(Stats.WeeklyLogFormat.messagesIndexedField, "messagesIndexed",
            "messagesIndexed field-name drift orphans the search-index health metric")
        XCTAssertEqual(Stats.WeeklyLogFormat.ruleLoadSkipsField, "ruleLoadSkips",
            "ruleLoadSkips field-name drift hides rules.json corruption signal from the aggregator")
        XCTAssertEqual(Stats.WeeklyLogFormat.sessionDurationField, "sessionDuration",
            "sessionDuration field-name drift breaks the per-session normalization the aggregator applies")
    }

    /// `Stats.WeeklyLogFormat.line(_:value:)` is the format every
    /// counter line flows through. Drift to e.g. `* <field>: ...`
    /// (asterisk bullet) or `<field> = <value>` would silently break
    /// the planner's dash-prefix line filter. Pin both the format
    /// shape and the round-trip through the writeWeeklyLog source
    /// (every assertion below would fail if either the constant or
    /// the call site drifted).
    func testWeeklyLogLineFormatIsExact() {
        XCTAssertEqual(Stats.WeeklyLogFormat.line("draftsGenerated", value: "42"),
                       "- draftsGenerated: 42",
                       "line format `- <field>: <value>` is the planner-script contract — drift breaks every dash-prefixed counter")
        XCTAssertEqual(Stats.WeeklyLogFormat.line("rulesFiredByAction", value: "{archive: 7}"),
                       "- rulesFiredByAction: {archive: 7}",
                       "line format must round-trip the brace-wrapped value verbatim — drift either escapes braces or strips them")
    }

    func testWeeklyLogLineFormatRoundTripsThroughWriteWeeklyLog() throws {
        let stats = Stats(fileURL: nil)
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-weekly-log-format-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: logURL) }
        try stats.writeWeeklyLog(to: logURL)
        let content = try String(contentsOf: logURL)
        // Every line in the output must round-trip through the format
        // — drift in either the constant or the call site is caught.
        XCTAssertTrue(content.contains(Stats.WeeklyLogFormat.line(Stats.WeeklyLogFormat.draftsGeneratedField, value: "2")),
            "writeWeeklyLog output must contain the draftsGenerated line in the exact `WeeklyLogFormat.line(...)` shape — source and format constant must not drift")
        XCTAssertTrue(content.contains(Stats.WeeklyLogFormat.headingPrefix),
            "writeWeeklyLog output must start with the headingPrefix verbatim — source and constant must not drift")
    }
}

// MARK: - REP-149: acceptanceRate nil-vs-zero distinction

final class StatsAcceptanceRateTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatsAcceptanceRateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func tempURL(_ name: String = "stats.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    func testAcceptanceRateNilForUntrackedTone() {
        let stats = Stats(fileURL: tempURL())
        XCTAssertNil(stats.acceptanceRate(for: .warm),
                     "fresh Stats with no recorded drafts must return nil — no data yet")
    }

    func testAcceptanceRateZeroForNoSends() {
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftGenerated(tone: .direct)
        stats.recordDraftGenerated(tone: .direct)
        let rate = stats.acceptanceRate(for: .direct)
        XCTAssertNotNil(rate, "rate must be non-nil when drafts were generated")
        XCTAssertEqual(rate!, 0.0, accuracy: 1e-9,
                       "0 sends out of 2 generated must yield 0.0, not nil")
    }

    func testAcceptanceRateRatioWhenBothPresent() {
        let stats = Stats(fileURL: tempURL())
        for _ in 0..<5 { stats.recordDraftGenerated(tone: .playful) }
        stats.recordDraftSent(tone: .playful)
        stats.recordDraftSent(tone: .playful)
        let rate = stats.acceptanceRate(for: .playful)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate!, 0.4, accuracy: 1e-9,
                       "2 sent / 5 generated must yield 0.4 acceptance rate")
    }

    func testAcceptanceRateToneIsolation() {
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftGenerated(tone: .warm)
        XCTAssertNotNil(stats.acceptanceRate(for: .warm), "warm should have data")
        XCTAssertNil(stats.acceptanceRate(for: .direct), "direct must remain nil with no data")
    }

    /// Inverse of testAcceptanceRateZeroForNoSends: if a `recordDraftSent`
    /// fires *without* a corresponding `recordDraftGenerated` (a logic
    /// bug that would surface as e.g. a tone cycle clearing the generated
    /// counter mid-stream), `acceptanceRate` must still return nil
    /// because the denominator is zero — never crash with division-by-
    /// zero or surface an out-of-range rate. The raw sent counter still
    /// reflects the events so an audit can detect the divergence.
    func testAcceptanceRateNilWhenSentWithoutGenerated() {
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftSent(tone: .warm)
        stats.recordDraftSent(tone: .warm)
        XCTAssertNil(stats.acceptanceRate(for: .warm),
            "sends without any generated must return nil — denominator is zero, not a usable rate")
        XCTAssertEqual(stats.snapshot().draftsSentByTone[Tone.warm.rawValue], 2,
            "raw sent counter must still record both events — only the rate calculation guards against zero generated")
    }

    /// `recordDraftSent(tone:)` more times than `recordDraftGenerated(tone:)`
    /// is also a logic bug (e.g. an idempotency miss), but the rate
    /// calculation must keep functioning — it'll exceed 1.0 deliberately
    /// rather than capping or reporting nil. Pin so a future "clamp to
    /// [0,1]" tightening shows up here as a deliberate choice.
    func testAcceptanceRateAllowsOverOneWhenSentExceedsGenerated() {
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftGenerated(tone: .direct)
        stats.recordDraftSent(tone: .direct)
        stats.recordDraftSent(tone: .direct)
        let rate = stats.acceptanceRate(for: .direct)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate!, 2.0, accuracy: 1e-9,
            "sent > generated must surface as the raw ratio (2.0 here) rather than be clamped to 1.0 — the divergence is information for the audit log")
    }
}

// MARK: - REP-160: Stats concurrent mixed-counter stress test

final class StatsConcurrentMixedCounterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatsConcurrentMixedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testConcurrentMixedCountersNoCrashAndAllUpdatesReflected() {
        let stats = Stats(fileURL: tempDir.appendingPathComponent("mixed-concurrent.json"))
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            stats.recordRuleFired(action: "archive")
            stats.recordMessagesIndexed(1)
            stats.incrementIndexed(channel: .imessage, count: 1)
        }

        let snap = stats.snapshot()
        XCTAssertGreaterThanOrEqual(snap.rulesFiredByAction["archive"] ?? 0, iterations,
                                    "all \(iterations) rule-fired increments must be reflected")
        XCTAssertGreaterThanOrEqual(snap.messagesIndexed, iterations,
                                    "all recordMessagesIndexed calls must be reflected")
        let imessageCount = snap.messagesIndexedByChannel[Channel.imessage.rawValue] ?? 0
        XCTAssertGreaterThanOrEqual(imessageCount, iterations,
                                    "all incrementIndexed calls must be reflected in per-channel count")
    }
}

// MARK: - Snapshot keys regression guard (REP-171)

extension StatsTests {

    /// Pins every key that snapshot() serialises to JSON. If a CodingKey is
    /// renamed, this test fails, surfacing the format break before it reaches
    /// production weekly-log consumers. Update knownKeys whenever a new
    /// counter is added to Stats.Snapshot.
    func testSnapshotContainsAllExpectedKeys() throws {
        let stats = Stats(fileURL: tempURL("rep171.json"))
        let snap = stats.snapshot()
        let data = try JSONEncoder().encode(snap)
        let dict = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            "encoded snapshot must deserialise as a JSON object")

        let knownKeys: [String] = [
            "rulesFiredByAction",
            "draftsGenerated",
            "draftsSent",
            "draftsGeneratedByTone",
            "draftsSentByTone",
            "messagesIndexed",
            "messagesIndexedByChannel",
            "ruleLoadSkips",
            "rulesMatchedCount",
        ]

        for key in knownKeys {
            XCTAssertNotNil(dict[key],
                "snapshot JSON must contain key '\(key)' — update knownKeys if you rename it")
        }

        XCTAssertEqual(
            Set(dict.keys), Set(knownKeys),
            "snapshot JSON must contain exactly the expected counter keys — update knownKeys when adding a new counter")
    }
}

// MARK: - REP-105: lifetime counter persistence across inits

final class StatsLifetimePersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatsLifetimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func tempURL(_ name: String = "stats.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    /// Pre-write a JSON file representing previous-session counters, then init a
    /// fresh Stats — it must seed from the file rather than starting at zero.
    func testLifetimeCountersSeedFromDisk() throws {
        let url = tempURL()
        let seed = Stats.Snapshot(
            rulesFiredByAction: ["archive": 7],
            draftsGenerated: 12,
            draftsSent: 3,
            messagesIndexed: 500
        )
        let data = try JSONEncoder().encode(seed)
        try data.write(to: url, options: .atomic)

        let stats = Stats(fileURL: url)
        let snap = stats.snapshot()
        XCTAssertEqual(snap.rulesFiredByAction["archive"], 7,
                       "must seed rulesFiredByAction from disk on init")
        XCTAssertEqual(snap.draftsGenerated, 12,
                       "must seed draftsGenerated from disk on init")
        XCTAssertEqual(snap.draftsSent, 3,
                       "must seed draftsSent from disk on init")
        XCTAssertEqual(snap.messagesIndexed, 500,
                       "must seed messagesIndexed from disk on init")
    }

    /// First instance writes counters, second instance loads them and keeps
    /// incrementing — total must reflect both sessions cumulatively.
    func testLifetimeCountersAccumulateAcrossInits() throws {
        let url = tempURL()

        let session1 = Stats(fileURL: url)
        session1.recordDraftGenerated()
        session1.recordDraftGenerated()
        session1.recordDraftSent()
        session1.flushNow()

        let session2 = Stats(fileURL: url)
        XCTAssertEqual(session2.snapshot().draftsGenerated, 2,
                       "second session must start from first session's persisted count")
        session2.recordDraftGenerated()
        XCTAssertEqual(session2.snapshot().draftsGenerated, 3,
                       "second session increments on top of inherited count")
        XCTAssertEqual(session2.snapshot().draftsSent, 1,
                       "draftsSent from first session must persist into second")
    }

    /// Stats with nil fileURL must never create or read any file — safe for
    /// tests that only care about in-memory counters.
    func testNilURLSkipsPersistence() {
        let stats = Stats(fileURL: nil)
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        stats.recordRuleFired(action: "pin")

        // In-memory counters still work correctly.
        XCTAssertEqual(stats.snapshot().draftsGenerated, 2)
        XCTAssertEqual(stats.snapshot().rulesFiredByAction["pin"], 1)

        // flushNow() must be a no-op — no crash and no files created.
        stats.flushNow()

        // No stats file should exist anywhere in the temp dir.
        let items = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        XCTAssertTrue(items.isEmpty,
                      "nil-URL Stats must not create any files — found: \(items)")
    }
}

// MARK: - REP-139: flushNow() for clean-shutdown persistence

final class StatsFlushNowTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatsFlushNowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func tempURL(_ name: String = "stats.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    /// Increment counters, call flushNow() immediately (before the 2 s debounce
    /// fires), then init a fresh Stats — all increments must be reflected.
    func testFlushNowPersistsBeforeDebounce() throws {
        let url = tempURL()
        let stats = Stats(fileURL: url)
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        stats.recordDraftSent()
        stats.flushNow()

        let reloaded = Stats(fileURL: url)
        XCTAssertEqual(reloaded.snapshot().draftsGenerated, 3,
                       "flushNow() must write all increments before the debounce window expires")
        XCTAssertEqual(reloaded.snapshot().draftsSent, 1,
                       "draftsSent must also survive a synchronous flush")
    }

    /// Calling flushNow() twice must leave counters correct — no double-zero,
    /// no corrupt encoding from concurrent writes.
    func testFlushNowIsIdempotent() throws {
        let url = tempURL()
        let stats = Stats(fileURL: url)
        stats.recordMessagesIndexed(42)
        stats.flushNow()
        stats.flushNow()

        let reloaded = Stats(fileURL: url)
        XCTAssertEqual(reloaded.snapshot().messagesIndexed, 42,
                       "two consecutive flushNow() calls must not corrupt the persisted count")
    }

    /// Stats with nil fileURL — flushNow() must silently do nothing.
    func testFlushNowWithNilURLIsNoop() {
        let stats = Stats(fileURL: nil)
        stats.recordDraftGenerated()
        // Must not crash and must not create any file.
        stats.flushNow()
        stats.flushNow()
        XCTAssertEqual(stats.snapshot().draftsGenerated, 1,
                       "in-memory counter must still be correct after no-op flushes")
    }
}

// MARK: - REP-135: sessionStartedAt and sessionDuration

extension StatsTests {

    func testSessionStartedAtApproximatelyNow() {
        let before = Date()
        let stats = Stats(fileURL: tempURL("session-ts.json"))
        let after = Date()
        XCTAssertGreaterThanOrEqual(stats.sessionStartedAt, before,
            "sessionStartedAt must be set at or after the test's start time")
        XCTAssertLessThanOrEqual(stats.sessionStartedAt, after,
            "sessionStartedAt must be set at or before the test's end time")
    }

    func testSessionDurationIsNonNegative() {
        var tick = Date()
        let stats = Stats(fileURL: tempURL("session-dur.json"), nowProvider: { tick })
        tick = tick.addingTimeInterval(5)
        XCTAssertGreaterThanOrEqual(stats.sessionDuration, 0,
            "sessionDuration must be non-negative")
        XCTAssertEqual(stats.sessionDuration, 5, accuracy: 0.001,
            "sessionDuration must reflect elapsed time from sessionStartedAt")
    }

    func testSessionDurationIncludesInWeeklyLog() throws {
        var tick = Date()
        let stats = Stats(fileURL: tempURL("session-log.json"), nowProvider: { tick })
        tick = tick.addingTimeInterval(10)
        let logURL = tempURL("weekly-session.md")
        try stats.writeWeeklyLog(to: logURL)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("sessionDuration:"),
            "weekly log must include sessionDuration key")
    }
}

// MARK: - REP-177: overallAcceptanceRate

extension StatsTests {

    func testOverallAcceptanceRateNilWhenNoData() {
        let stats = Stats(fileURL: tempURL("overall-nil.json"))
        XCTAssertNil(stats.overallAcceptanceRate(),
            "fresh instance with no drafts must return nil — no data yet")
    }

    func testOverallAcceptanceRateAggregatesAcrossTones() {
        let stats = Stats(fileURL: tempURL("overall-agg.json"))
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftGenerated(tone: .direct)
        stats.recordDraftSent(tone: .warm)

        let rate = stats.overallAcceptanceRate()
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate!, 1.0 / 3.0, accuracy: 1e-9,
            "1 sent out of 3 generated across 2 tones must yield 1/3")
    }

    func testOverallAcceptanceRateZeroWhenGeneratedButNoneSent() {
        let stats = Stats(fileURL: tempURL("overall-zero.json"))
        stats.recordDraftGenerated(tone: .playful)
        stats.recordDraftGenerated(tone: .direct)
        let rate = stats.overallAcceptanceRate()
        XCTAssertNotNil(rate, "rate must be non-nil when drafts were generated")
        XCTAssertEqual(rate!, 0.0, accuracy: 1e-9,
            "0 sent out of 2 generated must yield 0.0, not nil")
    }
}

// MARK: - REP-187: snapshot() JSON-serializable contract

extension StatsTests {

    func testSnapshotIsValidJSONObject() throws {
        let stats = Stats(fileURL: tempURL("snap-json.json"))
        let data = try JSONEncoder().encode(stats.snapshot())
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(obj),
            "encoded snapshot must produce a valid JSON object")
    }

    func testSnapshotWithCountersIsValidJSON() throws {
        let stats = Stats(fileURL: tempURL("snap-json-counters.json"))
        stats.recordDraftGenerated(tone: .warm)
        stats.recordDraftSent(tone: .warm)
        stats.recordRuleFired(action: "pin")
        stats.incrementIndexed(channel: .imessage, count: 3)
        let data = try JSONEncoder().encode(stats.snapshot())
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(obj),
            "snapshot with non-zero counters must still produce valid JSON")
    }
}

// MARK: - REP-213: rulesMatchedCount increments per matched rule

final class RulesMatchedCountTests: XCTestCase {

    // Three rules match one evaluation → rulesMatchedCount grows by 3.
    // Guards against an impl that calls incrementRulesMatched() once per
    // evaluation call regardless of how many rules matched.
    func testRulesMatchedCountIncrementsPerMatchedRule() {
        let stats = Stats(fileURL: nil)
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 0)
        stats.incrementRulesMatched()
        stats.incrementRulesMatched()
        stats.incrementRulesMatched()
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 3,
                       "3 matched rules must increment counter by 3, not 1")
    }

    // Zero rules match → counter untouched.
    func testRulesMatchedCountUnchangedOnZeroMatches() {
        let stats = Stats(fileURL: nil)
        // No incrementRulesMatched() calls — simulates an evaluation where nothing matched.
        XCTAssertEqual(stats.snapshot().rulesMatchedCount, 0,
                       "zero matched rules must leave counter at 0")
    }
}

// MARK: - Stats.defaultFileURL() — production persistence path contract
//
// Stats.shared is initialised with `Stats(fileURL: defaultFileURL())`, so
// changing the path silently abandons every shipped user's stats.json.
// Pin the path components so a future refactor (renaming the parent
// folder, dropping "Application Support", changing the file extension)
// trips a test instead of an unnoticed data migration.

final class StatsDefaultFileURLTests: XCTestCase {

    func testDefaultFileURLEndsWithStatsJSON() {
        let url = Stats.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, "stats.json",
                       "production path must end with stats.json — anything else orphans existing user data")
    }

    /// Pin the source-side hoisted constant byte-for-byte. Sibling to
    /// `testDefaultFileURLEndsWithStatsJSON` (which asserts against
    /// the inline literal `"stats.json"`); this pin asserts the
    /// source constant equals the same literal so a future refactor
    /// that defines the constant but inlines a different literal in
    /// `defaultFileURL()` would still pass that test while drifting
    /// the constant — pinning both directions catches it.
    func testProductionFileNameIsStatsDotJSON() {
        XCTAssertEqual(Stats.productionFileName, "stats.json",
            "Stats.productionFileName drift orphans every install's stats.json — pin both this and testDefaultFileURLEndsWithStatsJSON to catch drift in either direction")
    }

    /// Round-trip pin: `defaultFileURL()` must compose its path through
    /// `productionFileName`. Catches a constant-defined-but-not-used
    /// drift where the function inlines a different literal.
    func testDefaultFileURLRoutesThroughHoistedFileName() {
        let url = Stats.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, Stats.productionFileName,
            "defaultFileURL() must compose through productionFileName byte-for-byte — drift between source and constant is silent")
    }

    func testDefaultFileURLLivesUnderReplyAIDirectory() {
        let url = Stats.defaultFileURL()
        let parent = url.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(parent, "ReplyAI",
                       "stats.json must live in the ReplyAI/ application-support folder so factory-reset can sweep the whole directory")
    }

    func testDefaultFileURLDirectoryExistsAfterCall() {
        // The helper is documented to lazily create the parent directory
        // (`try? FileManager.default.createDirectory(... withIntermediateDirectories: true)`).
        // If that side-effect ever drops, the very first launch on a fresh
        // install fails to write stats and Stats.shared silently degrades
        // to in-memory only — pin it.
        let url = Stats.defaultFileURL()
        let dir = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                      "defaultFileURL() must create the parent directory so the first write succeeds")
        XCTAssertTrue(isDirectory.boolValue,
                      "the ReplyAI/ entry must be a directory, not a stray file")
    }

    func testDefaultFileURLIsAbsoluteAndFileScheme() {
        // A relative URL or a non-file scheme would silently break Data(contentsOf:)
        // / Data.write(to:); pin the basic shape of the URL.
        let url = Stats.defaultFileURL()
        XCTAssertTrue(url.isFileURL, "stats path must be a file:// URL for FileManager + Data(contentsOf:)")
        XCTAssertTrue(url.path.hasPrefix("/"),
                      "stats path must be absolute so behavior doesn't depend on the cwd of the launching process")
    }
}

// MARK: - resetIndexedCounters + guard-clause coverage

final class StatsResetAndGuardTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAIStatsResetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func tempURL(_ name: String = "stats.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    func testResetIndexedCountersZeroesAggregateAndPerChannel() {
        // SearchIndex.clear() relies on this to keep the counter aligned
        // with current index content rather than cumulative history. Both
        // the aggregate counter and every per-channel bucket must drop
        // to zero in one call.
        let stats = Stats(fileURL: tempURL())
        stats.recordMessagesIndexed(100)
        stats.incrementIndexed(channel: .imessage, count: 30)
        stats.incrementIndexed(channel: .slack, count: 70)
        XCTAssertEqual(stats.snapshot().messagesIndexed, 100,
                       "precondition: aggregate counter was bumped")
        XCTAssertEqual(stats.snapshot().messagesIndexedByChannel.values.reduce(0, +), 100,
                       "precondition: per-channel total was bumped")

        stats.resetIndexedCounters()

        XCTAssertEqual(stats.snapshot().messagesIndexed, 0,
                       "aggregate counter must zero after reset")
        XCTAssertTrue(stats.snapshot().messagesIndexedByChannel.isEmpty,
                      "per-channel dictionary must empty after reset — not just zeroed values")
    }

    func testResetIndexedCountersLeavesUnrelatedCountersAlone() {
        // resetIndexedCounters is targeted — drafts/rules counters belong
        // to lifetime stats and must survive a search-index rebuild.
        let stats = Stats(fileURL: tempURL())
        stats.recordDraftGenerated()
        stats.recordDraftSent()
        stats.recordRuleFired(action: "archive")
        stats.recordMessagesIndexed(50)

        stats.resetIndexedCounters()

        let snap = stats.snapshot()
        XCTAssertEqual(snap.draftsGenerated, 1,
                       "drafts counter must survive an indexed-counter reset")
        XCTAssertEqual(snap.draftsSent, 1,
                       "drafts-sent counter must survive an indexed-counter reset")
        XCTAssertEqual(snap.rulesFiredByAction["archive"], 1,
                       "rules-fired counter must survive an indexed-counter reset")
        XCTAssertEqual(snap.messagesIndexed, 0)
    }

    func testResetIndexedCountersPersistsToDisk() {
        // The reset must round-trip through stats.json so a process restart
        // doesn't see the pre-reset counters resurrect.
        let url = tempURL()
        let stats = Stats(fileURL: url)
        stats.incrementIndexed(channel: .imessage, count: 5)
        stats.recordMessagesIndexed(5)
        stats.resetIndexedCounters()
        stats.flushNow()

        let reopened = Stats(fileURL: url)
        XCTAssertEqual(reopened.snapshot().messagesIndexed, 0)
        XCTAssertTrue(reopened.snapshot().messagesIndexedByChannel.isEmpty)
    }

    func testIncrementIndexedIgnoresZeroAndNegativeCounts() {
        // Defensive guard — callers passing 0 (no-op rebuild) or a negative
        // (bug) must not corrupt the per-channel dictionary with phantom
        // entries.
        let stats = Stats(fileURL: tempURL())
        stats.incrementIndexed(channel: .slack, count: 0)
        stats.incrementIndexed(channel: .slack, count: -3)
        XCTAssertTrue(stats.snapshot().messagesIndexedByChannel.isEmpty,
                      "non-positive counts must not create a per-channel entry")
    }

    func testRecordRuleLoadSkipsIgnoresZeroAndNegativeCounts() {
        // Same defensive guard — passing 0 (clean load, no skips) or a
        // negative (bug) must leave the counter untouched.
        let stats = Stats(fileURL: tempURL())
        stats.recordRuleLoadSkips(2)  // baseline
        stats.recordRuleLoadSkips(0)
        stats.recordRuleLoadSkips(-5)
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 2,
                       "non-positive counts must leave the counter at the prior value")
    }

    /// Multiple positive calls must accumulate (`+=`), not overwrite (`=`).
    /// The sibling guard test above only exercises one positive call before
    /// the no-op cases, so a refactor of `state.withLock { $0.ruleLoadSkips
    /// += count }` to `= count` would silently pass it. Pin the accumulation
    /// contract directly so a future "simplification" can't regress it.
    func testRecordRuleLoadSkipsAccumulatesAcrossPositiveCalls() {
        let stats = Stats(fileURL: tempURL())
        stats.recordRuleLoadSkips(2)
        stats.recordRuleLoadSkips(3)
        stats.recordRuleLoadSkips(7)
        XCTAssertEqual(stats.snapshot().ruleLoadSkips, 12,
                       "successive positive recordRuleLoadSkips calls must add to the running total, not overwrite it")
    }

    // MARK: - Forward-compat decode of partial stats.json

    /// Pin that an on-disk stats.json missing some-but-not-all keys decodes
    /// successfully, with the missing keys defaulting to their zero values.
    /// This is the contract that makes a counter-set extension safe: when a
    /// new counter (`rulesMatchedCount`, future `tokensConsumed`, etc.) is
    /// added, existing stats.json files written by older builds still load
    /// without dropping accumulated lifetime counts.
    ///
    /// The custom `Snapshot.init(from:)` uses `decodeIfPresent ?? default`
    /// for every key. `testEmptyFileReturnsFreshSnapshot` covers the
    /// empty-file path; `testMalformedFileFallsBackToFreshSnapshot` covers
    /// the invalid-JSON path; this test covers the in-between case where
    /// the JSON is valid but incomplete.
    func testStatsSnapshotDecodesPartialJSONWithDefaultedMissingKeys() throws {
        let url = tempURL()
        // Only `draftsGenerated` and `messagesIndexed` are written. Every
        // other key is omitted — older builds produced files of this shape
        // before the per-tone, per-channel, and matched-count counters
        // landed. The decode must NOT throw on the missing keys.
        let partialJSON = #"{"draftsGenerated": 7, "messagesIndexed": 42}"#
        try Data(partialJSON.utf8).write(to: url)

        let stats = Stats(fileURL: url)
        let snap = stats.snapshot()

        XCTAssertEqual(snap.draftsGenerated, 7,
            "explicitly-set key must round-trip")
        XCTAssertEqual(snap.messagesIndexed, 42,
            "explicitly-set key must round-trip")

        // Every other key must default cleanly. Drift here (e.g. swapping
        // any `decodeIfPresent ?? …` to a bare `decode`) would break the
        // upgrade path for every user with an existing stats.json.
        XCTAssertEqual(snap.draftsSent, 0)
        XCTAssertEqual(snap.rulesFiredByAction, [:])
        XCTAssertEqual(snap.draftsGeneratedByTone, [:])
        XCTAssertEqual(snap.draftsSentByTone, [:])
        XCTAssertEqual(snap.messagesIndexedByChannel, [:])
        XCTAssertEqual(snap.ruleLoadSkips, 0)
        XCTAssertEqual(snap.rulesMatchedCount, 0)
    }

    /// Pin that an on-disk stats.json containing extra/unknown keys (e.g.
    /// from a newer build that's been downgraded) decodes successfully and
    /// silently ignores the unknown keys. This is the symmetric forward-
    /// compat invariant: old code reading new files must not lose known-key
    /// data just because there are extras.
    func testStatsSnapshotDecodeIgnoresUnknownKeys() throws {
        let url = tempURL()
        let futureJSON = #"""
        {"draftsGenerated": 3, "tokensConsumed": 99, "futureCounter": "hello"}
        """#
        try Data(futureJSON.utf8).write(to: url)

        let stats = Stats(fileURL: url)
        XCTAssertEqual(stats.snapshot().draftsGenerated, 3,
            "decoder must accept and ignore unknown keys without dropping known-key data")
    }

    // MARK: - RuleAction constants freeze

    /// Pin the five `Stats.RuleAction` discriminator strings. These are
    /// also the dictionary keys persisted to disk via
    /// `Stats.persist()` — drift here splits historical counters
    /// across two keys (old builds wrote "pin" and a renamed constant
    /// would create a new bucket while the old one stays untouched on
    /// disk forever).
    func testRuleActionConstantsAreFrozen() {
        XCTAssertEqual(Stats.RuleAction.archive,        "archive")
        XCTAssertEqual(Stats.RuleAction.silentlyIgnore, "silentlyIgnore")
        XCTAssertEqual(Stats.RuleAction.markDone,       "markDone")
        XCTAssertEqual(Stats.RuleAction.setDefaultTone, "setDefaultTone")
        XCTAssertEqual(Stats.RuleAction.pin,            "pin")
    }

    /// Pin the partition invariant: the five constants are pairwise
    /// distinct. Collision (two constants resolving to the same string)
    /// would silently merge two action counters into one bucket — the
    /// stats surface would show the right total but the wrong per-
    /// action breakdown.
    func testRuleActionConstantsArePairwiseDistinct() {
        let all = [
            Stats.RuleAction.archive,
            Stats.RuleAction.silentlyIgnore,
            Stats.RuleAction.markDone,
            Stats.RuleAction.setDefaultTone,
            Stats.RuleAction.pin,
        ]
        XCTAssertEqual(Set(all).count, all.count,
            "RuleAction constants must be pairwise distinct — collision merges per-action counters")
    }

    /// Route-through pin: counting `recordRuleFired(action:)` with the
    /// hoisted constant is observed by the snapshot under the same
    /// raw-string key. Catches a refactor that would route the constant
    /// through a transformer (lowercasing, trimming) before storage.
    func testRecordRuleFiredRoutesThroughRuleActionConstant() {
        let stats = Stats(fileURL: tempURL())
        stats.recordRuleFired(action: Stats.RuleAction.archive)
        stats.recordRuleFired(action: Stats.RuleAction.archive)
        stats.recordRuleFired(action: Stats.RuleAction.pin)
        let snap = stats.snapshot()
        XCTAssertEqual(snap.rulesFiredByAction[Stats.RuleAction.archive], 2)
        XCTAssertEqual(snap.rulesFiredByAction[Stats.RuleAction.pin],     1)
        XCTAssertEqual(snap.rulesFiredByAction["archive"], 2,
            "constants must round-trip to the bare-string key — the snapshot dictionary is keyed on the raw value")
    }

    /// Pin the literal `Stats.writeQueueLabel` value. The label
    /// surfaces in Instruments / sample traces — drift in the
    /// literal (e.g. a refactor that "tidies up" the queue label
    /// without realizing external tooling keys off it) silently
    /// breaks production observability filters. Hoisted from the
    /// inline `DispatchQueue(label:)` so this pin can assert the
    /// exact string a profiler will see.
    func testWriteQueueLabelIsFrozen() {
        XCTAssertEqual(Stats.writeQueueLabel, "com.replyai.stats.write",
            "writeQueueLabel drift breaks Instruments filters keyed on the literal queue label — re-prefixing requires migrating any external observability rules first")
    }

    /// Cross-file divergence pin. The Stats writer queue uses the
    /// `com.replyai.` Java-style reverse-DNS prefix, while every
    /// other queue / Notification.Name / Keychain service in the
    /// codebase uses `co.replyai.`. The Stats label is the only
    /// drifted one. Pin asserts the inequality so a future
    /// "let's harmonize prefixes across the codebase" refactor
    /// surfaces as a deliberate change here, with a migration
    /// note for any external observability tooling pinned to
    /// the historical `com.replyai.` literal.
    func testWriteQueueLabelDivergesFromCoReplyAIPrefix() {
        // The non-stats sibling labels all start with `co.replyai.`.
        XCTAssertTrue(ChatDBWatcher.dispatchQueueLabel.hasPrefix("co.replyai."),
            "ChatDBWatcher uses co.replyai. prefix — sibling for the divergence pin")
        XCTAssertTrue(MessagesAppActivationObserver.dispatchQueueLabel.hasPrefix("co.replyai."),
            "MessagesAppActivationObserver uses co.replyai. prefix — sibling for the divergence pin")

        // Stats does NOT start with co.replyai. — pin the divergence.
        XCTAssertFalse(Stats.writeQueueLabel.hasPrefix("co.replyai."),
            "Stats.writeQueueLabel uses 'com.replyai.' (Java-style) while every sibling uses 'co.replyai.' — pin so a future harmonization is a deliberate change with a migration plan, not a silent rename")
        XCTAssertTrue(Stats.writeQueueLabel.hasPrefix("com.replyai."),
            "Stats.writeQueueLabel uses 'com.replyai.' prefix specifically — drift away breaks the assumption that the divergence shape is com vs co (e.g. drift to 'app.replyai.' would still satisfy `!hasPrefix(\"co.replyai.\")` but isn't the documented historical state)")
    }

    /// Pin the cross-vocabulary divergence between Stats counters
    /// (camelCase, used in the on-disk stats.json) and the
    /// rules.json schema's RuleAction Codable form (snake_case,
    /// pinned by `RulesTests.testActionKindDiscriminatorsAreStable`).
    /// Three of the five action names diverge between the two
    /// vocabularies on purpose — the camelCase form predates the
    /// snake_case rules.json schema and renaming Stats keys would
    /// orphan every existing user's persisted stats.json. A
    /// well-meaning "consistency fix" that aligns the two would
    /// pass both vocabularies' individual pins (Stats round-trip
    /// + rules.json kind discriminators) while silently splitting
    /// historical counters across two keys on every shipped user's
    /// stats file. Pin asserts the divergence so a future
    /// harmonization refactor surfaces here as a deliberate change
    /// with a migration plan attached.
    func testStatsRuleActionConstantsDivergeFromRulesJSONSnakeCase() {
        // Three actions whose camelCase Stats key differs from the
        // snake_case rules.json kind. Pin the inequality, not just
        // the values — so a future build that aligns either side
        // surfaces here.
        XCTAssertNotEqual(Stats.RuleAction.silentlyIgnore, "silently_ignore",
            "Stats counters use camelCase 'silentlyIgnore' on disk; rules.json uses snake_case 'silently_ignore' — a future consistency refactor must migrate stats.json before flipping either side")
        XCTAssertNotEqual(Stats.RuleAction.markDone, "mark_done",
            "Stats counters use camelCase 'markDone' on disk; rules.json uses snake_case 'mark_done' — divergence is intentional, not a bug")
        XCTAssertNotEqual(Stats.RuleAction.setDefaultTone, "set_default_tone",
            "Stats counters use camelCase 'setDefaultTone' on disk; rules.json uses snake_case 'set_default_tone' — divergence is intentional, not a bug")

        // Two actions whose names happen to coincide across both
        // vocabularies (single-word identifiers, no camelCase to
        // diverge from). Pin the equality so a future "let's at
        // least normalize the diverging ones" partial harmonization
        // doesn't accidentally unify the wrong direction here.
        XCTAssertEqual(Stats.RuleAction.archive, "archive",
            "single-word 'archive' coincides across both vocabularies — Stats and rules.json agree by accident, not by design")
        XCTAssertEqual(Stats.RuleAction.pin, "pin",
            "single-word 'pin' coincides across both vocabularies — Stats and rules.json agree by accident, not by design")
    }
}
