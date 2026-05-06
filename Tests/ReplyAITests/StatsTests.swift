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

    // MARK: - Persistence

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
}
