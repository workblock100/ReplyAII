import Foundation

/// Lightweight counter service for runtime observability. Tracks how
/// often rules fire, how many drafts ReplyAI produces vs. sends, and
/// how many messages have been indexed for search. Surfacing lives in
/// a follow-up — this service just persists.
///
/// Thread-safety: state is wrapped in `Locked<Snapshot>` so it's callable
/// from the SQLite worker thread, the DraftEngine's cooperative-queue stream
/// task, and the main actor without bridging. The JSON write happens after
/// releasing the lock so a slow write never blocks short reads.
final class Stats: @unchecked Sendable {
    /// Process-wide shared instance used by production code paths that
    /// don't have an injected Stats (e.g. RulesStore on load). Tests
    /// construct their own instances to avoid cross-test interference.
    static let shared = Stats()

    /// Codable snapshot of every counter. Used as both the on-disk
    /// shape and the value callers see through `snapshot()`.
    struct Snapshot: Codable, Equatable, Sendable {
        var rulesFiredByAction: [String: Int] = [:]
        var draftsGenerated: Int = 0
        var draftsSent: Int = 0
        var messagesIndexed: Int = 0
        /// Cumulative count of SmartRule entries skipped during rules.json
        /// load because they failed to decode. Non-zero means the file was
        /// partially corrupt; the app kept the valid portion.
        var ruleLoadSkips: Int = 0
    }

    private let state: Locked<Snapshot>
    private let fileURL: URL

    /// - Parameter fileURL: Override the persistence path. Nil picks
    ///   `~/Library/Application Support/ReplyAI/stats.json`. Tests
    ///   pass a temp URL so assertions don't fight the running app.
    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.state = Locked(Self.load(from: url) ?? Snapshot())
    }

    // MARK: - Reads

    /// Current counter values. Safe to call from any thread.
    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }

    // MARK: - Writes

    /// Record a rule firing by its action discriminator
    /// (`archive`, `silentlyIgnore`, `markDone`, `setDefaultTone`,
    /// `pin`). Unknown strings are tracked verbatim — a typo shows up
    /// in the stats rather than silently disappearing.
    func recordRuleFired(action: String) {
        state.withLock { $0.rulesFiredByAction[action, default: 0] += 1 }
        persist()
    }

    /// A new draft stream started. Called once per
    /// `DraftEngine.generate`, before any tokens arrive.
    func recordDraftGenerated() {
        state.withLock { $0.draftsGenerated += 1 }
        persist()
    }

    /// A staged draft dispatched through IMessageSender successfully.
    /// Called from `InboxViewModel.confirmSend`.
    func recordDraftSent() {
        state.withLock { $0.draftsSent += 1 }
        persist()
    }

    /// Bump the indexed-message counter by the size of a fresh rebuild
    /// batch. Cumulative — we accumulate re-index volume, not the
    /// current index size.
    func recordMessagesIndexed(_ count: Int) {
        guard count > 0 else { return }
        state.withLock { $0.messagesIndexed += count }
        persist()
    }

    /// Record that `count` SmartRule entries were skipped during
    /// rules.json load due to decode failures.
    func recordRuleLoadSkips(_ count: Int) {
        guard count > 0 else { return }
        state.withLock { $0.ruleLoadSkips += count }
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
    /// must never break the caller. Snapshot is copied out of the lock
    /// first so the encode doesn't hold the lock across I/O.
    private func persist() {
        let snap = snapshot()
        guard let data = try? JSONEncoder().encode(snap) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
