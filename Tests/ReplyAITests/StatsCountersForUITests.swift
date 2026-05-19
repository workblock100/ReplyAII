import XCTest
@testable import ReplyAICore

/// Pin `Stats.countersForUI()` — the narrow public read API the
/// privacy screen depends on (REP-045). Locks in:
/// (1) the field names callers expect, (2) `rulesFiredTotal` matches
/// the sum of `rulesFiredByAction.values`, and (3) zero-state returns
/// real zeros rather than nil-or-missing.
final class StatsCountersForUITests: XCTestCase {

    private func makeIsolatedStats() -> Stats {
        // fileURL: nil → no persistence; safe for test isolation.
        Stats(fileURL: nil)
    }

    func testZeroStateAllFieldsZero() {
        let stats = makeIsolatedStats()
        let c = stats.countersForUI()
        XCTAssertEqual(c.draftsGenerated, 0)
        XCTAssertEqual(c.draftsSent, 0)
        XCTAssertEqual(c.messagesIndexed, 0)
        XCTAssertEqual(c.rulesMatchedCount, 0)
        XCTAssertEqual(c.rulesFiredTotal, 0)
        XCTAssertEqual(c.rulesFiredByAction, [:])
    }

    func testDraftCountersTracked() {
        let stats = makeIsolatedStats()
        stats.recordDraftGenerated()
        stats.recordDraftGenerated()
        stats.recordDraftSent()
        let c = stats.countersForUI()
        XCTAssertEqual(c.draftsGenerated, 2)
        XCTAssertEqual(c.draftsSent, 1)
    }

    func testMessagesIndexedTracked() {
        let stats = makeIsolatedStats()
        stats.recordMessagesIndexed(42)
        XCTAssertEqual(stats.countersForUI().messagesIndexed, 42)
        stats.recordMessagesIndexed(8)
        XCTAssertEqual(stats.countersForUI().messagesIndexed, 50,
                       "messagesIndexed must accumulate across calls (not overwrite)")
    }

    func testRulesFiredTotalSumsByActionDictionary() {
        let stats = makeIsolatedStats()
        stats.recordRuleFired(action: Stats.RuleAction.archive)
        stats.recordRuleFired(action: Stats.RuleAction.archive)
        stats.recordRuleFired(action: Stats.RuleAction.pin)
        let c = stats.countersForUI()
        XCTAssertEqual(c.rulesFiredTotal, 3,
                       "rulesFiredTotal must equal sum of rulesFiredByAction values")
        XCTAssertEqual(c.rulesFiredByAction[Stats.RuleAction.archive], 2)
        XCTAssertEqual(c.rulesFiredByAction[Stats.RuleAction.pin], 1)
        XCTAssertEqual(c.rulesFiredByAction.values.reduce(0, +), c.rulesFiredTotal)
    }

    func testRulesMatchedCountTracked() {
        let stats = makeIsolatedStats()
        stats.incrementRulesMatched()
        stats.incrementRulesMatched()
        XCTAssertEqual(stats.countersForUI().rulesMatchedCount, 2)
    }

    func testCountersForUIIsEquatable() {
        let stats = makeIsolatedStats()
        let a = stats.countersForUI()
        let b = stats.countersForUI()
        XCTAssertEqual(a, b, "two snapshots of identical state must compare equal — relied on by SwiftUI for redraw avoidance")
        stats.recordDraftGenerated()
        let c = stats.countersForUI()
        XCTAssertNotEqual(a, c, "snapshot after a counter increment must compare unequal")
    }
}
