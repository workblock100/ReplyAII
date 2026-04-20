import XCTest
@testable import ReplyAI

final class SearchIndexTests: XCTestCase {
    // MARK: - Query translation

    func testFTSQueryAppendsPrefix() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "dinner"),       "dinner*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "dinner mom"),   "dinner* mom*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "   dinner   "), "dinner*")
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
}
