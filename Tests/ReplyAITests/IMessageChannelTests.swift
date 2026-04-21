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
            date INTEGER
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
        let msgSQL = "INSERT INTO message VALUES (?1, ?2, NULL, ?3, 0, ?4);"
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

    private func insertMessageWithAttributedBody(
        rowid: Int64, chatRowID: Int64, attributedBody: Data,
        fromMe: Bool, date: Int64
    ) throws {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let msgSQL = "INSERT INTO message VALUES (?1, NULL, ?2, ?3, 0, ?4);"
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
