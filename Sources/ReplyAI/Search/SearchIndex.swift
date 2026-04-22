import Foundation
import SQLite3

/// SQLite FTS5 index over live message bodies + thread names.
/// Supports both in-memory (tests, default) and file-backed (production)
/// modes. File-backed mode survives app restarts so the first post-launch
/// search does not block on a full inbox rebuild.
actor SearchIndex {
    struct Result: Hashable, Sendable {
        let threadID: String
        let threadName: String
        let senderName: String?
        let text: String
        let time: String
    }

    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    /// - Parameter databaseURL: Path for the on-disk SQLite file.
    ///   Pass `nil` (the default) for an in-memory database — suitable for
    ///   tests where isolation matters more than persistence.
    init(databaseURL: URL? = nil) {
        open(url: databaseURL)
        createSchema()
    }

    /// Convenience URL pointing to the shared app-support search database.
    static func productionDatabaseURL() -> URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport?.appendingPathComponent("ReplyAI", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/ReplyAI", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("search.db")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Public API

    /// Wipe and repopulate the index. Fast — we're running against an
    /// in-memory page cache.
    func rebuild(from messagesByThread: [String: [Message]], threads: [MessageThread]) {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM messages_fts", nil, nil, nil)

        let namesByID    = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.name) })
        let channelsByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.channel.rawValue) })

        let insertSQL = """
        INSERT INTO messages_fts (thread_id, thread_name, sender, text, time, channel)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for (threadID, messages) in messagesByThread {
            let threadName = namesByID[threadID] ?? threadID
            let channel    = channelsByID[threadID] ?? ""
            for m in messages {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, threadID,   -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, threadName, -1, Self.SQLITE_TRANSIENT)
                let sender = m.from == .me ? "me" : threadName
                sqlite3_bind_text(stmt, 3, sender,     -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, m.text,     -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, m.time,     -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 6, channel,    -1, Self.SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    /// Remove all index rows for a thread. Called when a thread is archived
    /// so it no longer appears in search results.
    func delete(threadID: String) {
        guard let db else { return }
        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM messages_fts WHERE thread_id = ?1;", -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, threadID, -1, Self.SQLITE_TRANSIENT)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)
    }

    /// Replace the index rows for a single thread. Used on the hot
    /// path — a watcher fire brings in one updated thread at a time,
    /// and re-running a full `rebuild` per fire is O(n) in the whole
    /// inbox. FTS5 has no `INSERT OR REPLACE` semantics keyed by an
    /// application column, so we delete + insert under one transaction.
    func upsert(thread: MessageThread, messages: [Message]) {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)

        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM messages_fts WHERE thread_id = ?1;", -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, thread.id, -1, Self.SQLITE_TRANSIENT)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)

        let insertSQL = """
        INSERT INTO messages_fts (thread_id, thread_name, sender, text, time, channel)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        let channelVal = thread.channel.rawValue
        for m in messages {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, thread.id,   -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, thread.name, -1, Self.SQLITE_TRANSIENT)
            let sender = m.from == .me ? "me" : thread.name
            sqlite3_bind_text(stmt, 3, sender,      -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, m.text,      -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, m.time,      -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, channelVal,  -1, Self.SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        if !messages.isEmpty {
            Stats.shared.incrementIndexed(channel: thread.channel, count: messages.count)
        }
    }

    /// FTS5 match query. Empty input returns an empty array. The caller
    /// is expected to debounce UI input.
    func search(_ query: String, limit: Int = 20) -> [Result] {
        search(query: query, channel: nil, limit: limit)
    }

    /// FTS5 match query with optional per-channel filter (REP-080).
    /// When `channel` is non-nil, only rows indexed for that channel are returned.
    /// The `channel` column is UNINDEXED so the filter is a post-MATCH WHERE clause,
    /// not a full-text search — this is safe and efficient for small result sets.
    func search(query: String, channel: Channel?, limit: Int = 20) -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db else { return [] }

        let fts = Self.ftsQuery(from: trimmed)
        guard !fts.isEmpty else { return [] }

        let sql: String
        if channel != nil {
            sql = """
            SELECT thread_id, thread_name, sender, text, time
            FROM messages_fts
            WHERE messages_fts MATCH ?1
            AND channel = ?2
            ORDER BY rank
            LIMIT ?3;
            """
        } else {
            sql = """
            SELECT thread_id, thread_name, sender, text, time
            FROM messages_fts
            WHERE messages_fts MATCH ?1
            ORDER BY rank
            LIMIT ?2;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, fts, -1, Self.SQLITE_TRANSIENT)
        if let ch = channel {
            sqlite3_bind_text(stmt, 2, ch.rawValue, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }

        var results: [Result] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Result(
                threadID:   Self.text(stmt, 0) ?? "",
                threadName: Self.text(stmt, 1) ?? "",
                senderName: Self.text(stmt, 2),
                text:       Self.text(stmt, 3) ?? "",
                time:       Self.text(stmt, 4) ?? ""
            ))
        }
        return results
    }

    // MARK: - Setup

    private func open(url: URL?) {
        var handle: OpaquePointer?
        let path = url?.path ?? ":memory:"
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            return
        }
        self.db = handle
    }

    private func createSchema() {
        guard let db else { return }
        let sql = """
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
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Query translation

    /// Translate a user's free-form input into an FTS5 MATCH expression.
    ///
    /// Sanitization (REP-092):
    ///   - Strip double-quotes (prevent unclosed phrase literals)
    ///   - Strip hyphens (bare `-` confuses FTS5's phrase-boundary parser)
    ///   - Skip tokens that collapse to empty after stripping
    ///   - Wrap remaining FTS5 syntax characters `()*:` in phrase quotes
    ///   - Otherwise append `*` for prefix matching
    ///
    /// Multi-word queries join tokens with explicit `AND` so both words must
    /// appear somewhere in the document (not as an adjacent phrase), giving
    /// better recall for inbox search.
    static func ftsQuery(from input: String) -> String {
        let raw = input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !raw.isEmpty else { return "" }
        let tokens: [String] = raw.compactMap { token in
            var safe = token.replacingOccurrences(of: "\"", with: "")
            safe = safe.replacingOccurrences(of: "-", with: "")
            guard !safe.isEmpty else { return nil }
            let specialSet = CharacterSet(charactersIn: "()*:")
            let hasSpecial = safe.rangeOfCharacter(from: specialSet) != nil
            if hasSpecial { return "\"\(safe)\"" }
            return "\(safe)*"
        }
        guard !tokens.isEmpty else { return "" }
        return tokens.count == 1 ? tokens[0] : tokens.joined(separator: " AND ")
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: raw)
    }
}
