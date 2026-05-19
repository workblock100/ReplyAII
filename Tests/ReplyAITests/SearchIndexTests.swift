import XCTest
@testable import ReplyAICore

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

    /// All-special-char inputs sanitize down to nothing — the function
    /// strips `"` and `-` then drops empty tokens. A query like `--` or
    /// `"` should produce the empty string, NOT a malformed FTS5 query
    /// like `*` or `AND` that SQLite would reject. Pin so a future
    /// sanitizer change that emits an empty `""` token (and lets it
    /// through) surfaces here.
    func testFTSQueryAllSanitizedAwayReturnsEmpty() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "--"),    "",
            "input that sanitizes to no tokens must return empty, not a malformed FTS query")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "\""),    "",
            "input of bare double-quote must return empty after sanitization")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "\"-\""), "",
            "input of all-strip chars must return empty after sanitization")
    }

    /// Hyphens are stripped wholesale, not just leading — so `hello-world`
    /// becomes a single token `helloworld` (not two tokens). This is
    /// intentional: FTS5 treats `-` as a NOT operator, so leaving it in
    /// the query would silently exclude the second term. Pin the
    /// merge-into-one-token behavior so a future "preserve hyphens"
    /// refactor surfaces here as a deliberate FTS-semantics change.
    func testFTSQueryHyphensCollapseInternal() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello-world"), "helloworld*",
            "internal hyphens must be stripped — token collapses to one prefix-search term")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "co-op-store"), "coopstore*",
            "multiple internal hyphens must all be stripped, producing a single token")
    }

    /// Each of `(`, `)`, `*`, `:` individually triggers the phrase-quote
    /// branch of the sanitizer. testFTSQueryQuotesSpecialChars only covers
    /// the `:` case explicitly; pin the other three so a future "trim
    /// special chars instead of quoting them" refactor can't silently turn
    /// e.g. `parens(x)` into a malformed FTS5 expression at runtime.
    func testFTSQueryQuotesEachSpecialCharIndividually() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "alpha(beta)"),
                       #""alpha(beta)""#,
                       "parentheses must trigger phrase-quote wrapping")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "wild*card"),
                       #""wild*card""#,
                       "asterisk inside the token must trigger phrase-quote wrapping (NOT prefix-append)")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "key:value"),
                       #""key:value""#,
                       "colon must trigger phrase-quote wrapping (regression guard for the existing :-only test)")
    }

    // MARK: - FTS5 syntax constants pin

    /// `SearchIndex.ftsSpecialCharacters` is the single source of
    /// truth for which characters trigger phrase-quote wrapping.
    /// Drift either over-quotes ordinary tokens (silently disabling
    /// prefix matching) or under-quotes a real FTS5 special char
    /// (returning a `malformed MATCH expression` SQLite error which
    /// surfaces as an empty palette). The set is intentionally
    /// narrow — only chars FTS5 itself treats syntactically.
    func testFTSSpecialCharactersConstantIsFrozen() {
        XCTAssertEqual(SearchIndex.ftsSpecialCharacters, "()*:",
            "ftsSpecialCharacters drift either over-quotes ordinary tokens or under-quotes real FTS5 special chars — pin so a deliberate FTS5-grammar update lands in code review")
    }

    func testFTSSpecialCharactersIncludesEachKnownSpecialChar() {
        // Independent witness: each char individually must be in the
        // set. Pin so a future refactor that, e.g., dropped `*` while
        // the existing testFTSQueryQuotesEachSpecialCharIndividually
        // continued to pass somehow can't slip through unnoticed.
        for c in ["(", ")", "*", ":"] {
            XCTAssertTrue(SearchIndex.ftsSpecialCharacters.contains(c),
                "ftsSpecialCharacters must include `\(c)` — drift here silently disables phrase-quoting for tokens containing it")
        }
        // And the same set must NOT include benign chars that should
        // remain prefix-appended.
        for c in ["a", "0", "_", "'", ".", "@"] {
            XCTAssertFalse(SearchIndex.ftsSpecialCharacters.contains(c),
                "ftsSpecialCharacters must NOT include `\(c)` — drift would over-quote tokens like `bob's` or `user@host` and silently disable prefix matching")
        }
    }

    /// `ftsTokenJoiner` defines multi-word search semantics. Drift to
    /// `OR` would silently widen every multi-token query to a much
    /// larger result set — a stealth recall change users notice as
    /// "the palette suddenly shows random matches".
    func testFTSTokenJoinerIsAndWithSpaces() {
        XCTAssertEqual(SearchIndex.ftsTokenJoiner, " AND ",
            "ftsTokenJoiner drift flips multi-word semantics from intersection to union — every palette query starts surfacing far more (less relevant) results")

        // Witness: the joiner round-trips through ftsQuery for the
        // simplest two-token case.
        XCTAssertEqual(SearchIndex.ftsQuery(from: "foo bar"),
                       "foo*\(SearchIndex.ftsTokenJoiner)bar*",
                       "ftsQuery must compose tokens through ftsTokenJoiner — drift either at the constant or the call site changes search semantics")
    }

    /// `ftsPrefixSuffix` is the single character FTS5 treats as the
    /// prefix-match operator. Drift to `%` (LIKE-style wildcard) or
    /// blank would silently disable prefix matching across every
    /// palette query — typing `din` would no longer surface
    /// `dinner`.
    func testFTSPrefixSuffixIsAsterisk() {
        XCTAssertEqual(SearchIndex.ftsPrefixSuffix, "*",
            "ftsPrefixSuffix drift breaks prefix matching — FTS5 treats only `*` as the prefix operator")

        // Witness: a single-token query round-trips through
        // ftsPrefixSuffix.
        XCTAssertEqual(SearchIndex.ftsQuery(from: "din"),
                       "din\(SearchIndex.ftsPrefixSuffix)",
                       "single-token query composes through ftsPrefixSuffix — drift here changes the on-the-wire FTS5 expression")
    }

    /// Mixing one normal token and one with a special char must produce
    /// `normal* AND "special:token"` — both branches participate in the
    /// AND join. Pin the order-preserving join because a future "collapse
    /// quoted tokens to OR" refactor would silently widen result sets.
    func testFTSQueryMixesPrefixAndQuotedTokensWithAND() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "foo bar:baz"),
                       #"foo* AND "bar:baz""#,
                       "mixed normal + special tokens must AND-join in input order")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "key:value plain"),
                       #""key:value" AND plain*"#,
                       "input order must be preserved across the AND join (special-then-normal)")
    }

    /// When a token is dropped entirely (e.g. a bare hyphen) the remaining
    /// tokens still form a valid query — the surviving single token does
    /// NOT get an `AND` separator added to its right because there's
    /// nothing to AND it with. Pin the single-token-after-drop path.
    func testFTSQuerySurvivingTokenAfterDropDoesNotEmitTrailingAND() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "- foo"),
                       "foo*",
                       "a bare-hyphen token gets dropped; the surviving token must not carry an AND prefix or suffix")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "\"\" hello"),
                       "hello*",
                       "a bare-quote token gets dropped; surviving token must produce a clean prefix query")
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

    /// Pin: empty thread.id is rejected on both `upsert` and `delete`.
    /// Without the guard, `upsert` would insert orphan rows whose
    /// `thread_id = ''` are searchable but unnavigable (the inbox keys
    /// thread lookup by id and never has a thread with an empty id).
    /// Verify that an "empty-id upsert" leaves the index clean and a
    /// later `search` finds nothing.
    func testUpsertWithEmptyThreadIDIsRejected() async {
        let index = SearchIndex()
        let bad = MessageThread(id: "", channel: .imessage, name: "Maya",
                                avatar: "M", preview: "", time: "", unread: 0)
        await index.upsert(thread: bad, messages: [
            Message(from: .them, text: "would-be-orphan-text", time: "now")
        ])
        let hits = await index.search("would-be-orphan-text")
        XCTAssertTrue(hits.isEmpty,
            "empty thread.id must NOT produce searchable orphan rows in the index")
    }

    func testDeleteWithEmptyThreadIDIsNoOp() async {
        // Symmetric guard with upsert. A delete with empty threadID would
        // otherwise execute `WHERE thread_id = ''` against a clean index,
        // which is a no-op by accident — but a malformed call is still
        // a caller bug worth refusing fast.
        let index = SearchIndex()
        let thread = MessageThread(id: "real", channel: .imessage, name: "R",
                                   avatar: "R", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "kingfisher", time: "now")
        ])

        await index.delete(threadID: "")  // must not affect the real thread

        let hits = await index.search("kingfisher")
        XCTAssertEqual(hits.count, 1,
            "empty-threadID delete must leave the real thread's index intact")
    }

    /// Pin: `rebuild` skips entries whose thread ID is empty. Same rationale
    /// as the upsert guard — empty-id rows are searchable but unnavigable.
    /// A degenerate caller (e.g. iMessageChannel returning `""` for a
    /// missing chat_identifier) must NOT poison the index for valid
    /// neighboring threads.
    func testRebuildSkipsEmptyThreadIDEntries() async {
        let index = SearchIndex()
        let real = MessageThread(id: "ok", channel: .imessage, name: "OK",
                                 avatar: "O", preview: "", time: "", unread: 0)
        let messages: [String: [Message]] = [
            "ok": [Message(from: .them, text: "alligator", time: "now")],
            "":   [Message(from: .them, text: "should-not-index", time: "now")],
        ]
        await index.rebuild(from: messages, threads: [real])

        let realHits = await index.search("alligator")
        XCTAssertEqual(realHits.count, 1, "valid thread must still be indexed")
        XCTAssertEqual(realHits.first?.threadID, "ok")
    }

    /// Stronger pin on the rebuild empty-threadID skip: assert via a positive
    /// search that the empty-threadID row's text is genuinely absent from the
    /// FTS table, not just that it didn't masquerade under another thread.
    /// The previous test only checks that the valid thread is indexed; a
    /// regression that forwarded empty-threadID rows through and bound them
    /// to threadID="" would still pass that assertion. This negative search
    /// catches it.
    func testRebuildEmptyThreadIDRowsAreNotSearchable() async {
        let index = SearchIndex()
        let real = MessageThread(id: "ok", channel: .imessage, name: "OK",
                                 avatar: "O", preview: "", time: "", unread: 0)
        let messages: [String: [Message]] = [
            "ok": [Message(from: .them, text: "alligator", time: "now")],
            "":   [Message(from: .them, text: "should-not-index", time: "now")],
        ]
        await index.rebuild(from: messages, threads: [real])

        let phantomHits = await index.search("should-not-index")
        XCTAssertTrue(phantomHits.isEmpty,
            "empty-threadID rows must not be searchable — found \(phantomHits.count) phantom hit(s) for `should-not-index`")
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

    /// Pin the literal default cap independently of behavior. The behavior
    /// tests below populate 100 rows and assert the result count is 50 —
    /// they would still pass if a refactor changed both the literal default
    /// AND the test cap together. Pinning the constant catches a drift
    /// even when accompanied by a "fix the test" edit, because the
    /// constant lives in source as the source-of-truth for both call
    /// sites of `search`.
    func testDefaultSearchLimitConstantIsFifty() {
        XCTAssertEqual(SearchIndex.defaultSearchLimit, 50,
                       "search default cap is shipped UX — see test rationale")
    }

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

    /// `limit: 0` is bound directly into a SQLite `LIMIT 0` clause,
    /// which returns zero rows. Pin so a future "treat 0 as default 50"
    /// shortcut doesn't silently flood the palette when a caller passes
    /// a misconfigured value (e.g. zero from a slider that's been reset).
    func testSearchLimitZeroReturnsNoResults() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...3 {
            let t = MessageThread(id: "z-\(i)", channel: .imessage, name: "Z\(i)",
                                  avatar: "Z", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "limitzeropin", time: "t")
            ])
        }
        let results = await index.search("limitzeropin", limit: 0)
        XCTAssertEqual(results.count, 0,
            "limit: 0 must produce zero rows — SQLite's `LIMIT 0` semantic, not a default-50 fallback")
    }

    /// `limit: 1` returns exactly one row even when many match. The
    /// rank-ordered SELECT means the highest-relevance hit comes back —
    /// typically the most-recently-upserted match for a unique term in
    /// this test's setup. Pin the LIMIT 1 contract so the palette can
    /// rely on a "give me the single best match" call shape.
    func testSearchLimitOneReturnsExactlyOneRow() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...10 {
            let t = MessageThread(id: "one-\(i)", channel: .imessage, name: "One\(i)",
                                  avatar: "O", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "limitonetokenpin", time: "t")
            ])
        }
        let results = await index.search("limitonetokenpin", limit: 1)
        XCTAssertEqual(results.count, 1,
            "limit: 1 must return exactly one row even when 10 are indexed")
    }

    /// `limit: -1` must NOT bind through to SQLite. SQLite treats
    /// `LIMIT -1` as "no limit", which can flood the palette if a caller
    /// accidentally passes a sentinel value. SearchIndex normalizes
    /// negative values back to the shipped default cap.
    func testSearchLimitNegativeOneFallsBackToDefaultCap() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...60 {
            let t = MessageThread(id: "neg-\(i)", channel: .imessage, name: "Neg\(i)",
                                  avatar: "N", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "neglimittokenpin", time: "t")
            ])
        }
        let results = await index.search("neglimittokenpin", limit: -1)
        XCTAssertEqual(results.count, SearchIndex.defaultSearchLimit,
            "negative limits must fall back to the default cap, not SQLite's unbounded LIMIT -1 behavior")
    }

    func testExplicitSearchLimitAboveDefaultIsCapped() async {
        let index = SearchIndex(databaseURL: nil)
        for i in 1...75 {
            let t = MessageThread(id: "high-\(i)", channel: .imessage, name: "High\(i)",
                                  avatar: "H", preview: "", time: "", unread: 0)
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "highlimittokenpin", time: "t")
            ])
        }
        let results = await index.search("highlimittokenpin", limit: 10_000)
        XCTAssertEqual(results.count, SearchIndex.defaultSearchLimit,
            "explicitly huge limits must still respect the shipped palette cap")
    }

    func testBoundedSearchLimitNormalization() {
        XCTAssertEqual(SearchIndex.boundedSearchLimit(from: -1), SearchIndex.defaultSearchLimit)
        XCTAssertEqual(SearchIndex.boundedSearchLimit(from: 0), 0)
        XCTAssertEqual(SearchIndex.boundedSearchLimit(from: 1), 1)
        XCTAssertEqual(SearchIndex.boundedSearchLimit(from: SearchIndex.defaultSearchLimit + 1),
                       SearchIndex.defaultSearchLimit)
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

// MARK: - REP-150: Result struct fields populated correctly from upsert data

final class SearchIndexResultFieldsTests: XCTestCase {

    func testResultThreadNameMatchesUpsertedThread() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "t-fields", channel: .imessage, name: "Zara",
                                   avatar: "Z", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "xylophonetest150a", time: "10:00")
        await index.upsert(thread: thread, messages: [msg])

        let hits = await index.search("xylophonetest150a")
        XCTAssertEqual(hits.count, 1, "search must return 1 result for the upserted message")
        XCTAssertEqual(hits.first?.threadName, "Zara",
                       "Result.threadName must match the thread name supplied to upsert")
    }

    func testResultThreadIDMatchesUpsertedThread() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "rep150idcheck", channel: .imessage, name: "Kai",
                                   avatar: "K", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "xylophonetest150b", time: "11:00")
        await index.upsert(thread: thread, messages: [msg])

        let hits = await index.search("xylophonetest150b")
        XCTAssertEqual(hits.count, 1, "search must return 1 result for the upserted message")
        XCTAssertEqual(hits.first?.threadID, "rep150idcheck",
                       "Result.threadID must match the thread id supplied to upsert")
    }

    func testResultTextContainsMessageBody() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "t-text", channel: .imessage, name: "Sam",
                                   avatar: "S", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "xylophonetest150c verbatim", time: "12:00")
        await index.upsert(thread: thread, messages: [msg])

        let hits = await index.search("xylophonetest150c")
        XCTAssertEqual(hits.count, 1, "search must return 1 result for the upserted message")
        XCTAssertTrue(hits.first?.text.contains("xylophonetest150c") == true,
                      "Result.text must contain the message body supplied to upsert")
    }

    func testResultSenderNamePopulatedForIncomingMessage() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "t-sender", channel: .imessage, name: "Jordan",
                                   avatar: "J", preview: "", time: "", unread: 0)
        let msg = Message(from: .them, text: "xylophonetest150d", time: "13:00")
        await index.upsert(thread: thread, messages: [msg])

        let hits = await index.search("xylophonetest150d")
        XCTAssertEqual(hits.count, 1, "search must return 1 result for the upserted message")
        XCTAssertEqual(hits.first?.senderName, "Jordan",
                       "Result.senderName must equal thread.name for incoming messages")
    }

    func testResultSenderNameIsMeForOutgoingMessage() async {
        let index = SearchIndex(databaseURL: nil)
        let thread = MessageThread(id: "t-outgoing", channel: .imessage, name: "Pat",
                                   avatar: "P", preview: "", time: "", unread: 0)
        let msg = Message(from: .me, text: "xylophonetest150e", time: "14:00")
        await index.upsert(thread: thread, messages: [msg])

        let hits = await index.search("xylophonetest150e")
        XCTAssertEqual(hits.count, 1, "search must return 1 result for the upserted message")
        XCTAssertEqual(hits.first?.senderName, SearchIndex.outgoingSenderLabel,
                       "Result.senderName must be 'me' for outgoing messages")
    }

    // MARK: - REP-165: SearchIndex.clear()

    func testClearWipesAllIndexedThreads() async {
        let index = SearchIndex()
        let threads = (1...3).map { i in
            MessageThread(id: "clr-t\(i)", channel: .imessage, name: "T\(i)",
                          avatar: "T", preview: "", time: "", unread: 0)
        }
        for (i, t) in threads.enumerated() {
            await index.upsert(thread: t, messages: [
                Message(from: .them, text: "cleartest165_unique\(i)", time: "now")
            ])
        }
        let before = await index.search("cleartest165_unique")
        XCTAssertEqual(before.count, 3, "pre-condition: 3 threads indexed")

        await index.clear()

        let after = await index.search("cleartest165_unique")
        XCTAssertEqual(after.count, 0, "clear() must wipe all indexed rows")
    }

    func testClearThenUpsertIsSearchable() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "clr-reup", channel: .imessage, name: "ReUp",
                                   avatar: "R", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "cleartest165_before", time: "now")
        ])
        await index.clear()
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "cleartest165_after", time: "now")
        ])

        let hits = await index.search("cleartest165_after")
        XCTAssertEqual(hits.count, 1, "re-indexed content must be searchable after clear()")
        let stale = await index.search("cleartest165_before")
        XCTAssertEqual(stale.count, 0, "cleared content must not appear after re-index")
    }

    func testConcurrentClearAndUpsertNoCrash() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "clr-race", channel: .imessage, name: "Race",
                                   avatar: "R", preview: "", time: "", unread: 0)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await index.upsert(thread: thread, messages: [
                        Message(from: .them, text: "race\(i)", time: "now")
                    ])
                }
                if i % 3 == 0 {
                    group.addTask { await index.clear() }
                }
            }
        }
        // Reaching here without crash = pass.
    }

    // MARK: - REP-184: 3-word AND semantics

    func testTwoWordQueryFiltersCorrectly() async {
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "and-a", channel: .imessage, name: "A",
                          avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "and-b", channel: .imessage, name: "B",
                          avatar: "B", preview: "", time: "", unread: 0),
            MessageThread(id: "and-c", channel: .imessage, name: "C",
                          avatar: "C", preview: "", time: "", unread: 0),
        ]
        await index.upsert(thread: threads[0], messages: [
            Message(from: .them, text: "quick brown fox", time: "now")
        ])
        await index.upsert(thread: threads[1], messages: [
            Message(from: .them, text: "quick lazy dog", time: "now")
        ])
        await index.upsert(thread: threads[2], messages: [
            Message(from: .them, text: "lazy brown cat", time: "now")
        ])

        let hits = await index.search("quick brown")
        XCTAssertEqual(hits.count, 1, "'quick brown' must match only thread A")
        XCTAssertEqual(hits.first?.threadID, "and-a")
    }

    func testThreeWordQueryRequiresAllTerms() async {
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "and3-a", channel: .imessage, name: "A",
                          avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "and3-b", channel: .imessage, name: "B",
                          avatar: "B", preview: "", time: "", unread: 0),
            MessageThread(id: "and3-c", channel: .imessage, name: "C",
                          avatar: "C", preview: "", time: "", unread: 0),
        ]
        await index.upsert(thread: threads[0], messages: [
            Message(from: .them, text: "quick brown fox", time: "now")
        ])
        await index.upsert(thread: threads[1], messages: [
            Message(from: .them, text: "quick lazy dog", time: "now")
        ])
        await index.upsert(thread: threads[2], messages: [
            Message(from: .them, text: "lazy brown cat", time: "now")
        ])

        // "quick lazy fox" — no single thread has all three terms
        let hits = await index.search("quick lazy fox")
        XCTAssertEqual(hits.count, 0,
            "'quick lazy fox' must return empty: no thread contains all 3 terms")
    }

    func testThreeWordQueryMatchesWhenAllTermsPresent() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "and3-full", channel: .imessage, name: "Full",
                                   avatar: "F", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "quick brown fox", time: "now")
        ])

        let hits = await index.search("quick brown fox")
        XCTAssertEqual(hits.count, 1, "'quick brown fox' must match thread that has all 3 terms")
    }
}

// MARK: - REP-067: FTS5 snippet extraction

final class SearchIndexSnippetTests: XCTestCase {

    func testSnippetContainsMatchedTerm() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "snip-1", channel: .imessage, name: "Alice",
                                   avatar: "A", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "the quarterly budget review is tomorrow", time: "now")
        ])
        let hits = await index.search("budget")
        XCTAssertEqual(hits.count, 1)
        let snippet = hits.first?.snippet
        XCTAssertNotNil(snippet, "snippet must be non-nil for a matching query")
        XCTAssertTrue(snippet?.contains("budget") == true,
                      "snippet must contain the matched term")
        // FTS5 wraps the match in «» markers.
        XCTAssertTrue(snippet?.contains("«") == true || snippet?.contains("budget") == true,
                      "snippet must mark the matched term with «» or contain the term")
    }

    func testSnippetMarksMatchedTermWithAngles() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "snip-2", channel: .imessage, name: "Bob",
                                   avatar: "B", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "please review the proposal before Friday", time: "t")
        ])
        let hits = await index.search("proposal")
        XCTAssertEqual(hits.count, 1)
        let snippet = hits.first?.snippet ?? ""
        // FTS5 snippet() wraps matched term with the start/end markers we passed.
        XCTAssertTrue(snippet.contains("«proposal»"),
                      "snippet must wrap matched term with «» markers")
    }

    func testSnippetNilOnEmptyQuery() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "snip-3", channel: .imessage, name: "Carol",
                                   avatar: "C", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "hello world", time: "t")
        ])
        // Empty query returns [] — no results means no snippet to check; verify guard holds.
        let hits = await index.search("")
        XCTAssertTrue(hits.isEmpty, "empty query must return no results (and therefore no snippets)")
    }

    func testResultTypeCarriesSnippetField() async {
        // Verifies SearchIndex.Result has a snippet property accessible on live results.
        let index = SearchIndex()
        let thread = MessageThread(id: "snip-4", channel: .imessage, name: "Dan",
                                   avatar: "D", preview: "", time: "", unread: 0)
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "finalizing the contract terms today", time: "t")
        ])
        let hits = await index.search("contract")
        XCTAssertEqual(hits.count, 1)
        // Access .snippet — compile error here would mean the field was removed.
        let _ = hits.first?.snippet
    }

    // MARK: - REP-205: delete() isolation

    /// Deleting thread B must remove it from single-term searches that
    /// previously matched B — other threads sharing that term are unaffected.
    func testDeleteRemovesThreadFromSingleTermSearch() async {
        let index = SearchIndex()
        let threadA = MessageThread(id: "rep205-a", channel: .imessage, name: "Alice",
                                    avatar: "A", preview: "", time: "", unread: 0)
        let threadB = MessageThread(id: "rep205-b", channel: .slack,   name: "Bob",
                                    avatar: "B", preview: "", time: "", unread: 0)
        let threadC = MessageThread(id: "rep205-c", channel: .imessage, name: "Carol",
                                    avatar: "C", preview: "", time: "", unread: 0)

        await index.upsert(thread: threadA, messages: [Message(from: .them, text: "hello world", time: "t")])
        await index.upsert(thread: threadB, messages: [Message(from: .them, text: "hello swift", time: "t")])
        await index.upsert(thread: threadC, messages: [Message(from: .them, text: "goodbye world", time: "t")])

        await index.delete(threadID: "rep205-b")

        let swiftHits = await index.search("swift")
        XCTAssertTrue(swiftHits.isEmpty, "'swift' should return empty after deleting thread B")
    }

    /// After deleting B, other threads that matched the same term must still appear.
    func testDeleteDoesNotAffectOtherMatchingThreads() async {
        let index = SearchIndex()
        let threadA = MessageThread(id: "rep205-d", channel: .imessage, name: "Alice",
                                    avatar: "A", preview: "", time: "", unread: 0)
        let threadB = MessageThread(id: "rep205-e", channel: .slack,   name: "Bob",
                                    avatar: "B", preview: "", time: "", unread: 0)
        let threadC = MessageThread(id: "rep205-f", channel: .imessage, name: "Carol",
                                    avatar: "C", preview: "", time: "", unread: 0)

        await index.upsert(thread: threadA, messages: [Message(from: .them, text: "hello world", time: "t")])
        await index.upsert(thread: threadB, messages: [Message(from: .them, text: "hello swift", time: "t")])
        await index.upsert(thread: threadC, messages: [Message(from: .them, text: "goodbye world", time: "t")])

        await index.delete(threadID: "rep205-e")

        let helloHits = await index.search("hello")
        XCTAssertEqual(helloHits.count, 1, "'hello' should still return thread A after deleting B")
        XCTAssertEqual(helloHits.first?.threadID, "rep205-d")
    }

    /// Deleting B must not affect threads that share no terms with B.
    func testDeleteDoesNotAffectUnrelatedThread() async {
        let index = SearchIndex()
        let threadA = MessageThread(id: "rep205-g", channel: .imessage, name: "Alice",
                                    avatar: "A", preview: "", time: "", unread: 0)
        let threadB = MessageThread(id: "rep205-h", channel: .slack,   name: "Bob",
                                    avatar: "B", preview: "", time: "", unread: 0)
        let threadC = MessageThread(id: "rep205-i", channel: .imessage, name: "Carol",
                                    avatar: "C", preview: "", time: "", unread: 0)

        await index.upsert(thread: threadA, messages: [Message(from: .them, text: "hello world", time: "t")])
        await index.upsert(thread: threadB, messages: [Message(from: .them, text: "hello swift", time: "t")])
        await index.upsert(thread: threadC, messages: [Message(from: .them, text: "goodbye world", time: "t")])

        await index.delete(threadID: "rep205-h")

        let goodbyeHits = await index.search("goodbye")
        XCTAssertEqual(goodbyeHits.count, 1, "'goodbye' should still return thread C unaffected")
        XCTAssertEqual(goodbyeHits.first?.threadID, "rep205-i")
    }

    // MARK: - REP-196: repeated search returns identical order

    func testRepeatedSearchReturnsSameOrder() async {
        // BM25 ranking is deterministic for a fixed index. Two identical searches
        // on an unchanged index must return results in the same order.
        let index = SearchIndex()
        let threads = [
            MessageThread(id: "rep196-a", channel: .imessage, name: "Alice",
                          avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "rep196-b", channel: .imessage, name: "Bob",
                          avatar: "B", preview: "", time: "", unread: 0),
            MessageThread(id: "rep196-c", channel: .imessage, name: "Carol",
                          avatar: "C", preview: "", time: "", unread: 0),
        ]
        // Different relevance levels: A has 3 occurrences of "hello", B has 1, C has 2.
        await index.upsert(thread: threads[0], messages: [
            Message(from: .them, text: "hello hello hello world", time: "t"),
        ])
        await index.upsert(thread: threads[1], messages: [
            Message(from: .them, text: "hello there", time: "t"),
        ])
        await index.upsert(thread: threads[2], messages: [
            Message(from: .them, text: "hello hello sunshine", time: "t"),
        ])

        let first  = await index.search("hello")
        let second = await index.search("hello")

        XCTAssertEqual(first.map(\.threadID), second.map(\.threadID),
                       "repeated search on unchanged index must return identical order")
        XCTAssertEqual(first.count, 3, "all three threads must match")
    }

    func testSearchOrderStableAfterUnrelatedUpsert() async {
        // An upsert for a thread that does not match the query must not
        // disturb the ranking of threads that do match.
        let index = SearchIndex()
        let matchA = MessageThread(id: "rep196-stab-a", channel: .imessage, name: "A",
                                   avatar: "A", preview: "", time: "", unread: 0)
        let matchB = MessageThread(id: "rep196-stab-b", channel: .imessage, name: "B",
                                   avatar: "B", preview: "", time: "", unread: 0)
        let unrelated = MessageThread(id: "rep196-stab-x", channel: .imessage, name: "X",
                                      avatar: "X", preview: "", time: "", unread: 0)

        await index.upsert(thread: matchA, messages: [
            Message(from: .them, text: "quarterly report review hello hello", time: "t"),
        ])
        await index.upsert(thread: matchB, messages: [
            Message(from: .them, text: "hello one mention", time: "t"),
        ])

        let before = await index.search("hello")

        // Upsert a thread whose content has nothing to do with "hello".
        await index.upsert(thread: unrelated, messages: [
            Message(from: .them, text: "completely different topic — no keyword", time: "t"),
        ])

        let after = await index.search("hello")

        // The matching threads must appear in the same order; the unrelated
        // thread must not appear in results.
        XCTAssertEqual(before.map(\.threadID), after.map(\.threadID),
                       "unrelated upsert must not disturb ranking of existing matches")
        XCTAssertFalse(after.map(\.threadID).contains("rep196-stab-x"),
                       "unrelated thread must not appear in results for 'hello'")
    }
}

// MARK: - REP-225: snippet comes from message body, not thread_name

final class SearchIndexSnippetColumnTests: XCTestCase {

    // If the search term appears only in thread_name (not in any message body),
    // FTS5 snippet() must NOT surface it — snippet is pinned to column 3 (body text).
    func testSnippetExtractsFromMessageBodyNotThreadName() async {
        let index = SearchIndex()
        // Thread name contains "alpha", body does not.
        let thread = MessageThread(id: "rep225-name", channel: .imessage, name: "alpha team",
                                   avatar: "A", preview: "", time: "")
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "let's catch up soon", time: "t")
        ])
        let hits = await index.search("alpha")
        // The thread IS found (FTS5 indexes thread_name), but the snippet must
        // come from the body column — it will not contain "alpha".
        if let hit = hits.first {
            let snippet = hit.snippet ?? ""
            XCTAssertFalse(snippet.contains("alpha"),
                           "snippet must come from message body column, not thread_name")
        }
    }

    // When the match is in the message body, snippet must wrap it with «».
    func testSnippetContainsBoldMarkerAroundMatchedTerm() async {
        let index = SearchIndex()
        let thread = MessageThread(id: "rep225-body", channel: .imessage, name: "Carol",
                                   avatar: "C", preview: "", time: "")
        await index.upsert(thread: thread, messages: [
            Message(from: .them, text: "the beta release ships this week", time: "t")
        ])
        let hits = await index.search("beta")
        XCTAssertEqual(hits.count, 1)
        let snippet = hits.first?.snippet ?? ""
        XCTAssertTrue(snippet.contains("«beta»"),
                      "snippet must wrap body-matched term with «» markers")
    }
}

// MARK: - REP-223: SearchIndex.clear() resets Stats indexed counters

final class SearchIndexClearStatsTests: XCTestCase {

    // After clear(), per-channel indexed counts must be zero.
    func testClearResetsStatsIndexedCount() async {
        let stats = Stats(fileURL: nil)
        let index = SearchIndex(databaseURL: nil)

        stats.incrementIndexed(channel: .imessage, count: 5)
        XCTAssertEqual(stats.snapshot().messagesIndexedByChannel[Channel.imessage.rawValue], 5,
                       "precondition: channel counter must be 5 before clear")

        await index.clear(stats: stats)

        XCTAssertNil(stats.snapshot().messagesIndexedByChannel[Channel.imessage.rawValue],
                     "indexed channel counter must be zero (nil) after SearchIndex.clear()")
        XCTAssertEqual(stats.snapshot().messagesIndexed, 0,
                       "aggregate indexed counter must be 0 after clear()")
    }

    // clear() must not touch unrelated Stats counters (rules fired, drafts generated).
    func testClearDoesNotAffectOtherStatsCounters() async {
        let stats = Stats(fileURL: nil)
        let index = SearchIndex(databaseURL: nil)

        stats.recordRuleFired(action: "pin")
        stats.recordDraftGenerated(tone: .warm)
        let snap = stats.snapshot()

        await index.clear(stats: stats)

        let after = stats.snapshot()
        XCTAssertEqual(after.rulesFiredByAction, snap.rulesFiredByAction,
                       "rulesFiredByAction must be unchanged by clear()")
        XCTAssertEqual(after.draftsGenerated, snap.draftsGenerated,
                       "draftsGenerated must be unchanged by clear()")
    }
}

// MARK: - REP-252: BM25 ranking — higher term frequency ranks first

final class SearchIndexBM25Tests: XCTestCase {

    // FTS5 ORDER BY rank uses BM25: thread with more occurrences of the query
    // term in its message body should appear before threads with fewer.
    func testBM25RanksHigherFrequencyFirst() async {
        let index = SearchIndex()
        let threadA = MessageThread(id: "rep252-a", channel: .imessage, name: "Alice",
                                    avatar: "A", preview: "", time: "")
        let threadB = MessageThread(id: "rep252-b", channel: .imessage, name: "Bob",
                                    avatar: "B", preview: "", time: "")
        // Thread A: "hello" appears 3 times in one message body.
        await index.upsert(thread: threadA, messages: [
            Message(from: .them, text: "hello hello hello", time: "t")
        ])
        // Thread B: "hello" appears once.
        await index.upsert(thread: threadB, messages: [
            Message(from: .them, text: "hello", time: "t")
        ])

        let hits = await index.search("hello")
        let ids = hits.map(\.threadID)
        XCTAssertTrue(ids.contains("rep252-a"), "thread A must appear in results")
        XCTAssertTrue(ids.contains("rep252-b"), "thread B must appear in results")
        let idxA = ids.firstIndex(of: "rep252-a")!
        let idxB = ids.firstIndex(of: "rep252-b")!
        XCTAssertLessThan(idxA, idxB,
            "thread with 3× 'hello' must rank before thread with 1× 'hello'")
    }

    // Three-way monotonic check: 5 occurrences > 3 > 1, all ranked in frequency order.
    func testBM25RankingIsMonotonic() async {
        let index = SearchIndex()
        let t1 = MessageThread(id: "rep252-m1", channel: .imessage, name: "One",
                               avatar: "1", preview: "", time: "")
        let t3 = MessageThread(id: "rep252-m3", channel: .imessage, name: "Three",
                               avatar: "3", preview: "", time: "")
        let t5 = MessageThread(id: "rep252-m5", channel: .imessage, name: "Five",
                               avatar: "5", preview: "", time: "")

        await index.upsert(thread: t1, messages: [
            Message(from: .them, text: "apple", time: "t")
        ])
        await index.upsert(thread: t3, messages: [
            Message(from: .them, text: "apple apple apple", time: "t")
        ])
        await index.upsert(thread: t5, messages: [
            Message(from: .them, text: "apple apple apple apple apple", time: "t")
        ])

        let hits = await index.search("apple")
        let ids = hits.map(\.threadID)
        XCTAssertTrue(ids.contains("rep252-m1"), "1× thread must appear")
        XCTAssertTrue(ids.contains("rep252-m3"), "3× thread must appear")
        XCTAssertTrue(ids.contains("rep252-m5"), "5× thread must appear")
        let idx1 = ids.firstIndex(of: "rep252-m1")!
        let idx3 = ids.firstIndex(of: "rep252-m3")!
        let idx5 = ids.firstIndex(of: "rep252-m5")!
        XCTAssertLessThan(idx5, idx3, "5× must rank above 3×")
        XCTAssertLessThan(idx3, idx1, "3× must rank above 1×")
    }
}

// MARK: - SearchIndex.productionDatabaseURL() — search.db path contract
//
// Production callers construct `SearchIndex(databaseURL: SearchIndex.productionDatabaseURL())`
// and the FTS5 index lives there across launches. A silent path change
// orphans every shipped user's index — the app would re-index from
// chat.db on next launch (slow, and only works if FDA still holds).
// Pin the path components.

final class SearchIndexProductionDatabaseURLTests: XCTestCase {

    func testProductionDatabaseURLEndsWithSearchDB() {
        let url = SearchIndex.productionDatabaseURL()
        XCTAssertEqual(url.lastPathComponent, SearchIndex.productionFileName,
                       "production index filename must remain search.db — anything else orphans the FTS5 index and forces a re-index from chat.db")
    }

    func testProductionDatabaseURLLivesUnderReplyAIDirectory() {
        let url = SearchIndex.productionDatabaseURL()
        let parent = url.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(parent, Preferences.appSupportDirectoryName,
                       "search.db must sit in ReplyAI/ so factory-reset can wipe the index along with stats and rules in a single directory sweep")
    }

    func testProductionDatabaseURLDirectoryExistsAfterCall() {
        // Documented to lazily create the parent directory; without it,
        // sqlite3_open_v2 with SQLITE_OPEN_CREATE fails on first launch.
        let url = SearchIndex.productionDatabaseURL()
        let dir = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                      "productionDatabaseURL() must create the parent directory so sqlite3_open_v2 can create the file on first launch")
        XCTAssertTrue(isDirectory.boolValue,
                      "the ReplyAI/ entry must be a directory, not a stray file")
    }

    func testProductionDatabaseURLIsAbsoluteAndFileScheme() {
        let url = SearchIndex.productionDatabaseURL()
        XCTAssertTrue(url.isFileURL,
                      "search.db path must be a file:// URL for sqlite3_open_v2(url.path, ...)")
        XCTAssertTrue(url.path.hasPrefix("/"),
                      "search.db path must be absolute so behavior doesn't depend on the launching process's cwd")
    }
}

// MARK: - FTS5 snippet config — visible-string contract pin

/// `SearchIndex.snippet*` constants are the FTS5 `snippet(...)` arguments
/// embedded into both search SQL paths (channel-filtered + unfiltered).
/// The palette renders match highlights by splitting on the start/end
/// markers — drift on either silently breaks highlighting without
/// failing search itself. The ellipsis is the visible truncation cue.
/// Column index 3 is the `text` column in the `messages_fts` schema
/// (`thread_id(0), thread_name(1), sender(2), text(3), time(4), channel(5)`);
/// drift points snippet generation at the wrong column. Token count 8
/// is the width that keeps snippets one line in the popover.
final class SearchIndexSnippetConfigTests: XCTestCase {
    func testSnippetMarkersAreGuillemetsWithEllipsis() {
        XCTAssertEqual(SearchIndex.snippetStartMarker, "«",
            "snippetStartMarker drift breaks the palette's term-highlight rendering — search still returns results, but no terms appear highlighted")
        XCTAssertEqual(SearchIndex.snippetEndMarker, "»",
            "snippetEndMarker drift breaks the palette's term-highlight rendering — same blast radius as the start marker")
        XCTAssertEqual(SearchIndex.snippetEllipsis, "…",
            "snippetEllipsis is the visible truncation cue users associate with omitted context")
    }

    func testSnippetTokenContextIsEightTokens() {
        XCTAssertEqual(SearchIndex.snippetTokenContext, 8,
            "snippetTokenContext drift either pushes snippets to multi-line (too high) or shows chip-sized fragments without context (too low)")
    }

    func testSnippetTextColumnIndexIsThree() {
        XCTAssertEqual(SearchIndex.snippetTextColumnIndex, 3,
            "snippetTextColumnIndex must remain the FTS5 column index of `text` in messages_fts (thread_id=0, thread_name=1, sender=2, text=3, time=4, channel=5) — drift produces snippets from the wrong column")
    }

    // MARK: - SQL statement pin
    //
    // Transaction strings, the truncate, the per-thread delete, and the
    // INSERT used to be re-typed inline at every writer (rebuild + upsert
    // + clear + delete). Drift between writers is silent corruption: an
    // INSERT that binds 6 columns vs 5 raises a parse error only at
    // runtime; a DELETE that drops the WHERE clause nukes the entire
    // index from one code path while another path still operates
    // surgically. Hoisted to `SearchIndex.SQL`; pin freezes the literals.

    func testSQLStatementsAreFrozen() {
        XCTAssertEqual(SearchIndex.SQL.beginTransaction,    "BEGIN")
        XCTAssertEqual(SearchIndex.SQL.commitTransaction,   "COMMIT")
        XCTAssertEqual(SearchIndex.SQL.rollbackTransaction, "ROLLBACK")
        XCTAssertEqual(SearchIndex.SQL.truncateAll,         "DELETE FROM messages_fts",
            "truncateAll must NOT carry a WHERE clause — drift here would silently downgrade clear() into a per-thread delete")
        XCTAssertEqual(SearchIndex.SQL.deleteByThreadID,    "DELETE FROM messages_fts WHERE thread_id = ?1;",
            "deleteByThreadID must carry the WHERE clause — drift here would silently nuke the entire index on every upsert/delete call")

        // INSERT must list the same 6 columns in the same order — sqlite3
        // binds parameters by index, so a column reorder silently writes
        // sender into thread_name, channel into text, etc.
        let expectedInsert = """
        INSERT INTO messages_fts (thread_id, thread_name, sender, text, time, channel)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6);
        """
        XCTAssertEqual(SearchIndex.SQL.insertRow, expectedInsert,
            "insertRow column order must match the FTS5 schema; a reorder writes sender bytes into thread_name, etc.")
    }

    /// `createMessagesFTSTable` is the FTS5 virtual-table DDL. Drift
    /// in column names / column order silently breaks every INSERT
    /// (which binds by position) AND every snippet query (which
    /// references column index 3 = `text`). Drift in the tokenize
    /// spec changes the recall surface — `unicode61` vs `porter` is
    /// the difference between "Slack" / "slack" matching and stemming
    /// "slacking" / "slack". Pin the literal byte-for-byte so any
    /// schema edit lands deliberately.
    func testCreateMessagesFTSTableDDLIsFrozen() {
        let expected = """
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            thread_id   UNINDEXED,
            thread_name,
            sender,
            text,
            time        UNINDEXED,
            channel     UNINDEXED,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
        XCTAssertEqual(SearchIndex.SQL.createMessagesFTSTable, expected,
            "DDL drift would silently break INSERTs (positional binding) AND snippet queries (column-index 3 assumption) — every shipped install rebuilds an empty index on launch")
    }

    /// Cross-check: the DDL must reference the same `messages_fts`
    /// table name the other SQL statements (truncate / delete /
    /// insert) already pin. Otherwise createSchema could land a table
    /// called `messages_fts_v2` while every writer still targets
    /// `messages_fts` — index would always be empty.
    func testCreateMessagesFTSTableDDLAndDMLAgreeOnTableName() {
        let tableName = "messages_fts"
        XCTAssertTrue(SearchIndex.SQL.createMessagesFTSTable.contains(tableName),
            "createMessagesFTSTable DDL must declare the `\(tableName)` table — drift would land an empty index that no DML writer ever sees")
        XCTAssertTrue(SearchIndex.SQL.truncateAll.contains(tableName),
            "truncateAll DML must target the `\(tableName)` table the DDL declares")
        XCTAssertTrue(SearchIndex.SQL.deleteByThreadID.contains(tableName),
            "deleteByThreadID DML must target the `\(tableName)` table the DDL declares")
        XCTAssertTrue(SearchIndex.SQL.insertRow.contains(tableName),
            "insertRow DML must target the `\(tableName)` table the DDL declares")
    }

    /// Cross-check: DDL column-order must match the position the
    /// `snippetTextColumnIndex` constant assumes (`text` is column
    /// index 3, zero-indexed: `thread_id=0, thread_name=1, sender=2,
    /// text=3, time=4, channel=5`). The existing
    /// `testSnippetTextColumnIndexMatchesSchemaPosition` pins the
    /// constant value; this pin grounds the same invariant in the
    /// DDL itself, so a column-reorder refactor that updates the
    /// constant but not the DDL (or vice versa) trips here.
    func testCreateMessagesFTSTableDDLPlacesTextAtSnippetColumnIndex() {
        let ddl = SearchIndex.SQL.createMessagesFTSTable
        let columnsInOrder = ["thread_id", "thread_name", "sender", "text", "time", "channel"]
        var lastUpper: String.Index? = nil
        for (i, col) in columnsInOrder.enumerated() {
            guard let r = ddl.range(of: col) else {
                XCTFail("DDL missing expected column `\(col)` at position \(i)")
                return
            }
            if let prev = lastUpper {
                XCTAssertTrue(r.lowerBound > prev,
                    "column `\(col)` must appear AFTER prior column in DDL — reorder breaks every positional INSERT")
            }
            lastUpper = r.upperBound
        }
        XCTAssertEqual(columnsInOrder.firstIndex(of: "text"),
                       Int(SearchIndex.snippetTextColumnIndex),
            "DDL column position of `text` must match snippetTextColumnIndex — drift produces snippets from the wrong column")
    }

    /// `productionFileName` is the on-disk handle every install reads
    /// from. Drift is a silent migration — the install's old index
    /// stays on disk, the new build creates an empty new one, and
    /// every `⌘K` palette query returns no results until a re-sync.
    func testProductionFileNameIsSearchDb() {
        XCTAssertEqual(SearchIndex.productionFileName, "search.db",
            "search.db filename is the canonical on-disk handle — drift orphans every install's existing index")
    }

    /// Round-trip the production URL builder to pin that the path
    /// actually flows through `productionFileName`. A future refactor
    /// that defines the constant but inlines a different literal in
    /// `productionDatabaseURL` would still pass `testProductionFileNameIsSearchDb`
    /// while silently re-orphaning every install's index.
    func testProductionDatabaseURLEndsInProductionFileName() {
        let url = SearchIndex.productionDatabaseURL()
        XCTAssertEqual(url.lastPathComponent, SearchIndex.productionFileName,
            "productionDatabaseURL must end in productionFileName — drift between source and constant orphans every install's index")
    }

    /// And the directory must be the canonical app-support folder so
    /// factory-reset's single-directory sweep finds the index.
    func testProductionDatabaseURLLivesInAppSupportSubdirectory() {
        let url = SearchIndex.productionDatabaseURL()
        XCTAssertTrue(url.path.contains(Preferences.appSupportDirectoryName),
            "search.db must sit inside `\(Preferences.appSupportDirectoryName)/` so factory-reset wipes it as part of the directory sweep — got: \(url.path)")
    }

    /// `outgoingSenderLabel` is what `m.from == .me` rows write into
    /// the FTS5 `sender` column. The label is duplicated at TWO call
    /// sites (`rebuild` + `upsert`) — drift between them would
    /// silently mix conventions, with full-rebuild rows tagged one
    /// way and per-thread-upsert rows the other. Pin the literal.
    func testOutgoingSenderLabelIsFrozen() {
        XCTAssertEqual(SearchIndex.outgoingSenderLabel, "me",
            "outgoingSenderLabel drift mixes conventions between full-rebuild and per-thread-upsert paths")
    }

    /// And the label must equal `PromptBuilder.Template.speakerSelf`
    /// so a future search feature like `from:me hello` matches the
    /// same speaker label the LLM prompt uses. Currently they coincide
    /// at `"me"`. Pin the cross-file invariant explicitly so a future
    /// rename in either place trips here.
    func testOutgoingSenderLabelEqualsPromptBuilderSpeakerSelf() {
        XCTAssertEqual(SearchIndex.outgoingSenderLabel,
                       PromptBuilder.Template.speakerSelf,
            "search-index outgoing-sender label must match PromptBuilder.Template.speakerSelf — drift desyncs `from:me` search from prompt formatting")
    }

    /// And the label must equal `ShortcutsExportHandler.outgoingMessageMarker`
    /// — the third leg of the three-module `me` triangle (search index ↔
    /// prompt builder ↔ shortcuts wire format). The Shortcut JSON tags
    /// outgoing rows with `"from": "me"`; SearchIndex tags FTS5 rows the
    /// same way; PromptBuilder formats LLM context the same way. Drift
    /// between SearchIndex and ShortcutsExportHandler would silently
    /// misclassify imported-thread rows when full-text search runs over
    /// them. The transitive equality is already covered via
    /// `PromptBuilder.Template.speakerSelf` (pinned above and via
    /// `ShortcutsExportHandlerTests.testOutgoingMarkerEqualsSpeakerSelf`),
    /// but pinning the direct pair here means a refactor that touches
    /// only SearchIndex + ShortcutsExportHandler (without PromptBuilder)
    /// still trips a SearchIndex test instead of relying on a sibling
    /// file's transitive coverage.
    func testOutgoingSenderLabelEqualsShortcutsExportHandlerMarker() {
        XCTAssertEqual(SearchIndex.outgoingSenderLabel,
                       ShortcutsExportHandler.outgoingMessageMarker,
            "search-index outgoing-sender label must match ShortcutsExportHandler.outgoingMessageMarker — drift desyncs imported-thread authorship between Shortcut import and full-text search")
    }

    /// Pin the SQLite in-memory-database sentinel filename. Drift to
    /// e.g. `":memory"` (no trailing colon) silently makes SQLite open
    /// a real disk file named `:memory` in the current working
    /// directory instead of an in-memory DB, polluting test state.
    /// Surfaces in every SearchIndex unit test that constructs the
    /// index without a `databaseURL`.
    func testInMemoryDatabasePathIsFrozen() {
        XCTAssertEqual(SearchIndex.inMemoryDatabasePath, ":memory:")
        XCTAssertTrue(SearchIndex.inMemoryDatabasePath.hasPrefix(":"),
            "in-memory sentinel must start with `:` — SQLite parses the leading colon as the in-memory marker")
        XCTAssertTrue(SearchIndex.inMemoryDatabasePath.hasSuffix(":"),
            "in-memory sentinel must end with `:` — SQLite parses the trailing colon as part of the marker")
    }
}
