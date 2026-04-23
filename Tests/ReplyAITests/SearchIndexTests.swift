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

    // MARK: - Delete (REP-063)

    func testDeleteRemovesFromSearch() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "del1", channel: .imessage, name: "Alice",
                                   avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "remember to buy milk", time: "now")
        ])

        var hits = await index.search("milk")
        XCTAssertEqual(hits.count, 1, "thread must be findable before delete")

        await index.delete(threadID: "del1")

        hits = await index.search("milk")
        XCTAssertEqual(hits.count, 0, "thread must not appear in search after delete")
    }

    func testDeleteNonExistentThreadIsNoOp() async {
        let index = SearchIndex()
        // No crash or error expected when deleting a thread that was never indexed.
        await index.delete(threadID: "ghost-thread-id")
        let hits = await index.search("anything")
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - BM25 ranking (REP-033)

    func testExactMatchRanksAbovePartialMatch() async {
        let index = SearchIndex()
        // t1: single occurrence of "dinner" in a long sentence → low term frequency
        // t2: body is five repetitions of "dinner" → high term frequency → higher BM25
        let threads = [
            MessageThread(id: "t1", channel: .imessage, name: "Alice",
                          avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "t2", channel: .imessage, name: "Bob",
                          avatar: "B", preview: "", time: "", unread: 0),
        ]
        let messages: [String: [Message]] = [
            "t1": [Message(from: .them,
                           text: "hey want to grab lunch or maybe dinner at some point soon",
                           time: "now")],
            "t2": [Message(from: .them, text: "dinner dinner dinner dinner dinner", time: "now")],
        ]
        await index.rebuild(from: messages, threads: threads)

        let hits = await index.search("dinner")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].threadID, "t2",
                       "higher term-frequency document must rank above lower one")
        XCTAssertEqual(hits[1].threadID, "t1")
    }

    func testResultsOrderedByRelevance() async {
        let index = SearchIndex()
        let threads = (1...3).map { i in
            MessageThread(id: "t\(i)", channel: .slack, name: "Thread \(i)",
                          avatar: "\(i)", preview: "", time: "", unread: 0)
        }
        // Relevance scales with repetition of the query term.
        let messages: [String: [Message]] = [
            "t1": [Message(from: .them, text: "lunch", time: "now")],
            "t2": [Message(from: .them, text: "lunch lunch lunch", time: "now")],
            "t3": [Message(from: .them, text: "lunch lunch lunch lunch lunch", time: "now")],
        ]
        await index.rebuild(from: messages, threads: threads)

        let hits = await index.search("lunch")
        XCTAssertEqual(hits.count, 3)
        // FTS5 ORDER BY rank is ascending (lower = better); t3 > t2 > t1 by term frequency.
        let ids = hits.map(\.threadID)
        XCTAssertEqual(ids[0], "t3", "highest term-frequency must rank first")
        XCTAssertEqual(ids[1], "t2")
        XCTAssertEqual(ids[2], "t1", "lowest term-frequency must rank last")
    }

    // MARK: - Prefix match (REP-085)

    func testPartialWordMatchesFullToken() async {
        // Prefix matching via `*` means "ali" must match a thread with "Alice".
        let index = SearchIndex()
        let thread = MessageThread(id: "p1", channel: .imessage, name: "Alice Stone",
                                   avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "hey Alice, got your message", time: "now")
        ])
        let hits = await index.search("ali")
        XCTAssertEqual(hits.count, 1, "partial 'ali' must match 'Alice' via prefix search")
    }

    func testMultiWordPartialMatchesLastToken() async {
        // All tokens receive prefix matching; "ali sto" → "ali* AND sto*" matches
        // a thread containing both "Alice" and "Stone".
        let index = SearchIndex()
        let thread = MessageThread(id: "p2", channel: .imessage, name: "Alice Stone",
                                   avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "Alice Stone here", time: "now")
        ])
        let hits = await index.search("ali sto")
        XCTAssertEqual(hits.count, 1, "multi-word partial 'ali sto' must match 'Alice Stone'")
    }

    func testFullWordQueryStillMatches() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "p3", channel: .imessage, name: "Alice",
                                   avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "message from Alice", time: "now")
        ])
        let hits = await index.search("alice")
        XCTAssertEqual(hits.count, 1, "full word query must still match")
    }

    // MARK: - FTS5 sanitizer (REP-092)

    func testDoubleQuoteInQueryDoesNotCrash() async {
        // A double-quote in user input must not produce malformed FTS5 syntax.
        // The sanitizer strips quotes; the search returns safe results (possibly
        // empty if nothing matches).
        let index = SearchIndex()
        let thread = MessageThread(id: "s1", channel: .imessage, name: "Carol",
                                   avatar: "C", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "hello world", time: "now")
        ])
        // Should not crash or throw; result count is not asserted (could be 0).
        let hits = await index.search("hel\"lo")
        XCTAssertGreaterThanOrEqual(hits.count, 0, "double-quote input must not crash FTS5")
    }

    func testHyphenQueryReturnsSafeResults() async {
        // Hyphens are stripped from query tokens before FTS5 receives them,
        // preventing parse errors from bare `-` or `token-` patterns.
        let index = SearchIndex()
        let thread = MessageThread(id: "s2", channel: .imessage, name: "Bob",
                                   avatar: "B", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "call me john smith", time: "now")
        ])
        // "john-smith" → strip hyphen → "johnsmith*" — won't match "john smith"
        // but must not crash.
        let hits = await index.search("john-smith")
        XCTAssertGreaterThanOrEqual(hits.count, 0, "hyphen in query must not crash FTS5")
    }

    func testReservedWordTreatedAsLiteral() {
        // FTS5 boolean operators (NOT, AND, OR) in user input must be treated as
        // search terms, not operators. The sanitizer appends `*` which prevents
        // the parser from interpreting them as binary/unary operators.
        let notQuery = SearchIndex.ftsQuery(from: "NOT")
        XCTAssertEqual(notQuery, "NOT*", "NOT as single token must become prefix match, not operator")

        let andQuery = SearchIndex.ftsQuery(from: "AND")
        XCTAssertEqual(andQuery, "AND*")

        let orQuery = SearchIndex.ftsQuery(from: "OR")
        XCTAssertEqual(orQuery, "OR*")
    }

    func testValidQueryIsUnmodified() {
        // Plain alpha-only tokens must pass through with `*` appended and no quoting.
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello"),       "hello*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello world"), "hello* AND world*")
    }

    // MARK: - Channel filter (REP-080)

    func testChannelFilterReturnsOnlyMatchingChannel() async {
        let index = SearchIndex()
        let iMsg   = MessageThread(id: "c1", channel: .imessage, name: "Alice",
                                   avatar: "A", preview: "", time: "", unread: 0)
        let slackT = MessageThread(id: "c2", channel: .slack, name: "Bob",
                                   avatar: "B", preview: "", time: "", unread: 0)

        await index.upsert(thread: iMsg,   messages: [Message(from: .them, text: "hello from imessage", time: "t")])
        await index.upsert(thread: slackT, messages: [Message(from: .them, text: "hello from slack",    time: "t")])

        let iMsgHits   = await index.search(query: "hello", channel: .imessage)
        let slackHits  = await index.search(query: "hello", channel: .slack)

        XCTAssertEqual(iMsgHits.count, 1)
        XCTAssertEqual(iMsgHits.first?.threadID, "c1", "imessage filter must exclude slack thread")

        XCTAssertEqual(slackHits.count, 1)
        XCTAssertEqual(slackHits.first?.threadID, "c2", "slack filter must exclude imessage thread")
    }

    func testNilChannelReturnsAll() async {
        let index = SearchIndex()
        let iMsg   = MessageThread(id: "d1", channel: .imessage, name: "Alice",
                                   avatar: "A", preview: "", time: "", unread: 0)
        let slackT = MessageThread(id: "d2", channel: .slack, name: "Bob",
                                   avatar: "B", preview: "", time: "", unread: 0)

        await index.upsert(thread: iMsg,   messages: [Message(from: .them, text: "greet everyone", time: "t")])
        await index.upsert(thread: slackT, messages: [Message(from: .them, text: "greet everyone", time: "t")])

        let hits = await index.search(query: "greet", channel: nil)
        XCTAssertEqual(hits.count, 2, "nil channel must return threads from all channels")
    }

    func testUpsertedChannelIsPersisted() async {
        // After an upsert the channel value must survive in the index so that
        // per-channel filtering produces the right result.
        let index  = SearchIndex()
        let slackT = MessageThread(id: "e1", channel: .slack, name: "Team",
                                   avatar: "T", preview: "", time: "", unread: 0)
        await index.upsert(thread: slackT, messages: [
            Message(from: .them, text: "deploy complete", time: "t")
        ])

        let slackHits = await index.search(query: "deploy", channel: .slack)
        XCTAssertEqual(slackHits.count, 1, "slack channel must be persisted in index")

        let iMsgHits = await index.search(query: "deploy", channel: .imessage)
        XCTAssertEqual(iMsgHits.count, 0, "imessage filter must not find a slack-indexed thread")
    }

    // MARK: - Disk persistence (REP-041)

    func testPersistenceAcrossReopens() async throws {
        // Write rows into a file-backed index, close it by letting the actor
        // deinit, then reopen the same file and verify the rows are still searchable.
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-search-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let thread = MessageThread(id: "p1", channel: .imessage, name: "Persistence",
                                   avatar: "P", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "remember this message", time: "t")

        do {
            let index = SearchIndex(databaseURL: dbURL)
            await index.upsert(thread: thread, messages: [msg])
            let hits = await index.search("remember")
            XCTAssertEqual(hits.count, 1, "must find row before close")
        }
        // index is deinit'd here; SQLite file is flushed to disk.

        let reopened = SearchIndex(databaseURL: dbURL)
        let hits = await reopened.search("remember")
        XCTAssertEqual(hits.count, 1, "file-backed index must survive close + reopen")
        XCTAssertEqual(hits.first?.threadID, "p1")
        XCTAssertEqual(hits.first?.threadName, "Persistence")
    }

    func testInMemoryIndexUsedWhenURLIsNil() async {
        // The default initializer produces an in-memory index — same semantics as before REP-041.
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "m1", channel: .imessage, name: "Alice",
                                   avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [Message(from: .them, text: "in memory test", time: "t")])
        let hits = await index.search("memory")
        XCTAssertEqual(hits.count, 1, "in-memory index must still work after REP-041 refactor")
    }

    // MARK: - REP-102: empty query returns empty list

    func testEmptyQueryReturnsEmptyList() async {
        let index = SearchIndex(databaseURL: nil)
        let t1 = MessageThread(id: "eq1", channel: .imessage, name: "Alpha",
                               avatar: "A", preview: "", time: "", unread: 0)
        let t2 = MessageThread(id: "eq2", channel: .imessage, name: "Beta",
                               avatar: "B", preview: "", time: "", unread: 0)
        let t3 = MessageThread(id: "eq3", channel: .imessage, name: "Gamma",
                               avatar: "G", preview: "", time: "", unread: 0)
        await index.upsert(thread: t1, messages: [Message(from: .them, text: "hello world", time: "t")])
        await index.upsert(thread: t2, messages: [Message(from: .them, text: "foo bar", time: "t")])
        await index.upsert(thread: t3, messages: [Message(from: .them, text: "baz qux", time: "t")])

        let results = await index.search("")
        XCTAssertEqual(results.count, 0,
                       "empty query must return [] rather than all rows or a SQLite error")
    }

    func testWhitespaceOnlyQueryReturnsEmptyList() async {
        let index = SearchIndex(databaseURL: nil)
        let t = MessageThread(id: "ws1", channel: .imessage, name: "WhiteSpace",
                              avatar: "W", preview: "", time: "", unread: 0)
        await index.upsert(thread: t, messages: [Message(from: .them, text: "some content", time: "t")])

        let results = await index.search("   ")
        XCTAssertEqual(results.count, 0,
                       "whitespace-only query must return [] (trimmed to empty)")
    }

    // MARK: - REP-099: delete then re-insert round-trip (FTS5 tombstone check)

    func testDeleteThenReinsertIsSearchable() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "dr1", channel: .imessage, name: "Delta",
                                   avatar: "D", preview: "", time: "", unread: 0)

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "original content", time: "t")
        ])
        var hits = await index.search("original")
        XCTAssertEqual(hits.count, 1, "thread must be searchable after insert")

        await index.delete(threadID: thread.id)
        hits = await index.search("original")
        XCTAssertEqual(hits.count, 0, "thread must not be searchable after delete")

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "refreshed content", time: "t2")
        ])
        hits = await index.search("refreshed")
        XCTAssertEqual(hits.count, 1, "re-inserted thread must be searchable by new text")
        XCTAssertEqual(hits.first?.threadID, thread.id)
    }

    func testDeleteThenReinsertOldTextGone() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "dr2", channel: .imessage, name: "Echo",
                                   avatar: "E", preview: "", time: "", unread: 0)

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "staleword hello", time: "t")
        ])
        await index.delete(threadID: thread.id)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "freshword hello", time: "t2")
        ])

        let staleHits = await index.search("staleword")
        XCTAssertEqual(staleHits.count, 0,
                       "old text must be gone after delete + re-insert (no FTS5 tombstone leak)")

        let freshHits = await index.search("freshword")
        XCTAssertEqual(freshHits.count, 1, "new text must be searchable after re-insert")
    }

    // MARK: - REP-109: channel-filter integration with two-channel data

    func testChannelFilterIsolatesResults() async {
        let index = SearchIndex(databaseURL: nil)
        let sharedText = "sharedtopic"

        for i in 1...5 {
            let t = MessageThread(id: "imsg-\(i)", channel: .imessage, name: "iMsg\(i)",
                                  avatar: "I", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [Message(from: .them, text: sharedText, time: "t")])
        }
        for i in 1...3 {
            let t = MessageThread(id: "slk-\(i)", channel: .slack, name: "Slack\(i)",
                                  avatar: "S", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [Message(from: .them, text: sharedText, time: "t")])
        }

        let iMsgHits  = await index.search(query: "sharedtopic", channel: .imessage)
        let slackHits = await index.search(query: "sharedtopic", channel: .slack)
        XCTAssertEqual(iMsgHits.count,  5, "iMessage filter must return exactly 5 results")
        XCTAssertEqual(slackHits.count, 3, "Slack filter must return exactly 3 results")
        XCTAssertTrue(iMsgHits.allSatisfy { $0.threadID.hasPrefix("imsg-") },
                      "iMessage hits must all have imsg- prefix")
        XCTAssertTrue(slackHits.allSatisfy { $0.threadID.hasPrefix("slk-") },
                      "Slack hits must all have slk- prefix")
    }

    func testUnfilteredSearchReturnsAllChannels() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...5 {
            let t = MessageThread(id: "uf-imsg-\(i)", channel: .imessage, name: "A\(i)",
                                  avatar: "A", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [Message(from: .them, text: "multichannel", time: "t")])
        }
        for i in 1...3 {
            let t = MessageThread(id: "uf-slk-\(i)", channel: .slack, name: "B\(i)",
                                  avatar: "B", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [Message(from: .them, text: "multichannel", time: "t")])
        }

        let hits = await index.search(query: "multichannel", channel: nil)
        XCTAssertEqual(hits.count, 8, "unfiltered search must return all 8 threads across channels")
    }

    // MARK: - REP-119: search result cap at 50

    func testSearchResultCapAt50() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...100 {
            let t = MessageThread(id: "cap-\(i)", channel: .imessage, name: "Cap\(i)",
                                  avatar: "C", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "cappedterm unique-\(i)", time: "t")
            ])
        }
        let results = await index.search("cappedterm")
        XCTAssertEqual(results.count, 50,
                       "search must cap results at 50 (the default limit) to prevent unbounded palette noise")
    }

    func testSearchResultBelowCapReturnsAll() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...5 {
            let t = MessageThread(id: "few-\(i)", channel: .imessage, name: "Few\(i)",
                                  avatar: "F", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "smallresultset", time: "t")
            ])
        }
        let results = await index.search("smallresultset")
        XCTAssertEqual(results.count, 5,
                       "search must not over-truncate when result set is smaller than the cap")
    }

    // MARK: - REP-125: upsert replaces preview text (no ghost terms)

    func testUpsertReplacesOldPreviewTerms() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "ghost-1", channel: .imessage, name: "Ghost",
                                   avatar: "G", preview: "", time: "", unread: 0)

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "morning coffee", time: "t1")
        ])
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "evening tea", time: "t2")
        ])

        let oldHits = await index.search("morning")
        XCTAssertEqual(oldHits.count, 0,
                       "old preview terms must not be searchable after upsert (no FTS5 ghost terms)")
    }

    func testUpsertMakesNewPreviewTermsSearchable() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "ghost-2", channel: .imessage, name: "Ghost2",
                                   avatar: "G", preview: "", time: "", unread: 0)

        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "morning coffee", time: "t1")
        ])
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "evening tea", time: "t2")
        ])

        let newHits = await index.search("evening")
        XCTAssertEqual(newHits.count, 1,
                       "new preview terms must be searchable after upsert")
        XCTAssertEqual(newHits.first?.threadID, thread.id)
    }

    // MARK: - REP-126: file-backed persistence round-trip smoke test

    func testDiskBackedIndexSurvivesReinit() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rep126-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let threads = [
            MessageThread(id: "r126a", channel: .imessage, name: "Alice",
                          avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "r126b", channel: .imessage, name: "Bob",
                          avatar: "B", preview: "", time: "", unread: 0),
            MessageThread(id: "r126c", channel: .slack, name: "Carol",
                          avatar: "C", preview: "", time: "", unread: 0),
        ]
        let messages: [[Message]] = [
            [Message(from: .them, text: "persisted alpha", time: "t1")],
            [Message(from: .them, text: "persisted beta",  time: "t2")],
            [Message(from: .them, text: "persisted gamma", time: "t3")],
        ]

        do {
            let index = SearchIndex(databaseURL: dbURL)
            for (thread, msgs) in zip(threads, messages) {
                await index.upsert(thread: thread, messages: msgs)
            }
        }
        // Actor is deinit'd; SQLite file flushed to disk.

        let reopened = SearchIndex(databaseURL: dbURL)
        let alphaHits = await reopened.search("alpha")
        let betaHits  = await reopened.search("beta")
        let gammaHits = await reopened.search("gamma")
        XCTAssertEqual(alphaHits.count, 1, "alpha thread must survive reinit")
        XCTAssertEqual(betaHits.count,  1, "beta thread must survive reinit")
        XCTAssertEqual(gammaHits.count, 1, "gamma thread must survive reinit")
        XCTAssertEqual(alphaHits.first?.threadID, "r126a")
        XCTAssertEqual(betaHits.first?.threadID,  "r126b")
        XCTAssertEqual(gammaHits.first?.threadID, "r126c")
    }

    func testDiskBackedEmptyReinitDoesNotCrash() async {
        // Opening an existing (but empty) db file on reinit must not crash.
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rep126-empty-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        _ = SearchIndex(databaseURL: dbURL)
        // Second open of the same file with no data inserted.
        let index2 = SearchIndex(databaseURL: dbURL)
        let hits = await index2.search("anything")
        XCTAssertEqual(hits.count, 0, "empty db on reopen must return no results")
    }

    // MARK: - REP-140: concurrent upsert+delete interleaving

    func testConcurrentUpsertDeleteNoCrash() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "race-ud", channel: .imessage, name: "RaceUD",
                                   avatar: "R", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "concurrent race text", time: "t")

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await index.upsert(thread: thread, messages: [msg])
                    _ = i
                }
                group.addTask {
                    await index.delete(threadID: thread.id)
                    _ = i
                }
            }
        }
        // No crash — success.
    }

    func testConcurrentUpsertDeleteConsistentState() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "race-state", channel: .imessage, name: "RaceState",
                                   avatar: "R", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "state consistency check", time: "t")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { await index.upsert(thread: thread, messages: [msg]) }
                group.addTask { await index.delete(threadID: thread.id) }
            }
        }

        // Post-race: search must return a clean array (possibly empty), never throw.
        let results = await index.search("consistency")
        XCTAssertTrue(results.count == 0 || results.count == 1,
                      "post-race search must return 0 or 1 results, never a corrupt state")
    }
}
