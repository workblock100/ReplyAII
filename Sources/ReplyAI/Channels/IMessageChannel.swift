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

    /// Optional name-resolver that translates phone/email handles to
    /// contact names. Injected from the ViewModel so we don't couple
    /// channel code to Contacts framework directly.
    let nameFor: @Sendable (String) -> String?

    /// Override path for the Messages database. Nil means the real
    /// `~/Library/Messages/chat.db`. Tests point this at a temp file
    /// so the query layer can be exercised without Full Disk Access.
    let dbPathOverride: String?

    init(
        nameFor: @escaping @Sendable (String) -> String? = { _ in nil },
        dbPathOverride: String? = nil
    ) {
        self.nameFor = nameFor
        self.dbPathOverride = dbPathOverride
    }

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
                SELECT m.ROWID FROM message m
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                WHERE cmj.chat_id = c.ROWID
                ORDER BY m.date DESC
                LIMIT 1
            ) AS last_msg_rowid,
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
            ) AS unread_count,
            COALESCE(c.guid, '') AS chat_guid
        FROM chat c
        WHERE EXISTS (SELECT 1 FROM chat_message_join cmj WHERE cmj.chat_id = c.ROWID)
        ORDER BY last_date DESC NULLS LAST
        LIMIT ?1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChannelError.query(lastError(db))
        }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        struct Pending {
            let chatID: String
            let name: String
            let channel: Channel
            let lastMsgRowID: Int64
            let lastDateRaw: Int64
            let msgCount: Int
            let unread: Int
            let chatGUID: String?
        }

        var pending: [Pending] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chatID       = Self.text(stmt, 1) ?? "unknown"
            let displayName  = Self.text(stmt, 2) ?? ""
            let service      = Self.text(stmt, 3) ?? "iMessage"
            let firstHandle  = Self.text(stmt, 4) ?? ""
            let lastRow      = sqlite3_column_int64(stmt, 5)
            let lastDateRaw  = sqlite3_column_int64(stmt, 6)
            let msgCount     = Int(sqlite3_column_int(stmt, 7))
            let unread       = Int(sqlite3_column_int(stmt, 8))
            let guid         = Self.text(stmt, 9) ?? ""

            let resolvedName: String = {
                if !displayName.isEmpty { return displayName }
                if !firstHandle.isEmpty, let contact = nameFor(firstHandle) { return contact }
                return firstHandle.isEmpty ? chatID : firstHandle
            }()

            let channel: Channel = (service.lowercased() == "sms") ? .sms : .imessage

            pending.append(Pending(
                chatID: chatID.isEmpty ? "chat_\(sqlite3_column_int64(stmt, 0))" : chatID,
                name: resolvedName,
                channel: channel,
                lastMsgRowID: lastRow,
                lastDateRaw: lastDateRaw,
                msgCount: msgCount,
                unread: unread,
                chatGUID: guid.isEmpty ? nil : guid
            ))
        }
        sqlite3_finalize(stmt)

        // Resolve each row's preview text — prefer `text`, fall back to
        // a best-effort decode of `attributedBody`, else a neutral hint.
        var out: [MessageThread] = []
        for p in pending {
            let preview = previewText(db: db, messageRowID: p.lastMsgRowID) ?? "[non-text message]"
            out.append(MessageThread(
                id: p.chatID,
                channel: p.channel,
                name: p.name,
                avatar: Self.avatarInitial(for: p.name),
                preview: preview,
                time: Self.formatRelative(appleDate: p.lastDateRaw),
                unread: p.unread,
                pinned: false,
                contextCount: p.msgCount,
                contextSummary: nil,
                chatGUID: p.chatGUID
            ))
        }
        return out
    }

    /// Pull plain-text preview for one message, trying `text` first and
    /// `attributedBody` as a fallback. Returns nil only if both fail.
    private func previewText(db: OpaquePointer, messageRowID: Int64) -> String? {
        let sql = "SELECT text, attributedBody FROM message WHERE ROWID = ?1 LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, messageRowID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        if let t = Self.text(stmt, 0), !t.isEmpty { return t }

        if sqlite3_column_type(stmt, 1) == SQLITE_BLOB,
           let raw = sqlite3_column_blob(stmt, 1) {
            let len = Int(sqlite3_column_bytes(stmt, 1))
            let data = Data(bytes: raw, count: len)
            return AttributedBodyDecoder.extractText(from: data)
        }
        return nil
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            m.ROWID,
            m.text,
            m.attributedBody,
            m.is_from_me,
            m.date
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE c.chat_identifier = ?1
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
            let rowID   = sqlite3_column_int64(stmt, 0)
            let textCol = Self.text(stmt, 1)
            let decoded: String? = {
                if let t = textCol, !t.isEmpty { return t }
                if sqlite3_column_type(stmt, 2) == SQLITE_BLOB,
                   let raw = sqlite3_column_blob(stmt, 2) {
                    let len = Int(sqlite3_column_bytes(stmt, 2))
                    return AttributedBodyDecoder.extractText(from: Data(bytes: raw, count: len))
                }
                return nil
            }()
            guard let body = decoded, !body.isEmpty else { continue }

            let fromMe = sqlite3_column_int(stmt, 3) != 0
            let date   = sqlite3_column_int64(stmt, 4)
            out.append(Message(
                from: fromMe ? .me : .them,
                text: body,
                time: Self.formatTime(appleDate: date),
                rowID: rowID
            ))
        }
        return out.reversed()  // oldest → newest for thread stream
    }

    func newIncomingMessages(forThreadID id: String, sinceRowID: Int64) async throws -> [Message] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            m.ROWID,
            m.text,
            m.attributedBody,
            m.date
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE c.chat_identifier = ?1
          AND m.ROWID > ?2
          AND COALESCE(m.is_from_me, 0) = 0
        ORDER BY m.ROWID ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChannelError.query(lastError(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, sinceRowID)

        var out: [Message] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID   = sqlite3_column_int64(stmt, 0)
            let textCol = Self.text(stmt, 1)
            let decoded: String? = {
                if let t = textCol, !t.isEmpty { return t }
                if sqlite3_column_type(stmt, 2) == SQLITE_BLOB,
                   let raw = sqlite3_column_blob(stmt, 2) {
                    let len = Int(sqlite3_column_bytes(stmt, 2))
                    return AttributedBodyDecoder.extractText(from: Data(bytes: raw, count: len))
                }
                return nil
            }()
            guard let body = decoded, !body.isEmpty else { continue }

            let date = sqlite3_column_int64(stmt, 3)
            out.append(Message(
                from: .them,
                text: body,
                time: Self.formatTime(appleDate: date),
                rowID: rowID
            ))
        }
        return out
    }

    // MARK: - SQLite plumbing

    private func openReadOnly() throws -> OpaquePointer {
        let path = dbPathOverride ?? Self.chatDBPath
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
