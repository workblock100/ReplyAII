import Foundation
import SQLite3

/// In-memory SQLite FTS5 index over live message bodies + thread names.
/// Rebuilt on each successful sync — cheap enough for 50 × 40 rows, and
/// avoids the staleness headaches of a disk-persistent index whose
/// writes race the FSEvents watcher. Move to disk if this ever shows up
/// in a profile.
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

    init() {
        open()
        createSchema()
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

        let namesByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.name) })

        let insertSQL = """
        INSERT INTO messages_fts (thread_id, thread_name, sender, text, time)
        VALUES (?1, ?2, ?3, ?4, ?5);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for (threadID, messages) in messagesByThread {
            let threadName = namesByID[threadID] ?? threadID
            for m in messages {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, threadID,   -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, threadName, -1, Self.SQLITE_TRANSIENT)
                let sender = m.from == .me ? "me" : threadName
                sqlite3_bind_text(stmt, 3, sender,     -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, m.text,     -1, Self.SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, m.time,     -1, Self.SQLITE_TRANSIENT)
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
        INSERT INTO messages_fts (thread_id, thread_name, sender, text, time)
        VALUES (?1, ?2, ?3, ?4, ?5);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for m in messages {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, thread.id,   -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, thread.name, -1, Self.SQLITE_TRANSIENT)
            let sender = m.from == .me ? "me" : thread.name
            sqlite3_bind_text(stmt, 3, sender,      -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, m.text,      -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, m.time,      -1, Self.SQLITE_TRANSIENT)
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db else { return [] }

        let fts = Self.ftsQuery(from: trimmed)
        let sql = """
        SELECT thread_id, thread_name, sender, text, time
        FROM messages_fts
        WHERE messages_fts MATCH ?1
        ORDER BY rank
        LIMIT ?2;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, fts, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

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

    private func open() {
        var handle: OpaquePointer?
        // :memory: database — fresh state every app launch.
        guard sqlite3_open_v2(":memory:", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
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
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Query translation

    /// Translate a user's free-form input into an FTS5 MATCH expression:
    /// - Split on whitespace
    /// - Append `*` to each token for prefix matching ("dinner" → "dinner*")
    /// - Quote any token with FTS-reserved characters
    /// - Join 2+ tokens with explicit `AND` so multi-word queries match
    ///   both words anywhere in the document, not as an adjacent phrase
    static func ftsQuery(from input: String) -> String {
        let raw = input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !raw.isEmpty else { return "" }
        let tokens = raw.map { token -> String in
            let safe = token.replacingOccurrences(of: "\"", with: "")
            // Quote if it contains anything an FTS5 tokenizer would
            // gag on; otherwise append `*` for prefix search.
            let specialSet = CharacterSet(charactersIn: "()\"*:")
            let hasSpecial = safe.rangeOfCharacter(from: specialSet) != nil
            if hasSpecial { return "\"\(safe)\"" }
            return "\(safe)*"
        }
        return tokens.count == 1 ? tokens[0] : tokens.joined(separator: " AND ")
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: raw)
    }
}
