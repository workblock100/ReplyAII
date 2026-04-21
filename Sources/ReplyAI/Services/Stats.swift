import Foundation

/// Lightweight counter service for runtime observability. Tracks how
/// often rules fire, how many drafts ReplyAI produces vs. sends, and
/// how many messages have been indexed for search. Surfacing lives in
/// a follow-up — this service just persists.
///
/// Thread-safety mirrors `ContactsResolver`: `@unchecked Sendable` +
/// `NSLock`-guarded state so it's callable from the SQLite worker
/// thread, the DraftEngine's cooperative-queue stream task, and the
/// main actor without bridging. The JSON write happens under the lock
/// with atomic replace so a crash mid-write can't corrupt the file.
final class Stats: @unchecked Sendable {
    /// Codable snapshot of every counter. Used as both the on-disk
    /// shape and the value callers see through `snapshot()`.
    struct Snapshot: Codable, Equatable, Sendable {
        var rulesFiredByAction: [String: Int] = [:]
        var draftsGenerated: Int = 0
        var draftsSent: Int = 0
        var messagesIndexed: Int = 0
    }

    private let lock = NSLock()
    private var state: Snapshot
    private let fileURL: URL

    /// - Parameter fileURL: Override the persistence path. Nil picks
    ///   `~/Library/Application Support/ReplyAI/stats.json`. Tests
    ///   pass a temp URL so assertions don't fight the running app.
    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.state = Self.load(from: url) ?? Snapshot()
    }

    // MARK: - Reads

    /// Current counter values. Safe to call from any thread.
    func snapshot() -> Snapshot {
        synced { state }
    }

    // MARK: - Writes

    /// Record a rule firing by its action discriminator
    /// (`archive`, `silentlyIgnore`, `markDone`, `setDefaultTone`,
    /// `pin`). Unknown strings are tracked verbatim — a typo shows up
    /// in the stats rather than silently disappearing.
    func recordRuleFired(action: String) {
        synced {
            state.rulesFiredByAction[action, default: 0] += 1
        }
        persist()
    }

    /// A new draft stream started. Called once per
    /// `DraftEngine.generate`, before any tokens arrive.
    func recordDraftGenerated() {
        synced { state.draftsGenerated += 1 }
        persist()
    }

    /// A staged draft dispatched through IMessageSender successfully.
    /// Called from `InboxViewModel.confirmSend`.
    func recordDraftSent() {
        synced { state.draftsSent += 1 }
        persist()
    }

    /// Bump the indexed-message counter by the size of a fresh rebuild
    /// batch. Cumulative — we accumulate re-index volume, not the
    /// current index size.
    func recordMessagesIndexed(_ count: Int) {
        guard count > 0 else { return }
        synced { state.messagesIndexed += count }
        persist()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("ReplyAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stats.json")
    }

    private static func load(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Atomic write. Errors are swallowed — an observability failure
    /// must never break the caller. Runs under the lock so the on-disk
    /// shape always reflects a single consistent in-memory state.
    private func persist() {
        let data: Data? = synced {
            try? JSONEncoder().encode(state)
        }
        guard let data else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func synced<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
