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

    /// Opening a directory as a db reaches sqlite3_open_v2 (fileExists returns
    /// true for directories) and produces either databaseError or permissionDenied
    /// — never unavailable — because we passed the fileExists guard.
    func testOpenFailureSurfacesDatabaseOrPermissionError() async {
        let dirURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replyai-dbtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let channel = IMessageChannel(dbPathOverride: dirURL.path)
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
