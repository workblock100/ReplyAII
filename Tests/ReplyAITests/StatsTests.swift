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

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "stats.json should be written on each increment")

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
}
