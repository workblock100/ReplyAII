import XCTest
@testable import ReplyAI

final class FixturesTests: XCTestCase {
    func testEveryThreadHasStableID() {
        let ids = Fixtures.threads.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "thread IDs must be unique")
    }

    func testSeededDraftsExistForPrimaryThreads() {
        for tone in Tone.allCases {
            XCTAssertFalse(Fixtures.seedDraft(threadID: "t1", tone: tone).isEmpty)
            XCTAssertFalse(Fixtures.seedDraft(threadID: "t3", tone: tone).isEmpty)
        }
    }

    func testUnknownThreadReturnsGenericAcknowledgment() {
        // Live iMessage threads aren't in fixtures — the stub LLM must
        // return a neutral per-tone line instead of a canned Maya Chen
        // response that would read absurdly to anyone else.
        for tone in Tone.allCases {
            let fallback = Fixtures.seedDraft(threadID: "nonexistent-xyz", tone: tone)
            XCTAssertFalse(fallback.isEmpty)
            XCTAssertEqual(fallback, Fixtures.genericAcknowledgment(tone: tone))
            // Must NOT leak the t1 ("review the deck") copy.
            let t1 = Fixtures.seedDraft(threadID: "t1", tone: tone)
            XCTAssertNotEqual(fallback, t1)
        }
    }

    func testLowConfidenceThreadBelowThreshold() {
        // cmp-lowconf surfaces at confidence < 0.4. t4 (SMS verification code)
        // should fall in that bucket.
        let c = Fixtures.seedConfidence(threadID: "t4", tone: .warm)
        XCTAssertLessThan(c, 0.4)
    }

    func testHighContextThreadsAboveThreshold() {
        for id in ["t1", "t3"] {
            let c = Fixtures.seedConfidence(threadID: id, tone: .warm)
            XCTAssertGreaterThanOrEqual(c, 0.4)
        }
    }

    func testMessagesFallBackWhenNotSeeded() {
        let fallback = Fixtures.messages(forThread: "t2", fallback: "x", time: "1:00 PM")
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback[0].text, "x")
        XCTAssertEqual(fallback[0].from, .them)
    }

    func testChannelReplyCountsAreFinite() {
        for ch in Channel.allCases {
            XCTAssertGreaterThan(Fixtures.replyCount(for: ch), 0)
        }
    }
}
