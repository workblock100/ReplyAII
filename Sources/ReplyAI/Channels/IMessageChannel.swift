import Foundation
import SQLite3

/// Reads threads + messages directly out of `~/Library/Messages/chat.db`.
///
/// Access requires Full Disk Access. The bundle must be non-sandboxed
/// (see `Resources/ReplyAI.entitlements`) and listed in System Settings →
/// Privacy & Security → Full Disk Access.
///
/// Schema quirks we handle:
/// - `message.date` is either seconds or nanoseconds since 2001-01-01.
///   Modern macOS (≥10.13) uses nanoseconds; we autodetect.
/// - `message.text` is NULL for rich-content rows (tapbacks, attachments,
///   newer rich-text). We skip rows without plain text in this first pass.
/// - `chat.service_name` is "iMessage" or "SMS"; map to our Channel enum.
/// - Thread name: prefer `chat.display_name` for groups; otherwise the
///   first participant's handle. Contacts-based resolution is deferred
///   until we request that permission.
struct IMessageChannel: ChannelService {
    static let chatDBPath: String = {
        (NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath as String)
    }()

    // SQLite wants transient text to live long enough for bind+step; use
    // this marker like Apple's own samples.
    private static let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            c.ROWID AS chat_rowid,
            c.chat_identifier,
            COALESCE(c.display_name, '') AS display_name,
            COALESCE(c.service_name, 'iMessage') AS service_name,
            (
                SELECT h.id FROM handle h
                JOIN chat_handle_join chj ON chj.handle_id = h.ROWID
                WHERE chj.chat_id = c.ROWID
                ORDER BY h.ROWID ASC
                LIMIT 1
            ) AS first_handle,
            (
                SELECT m.text FROM message m
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                WHERE cmj.chat_id = c.ROWID AND m.text IS NOT NULL AND length(m.text) > 0
                ORDER BY m.date DESC
                LIMIT 1
            ) AS last_text,
            (
                SELECT m.date FROM message m
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                WHERE cmj.chat_id = c.ROWID
                ORDER BY m.date DESC
                LIMIT 1
            ) AS last_date,
            (
                SELECT COUNT(*) FROM chat_message_join cmj2
                WHERE cmj2.chat_id = c.ROWID
            ) AS msg_count,
            (
                SELECT COUNT(*) FROM message m2
                JOIN chat_message_join cmj3 ON cmj3.message_id = m2.ROWID
                WHERE cmj3.chat_id = c.ROWID AND m2.is_from_me = 0 AND COALESCE(m2.is_read, 0) = 0
            ) AS unread_count
        FROM chat c
        WHERE EXISTS (SELECT 1 FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID)
        ORDER BY last_date DESC NULLS LAST
        LIMIT ?1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChannelError.query(lastError(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var threads: [MessageThread] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chatID       = Self.text(stmt, 1) ?? "unknown"
            let displayName  = Self.text(stmt, 2) ?? ""
            let service      = Self.text(stmt, 3) ?? "iMessage"
            let firstHandle  = Self.text(stmt, 4) ?? ""
            let lastText     = Self.text(stmt, 5) ?? ""
            let lastDateRaw  = sqlite3_column_int64(stmt, 6)
            let msgCount     = Int(sqlite3_column_int(stmt, 7))
            let unread       = Int(sqlite3_column_int(stmt, 8))

            let name = displayName.isEmpty ? (firstHandle.isEmpty ? chatID : firstHandle) : displayName
            let time = Self.formatRelative(appleDate: lastDateRaw)
            let channel: Channel = (service.lowercased() == "sms") ? .sms : .imessage

            threads.append(MessageThread(
                id: chatID.isEmpty ? "chat_\(sqlite3_column_int64(stmt, 0))" : chatID,
                channel: channel,
                name: name,
                avatar: Self.avatarInitial(for: name),
                preview: lastText,
                time: time,
                unread: unread,
                pinned: false,
                contextCount: msgCount,
                contextSummary: nil
            ))
        }
        return threads
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            m.text,
            m.is_from_me,
            m.date
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE c.chat_identifier = ?1 AND m.text IS NOT NULL AND length(m.text) > 0
        ORDER BY m.date DESC
        LIMIT ?2;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChannelError.query(lastError(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var out: [Message] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let text   = Self.text(stmt, 0) ?? ""
            let fromMe = sqlite3_column_int(stmt, 1) != 0
            let date   = sqlite3_column_int64(stmt, 2)
            out.append(Message(
                from: fromMe ? .me : .them,
                text: text,
                time: Self.formatTime(appleDate: date)
            ))
        }
        return out.reversed()  // oldest → newest for thread stream
    }

    // MARK: - SQLite plumbing

    private func openReadOnly() throws -> OpaquePointer {
        let path = Self.chatDBPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw ChannelError.unavailable("No Messages database found at \(path).")
        }
        // Try opening; the common failure mode is FDA-denied, which reads
        // as "unable to open database file".
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error \(rc)"
            sqlite3_close(db)
            if msg.lowercased().contains("authorization") || msg.lowercased().contains("unable to open") {
                throw ChannelError.permissionDenied(hint: """
                    ReplyAI can't read your Messages database yet. Grant Full Disk Access in \
                    System Settings → Privacy & Security → Full Disk Access, then try again.
                    """)
            }
            throw ChannelError.unavailable("Can't open chat.db: \(msg)")
        }
        return db!
    }

    private func lastError(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Column helpers

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: raw)
    }

    // MARK: - Date handling

    /// macOS stores message.date in either seconds or nanoseconds since
    /// 2001-01-01. Nanosecond encoding is larger than ~10¹⁵ for anything
    /// after 2001.
    static func secondsSinceReferenceDate(appleDate: Int64) -> TimeInterval {
        if appleDate > 1_000_000_000_000 {   // nanoseconds
            return TimeInterval(appleDate) / 1_000_000_000
        }
        return TimeInterval(appleDate)
    }

    static func formatTime(appleDate: Int64) -> String {
        let date = Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate(appleDate: appleDate))
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    static func formatRelative(appleDate: Int64) -> String {
        guard appleDate != 0 else { return "" }
        let date = Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate(appleDate: appleDate))
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            let f = DateFormatter(); f.dateFormat = "EEE"   // Mon
            return f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    static func avatarInitial(for name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return "?" }
        if first == "+" || first == "(" { return "☎" }
        return String(first).uppercased()
    }
}
