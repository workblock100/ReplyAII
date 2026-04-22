import XCTest
@testable import ReplyAI

final class SearchIndexTests: XCTestCase {
    // MARK: - Query translation

    func testFTSQueryAppendsPrefix() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "dinner"),       "dinner*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "dinner mom"),   "dinner* AND mom*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "   dinner   "), "dinner*")
    }

    func testSingleWordUnchanged() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello"), "hello*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "world"), "world*")
    }

    func testMultiWordUsesExplicitAND() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello world"), "hello* AND world*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "a b c"), "a* AND b* AND c*")
    }

    func testEmptyQueryReturnsEmpty() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: ""), "")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "  "), "")
    }

    func testFTSQueryQuotesSpecialChars() {
        let out = SearchIndex.ftsQuery(from: "foo:bar")
        XCTAssertEqual(out, #""foo:bar""#)
    }

    func testFTSQueryHandlesEmpty() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: ""),    "")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "   "), "")
    }

    // MARK: - Live index

    func testIndexSearchMatchesText() async {
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "m", channel: .imessage, name: "Mom",
                          avatar: "M", preview: "", time: "", unread: 0),
            MessageThread(id: "r", channel: .slack, name: "Ravi",
                          avatar: "R", preview: "", time: "", unread: 0),
        ]
        let messages: [String: [Message]] = [
            "m": [Message(from: .them, text: "dont forget sundays dinner ♥", time: "1:08 PM")],
            "r": [Message(from: .them, text: "shipped the billing flow", time: "12:52 PM")],
        ]
        await index.rebuild(from: messages, threads: threads)

        let hits = await index.search("dinner")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.threadID, "m")
        XCTAssertEqual(hits.first?.threadName, "Mom")
        XCTAssertTrue(hits.first?.text.contains("dinner") == true)
    }

    func testIndexPrefixMatching() async {
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "t1", channel: .slack, name: "x",
                          avatar: "x", preview: "", time: "", unread: 0)
        ]
        let messages: [String: [Message]] = [
            "t1": [Message(from: .them, text: "review the billing flow", time: "now")]
        ]
        await index.rebuild(from: messages, threads: threads)

        let hits = await index.search("bill")
        XCTAssertEqual(hits.count, 1, "prefix should match 'billing'")
    }

    func testIndexMultiTokenAND() async {
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "t1", channel: .imessage, name: "Mom",
                          avatar: "M", preview: "", time: "", unread: 0),
            MessageThread(id: "t2", channel: .imessage, name: "Theo",
                          avatar: "T", preview: "", time: "", unread: 0),
        ]
        let messages: [String: [Message]] = [
            "t1": [Message(from: .them, text: "dinner sunday?", time: "today")],
            "t2": [Message(from: .them, text: "dinner with the crew", time: "yesterday")],
        ]
        await index.rebuild(from: messages, threads: threads)

        // "dinner sunday" should match only the Mom thread, since it's
        // the only row containing BOTH tokens.
        let hits = await index.search("dinner sunday")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.threadID, "t1")
    }

    func testIndexEmptyQueryReturnsNothing() async {
        let index = SearchIndex()
        let threads = [MessageThread(id: "x", channel: .imessage, name: "x",
                                     avatar: "x", preview: "", time: "", unread: 0)]
        await index.rebuild(
            from: ["x": [Message(from: .them, text: "anything", time: "")]],
            threads: threads
        )
        let hits = await index.search("")
        XCTAssertTrue(hits.isEmpty)
    }

    func testIndexRebuildReplacesContents() async {
        let index = SearchIndex()
        let threads = [MessageThread(id: "x", channel: .imessage, name: "x",
                                     avatar: "x", preview: "", time: "", unread: 0)]
        await index.rebuild(
            from: ["x": [Message(from: .them, text: "first", time: "")]],
            threads: threads
        )
        var hits = await index.search("first")
        XCTAssertEqual(hits.count, 1)

        await index.rebuild(
            from: ["x": [Message(from: .them, text: "second", time: "")]],
            threads: threads
        )
        hits = await index.search("first")
        XCTAssertEqual(hits.count, 0, "rebuild should have wiped the old row")
        hits = await index.search("second")
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - Incremental upsert

    func testUpsertMakesThreadSearchable() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "u1", channel: .imessage, name: "Maya",
                                   avatar: "M", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "ship the launch post", time: "now")
        ])
        let hits = await index.search("launch")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.threadID, "u1")
    }

    func testUpsertReplacesStaleEntry() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "u2", channel: .imessage, name: "Ravi",
                                   avatar: "R", preview: "", time: "", unread: 0)

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "first draft", time: "t0")
        ])
        var hits = await index.search("first")
        XCTAssertEqual(hits.count, 1)

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "second draft", time: "t1")
        ])
        hits = await index.search("first")
        XCTAssertEqual(hits.count, 0, "upsert should wipe prior rows for the thread")
        hits = await index.search("second")
        XCTAssertEqual(hits.count, 1)
    }

    func testUpsertLeavesOtherThreadsAlone() async {
        let index = SearchIndex()
        let a = MessageThread(id: "a", channel: .imessage, name: "Alice",
                              avatar: "A", preview: "", time: "", unread: 0)
        let b = MessageThread(id: "b", channel: .imessage, name: "Bob",
                              avatar: "B", preview: "", time: "", unread: 0)

        await index.upsert(thread: a, messages: [
            Message(from: .them, text: "alpha token", time: "t0")
        ])
        await index.upsert(thread: b, messages: [
            Message(from: .them, text: "bravo token", time: "t0")
        ])

        // Replacing Alice's content must not remove Bob's.
        await index.upsert(thread: a, messages: [
            Message(from: .them, text: "gamma token", time: "t1")
        ])

        let alphaHits = await index.search("alpha")
        XCTAssertEqual(alphaHits.count, 0)
        let bravoHits = await index.search("bravo")
        XCTAssertEqual(bravoHits.count, 1, "upsert must be scoped to the target thread")
        let gammaHits = await index.search("gamma")
        XCTAssertEqual(gammaHits.count, 1)
    }

    func testRebuildStillWorksAfterUpsert() async {
        let index = SearchIndex()
        let a = MessageThread(id: "a", channel: .imessage, name: "Alice",
                              avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: a, messages: [
            Message(from: .them, text: "alpha token", time: "t0")
        ])
        let preRebuildHits = await index.search("alpha")
        XCTAssertEqual(preRebuildHits.count, 1)

        // A full rebuild should wipe prior upserts — rebuild is the
        // authoritative reset path.
        let b = MessageThread(id: "b", channel: .imessage, name: "Bob",
                              avatar: "B", preview: "", time: "", unread: 0)
        await index.rebuild(from: ["b": [
            Message(from: .them, text: "bravo token", time: "t1")
        ]], threads: [b])

        let postRebuildAlpha = await index.search("alpha")
        XCTAssertEqual(postRebuildAlpha.count, 0,
                       "rebuild after upsert should clear stale rows")
        let postRebuildBravo = await index.search("bravo")
        XCTAssertEqual(postRebuildBravo.count, 1)
    }

    func testMultiWordAndSemantics() async {
        // "hello" and "world" appear in the same message but are not adjacent.
        // AND semantics must match; phrase semantics ("hello world") would not.
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "t1", channel: .imessage, name: "Alice",
                          avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "t2", channel: .imessage, name: "Bob",
                          avatar: "B", preview: "", time: "", unread: 0),
        ]
        let messages: [String: [Message]] = [
            // "hello" and "world" separated by several words — not adjacent
            "t1": [Message(from: .them, text: "hello everyone in the whole wide world", time: "now")],
            // only "hello", no "world"
            "t2": [Message(from: .them, text: "hello there", time: "now")],
        ]
        await index.rebuild(from: messages, threads: threads)

        let hits = await index.search("hello world")
        XCTAssertEqual(hits.count, 1, "AND query must match both words anywhere, not as a phrase")
        XCTAssertEqual(hits.first?.threadID, "t1")
    }

    func testIndexMatchesDiacriticsFolded() async {
        // unicode61 tokenizer with remove_diacritics=2 should match
        // "cafe" against "café".
        let index = SearchIndex()
        let threads = [MessageThread(id: "x", channel: .imessage, name: "x",
                                     avatar: "x", preview: "", time: "", unread: 0)]
        await index.rebuild(
            from: ["x": [Message(from: .them, text: "meet at the café tomorrow", time: "")]],
            threads: threads
        )
        let hits = await index.search("cafe")
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - Concurrency (REP-057)

    func testConcurrentUpsertAndSearch() async {
        // SearchIndex is a Swift actor, so all calls are serialised through
        // the actor executor — no data races are possible. This test verifies
        // that 100 concurrent upsert + search tasks drain cleanly and that
        // the index contains the expected rows after all work completes.
        let index = SearchIndex()
        let threadCount = 10

        // Seed an initial set of threads so searches can return results
        // while concurrent upserts are in flight.
        let threads = (0..<threadCount).map { i in
            MessageThread(id: "t\(i)", channel: .imessage, name: "Thread \(i)",
                          avatar: "T", preview: "", time: "", unread: 0)
        }
        let messages: [String: [Message]] = Dictionary(uniqueKeysWithValues: threads.map { t in
            (t.id, [Message(from: .them, text: "concurrent stress test \(t.id)", time: "now")])
        })
        await index.rebuild(from: messages, threads: threads)

        // Run 100 concurrent tasks — half upsert, half search.
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let threadIdx = i % threadCount
                    if i % 2 == 0 {
                        let t = threads[threadIdx]
                        let newMsg = Message(from: .them,
                                            text: "updated message \(i)",
                                            time: "now")
                        await index.upsert(thread: t, messages: [newMsg])
                    } else {
                        _ = await index.search("stress")
                    }
                }
            }
        }

        // After all concurrent work, the index must still be queryable and
        // return a deterministic count for a term present in upserted rows.
        let hits = await index.search("updated")
        // At least some threads were upserted with "updated message"; the
        // exact count depends on ordering but must be ≥ 1 and ≤ threadCount.
        XCTAssertGreaterThanOrEqual(hits.count, 1,
            "index must return results after concurrent upserts")
        XCTAssertLessThanOrEqual(hits.count, threadCount,
            "result count must not exceed the number of threads")
    }
}
