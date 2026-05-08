import Foundation
import SQLite3

/// SQLite FTS5 index over live message bodies + thread names.
/// Supports both in-memory (tests, default) and file-backed (production)
/// modes. File-backed mode survives app restarts so the first post-launch
/// search does not block on a full inbox rebuild.
actor SearchIndex {
    /// One row returned by the FTS5 search. `threadID` is what the UI
    /// uses to navigate when the user picks a result; `threadName` and
    /// `senderName` populate the row's two-line header; `text` is the
    /// raw matched body so the palette can render something when
    /// `snippet` is nil (which happens for empty-query browses where no
    /// terms were matched).
    struct Result: Hashable, Sendable {
        let threadID: String
        let threadName: String
        let senderName: String?
        let text: String
        let time: String
        /// FTS5 snippet with «matched» terms highlighted, nil when query was empty.
        let snippet: String?
    }

    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    /// SQL statement vocabulary. The INSERT and per-thread DELETE used to
    /// be re-typed inline at every call site (rebuild + upsert + clear +
    /// delete). Drift between the writers — e.g. one INSERT bound 6
    /// columns, the other 5; or one DELETE missed the WHERE clause and
    /// nuked the whole index — is the kind of silent corruption that's
    /// hard to spot in code review and surfaces as "search returns
    /// nothing" or "search returns rows from archived threads" only at
    /// runtime. Hoisted to a `SQL` enum so every writer threads through
    /// one source of truth. Pinned by
    /// `SearchIndexTests.testSQLStatementsAreFrozen`.
    enum SQL {
        static let beginTransaction      = "BEGIN"
        static let commitTransaction     = "COMMIT"
        static let rollbackTransaction   = "ROLLBACK"
        static let truncateAll           = "DELETE FROM messages_fts"
        static let deleteByThreadID      = "DELETE FROM messages_fts WHERE thread_id = ?1;"
        static let insertRow             = """
        INSERT INTO messages_fts (thread_id, thread_name, sender, text, time, channel)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6);
        """
    }

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
        sqlite3_exec(db, SQL.beginTransaction, nil, nil, nil)
        sqlite3_exec(db, SQL.truncateAll, nil, nil, nil)

        let namesByID    = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.name) })
        let channelsByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.channel.rawValue) })

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQL.insertRow, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, SQL.rollbackTransaction, nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for (threadID, messages) in messagesByThread {
            // Skip empty thread IDs for the same reason `upsert` rejects them:
            // the rows would be searchable orphans no thread can ever match.
            guard !threadID.isEmpty else { continue }
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

        sqlite3_exec(db, SQL.commitTransaction, nil, nil, nil)
    }

    /// Wipes the entire index and resets the per-channel indexed-message
    /// counter in Stats to zero. Called on preference wipe or schema
    /// migration so the counter reflects actual content rather than cumulative
    /// history.
    func clear(stats: Stats? = nil) {
        guard let db else { return }
        sqlite3_exec(db, SQL.truncateAll, nil, nil, nil)
        stats?.resetIndexedCounters()
    }

    /// Remove all index rows for a thread. Called when a thread is archived
    /// so it no longer appears in search results.
    /// Symmetric with `upsert` — empty threadID is rejected. The SQL would
    /// otherwise execute `DELETE ... WHERE thread_id = ''`, which is a no-op
    /// on a healthy index but masks caller-side bugs (the caller almost
    /// certainly meant a real thread).
    func delete(threadID: String) {
        guard let db else { return }
        guard !threadID.isEmpty else { return }
        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, SQL.deleteByThreadID, -1, &del, nil) == SQLITE_OK {
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
    /// No-op on an empty thread.id — would insert orphan rows whose
    /// `thread_id = ''` is searchable but unnavigable, since the inbox
    /// keys thread lookup by id and never has a thread with empty id.
    /// Caller error; refuse rather than corrupt the index.
    func upsert(thread: MessageThread, messages: [Message]) {
        guard let db else { return }
        guard !thread.id.isEmpty else { return }
        sqlite3_exec(db, SQL.beginTransaction, nil, nil, nil)

        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, SQL.deleteByThreadID, -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, thread.id, -1, Self.SQLITE_TRANSIENT)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQL.insertRow, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, SQL.rollbackTransaction, nil, nil, nil)
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

        sqlite3_exec(db, SQL.commitTransaction, nil, nil, nil)

        if !messages.isEmpty {
            Stats.shared.incrementIndexed(channel: thread.channel, count: messages.count)
        }
    }

    /// Default cap on the number of rows returned from `search`. Picked so
    /// the ⌘K palette never paints more than a screenful of suggestions
    /// (the popover renders ~20 visibly and scrolls; >50 is meaningless
    /// noise). Hoisted so the limit lives in one place and can be pinned
    /// against drift independently of either `search` overload.
    static let defaultSearchLimit: Int = 50

    /// FTS5 `snippet(...)` start marker — wraps each matched term in the
    /// returned snippet so the ⌘K palette can highlight terms via
    /// "split on `«` / `»`" rendering. Drift here breaks the palette's
    /// match-highlight pass without throwing — search still returns
    /// results, but no terms render as highlighted. Pinned by
    /// `SearchIndexTests.testSnippetMarkersAreGuillemetsWithEllipsis`.
    static let snippetStartMarker = "«"

    /// FTS5 `snippet(...)` end marker. Same drift impact as the start
    /// marker — palette highlight rendering silently degrades.
    static let snippetEndMarker = "»"

    /// FTS5 `snippet(...)` ellipsis marker — inserted in place of
    /// truncated context on either side of the match. Drift here changes
    /// the visible "…" cue users associate with truncated previews.
    static let snippetEllipsis = "…"

    /// FTS5 `snippet(...)` context-token count: how many tokens of
    /// surrounding text appear on each side of the match. 8 keeps the
    /// snippet roughly one line wide in the palette popover; raising it
    /// pushes snippets to multi-line and overlaps with the existing
    /// truncation rendering; lowering it shows a chip-sized fragment that
    /// loses match context.
    static let snippetTokenContext: Int = 8

    /// FTS5 `snippet(...)` column index: which column of the FTS5 table
    /// the snippet is built from. Column 3 is the `text` column in the
    /// `messages_fts` schema (`thread_id, thread_name, sender, text, time, channel`).
    /// Drift here points snippet generation at the wrong column — most
    /// likely the sender or thread name, which produces useless previews.
    static let snippetTextColumnIndex: Int = 3

    /// FTS5 match query. Empty input returns an empty array. The caller
    /// is expected to debounce UI input.
    func search(_ query: String, limit: Int = SearchIndex.defaultSearchLimit) -> [Result] {
        search(query: query, channel: nil, limit: limit)
    }

    /// FTS5 match query with optional per-channel filter (REP-080).
    /// When `channel` is non-nil, only rows indexed for that channel are returned.
    /// The `channel` column is UNINDEXED so the filter is a post-MATCH WHERE clause,
    /// not a full-text search — this is safe and efficient for small result sets.
    func search(query: String, channel: Channel?, limit: Int = SearchIndex.defaultSearchLimit) -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db else { return [] }

        let fts = Self.ftsQuery(from: trimmed)
        guard !fts.isEmpty else { return [] }

        let sql: String
        if channel != nil {
            sql = """
            SELECT thread_id, thread_name, sender, text, time,
                   snippet(messages_fts, \(SearchIndex.snippetTextColumnIndex), '\(SearchIndex.snippetStartMarker)', '\(SearchIndex.snippetEndMarker)', '\(SearchIndex.snippetEllipsis)', \(SearchIndex.snippetTokenContext))
            FROM messages_fts
            WHERE messages_fts MATCH ?1
            AND channel = ?2
            ORDER BY rank
            LIMIT ?3;
            """
        } else {
            sql = """
            SELECT thread_id, thread_name, sender, text, time,
                   snippet(messages_fts, \(SearchIndex.snippetTextColumnIndex), '\(SearchIndex.snippetStartMarker)', '\(SearchIndex.snippetEndMarker)', '\(SearchIndex.snippetEllipsis)', \(SearchIndex.snippetTokenContext))
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
                time:       Self.text(stmt, 4) ?? "",
                snippet:    Self.text(stmt, 5)
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
