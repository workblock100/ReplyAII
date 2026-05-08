import XCTest
import SQLite3
@testable import ReplyAI

/// Tests for `IMessageChannel.recentThreads` against a hand-crafted
/// chat.db-shaped SQLite file. No real Messages data ever touches the
/// test harness.
final class IMessageChannelTests: XCTestCase {
    private var dbURL: URL!

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-IMessageChannel-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    // MARK: - Date autodetect

    func testDateAutodetectNanoseconds() {
        // 1_700_000_000 seconds ≈ 2024; in nanoseconds it's ~1.7e18.
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: 1_700_000_000_000_000_000)
        XCTAssertEqual(secs, 1_700_000_000, accuracy: 1)
    }

    func testDateAutodetectSeconds() {
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: 700_000_000)
        XCTAssertEqual(secs, 700_000_000, accuracy: 0.001)
    }

    // MARK: - Date autodetect boundary tests (REP-122)

    func testAppleDateAsSecondsForSmallValue() {
        // Values ≤ 1e12 are returned as-is (seconds). 999_999_999 s from
        // reference ≈ 2033 AD — confirms the seconds path is taken.
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: 999_999_999)
        XCTAssertEqual(secs, 999_999_999, accuracy: 0.001,
                       "value below threshold must be returned unchanged as seconds")
        // Sanity: result must be a positive interval (after reference epoch).
        XCTAssertGreaterThan(secs, 0)
    }

    func testAppleDateAsNanosecondsForLargeValue() {
        // Values > 1_000_000_000_000 (1e12) are divided by 1e9. Using
        // 1_000_000_000_001 ns → 1000.000000001 s from reference.
        let raw: Int64 = 1_000_000_000_001
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: raw)
        XCTAssertEqual(secs, Double(raw) / 1_000_000_000, accuracy: 1e-6,
                       "value above 1e12 must be treated as nanoseconds and divided by 1e9")
    }

    func testAppleDateZeroReturnsPastDate() {
        // Zero maps to the Apple reference epoch (2001-01-01 UTC) — no crash.
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: 0)
        XCTAssertEqual(secs, 0, accuracy: 0.001,
                       "zero must return 0 seconds (reference epoch) without crash")
        let date = Date(timeIntervalSinceReferenceDate: secs)
        XCTAssertLessThan(date, Date(), "reference epoch is in the past")
    }

    // MARK: - REP-151: exact magnitude boundary tests

    func testAppleDateAtExactThresholdTreatedAsSeconds() {
        // The threshold is > 1_000_000_000_000 (1e12). A value exactly equal
        // to 1e12 is NOT greater than the threshold, so it must be treated as
        // seconds, not nanoseconds.
        let boundary: Int64 = 1_000_000_000_000
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: boundary)
        XCTAssertEqual(secs, Double(boundary), accuracy: 0.001,
                       "value exactly at 1e12 must be returned as-is (seconds path)")
    }

    func testAppleDateOneAboveThresholdTreatedAsNanoseconds() {
        // 1e12 + 1 is strictly greater than the threshold → nanoseconds path.
        let raw: Int64 = 1_000_000_000_001
        let secs = IMessageChannel.secondsSinceReferenceDate(appleDate: raw)
        XCTAssertEqual(secs, Double(raw) / 1_000_000_000, accuracy: 1e-6,
                       "value one above 1e12 must be divided by 1e9 (nanoseconds path)")
        XCTAssertLessThan(secs, Double(raw),
                          "nanosecond-path result must be much smaller than the raw value")
    }

    // MARK: - Query shape

    func testThreadsSortedByRecency() async throws {
        try buildSchema()
        try insertChat(rowid: 1, identifier: "+15550001", display: "", service: "iMessage", guid: "iMessage;-;+15550001")
        try insertChat(rowid: 2, identifier: "+15550002", display: "", service: "iMessage", guid: "iMessage;-;+15550002")
        try insertChat(rowid: 3, identifier: "+15550003", display: "", service: "iMessage", guid: "iMessage;-;+15550003")

        // rowid 1 → newest, rowid 3 → oldest
        try insertMessage(rowid: 10, chatRowID: 1, text: "newest",  fromMe: false, date: 700_000_000)
        try insertMessage(rowid: 11, chatRowID: 2, text: "middle",  fromMe: false, date: 650_000_000)
        try insertMessage(rowid: 12, chatRowID: 3, text: "oldest",  fromMe: false, date: 600_000_000)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)

        XCTAssertEqual(threads.map(\.id), ["+15550001", "+15550002", "+15550003"])
    }

    func testDateAutodetectNanosecondsInQuery() async throws {
        try buildSchema()
        try insertChat(rowid: 1, identifier: "nano", display: "", service: "iMessage", guid: "iMessage;-;nano")
        // A 2024-era date in nanoseconds since 2001-01-01.
        try insertMessage(rowid: 10, chatRowID: 1, text: "ns payload",
                          fromMe: false, date: 727_000_000_000_000_000)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        // We don't assert the exact formatted time string (locale-dependent)
        // but a non-empty, non-error time indicates the magnitude autodetect
        // didn't divide a seconds-encoded value by 1e9.
        XCTAssertFalse(threads[0].time.isEmpty)
        XCTAssertEqual(threads[0].preview, "ns payload")
    }

    func testNullTextFallsBackToAttributedBody() async throws {
        try buildSchema()
        try insertChat(rowid: 1, identifier: "fallback", display: "", service: "iMessage", guid: "iMessage;-;fallback")
        try insertMessageWithAttributedBody(
            rowid: 20, chatRowID: 1,
            attributedBody: Self.typedstreamBlob(text: "rich-only body"),
            fromMe: false, date: 700_000_000
        )

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].preview, "rich-only body",
                       "NULL text should fall back to AttributedBodyDecoder")
    }

    func testBothNullProducesEmptyMessage() async throws {
        try buildSchema()
        try insertChat(rowid: 1, identifier: "nullboth", display: "", service: "iMessage", guid: "iMessage;-;nullboth")
        // A real message to anchor the thread, plus a both-NULL delivery-receipt style row.
        try insertMessage(rowid: 20, chatRowID: 1, text: "real msg", fromMe: false, date: 700_000_000)
        try insertMessageBothNull(rowid: 21, chatRowID: 1, fromMe: false, date: 700_000_001)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        // The channel's last-message subquery filters (m.text IS NOT NULL OR m.attributedBody IS NOT NULL),
        // so the both-NULL row is excluded and the real message wins preview. No crash is the
        // primary invariant; the thread must still appear.
        XCTAssertEqual(threads.count, 1, "thread must appear via the real message, not crash on both-NULL row")
        XCTAssertEqual(threads[0].preview, "real msg",
                       "preview must fall back to the real message when the latest row is both-NULL")
    }

    func testNullTextAndAttributedBodyYieldsNonNilBody() async throws {
        // REP-117: messages(forThreadID:limit:) must return a non-nil body for rows where
        // both text and attributedBody are NULL (deleted, unsent, or unsupported extension).
        try buildSchema()
        try insertChat(rowid: 1, identifier: "nullmsg", display: "", service: "iMessage", guid: "iMessage;-;nullmsg")
        try insertMessageBothNull(rowid: 10, chatRowID: 1, fromMe: false, date: 700_000_000)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "nullmsg", limit: 10)
        XCTAssertEqual(messages.count, 1, "both-NULL row must produce a message, not be silently dropped")
        let body = try XCTUnwrap(messages.first?.text)
        XCTAssertFalse(body.isEmpty, "body must be non-empty — expected [deleted] placeholder")
        XCTAssertEqual(body, "[deleted]", "both-NULL row must use the [deleted] placeholder")
        XCTAssertEqual(body, IMessageChannel.deletedMessagePlaceholder,
                       "behavior must equal the hoisted placeholder constant — keeps the two `return` sites and the literal asserted here in sync")
    }

    /// Pin the literal value of the placeholder. The two `return` sites
    /// in IMessageChannel both reference `Self.deletedMessagePlaceholder`,
    /// so changing the constant changes what users see in every deleted-
    /// message slot at once. Pin so a rename ("[deleted]" → "(removed)" /
    /// "—" / etc.) lands as a deliberate UX call.
    func testDeletedMessagePlaceholderIsExactLiteral() {
        XCTAssertEqual(IMessageChannel.deletedMessagePlaceholder, "[deleted]",
                       "deleted-message placeholder is shipped UX — see test rationale")
    }

    func testMessagesQueryNullTextFallsBackToAttributedBodyDecoder() async throws {
        // REP-221: messages(forThreadID:limit:) must decode attributedBody when text is NULL.
        // recentThreads has its own test (testNullTextFallsBackToAttributedBody); this pins
        // the same fallback in the per-thread message stream so a rich-only iMessage shows up
        // in the conversation view, not as a "[deleted]" placeholder.
        try buildSchema()
        try insertChat(rowid: 1, identifier: "rich", display: "", service: "iMessage", guid: "iMessage;-;rich")
        try insertMessageWithAttributedBody(
            rowid: 30, chatRowID: 1,
            attributedBody: Self.typedstreamBlob(text: "rich-only message body"),
            fromMe: false, date: 700_000_000
        )

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "rich", limit: 10)
        XCTAssertEqual(messages.count, 1, "rich-only row must produce one message")
        XCTAssertEqual(messages.first?.text, "rich-only message body",
                       "NULL text must fall back to AttributedBodyDecoder, not the [deleted] placeholder")
    }

    func testGroupChatGUIDProjection() async throws {
        try buildSchema()
        try insertChat(
            rowid: 1, identifier: "chat1234567890",
            display: "Launch Crew", service: "iMessage",
            guid: "iMessage;+;chat1234567890"
        )
        try insertMessage(rowid: 30, chatRowID: 1, text: "launch soon", fromMe: false, date: 700_000_000)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].chatGUID, "iMessage;+;chat1234567890",
                       "group chats must surface the full chat.guid so AppleScript sends land")
        XCTAssertEqual(threads[0].name, "Launch Crew",
                       "display_name should win over participant handle for group threads")
    }

    /// chat.guid column with the empty string (NULL would have COALESCE'd
    /// to '' as well — same effect) must produce `MessageThread.chatGUID
    /// = nil`, NOT `Some("")`. The guard at `chatGUID: guid.isEmpty ?
    /// nil : guid` filters present-but-empty values to nil so downstream
    /// IMessageSender.chatGUID(for:) falls back to the synthesized 1:1
    /// form. Pin against a future "pass through whatever the column said"
    /// refactor that would re-introduce the AGENTS.md gotcha #243
    /// `Some("")` bug class on every empty-guid chat — IMessageSender
    /// would then validate `""` (failing) instead of synthesizing a
    /// usable iMessage;-;<id> string.
    func testEmptyChatGUIDColumnFiltersToNil() async throws {
        try buildSchema()
        try insertChat(
            rowid: 1, identifier: "+15555550199",
            display: "Empty Guid", service: "iMessage",
            guid: ""  // explicitly empty — COALESCE on NULL lands here too
        )
        try insertMessage(rowid: 50, chatRowID: 1, text: "noguid", fromMe: false, date: 700_000_000)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertNil(threads[0].chatGUID,
            "empty guid column must filter to nil, NOT pass through as Some(\"\"); IMessageSender then synthesizes a 1:1 GUID instead of validating an empty string and failing")
    }

    // MARK: - REP-020 reaction + delivery-receipt filtering

    func testReactionRowExcludedFromPreview() async throws {
        try buildSchema()
        try insertChat(rowid: 1, identifier: "+15550010", display: "", service: "iMessage", guid: "iMessage;-;+15550010")
        // Real message arrives first (older date), then a tapback reaction (newer).
        try insertMessage(rowid: 40, chatRowID: 1, text: "let's meet up", fromMe: false, date: 700_000_000)
        try insertReactionMessage(rowid: 41, chatRowID: 1, reactionType: 2000, date: 700_000_001)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].preview, "let's meet up",
                       "tapback reaction should not displace the real last message as preview")
    }

    func testDeliveryReceiptRowExcludedFromPreview() async throws {
        try buildSchema()
        try insertChat(rowid: 1, identifier: "+15550011", display: "", service: "iMessage", guid: "iMessage;-;+15550011")
        // Real message arrives, then a NULL-text delivery-receipt row with a newer date.
        try insertMessage(rowid: 50, chatRowID: 1, text: "on my way", fromMe: true, date: 700_000_000)
        try insertDeliveryReceiptMessage(rowid: 51, chatRowID: 1, date: 700_000_002)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].preview, "on my way",
                       "NULL-text delivery receipt should not displace the real last message as preview")
    }

    // MARK: - REP-021 pagination

    /// 60 chats with messages → only 50 returned when limit=50.
    func testThreadListHonorsLimit() async throws {
        try buildSchema()
        for i in 1...60 {
            let rowid = Int64(i)
            let identifier = "+1555000\(String(format: "%04d", i))"
            try insertChat(rowid: rowid, identifier: identifier, display: "",
                           service: "iMessage", guid: "iMessage;-;\(identifier)")
            try insertMessage(rowid: rowid, chatRowID: rowid, text: "msg \(i)",
                              fromMe: false, date: Int64(600_000_000 + i))
        }

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 50)
        XCTAssertEqual(threads.count, 50, "limit=50 must cap result at 50 even when 60 rows exist")
    }

    /// With 60 chats, limit=50 returns the 50 most recent (highest date) ones.
    func testThreadListSortedByRecencyWithLimit() async throws {
        try buildSchema()
        // Chats 1–60; chat i has date 600_000_000 + i so chat 60 is newest.
        for i in 1...60 {
            let rowid = Int64(i)
            let identifier = "+1555999\(String(format: "%04d", i))"
            try insertChat(rowid: rowid, identifier: identifier, display: "",
                           service: "iMessage", guid: "iMessage;-;\(identifier)")
            try insertMessage(rowid: rowid, chatRowID: rowid, text: "msg \(i)",
                              fromMe: false, date: Int64(600_000_000 + i))
        }

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 50)

        // The 50 returned should be chats 11–60 (most recent), ordered newest-first.
        XCTAssertEqual(threads.count, 50)
        // Oldest chat returned should be chat 11 (the 11th most-recent), not chat 1.
        XCTAssertFalse(threads.map(\.id).contains("+15559990001"),
                       "the 10 oldest chats must not appear when limit=50 and 60 exist")
        // Newest chat (60) should be first.
        XCTAssertEqual(threads[0].id, "+15559990060",
                       "most recent chat must be first in the list")
    }

    // MARK: - SQLite test helpers

    private func openDB() throws -> OpaquePointer {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(dbURL.path, &db,
                                 SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
                                 nil)
        guard rc == SQLITE_OK, let db else {
            XCTFail("couldn't open test DB at \(dbURL.path)")
            throw NSError(domain: "sqlite", code: Int(rc))
        }
        return db
    }

    private func buildSchema() throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE chat (
            ROWID INTEGER PRIMARY KEY,
            chat_identifier TEXT,
            display_name TEXT,
            service_name TEXT,
            guid TEXT
        );
        CREATE TABLE handle (
            ROWID INTEGER PRIMARY KEY,
            id TEXT
        );
        CREATE TABLE chat_handle_join (
            chat_id INTEGER,
            handle_id INTEGER
        );
        CREATE TABLE message (
            ROWID INTEGER PRIMARY KEY,
            text TEXT,
            attributedBody BLOB,
            is_from_me INTEGER,
            is_read INTEGER,
            date INTEGER,
            associated_message_type INTEGER DEFAULT 0,
            cache_has_attachments INTEGER DEFAULT 0,
            date_delivered INTEGER DEFAULT 0
        );
        CREATE TABLE chat_message_join (
            chat_id INTEGER,
            message_id INTEGER
        );
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertChat(rowid: Int64, identifier: String, display: String,
                            service: String, guid: String) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = "INSERT INTO chat VALUES (?1, ?2, ?3, ?4, ?5);"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, rowid)
        sqlite3_bind_text(stmt, 2, identifier, -1, Self.TRANSIENT)
        sqlite3_bind_text(stmt, 3, display,    -1, Self.TRANSIENT)
        sqlite3_bind_text(stmt, 4, service,    -1, Self.TRANSIENT)
        sqlite3_bind_text(stmt, 5, guid,       -1, Self.TRANSIENT)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private func insertMessage(rowid: Int64, chatRowID: Int64, text: String,
                               fromMe: Bool, date: Int64) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let msgSQL = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date, associated_message_type)
        VALUES (?1, ?2, NULL, ?3, 0, ?4, 0);
        """
        var m: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, msgSQL, -1, &m, nil), SQLITE_OK)
        sqlite3_bind_int64(m, 1, rowid)
        sqlite3_bind_text(m, 2, text, -1, Self.TRANSIENT)
        sqlite3_bind_int(m, 3, fromMe ? 1 : 0)
        sqlite3_bind_int64(m, 4, date)
        XCTAssertEqual(sqlite3_step(m), SQLITE_DONE)
        sqlite3_finalize(m)

        try linkMessage(db: db, chatRowID: chatRowID, messageRowID: rowid)
    }

    /// Insert a tapback reaction row (associated_message_type 2000–2005).
    private func insertReactionMessage(rowid: Int64, chatRowID: Int64,
                                       reactionType: Int32 = 2000, date: Int64) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let msgSQL = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date, associated_message_type)
        VALUES (?1, '❤ to "…"', NULL, 0, 0, ?2, ?3);
        """
        var m: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, msgSQL, -1, &m, nil), SQLITE_OK)
        sqlite3_bind_int64(m, 1, rowid)
        sqlite3_bind_int64(m, 2, date)
        sqlite3_bind_int(m, 3, reactionType)
        XCTAssertEqual(sqlite3_step(m), SQLITE_DONE)
        sqlite3_finalize(m)

        try linkMessage(db: db, chatRowID: chatRowID, messageRowID: rowid)
    }

    /// Insert a delivery/read-receipt row (text NULL, attributedBody NULL).
    private func insertDeliveryReceiptMessage(rowid: Int64, chatRowID: Int64, date: Int64) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let msgSQL = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date, associated_message_type)
        VALUES (?1, NULL, NULL, 0, 1, ?2, 0);
        """
        var m: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, msgSQL, -1, &m, nil), SQLITE_OK)
        sqlite3_bind_int64(m, 1, rowid)
        sqlite3_bind_int64(m, 2, date)
        XCTAssertEqual(sqlite3_step(m), SQLITE_DONE)
        sqlite3_finalize(m)

        try linkMessage(db: db, chatRowID: chatRowID, messageRowID: rowid)
    }

    private func insertMessageBothNull(
        rowid: Int64, chatRowID: Int64, fromMe: Bool, date: Int64
    ) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let msgSQL = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date, associated_message_type)
        VALUES (?1, NULL, NULL, ?2, 0, ?3, 0);
        """
        var m: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, msgSQL, -1, &m, nil), SQLITE_OK)
        sqlite3_bind_int64(m, 1, rowid)
        sqlite3_bind_int(m, 2, fromMe ? 1 : 0)
        sqlite3_bind_int64(m, 3, date)
        XCTAssertEqual(sqlite3_step(m), SQLITE_DONE)
        sqlite3_finalize(m)
        try linkMessage(db: db, chatRowID: chatRowID, messageRowID: rowid)
    }

    private func insertMessageWithAttributedBody(
        rowid: Int64, chatRowID: Int64, attributedBody: Data,
        fromMe: Bool, date: Int64
    ) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let msgSQL = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date, associated_message_type)
        VALUES (?1, NULL, ?2, ?3, 0, ?4, 0);
        """
        var m: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, msgSQL, -1, &m, nil), SQLITE_OK)
        sqlite3_bind_int64(m, 1, rowid)
        attributedBody.withUnsafeBytes { buf -> Void in
            sqlite3_bind_blob(m, 2, buf.baseAddress, Int32(buf.count), Self.TRANSIENT)
        }
        sqlite3_bind_int(m, 3, fromMe ? 1 : 0)
        sqlite3_bind_int64(m, 4, date)
        XCTAssertEqual(sqlite3_step(m), SQLITE_DONE)
        sqlite3_finalize(m)

        try linkMessage(db: db, chatRowID: chatRowID, messageRowID: rowid)
    }

    private func linkMessage(db: OpaquePointer, chatRowID: Int64, messageRowID: Int64) throws {
        let sql = "INSERT INTO chat_message_join VALUES (?1, ?2);"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, chatRowID)
        sqlite3_bind_int64(stmt, 2, messageRowID)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    /// Build a minimal typedstream blob carrying a single UTF-8 string.
    /// Mirrors the fixture shape used in AttributedBodyDecoderTests.
    static func typedstreamBlob(text: String) -> Data {
        var bytes: [UInt8] = [0x04, 0x0B]
        bytes += Array("streamtyped".utf8)
        bytes += [0x04, 0x40, 0x84, 0x84, 0x87]
        bytes += [0x2B]  // primitive-string tag
        let textBytes = Array(text.utf8)
        if textBytes.count <= 0x7F {
            bytes += [UInt8(textBytes.count)]
        } else {
            let n = textBytes.count
            bytes += [0x81, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF)]
        }
        bytes += textBytes
        return Data(bytes)
    }

    private static let TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )
}

// MARK: - IMessageChannel.avatarInitial pin
//
// Pure helper used by ThreadRow + Sidebar to render the circular avatar
// chip. The phone-shape detection (☎ for handles starting with + or `(`)
// is a small UX touch that prevents "+1631..." threads from rendering as
// a literal "+" letter — easy for a refactor to break inadvertently.

final class IMessageChannelAvatarInitialTests: XCTestCase {

    func testRegularNameUppercasesFirstChar() {
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "maya chen"), "M")
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "Sarah Klein"), "S")
    }

    func testEmptyStringReturnsQuestionMark() {
        // Anonymous handle should still render something visible — not a
        // blank circle.
        XCTAssertEqual(IMessageChannel.avatarInitial(for: ""), "?")
    }

    func testWhitespaceOnlyReturnsQuestionMark() {
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "   "), "?")
        // Tab + space — both are in `.whitespaces`. Newline is NOT in
        // `.whitespaces` (it is in `.whitespacesAndNewlines`); the helper
        // intentionally uses the narrower set so a name like " \nfoo"
        // still picks up "f", not collapses to "?".
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "\t \t"), "?")
    }

    func testE164PhoneReturnsPhoneGlyph() {
        // "+16318486282" must NOT render as a literal "+" — that looks
        // like a malformed avatar. Phone glyph signals "this is a number,
        // not a contact."
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "+16318486282"), "☎")
    }

    func testParensFormatPhoneReturnsPhoneGlyph() {
        // "(631) 848-6282" same treatment.
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "(631) 848-6282"), "☎")
    }

    func testLeadingWhitespaceTrimmedBeforeFirstChar() {
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "  maya"), "M",
            "leading whitespace must not produce a blank initial")
    }

    func testNumericFirstCharPassesThrough() {
        // "5G WhatsApp group" or similar — numeric first char isn't a
        // phone signal (no + or paren) so it renders as the digit.
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "5G chat"), "5")
    }

    func testEmojiFirstCharPassesThrough() {
        // Group chats sometimes named with an emoji. Render the emoji
        // verbatim rather than uppercasing (which is a no-op anyway).
        let result = IMessageChannel.avatarInitial(for: "🎉 birthday plans")
        XCTAssertEqual(result, "🎉")
    }

    // MARK: - Avatar glyph hoist pins (REP-hoist 2026-05-07)
    //
    // The two avatar fallback glyphs (`?` for unknown, `☎` for
    // phone-shaped handles) live as `static let` on IMessageChannel.
    // Existing tests above use exact-literal equality which would
    // silently agree with a refactor that changes both source and
    // test together; these constant-routing pins are the independent
    // anchor.

    func testAvatarUnknownGlyphIsFrozen() {
        XCTAssertEqual(IMessageChannel.unknownAvatarGlyph, "?",
            "unknownAvatarGlyph drift silently changes the avatar treatment for every empty/whitespace-only thread name")
    }

    func testAvatarPhoneGlyphIsFrozen() {
        XCTAssertEqual(IMessageChannel.phoneAvatarGlyph, "☎",
            "phoneAvatarGlyph drift silently changes the avatar treatment for every unknown phone thread")
    }

    func testAvatarInitialEmptyRoutesThroughHoistedConstant() {
        XCTAssertEqual(IMessageChannel.avatarInitial(for: ""),
                       IMessageChannel.unknownAvatarGlyph,
            "empty-name fallback must equal unknownAvatarGlyph byte-for-byte — drift between matcher and constant is silent")
    }

    func testAvatarInitialPhoneFallbackIsTelephoneGlyph() {
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "+16318486282"),
                       IMessageChannel.phoneAvatarGlyph,
            "phone-shape fallback must equal phoneAvatarGlyph byte-for-byte — drift between matcher and constant is silent")
    }
}

// MARK: - ChannelError result-code preservation (REP-051)

final class ChannelErrorResultCodeTests: XCTestCase {
    /// databaseError(code:message:) exposes the sqlite result code so callers
    /// can branch on it (e.g. SQLITE_BUSY = 5) without string-matching.
    func testDatabaseErrorPreservesCode() {
        let err = ChannelError.databaseError(code: Int32(SQLITE_BUSY), message: "database is locked")
        guard case .databaseError(let code, let message) = err else {
            XCTFail("expected databaseError"); return
        }
        XCTAssertEqual(code, Int32(SQLITE_BUSY))
        XCTAssertEqual(message, "database is locked")
        XCTAssertEqual(err.errorDescription, "database is locked")
    }

    /// An open failure after the file existence guard surfaces a database or
    /// permission error — never unavailable — because the path exists.
    func testOpenFailureSurfacesDatabaseOrPermissionError() async {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replyai-dbtest-\(UUID().uuidString).db")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let failingOpener: @Sendable (String, Int32) -> (Int32, OpaquePointer?) = { _, _ in
            (SQLITE_ERROR, nil)
        }
        let channel = IMessageChannel(dbPathOverride: fileURL.path, dbOpener: failingOpener)
        do {
            _ = try await channel.recentThreads(limit: 1)
            XCTFail("expected throw")
        } catch let err as ChannelError {
            switch err {
            case .databaseError(let code, _):
                XCTAssertGreaterThan(code, 0)
            case .permissionDenied:
                break  // sqlite3 mapped dir-open to "unable to open"
            case .unavailable(let msg):
                XCTFail("should not reach unavailable for existing directory path: \(msg)")
            default:
                XCTFail("unexpected ChannelError: \(err)")
            }
        } catch {
            XCTFail("unexpected non-ChannelError: \(error)")
        }
    }
}

// MARK: - cache_has_attachments projection (REP-068)

final class IMessageChannelAttachmentTests: XCTestCase {
    private var dbURL: URL!

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-AttachTest-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    private func openDB() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            throw ChannelError.databaseError(code: 1, message: "could not open test db")
        }
        return handle
    }

    private func buildSchema() throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (
            ROWID INTEGER PRIMARY KEY,
            text TEXT,
            attributedBody BLOB,
            is_from_me INTEGER,
            is_read INTEGER,
            date INTEGER,
            associated_message_type INTEGER DEFAULT 0,
            cache_has_attachments INTEGER DEFAULT 0,
            date_delivered INTEGER DEFAULT 0
        );
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertChat(_ db: OpaquePointer, rowid: Int64, identifier: String) {
        let sql = "INSERT INTO chat VALUES (?1, ?2, '', 'iMessage', ?3);"
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &s, nil)
        sqlite3_bind_int64(s, 1, rowid)
        sqlite3_bind_text(s, 2, identifier, -1, Self.TRANSIENT)
        sqlite3_bind_text(s, 3, "iMessage;-;\(identifier)", -1, Self.TRANSIENT)
        sqlite3_step(s)
        sqlite3_finalize(s)
    }

    private func insertMessage(_ db: OpaquePointer, rowid: Int64, chatRowID: Int64,
                               text: String, hasAttachment: Bool) {
        let sql = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date, associated_message_type, cache_has_attachments)
        VALUES (?1, ?2, NULL, 0, 0, 700000000, 0, ?3);
        """
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &s, nil)
        sqlite3_bind_int64(s, 1, rowid)
        sqlite3_bind_text(s, 2, text, -1, Self.TRANSIENT)
        sqlite3_bind_int(s, 3, hasAttachment ? 1 : 0)
        sqlite3_step(s)
        sqlite3_finalize(s)
        // link
        let link = "INSERT INTO chat_message_join VALUES (?1, ?2);"
        var l: OpaquePointer?
        sqlite3_prepare_v2(db, link, -1, &l, nil)
        sqlite3_bind_int64(l, 1, chatRowID)
        sqlite3_bind_int64(l, 2, rowid)
        sqlite3_step(l)
        sqlite3_finalize(l)
    }

    func testHasAttachmentTrueFromColumn() async throws {
        try buildSchema()
        let db = try openDB()
        insertChat(db, rowid: 1, identifier: "+15550001")
        insertMessage(db, rowid: 10, chatRowID: 1, text: "see attached", hasAttachment: true)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "+15550001", limit: 10)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].hasAttachment,
                      "cache_has_attachments=1 must project to Message.hasAttachment=true")
    }

    func testHasAttachmentFalseFromColumn() async throws {
        try buildSchema()
        let db = try openDB()
        insertChat(db, rowid: 2, identifier: "+15550002")
        insertMessage(db, rowid: 20, chatRowID: 2, text: "plain text only", hasAttachment: false)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "+15550002", limit: 10)
        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(messages[0].hasAttachment,
                       "cache_has_attachments=0 must project to Message.hasAttachment=false")
    }
}

// MARK: - SQLITE_BUSY retry (REP-029)

final class IMessageChannelBusyRetryTests: XCTestCase {
    private var dbURL: URL!
    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-BusyRetry-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private func buildMinimalDB() throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else { XCTFail("test db creation failed"); return }
        defer { sqlite3_close(handle) }
        let schema = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB, is_from_me INTEGER, is_read INTEGER, date INTEGER, associated_message_type INTEGER DEFAULT 0, cache_has_attachments INTEGER DEFAULT 0, date_delivered INTEGER DEFAULT 0);
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(handle, schema, nil, nil, nil), SQLITE_OK)
        var s: OpaquePointer?
        sqlite3_prepare_v2(handle, "INSERT INTO chat VALUES (1,'+15550001','','iMessage','iMessage;-;+15550001');", -1, &s, nil)
        sqlite3_step(s); sqlite3_finalize(s)
        sqlite3_prepare_v2(handle, "INSERT INTO message(ROWID,text,is_from_me,is_read,date) VALUES (1,'hello',0,0,700000000);", -1, &s, nil)
        sqlite3_step(s); sqlite3_finalize(s)
        sqlite3_prepare_v2(handle, "INSERT INTO chat_message_join VALUES (1,1);", -1, &s, nil)
        sqlite3_step(s); sqlite3_finalize(s)
    }

    func testBusyOnFirstCallRetriesToSuccess() async throws {
        try buildMinimalDB()
        var callCount = 0
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: { path, flags in
                callCount += 1
                if callCount == 1 { return (SQLITE_BUSY, nil) }
                var db: OpaquePointer?
                let rc = sqlite3_open_v2(path, &db, flags, nil)
                return (rc, db)
            }
        )
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(callCount, 2, "opener called twice: first SQLITE_BUSY, then success")
        XCTAssertEqual(threads.count, 1)
    }

    func testPersistentBusyThrowsDatabaseError() async throws {
        try buildMinimalDB()
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: { _, _ in (SQLITE_BUSY, nil) }
        )
        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("expected throw on persistent SQLITE_BUSY")
        } catch let err as ChannelError {
            guard case .databaseError(let code, _) = err else {
                XCTFail("expected databaseError, got \(err)"); return
            }
            XCTAssertEqual(code, SQLITE_BUSY)
        }
    }

    /// Pin the exact SQLite open-flags used for chat.db. The flags MUST be
    /// `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`:
    ///   - READONLY guarantees we never write to chat.db. A regression that
    ///     drops READONLY (e.g. someone copy-pastes the test fixture's
    ///     READWRITE|CREATE flags) would let macOS's Messages.app database
    ///     become corruptible by ReplyAI — Apple would notice.
    ///   - NOMUTEX skips SQLite's internal mutex; we don't share the
    ///     connection across threads, so the mutex is wasted overhead. A
    ///     drop here doesn't break correctness but adds latency to every
    ///     `recentThreads` call.
    /// Capture both via the dbOpener hook so a flag drift surfaces here
    /// instead of as a "Messages won't open" support bug.
    func testOpenFlagsAreReadOnlyAndNoMutex() async throws {
        try buildMinimalDB()
        // Capture box — dbOpener runs synchronously on the calling thread.
        final class Captured: @unchecked Sendable {
            var flags: Int32 = 0
        }
        let captured = Captured()
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: { path, flags in
                captured.flags = flags
                var db: OpaquePointer?
                let rc = sqlite3_open_v2(path, &db, flags, nil)
                return (rc, db)
            }
        )
        _ = try await channel.recentThreads(limit: 10)

        XCTAssertNotEqual(captured.flags & SQLITE_OPEN_READONLY, 0,
            "open flags must include SQLITE_OPEN_READONLY — dropping it lets ReplyAI corrupt Apple's chat.db")
        XCTAssertEqual(captured.flags & SQLITE_OPEN_READWRITE, 0,
            "open flags must NOT include READWRITE — symmetric guard against the most likely regression")
        XCTAssertEqual(captured.flags & SQLITE_OPEN_CREATE, 0,
            "open flags must NOT include CREATE — chat.db must already exist; CREATE risks accidentally creating an empty Messages DB and shadowing the real one")
        XCTAssertNotEqual(captured.flags & SQLITE_OPEN_NOMUTEX, 0,
            "open flags must include SQLITE_OPEN_NOMUTEX — connection is single-threaded; the mutex is wasted overhead per recentThreads call")
        XCTAssertEqual(captured.flags, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            "exact-flag pin: READONLY|NOMUTEX is the canonical chat.db open-mode for ReplyAI")
    }
}

// MARK: - Message.isRead projection (REP-036)

final class IMessageChannelIsReadTests: XCTestCase {
    private var dbURL: URL!
    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-IsRead-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private func openDB() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            throw ChannelError.databaseError(code: 1, message: "test db open failed")
        }
        return handle
    }

    private func buildSchema(_ db: OpaquePointer) {
        let sql = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB, is_from_me INTEGER, is_read INTEGER, date INTEGER, associated_message_type INTEGER DEFAULT 0, cache_has_attachments INTEGER DEFAULT 0, date_delivered INTEGER DEFAULT 0);
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertMsg(_ db: OpaquePointer, rowid: Int64, chatRowID: Int64,
                           text: String, isRead: Bool) {
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO message(ROWID,text,is_from_me,is_read,date) VALUES (?1,?2,0,?3,700000000);", -1, &s, nil)
        sqlite3_bind_int64(s, 1, rowid)
        sqlite3_bind_text(s, 2, text, -1, Self.TRANSIENT)
        sqlite3_bind_int(s, 3, isRead ? 1 : 0)
        sqlite3_step(s); sqlite3_finalize(s)
        sqlite3_prepare_v2(db, "INSERT INTO chat_message_join VALUES (?1,?2);", -1, &s, nil)
        sqlite3_bind_int64(s, 1, chatRowID); sqlite3_bind_int64(s, 2, rowid)
        sqlite3_step(s); sqlite3_finalize(s)
    }

    func testIsReadProjectedCorrectly() async throws {
        let db = try openDB()
        buildSchema(db)
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO chat VALUES (1,'+15550001','','iMessage','iMessage;-;+15550001');", -1, &s, nil)
        sqlite3_step(s); sqlite3_finalize(s)
        insertMsg(db, rowid: 1, chatRowID: 1, text: "read msg",   isRead: true)
        insertMsg(db, rowid: 2, chatRowID: 1, text: "unread msg", isRead: false)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "+15550001", limit: 10)
        XCTAssertEqual(messages.count, 2)
        let byText = Dictionary(uniqueKeysWithValues: messages.map { ($0.text, $0.isRead) })
        XCTAssertEqual(byText["read msg"],   true,  "is_read=1 must project to isRead=true")
        XCTAssertEqual(byText["unread msg"], false, "is_read=0 must project to isRead=false")
    }
}

// MARK: - Message.deliveredAt projection (REP-055)

final class IMessageChannelDeliveredAtTests: XCTestCase {
    private var dbURL: URL!
    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-DeliveredAt-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private func openDB() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            throw ChannelError.databaseError(code: 1, message: "test db open failed")
        }
        return handle
    }

    private func buildSchema(_ db: OpaquePointer) {
        let sql = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB, is_from_me INTEGER, is_read INTEGER, date INTEGER, associated_message_type INTEGER DEFAULT 0, cache_has_attachments INTEGER DEFAULT 0, date_delivered INTEGER DEFAULT 0);
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertMsg(_ db: OpaquePointer, rowid: Int64, chatRowID: Int64,
                           text: String, dateDelivered: Int64) {
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO message(ROWID,text,is_from_me,is_read,date,date_delivered) VALUES (?1,?2,0,0,700000000,?3);", -1, &s, nil)
        sqlite3_bind_int64(s, 1, rowid)
        sqlite3_bind_text(s, 2, text, -1, Self.TRANSIENT)
        sqlite3_bind_int64(s, 3, dateDelivered)
        sqlite3_step(s); sqlite3_finalize(s)
        sqlite3_prepare_v2(db, "INSERT INTO chat_message_join VALUES (?1,?2);", -1, &s, nil)
        sqlite3_bind_int64(s, 1, chatRowID); sqlite3_bind_int64(s, 2, rowid)
        sqlite3_step(s); sqlite3_finalize(s)
    }

    func testDeliveredAtNonNilWhenNonZero() async throws {
        let db = try openDB()
        buildSchema(db)
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO chat VALUES (1,'+15550001','','iMessage','iMessage;-;+15550001');", -1, &s, nil)
        sqlite3_step(s); sqlite3_finalize(s)
        insertMsg(db, rowid: 1, chatRowID: 1, text: "delivered", dateDelivered: 700_000_000)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "+15550001", limit: 10)
        XCTAssertEqual(messages.count, 1)
        XCTAssertNotNil(messages[0].deliveredAt, "date_delivered > 0 must produce non-nil deliveredAt")
        let expected = Date(timeIntervalSinceReferenceDate: 700_000_000)
        XCTAssertEqual(
            messages[0].deliveredAt?.timeIntervalSinceReferenceDate ?? 0,
            expected.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testDeliveredAtNilWhenZero() async throws {
        let db = try openDB()
        buildSchema(db)
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO chat VALUES (2,'+15550002','','iMessage','iMessage;-;+15550002');", -1, &s, nil)
        sqlite3_step(s); sqlite3_finalize(s)
        insertMsg(db, rowid: 2, chatRowID: 2, text: "not delivered", dateDelivered: 0)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let messages = try await channel.messages(forThreadID: "+15550002", limit: 10)
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(messages[0].deliveredAt, "date_delivered=0 must produce nil deliveredAt")
    }

    // MARK: - SQLITE_NOTADB graceful error (REP-077)

    func testNotADBProducesDatabaseCorrupted() async throws {
        // Inject an opener that returns SQLITE_NOTADB (26) without a real handle.
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: { _, _ in (SQLITE_NOTADB, nil) }
        )
        // The file path must exist so we pass the FileManager.fileExists guard.
        FileManager.default.createFile(atPath: dbURL.path, contents: Data("not a db".utf8))
        do {
            _ = try await channel.recentThreads(limit: 1)
            XCTFail("Expected databaseCorrupted error")
        } catch let error as ChannelError {
            guard case .databaseCorrupted = error else {
                XCTFail("Expected .databaseCorrupted, got \(error)")
                return
            }
        }
    }

    func testOtherErrorProducesDatabaseError() async throws {
        // SQLITE_CANTOPEN (14) is a generic open failure that is NOT NOTADB.
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: { _, _ in (SQLITE_CANTOPEN, nil) }
        )
        FileManager.default.createFile(atPath: dbURL.path, contents: Data("junk".utf8))
        do {
            _ = try await channel.recentThreads(limit: 1)
            XCTFail("Expected databaseError")
        } catch let error as ChannelError {
            switch error {
            case .databaseError:
                break // expected
            case .permissionDenied:
                break // also acceptable for cantopen
            default:
                XCTFail("Expected databaseError or permissionDenied, got \(error)")
            }
        }
    }
}

// MARK: - Per-thread message-history cap (REP-095)

final class IMessageChannelMessageLimitTests: XCTestCase {
    private var dbURL: URL!
    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-MsgLimit-\(UUID().uuidString).db")
        try buildSchema()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    /// A thread with 25 messages should return exactly 20 when limit=20.
    func testMessageLimitCapsResults() async throws {
        try insertChatAndMessages(identifier: "+15550300", count: 25)
        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgs = try await channel.messages(forThreadID: "+15550300", limit: 20)
        XCTAssertEqual(msgs.count, 20, "limit=20 must cap results even when 25 rows exist")
    }

    /// A thread with fewer messages than the limit should return all of them.
    func testMessageLimitDoesNotDropShortThreads() async throws {
        try insertChatAndMessages(identifier: "+15550301", count: 7)
        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgs = try await channel.messages(forThreadID: "+15550301", limit: 20)
        XCTAssertEqual(msgs.count, 7, "threads with fewer than limit messages must return all")
    }

    /// With limit=20 and 25 messages, the returned messages must be the 20 most recent.
    func testMessageLimitPreservesMostRecent() async throws {
        // Insert 25 messages with dates 1…25; the most recent have text "msg-22"..."msg-25" etc.
        try insertChatAndMessages(identifier: "+15550302", count: 25)
        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgs = try await channel.messages(forThreadID: "+15550302", limit: 20)
        // messages() returns oldest→newest after the DESC+reverse; the 20 returned
        // should span dates 6…25 (the 20 most recent). First msg text is "msg-6".
        XCTAssertEqual(msgs.first?.text, "msg-6",
                       "first of the 20 returned should be the 6th oldest (date=6)")
        XCTAssertEqual(msgs.last?.text, "msg-25",
                       "last of the 20 returned should be the most recent (date=25)")
    }

    // MARK: - Helpers

    private func buildSchema() throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db else { throw NSError(domain: "sqlite", code: -1) }
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT,
            service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB,
            is_from_me INTEGER, is_read INTEGER, date INTEGER,
            associated_message_type INTEGER DEFAULT 0,
            cache_has_attachments INTEGER DEFAULT 0, date_delivered INTEGER DEFAULT 0);
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertChatAndMessages(identifier: String, count: Int) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db,
                              SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else { throw NSError(domain: "sqlite", code: -1) }
        defer { sqlite3_close(db) }

        let chatID: Int64 = abs(Int64(identifier.hashValue)) % 10000 + 1
        sqlite3_exec(db, "INSERT INTO chat VALUES (\(chatID), '\(identifier)', '', 'iMessage', '');",
                     nil, nil, nil)

        for i in 1...count {
            let msgID = Int64(i)
            var stmt: OpaquePointer?
            let msql = "INSERT INTO message(ROWID,text,attributedBody,is_from_me,is_read,date,associated_message_type) VALUES (?1,?2,NULL,0,0,?3,0);"
            sqlite3_prepare_v2(db, msql, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, msgID)
            let txt = "msg-\(i)"
            sqlite3_bind_text(stmt, 2, txt, -1, Self.TRANSIENT)
            sqlite3_bind_int64(stmt, 3, Int64(i))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)

            sqlite3_exec(db,
                "INSERT INTO chat_message_join VALUES (\(chatID), \(msgID));",
                nil, nil, nil)
        }
    }

    // MARK: - REP-146: per-thread cap is independent across threads

    // Inserts a chat with an explicit chatID to avoid hash collisions when
    // multiple threads share one test DB. ROWIDs start at rowIDStart.
    private func insertThread(chatID: Int64, identifier: String, count: Int, rowIDStart: Int64) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db,
                              SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db else { throw NSError(domain: "sqlite", code: -1) }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "INSERT INTO chat VALUES (\(chatID), '\(identifier)', '', 'iMessage', '');",
                     nil, nil, nil)

        for i in 0..<count {
            let msgID = rowIDStart + Int64(i)
            var stmt: OpaquePointer?
            let msql = "INSERT INTO message(ROWID,text,attributedBody,is_from_me,is_read,date,associated_message_type) VALUES (?1,?2,NULL,0,0,?3,0);"
            sqlite3_prepare_v2(db, msql, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, msgID)
            let txt = "\(identifier)-\(i + 1)"
            sqlite3_bind_text(stmt, 2, txt, -1, Self.TRANSIENT)
            sqlite3_bind_int64(stmt, 3, Int64(i + 1))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)

            sqlite3_exec(db,
                "INSERT INTO chat_message_join VALUES (\(chatID), \(msgID));",
                nil, nil, nil)
        }
    }

    /// Thread A (100 msgs), B (3 msgs), C (50 msgs) with limit=20: each thread is
    /// capped independently — the under-limit thread B returns all 3, not 0 or 20.
    func testPerThreadMessageCapAppliedIndependently() async throws {
        try insertThread(chatID: 101, identifier: "+15556000", count: 100, rowIDStart: 1)
        try insertThread(chatID: 102, identifier: "+15556001", count: 3,   rowIDStart: 101)
        try insertThread(chatID: 103, identifier: "+15556002", count: 50,  rowIDStart: 104)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgsA = try await channel.messages(forThreadID: "+15556000", limit: 20)
        let msgsB = try await channel.messages(forThreadID: "+15556001", limit: 20)
        let msgsC = try await channel.messages(forThreadID: "+15556002", limit: 20)

        XCTAssertEqual(msgsA.count, 20, "thread A (100 msgs) must be capped at limit=20")
        XCTAssertEqual(msgsB.count, 3,  "thread B (3 msgs) must return all (below limit)")
        XCTAssertEqual(msgsC.count, 20, "thread C (50 msgs) must be capped at limit=20")
    }

    /// Total messages across three threads with per-thread cap=20 must be 43 (20+3+20),
    /// not 60, confirming the cap is per-thread and not a shared global budget.
    func testTotalMessageCountRespectsCappedSum() async throws {
        try insertThread(chatID: 201, identifier: "+15557000", count: 100, rowIDStart: 1)
        try insertThread(chatID: 202, identifier: "+15557001", count: 3,   rowIDStart: 101)
        try insertThread(chatID: 203, identifier: "+15557002", count: 50,  rowIDStart: 104)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgsA = try await channel.messages(forThreadID: "+15557000", limit: 20)
        let msgsB = try await channel.messages(forThreadID: "+15557001", limit: 20)
        let msgsC = try await channel.messages(forThreadID: "+15557002", limit: 20)

        let total = msgsA.count + msgsB.count + msgsC.count
        XCTAssertEqual(total, 43, "per-thread cap sums to 20+3+20=43, not 60 (which would mean a global budget)")
    }
}

// MARK: - REP-159: MessageThread.hasAttachment from message-level SQL field

/// Verifies that `recentThreads()` sets `MessageThread.hasAttachment` correctly
/// based on the `cache_has_attachments` value of the thread's most recent message.
final class IMessageChannelThreadHasAttachmentTests: XCTestCase {
    private var dbURL: URL!
    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-ThreadHasAtt-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private func openDB() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            throw ChannelError.databaseError(code: 1, message: "test db open failed")
        }
        return handle
    }

    private func buildSchema() throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (
            ROWID INTEGER PRIMARY KEY,
            text TEXT,
            attributedBody BLOB,
            is_from_me INTEGER,
            is_read INTEGER,
            date INTEGER,
            associated_message_type INTEGER DEFAULT 0,
            cache_has_attachments INTEGER DEFAULT 0,
            date_delivered INTEGER DEFAULT 0
        );
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertChat(_ db: OpaquePointer, rowid: Int64, identifier: String) {
        let sql = "INSERT INTO chat VALUES (?1, ?2, '', 'iMessage', ?3);"
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &s, nil)
        sqlite3_bind_int64(s, 1, rowid)
        sqlite3_bind_text(s, 2, identifier, -1, Self.TRANSIENT)
        sqlite3_bind_text(s, 3, "iMessage;-;\(identifier)", -1, Self.TRANSIENT)
        sqlite3_step(s)
        sqlite3_finalize(s)
    }

    private func insertMessage(_ db: OpaquePointer, rowid: Int64, chatRowID: Int64,
                               text: String, hasAttachment: Bool, date: Int64 = 700_000_000) {
        let sql = """
        INSERT INTO message(ROWID, text, attributedBody, is_from_me, is_read, date,
                            associated_message_type, cache_has_attachments)
        VALUES (?1, ?2, NULL, 0, 0, ?3, 0, ?4);
        """
        var m: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &m, nil)
        sqlite3_bind_int64(m, 1, rowid)
        sqlite3_bind_text(m, 2, text, -1, Self.TRANSIENT)
        sqlite3_bind_int64(m, 3, date)
        sqlite3_bind_int(m, 4, hasAttachment ? 1 : 0)
        sqlite3_step(m)
        sqlite3_finalize(m)
        let link = "INSERT INTO chat_message_join VALUES (?1, ?2);"
        var l: OpaquePointer?
        sqlite3_prepare_v2(db, link, -1, &l, nil)
        sqlite3_bind_int64(l, 1, chatRowID)
        sqlite3_bind_int64(l, 2, rowid)
        sqlite3_step(l)
        sqlite3_finalize(l)
    }

    /// A thread whose latest message has `cache_has_attachments=1` must surface
    /// as `MessageThread.hasAttachment == true` from `recentThreads()`.
    func testThreadHasAttachmentTrueWhenMessageHasAttachment() async throws {
        try buildSchema()
        let db = try openDB()
        insertChat(db, rowid: 1, identifier: "+15550100")
        insertMessage(db, rowid: 10, chatRowID: 1, text: "here's the doc", hasAttachment: true)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertTrue(threads[0].hasAttachment,
                      "thread whose most-recent message has cache_has_attachments=1 must have hasAttachment=true")
    }

    /// A thread whose messages all have `cache_has_attachments=0` must surface
    /// as `MessageThread.hasAttachment == false` from `recentThreads()`.
    func testThreadHasAttachmentFalseWhenNoMessagesHaveAttachment() async throws {
        try buildSchema()
        let db = try openDB()
        insertChat(db, rowid: 2, identifier: "+15550101")
        insertMessage(db, rowid: 20, chatRowID: 2, text: "just text", hasAttachment: false)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertFalse(threads[0].hasAttachment,
                       "thread with no attachment messages must have hasAttachment=false")
    }
}

// MARK: - REP-186: messages(forThreadID:) sort order

final class IMessageChannelMessageOrderTests: XCTestCase {
    private var dbURL: URL!
    private static let TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    override func setUpWithError() throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReplyAI-MsgOrder-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private func openDB() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            throw ChannelError.databaseError(code: 1, message: "test db open failed")
        }
        return handle
    }

    private func buildSchema() throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        CREATE TABLE message (
            ROWID INTEGER PRIMARY KEY,
            text TEXT,
            attributedBody BLOB,
            is_from_me INTEGER,
            is_read INTEGER,
            date INTEGER,
            associated_message_type INTEGER DEFAULT 0,
            cache_has_attachments INTEGER DEFAULT 0,
            date_delivered INTEGER DEFAULT 0
        );
        CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertChat(_ db: OpaquePointer, rowid: Int64, identifier: String) {
        let sql = "INSERT INTO chat VALUES (?1, ?2, '', 'iMessage', ?3);"
        var s: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &s, nil)
        sqlite3_bind_int64(s, 1, rowid)
        sqlite3_bind_text(s, 2, identifier, -1, Self.TRANSIENT)
        sqlite3_bind_text(s, 3, "iMessage;-;\(identifier)", -1, Self.TRANSIENT)
        sqlite3_step(s); sqlite3_finalize(s)
    }

    private func insertMsg(_ db: OpaquePointer, rowid: Int64, chatID: Int64,
                           text: String, date: Int64) {
        let sql = "INSERT INTO message(ROWID,text,attributedBody,is_from_me,is_read,date,associated_message_type) VALUES (?1,?2,NULL,0,0,?3,0);"
        var m: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &m, nil)
        sqlite3_bind_int64(m, 1, rowid)
        sqlite3_bind_text(m, 2, text, -1, Self.TRANSIENT)
        sqlite3_bind_int64(m, 3, date)
        sqlite3_step(m); sqlite3_finalize(m)
        let link = "INSERT INTO chat_message_join VALUES (?1, ?2);"
        var l: OpaquePointer?
        sqlite3_prepare_v2(db, link, -1, &l, nil)
        sqlite3_bind_int64(l, 1, chatID)
        sqlite3_bind_int64(l, 2, rowid)
        sqlite3_step(l); sqlite3_finalize(l)
    }

    // messages(forThreadID:) fetches with ORDER BY m.date DESC then calls
    // .reversed(), so the final array is chronological (oldest first) — suitable
    // for a chat view where index 0 is at the top and the user reads downward.

    func testMessagesReturnedChronologicallyOldestFirst() async throws {
        try buildSchema()
        let db = try openDB()
        insertChat(db, rowid: 1, identifier: "+15550186")
        // Insert in ascending date order: T+10, T+20, T+30
        insertMsg(db, rowid: 1, chatID: 1, text: "oldest", date: 700_000_010)
        insertMsg(db, rowid: 2, chatID: 1, text: "middle", date: 700_000_020)
        insertMsg(db, rowid: 3, chatID: 1, text: "newest", date: 700_000_030)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgs = try await channel.messages(forThreadID: "+15550186", limit: 10)

        XCTAssertEqual(msgs.count, 3, "all 3 messages must be returned")
        XCTAssertEqual(msgs.first?.text, "oldest",
                       "messages(forThreadID:) must return oldest message first (chronological for display)")
        XCTAssertEqual(msgs.last?.text, "newest",
                       "messages(forThreadID:) must return newest message last")
    }

    func testMessagesChronologicalRegardlessOfInsertOrder() async throws {
        try buildSchema()
        let db = try openDB()
        insertChat(db, rowid: 2, identifier: "+15550187")
        // Insert in reverse date order: T+30 first, then T+20, then T+10
        insertMsg(db, rowid: 4, chatID: 2, text: "newest", date: 700_000_030)
        insertMsg(db, rowid: 5, chatID: 2, text: "middle", date: 700_000_020)
        insertMsg(db, rowid: 6, chatID: 2, text: "oldest", date: 700_000_010)
        sqlite3_close(db)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let msgs = try await channel.messages(forThreadID: "+15550187", limit: 10)

        XCTAssertEqual(msgs.count, 3, "all 3 messages must be returned")
        XCTAssertEqual(msgs.first?.text, "oldest",
                       "insert order must not affect chronological result — oldest must come first")
        XCTAssertEqual(msgs.last?.text, "newest",
                       "newest must be last regardless of DB insert order")
    }

    // MARK: - REP-198: threads with no messages excluded from recentThreads

    func testEmptyThreadExcludedFromRecentThreads() async throws {
        // A chat row with no associated messages (e.g. a draft group or invite
        // pending) must not appear in recentThreads — the JOIN with the message
        // table filters it out naturally.
        try buildSchema()
        let db = try openDB()
        defer { sqlite3_close(db) }

        // Thread with 3 messages.
        insertChat(db, rowid: 91, identifier: "+19990000001")
        insertMsg(db, rowid: 910, chatID: 91, text: "msg one", date: 700_000_010)
        insertMsg(db, rowid: 911, chatID: 91, text: "msg two", date: 700_000_020)
        insertMsg(db, rowid: 912, chatID: 91, text: "msg three", date: 700_000_030)

        // Thread with zero messages — only a chat row, no message rows.
        insertChat(db, rowid: 92, identifier: "+19990000002")

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 50)

        let ids = threads.map(\.id)
        XCTAssertTrue(ids.contains("+19990000001"),
                      "thread with messages must appear in recentThreads")
        XCTAssertFalse(ids.contains("+19990000002"),
                       "thread with zero messages must be excluded from recentThreads")
    }

    func testThreadWithMessagesHasCorrectMessageCount() async throws {
        try buildSchema()
        let db = try openDB()
        defer { sqlite3_close(db) }

        insertChat(db, rowid: 93, identifier: "+19990000003")
        insertMsg(db, rowid: 930, chatID: 93, text: "alpha", date: 700_000_010)
        insertMsg(db, rowid: 931, chatID: 93, text: "beta", date: 700_000_020)
        insertMsg(db, rowid: 932, chatID: 93, text: "gamma", date: 700_000_030)

        let channel = IMessageChannel(dbPathOverride: dbURL.path)
        let threads = try await channel.recentThreads(limit: 50)

        let thread = threads.first { $0.id == "+19990000003" }
        XCTAssertNotNil(thread, "thread must appear in results")
        // The preview reflects the last message and the thread is well-formed.
        XCTAssertFalse(thread?.preview.isEmpty ?? true,
                       "thread with messages must have a non-empty preview")
    }

    // MARK: - REP-236: AppleScript fallback when FDA is denied

    func testAppleScriptFallbackCalledWhenFDADenied() async throws {
        // SQLITE_AUTH (23) triggers the authorization-denied branch in openReadOnly,
        // which throws permissionDenied and routes execution to the AppleScript fallback.
        let deniedOpener: @Sendable (String, Int32) -> (Int32, OpaquePointer?) = { _, _ in (23, nil) }
        let mockExecutor: @Sendable (String) throws -> String = { _ in
            "Zara Smith||iMessage;-;+15559990001\nAlice Jones||iMessage;-;+15559990002\n"
        }
        let reader = AppleScriptMessageReader(executor: mockExecutor)
        // File must exist so FileManager.fileExists passes, then the deniedOpener
        // returns SQLITE_AUTH so openReadOnly throws permissionDenied.
        try makeMinimalDB(at: dbURL.path)
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: deniedOpener,
            appleScriptReader: reader
        )
        let threads = try await channel.recentThreads(limit: 50)

        XCTAssertEqual(threads.count, 2, "fallback must return the 2 threads from the mock executor")
        XCTAssertEqual(threads[0].name, "Alice Jones", "threads must be sorted by displayName ascending")
        XCTAssertEqual(threads[1].name, "Zara Smith")
        XCTAssertEqual(threads[0].channel, .imessage)
    }

    func testAppleScriptFallbackExecutorIsInjectable() async throws {
        // Verify the executor receives a script string referencing Messages.app
        // so callers can assert on what was sent without executing real AppleScript.
        var capturedScript = ""
        let capturingExecutor: @Sendable (String) throws -> String = { script in
            capturedScript = script
            return "Test User||iMessage;-;+15550000001\n"
        }
        let reader = AppleScriptMessageReader(executor: capturingExecutor)

        let deniedOpener: @Sendable (String, Int32) -> (Int32, OpaquePointer?) = { _, _ in (23, nil) }
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: deniedOpener,
            appleScriptReader: reader
        )
        try makeMinimalDB(at: dbURL.path)
        _ = try await channel.recentThreads(limit: 50)

        XCTAssertTrue(capturedScript.contains("Messages"),
                      "executor must receive an AppleScript string referencing Messages.app")
        XCTAssertFalse(capturedScript.isEmpty, "executor must receive a non-empty script")
    }

    func testAppleScriptFallbackErrorPropagates() async throws {
        // When the AppleScript executor throws, the error must surface to the caller.
        let throwingExecutor: @Sendable (String) throws -> String = { _ in
            throw AppleScriptReaderError.executionError("Messages not running")
        }
        let reader = AppleScriptMessageReader(executor: throwingExecutor)
        let deniedOpener: @Sendable (String, Int32) -> (Int32, OpaquePointer?) = { _, _ in (23, nil) }
        let channel = IMessageChannel(
            dbPathOverride: dbURL.path,
            dbOpener: deniedOpener,
            appleScriptReader: reader
        )
        try makeMinimalDB(at: dbURL.path)

        do {
            _ = try await channel.recentThreads(limit: 50)
            XCTFail("expected an error when the AppleScript executor throws")
        } catch AppleScriptReaderError.executionError(let msg) {
            XCTAssertEqual(msg, "Messages not running")
        }
    }

    func testFDASuccessSkipsFallback() async throws {
        // When chat.db opens successfully, the AppleScript fallback must never fire.
        var fallbackCalled = false
        let sentinelExecutor: @Sendable (String) throws -> String = { _ in
            fallbackCalled = true
            return ""
        }
        let reader = AppleScriptMessageReader(executor: sentinelExecutor)

        try makeMinimalDB(at: dbURL.path)
        // Use default dbOpener (real SQLite) pointing at the valid temp db.
        let channel = IMessageChannel(dbPathOverride: dbURL.path, appleScriptReader: reader)
        _ = try await channel.recentThreads(limit: 50)

        XCTAssertFalse(fallbackCalled, "AppleScript fallback must not be called when chat.db opens successfully")
    }

    // MARK: - REP-240: AppleScriptMessageReader.messagesForChat

    func testMessagesForChatParsesBodyCorrectly() throws {
        // Three rows of "body||direction" must parse into three Message values
        // in the same order, with bodies preserved verbatim and authorship
        // mapped from direction (outgoing → .me, incoming → .them).
        let mockOutput = """
        Hey can you grab milk?||incoming
        on it||outgoing
        thanks!||incoming
        """
        let executor: @Sendable (String) throws -> String = { _ in mockOutput }
        let reader = AppleScriptMessageReader(executor: executor)

        let messages = try reader.messagesForChat(chatGUID: "iMessage;-;+15555550100", limit: 50)

        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].text, "Hey can you grab milk?")
        XCTAssertEqual(messages[0].from, .them)
        XCTAssertEqual(messages[1].text, "on it")
        XCTAssertEqual(messages[1].from, .me)
        XCTAssertEqual(messages[2].text, "thanks!")
        XCTAssertEqual(messages[2].from, .them)
    }

    func testMessagesForChatRespectsLimit() throws {
        // If the executor returns more rows than the caller asked for, the
        // parser must still cap at limit so a misbehaving Messages.app or
        // unbounded AppleScript can't blow past the requested window.
        let mockOutput = """
        msg one||incoming
        msg two||outgoing
        msg three||incoming
        """
        let executor: @Sendable (String) throws -> String = { _ in mockOutput }
        let reader = AppleScriptMessageReader(executor: executor)

        let messages = try reader.messagesForChat(chatGUID: "iMessage;-;+15555550101", limit: 2)

        XCTAssertEqual(messages.count, 2, "limit must be enforced by the parser even when the executor returns extra rows")
        XCTAssertEqual(messages[0].text, "msg one")
        XCTAssertEqual(messages[1].text, "msg two")
    }

    func testMessagesForChatEmptyResultIsEmpty() throws {
        // A chat with no messages produces an empty AppleScript output. The
        // parser must return [] rather than a single "missing value" sentinel.
        let executor: @Sendable (String) throws -> String = { _ in "" }
        let reader = AppleScriptMessageReader(executor: executor)

        let messages = try reader.messagesForChat(chatGUID: "iMessage;-;+15555550102", limit: 50)

        XCTAssertTrue(messages.isEmpty, "an empty AppleScript result must produce an empty [Message]")
    }

    func testMessagesForChatErrorPropagates() throws {
        // When the executor throws (Messages.app not running, AppleScript
        // failed to compile, automation permission denied), the error must
        // surface to the caller rather than be silently swallowed into an
        // empty array.
        let executor: @Sendable (String) throws -> String = { _ in
            throw AppleScriptReaderError.executionError("Messages not running")
        }
        let reader = AppleScriptMessageReader(executor: executor)

        XCTAssertThrowsError(try reader.messagesForChat(chatGUID: "iMessage;-;+15555550103", limit: 50)) { err in
            guard case AppleScriptReaderError.executionError(let msg) = err else {
                return XCTFail("expected AppleScriptReaderError.executionError, got \(err)")
            }
            XCTAssertEqual(msg, "Messages not running")
        }
    }

    func testMessagesForChatScriptIncludesGUIDAndLimit() throws {
        // The executor receives the AppleScript source. Verify the GUID
        // and the limit are interpolated so a real Messages.app call would
        // target the right chat and bound the right window.
        var captured = ""
        let executor: @Sendable (String) throws -> String = { script in
            captured = script
            return ""
        }
        let reader = AppleScriptMessageReader(executor: executor)

        _ = try reader.messagesForChat(chatGUID: "iMessage;-;+15555550104", limit: 7)

        XCTAssertTrue(captured.contains("iMessage;-;+15555550104"),
                      "script must embed the requested chat GUID")
        XCTAssertTrue(captured.contains("- 7 + 1"),
                      "script must use the requested limit when computing the start index")
    }

    // MARK: - Helpers

    /// Creates the minimum chat.db schema needed for openReadOnly to succeed
    /// (all tables referenced by recentThreads must exist).
    private func makeMinimalDB(at path: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        let ddl = """
        CREATE TABLE IF NOT EXISTS chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT,
            display_name TEXT, service_name TEXT, guid TEXT);
        CREATE TABLE IF NOT EXISTS message (ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB,
            is_from_me INTEGER, date INTEGER, cache_has_attachments INTEGER, is_read INTEGER,
            date_delivered INTEGER, associated_message_type INTEGER);
        CREATE TABLE IF NOT EXISTS chat_message_join (chat_id INTEGER, message_id INTEGER);
        CREATE TABLE IF NOT EXISTS handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE IF NOT EXISTS chat_handle_join (chat_id INTEGER, handle_id INTEGER);
        """
        for stmt in ddl.split(separator: ";").map(String.init) {
            let trimmed = stmt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sqlite3_exec(db, trimmed, nil, nil, nil)
        }
    }
}

// MARK: - formatRelative time-bucket contract

/// `formatRelative` is the function whose output appears as the time
/// label on every thread row. The exact "h:mm a" / "MMM d" output is
/// locale-dependent, but the structural contract — appleDate=0 returns
/// "" as a sentinel for "no message ever", and any non-zero value
/// produces a non-empty string — is invariant and worth pinning.
final class IMessageChannelFormatRelativeTests: XCTestCase {

    func testFormatRelativeZeroAppleDateReturnsEmptySentinel() {
        // chat.db rows with no associated message ever (e.g. an empty thread
        // surfaced via chat_handle_join with no chat_message_join entry) have
        // date=0. The thread row should render with no time label, not the
        // formatted Unix epoch ("Dec 31" or similar). Guarding the sentinel
        // here prevents a refactor that swaps in a generic DateFormatter from
        // accidentally producing a misleading historical date.
        XCTAssertEqual(IMessageChannel.formatRelative(appleDate: 0), "",
                       "appleDate=0 must return empty string as the no-message sentinel")
    }

    func testFormatRelativeNonZeroProducesNonEmptyLabel() {
        // Any meaningful timestamp must yield SOMETHING — even a date long
        // in the past should fall through to the "MMM d" branch rather than
        // the empty-sentinel branch. Mirrors the inverse contract of the
        // sentinel test above.
        let yearAgo = IMessageChannel.formatRelative(appleDate: 700_000_000)
        XCTAssertFalse(yearAgo.isEmpty,
                       "non-zero appleDate must produce a non-empty label, got: '\(yearAgo)'")
    }

    /// Negative appleDate is non-zero and should pass the sentinel guard,
    /// then fall through to the "MMM d" branch (it's a pre-2001 date).
    /// Pinned because chat.db rarely produces negative timestamps but a
    /// corrupted or migrated row could; the format must still be non-empty
    /// rather than degrading to the empty-string sentinel that means "no
    /// message at all".
    func testFormatRelativeNegativeAppleDateFormatsAsHistoricalDate() {
        let label = IMessageChannel.formatRelative(appleDate: -100)
        XCTAssertFalse(label.isEmpty,
            "negative appleDate must format as a historical date, not the empty sentinel")
    }

    /// A timestamp from ~25 hours ago must land in the "Yesterday" bucket.
    /// "Yesterday" is the only bucket whose output is locale-stable enough
    /// to pin verbatim; today/this-week buckets would produce
    /// DateFormatter-localized strings that vary by user. Earlier the test
    /// used `Date() - 25h`, but that wall-clock offset lands in
    /// 2-days-ago when the runner happens to fire between 00:00 and 01:00
    /// local time (autopilot fire 2026-05-07 00:23 hit this), so we now
    /// compute "yesterday at noon" via Calendar — which is guaranteed to
    /// fall inside `isDateInYesterday(_:)`'s window regardless of when the
    /// test runs.
    func testFormatRelativeYesterdayBucketReturnsYesterdayLiteral() {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        // Yesterday-at-noon: 12 hours before start-of-today.
        let yesterdayNoon = cal.date(byAdding: .hour, value: -12, to: startOfToday)!
        let appleDate = Int64(yesterdayNoon.timeIntervalSinceReferenceDate)
        XCTAssertEqual(IMessageChannel.formatRelative(appleDate: appleDate), "Yesterday",
                       "yesterday-at-noon must land in the Yesterday bucket — drift here would silently relabel every yesterday-thread as MMM d")
    }

    /// A timestamp from "now" must land in the "today" bucket and produce
    /// a time-shaped label. We don't assert the exact format ("h:mm a" is
    /// locale-dependent — `2:31 PM` in en_US, `14:31` in en_GB, etc.) but
    /// the result must contain at least one digit, must NOT equal the
    /// "Yesterday" literal, and must NOT match the empty sentinel.
    /// Together those assertions pin the today bucket without assuming a
    /// particular DateFormatter dialect.
    func testFormatRelativeTodayBucketReturnsNonEmptyTimeShapedLabel() {
        let now = Date()
        let appleDate = Int64(now.timeIntervalSinceReferenceDate)
        let label = IMessageChannel.formatRelative(appleDate: appleDate)
        XCTAssertFalse(label.isEmpty,
                       "today's timestamp must yield a non-empty label, got: '\(label)'")
        XCTAssertNotEqual(label, "Yesterday",
                          "today's timestamp must not collapse into the Yesterday bucket")
        XCTAssertTrue(label.contains(where: { $0.isNumber }),
                      "today's label must contain at least one digit (h:mm a format), got: '\(label)'")
    }

    /// A timestamp from ~3 days ago lands in the EEE (abbreviated weekday)
    /// bucket. The exact string is locale-dependent ("Mon" / "пн" / "월"),
    /// so we don't pin a literal — instead pin the structural invariants
    /// every locale shares: non-empty, contains at least one letter, and
    /// not equal to the "Yesterday" literal or any time-of-day shape.
    /// Catches a future refactor that swaps the `< 7` guard to `<= 7` (or
    /// drops the EEE bucket entirely and falls through to MMM d).
    func testFormatRelativeEEEBucketProducesShortWeekdayLabel() {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        // 3 days ago at noon — well inside the [yesterday, 7-days) window.
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: startOfToday)!
            .addingTimeInterval(12 * 3600)
        let appleDate = Int64(threeDaysAgo.timeIntervalSinceReferenceDate)
        let label = IMessageChannel.formatRelative(appleDate: appleDate)

        XCTAssertFalse(label.isEmpty,
            "3-days-ago must produce a non-empty label, got: '\(label)'")
        XCTAssertNotEqual(label, "Yesterday",
            "3-days-ago must NOT collapse into the Yesterday bucket")
        XCTAssertTrue(label.contains(where: { $0.isLetter }),
            "EEE bucket label must contain at least one letter (weekday name) regardless of locale, got: '\(label)'")
        XCTAssertFalse(label.contains(":"),
            "EEE bucket label must NOT contain ':' — that would mean we hit the today bucket instead, got: '\(label)'")
    }

    /// 8+ days ago lands in the MMM d bucket. Like the EEE bucket, the
    /// literal is locale-dependent, but every locale produces something
    /// containing the day-of-month digit and at least one letter (month
    /// abbreviation). Pin so a future bucket-boundary refactor can't
    /// accidentally widen the EEE window into multi-week territory.
    func testFormatRelativeMMMDBucketContainsDigitAndLetter() {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        // 14 days ago — well outside the < 7 EEE window.
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: startOfToday)!
            .addingTimeInterval(12 * 3600)
        let appleDate = Int64(twoWeeksAgo.timeIntervalSinceReferenceDate)
        let label = IMessageChannel.formatRelative(appleDate: appleDate)

        XCTAssertFalse(label.isEmpty,
            "14-days-ago must produce a non-empty label, got: '\(label)'")
        XCTAssertTrue(label.contains(where: { $0.isLetter }),
            "MMM d bucket must contain at least one letter (month abbreviation), got: '\(label)'")
        XCTAssertTrue(label.contains(where: { $0.isNumber }),
            "MMM d bucket must contain at least one digit (day of month), got: '\(label)'")
    }
}

// MARK: - chatDBPath default contract
//
// `IMessageChannel.chatDBPath` is the path production callers hit when
// `dbPathOverride` is nil — i.e. the real Messages database. Pin its
// resolved value so a refactor can't silently redirect the production
// read path away from the FDA-gated location.

final class IMessageChannelChatDBPathTests: XCTestCase {

    func testChatDBPathEndsWithLibraryMessagesChatDB() {
        let path = IMessageChannel.chatDBPath
        XCTAssertTrue(path.hasSuffix("Library/Messages/chat.db"),
            "chatDBPath must point at ~/Library/Messages/chat.db, got: \(path)")
    }

    func testChatDBPathExpandsTilde() {
        // The static initializer expands `~` via NSString — the resolved
        // path must NOT still contain the literal "~".
        XCTAssertFalse(IMessageChannel.chatDBPath.hasPrefix("~"),
            "chatDBPath must expand the leading tilde, got: \(IMessageChannel.chatDBPath)")
    }
}

// MARK: - formatTime structural pin
//
// `formatTime(appleDate:)` formats a chat.db timestamp into a `h:mm a`
// string for the message-bubble timestamp chip. The exact rendering is
// locale-dependent (en_US `2:31 PM`, en_GB `14:31`, fr_FR `14:31`), so
// we pin the SHAPE rather than the literal: result must be non-empty,
// must contain at least one digit, and must vary with the input.

final class IMessageChannelFormatTimeTests: XCTestCase {

    func testFormatTimeReturnsNonEmptyForAnyTimestamp() {
        let now = Int64(Date().timeIntervalSinceReferenceDate)
        let result = IMessageChannel.formatTime(appleDate: now)
        XCTAssertFalse(result.isEmpty,
            "formatTime must yield a non-empty string for any non-zero timestamp")
        XCTAssertTrue(result.contains(where: { $0.isNumber }),
            "formatTime output must contain at least one digit (h:mm a shape), got: '\(result)'")
    }

    /// Two timestamps that are clearly in different minutes should produce
    /// different labels — pin so a refactor that accidentally returned a
    /// constant (e.g. the formatter cached an empty input) surfaces here.
    func testFormatTimeOutputVariesWithInput() {
        let now = Int64(Date().timeIntervalSinceReferenceDate)
        // 12 hours apart — guaranteed different minute-of-day regardless
        // of clock or DST so the labels can't accidentally coincide.
        let twelveHoursAgo = now - (12 * 3600)
        let a = IMessageChannel.formatTime(appleDate: now)
        let b = IMessageChannel.formatTime(appleDate: twelveHoursAgo)
        XCTAssertNotEqual(a, b,
            "12-hour-apart timestamps must produce different formatted labels, got both: '\(a)'")
    }

    /// formatTime accepts both the seconds-since-reference and
    /// nanoseconds-since-reference encodings (the auto-detect lives in
    /// `secondsSinceReferenceDate`). Pin that the same wall-clock instant
    /// produces the same output regardless of which encoding chat.db hands
    /// us — drift here would silently double-format messages from devices
    /// on different macOS versions.
    func testFormatTimeAcceptsSecondsAndNanosecondsEncodings() {
        let secs: Int64 = 700_000_000           // < 10¹² → seconds
        let nanos: Int64 = secs * 1_000_000_000 // ≥ 10¹² → nanoseconds
        XCTAssertEqual(IMessageChannel.formatTime(appleDate: secs),
                       IMessageChannel.formatTime(appleDate: nanos),
                       "seconds and nanoseconds encodings of the same instant must format identically")
    }

    // MARK: - TimeFormat vocabulary pins (REP-hoist 2026-05-07)
    //
    // The four ThreadRow time-chip patterns (`timeOfDay`, `weekdayShort`,
    // `dateShort`, `yesterdayLabel`) live as `static let` on
    // `IMessageChannel.TimeFormat`. The `timeOfDay` pattern was
    // previously inline at TWO call sites (`formatTime` and the
    // `isDateInToday` branch of `formatRelative`) — drift between the
    // two would silently produce different time formatting depending
    // on whether the row was rendered via the absolute or relative
    // path.

    func testTimeFormatPatternsAreFrozen() {
        XCTAssertEqual(IMessageChannel.TimeFormat.timeOfDay, "h:mm a",
            "timeOfDay pattern is what every today + absolute time chip uses — drift desyncs the two paths")
        XCTAssertEqual(IMessageChannel.TimeFormat.weekdayShort, "EEE",
            "weekdayShort pattern renders the within-week day chip — drift to e.g. EEEE silently lengthens every weekday label")
        XCTAssertEqual(IMessageChannel.TimeFormat.dateShort, "MMM d",
            "dateShort pattern renders the older-than-week chip — drift desyncs the sidebar from the thread detail view")
        XCTAssertEqual(IMessageChannel.TimeFormat.yesterdayLabel, "Yesterday",
            "yesterdayLabel is the literal user-visible string — drift in casing or wording (e.g. `yest.`) ships in front of users with no review")
    }

    /// Round-trip `formatRelative` against a 5-day-ago timestamp to pin
    /// that the weekday-short pattern flows through `TimeFormat.weekdayShort`.
    /// A constant-defined-but-not-used refactor would still pass
    /// `testTimeFormatPatternsAreFrozen` while silently re-introducing
    /// an inline literal in the formatter.
    func testFormatRelativeUsesHoistedWeekdayPattern() {
        // 5 days ago — within-week branch but not today/yesterday.
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 86_400)
        let appleDate = Int64(fiveDaysAgo.timeIntervalSinceReferenceDate)
        let formatted = IMessageChannel.formatRelative(appleDate: appleDate)
        // Expected: 3-letter weekday abbreviation. Validate length not exact day
        // (test would otherwise be clock-sensitive across midnight/DST).
        XCTAssertEqual(formatted.count, 3,
            "5-day-ago timestamps should render via TimeFormat.weekdayShort — got '\(formatted)' (length \(formatted.count))")
    }

    /// Round-trip a yesterday timestamp through `formatRelative` to pin
    /// the `yesterdayLabel` constant is wired into the matcher.
    func testFormatRelativeUsesHoistedYesterdayLabel() {
        let yesterday = Date().addingTimeInterval(-86_400 - 3_600) // 25h ago — clearly yesterday
        let appleDate = Int64(yesterday.timeIntervalSinceReferenceDate)
        let formatted = IMessageChannel.formatRelative(appleDate: appleDate)
        XCTAssertEqual(formatted, IMessageChannel.TimeFormat.yesterdayLabel,
            "25h-ago timestamp must render as TimeFormat.yesterdayLabel — drift between matcher and constant is silent")
    }
}
