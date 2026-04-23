import Foundation

/// Lightweight counter service for runtime observability. Tracks how
/// often rules fire, how many drafts ReplyAI produces vs. sends, and
/// how many messages have been indexed for search. Surfacing lives in
/// a follow-up — this service just persists.
///
/// Thread-safety: state is wrapped in `Locked<Snapshot>` so it's callable
/// from the SQLite worker thread, the DraftEngine's cooperative-queue stream
/// task, and the main actor without bridging. The JSON write is debounced
/// (2 s window) so rapid-fire increments coalesce into one I/O call.
final class Stats: @unchecked Sendable {
    /// Process-wide shared instance used by production code paths that
    /// don't have an injected Stats (e.g. RulesStore on load). Tests
    /// construct their own instances to avoid cross-test interference.
    static let shared = Stats(fileURL: defaultFileURL())

    /// Codable snapshot of every counter. Used as both the on-disk
    /// shape and the value callers see through `snapshot()`.
    struct Snapshot: Codable, Equatable, Sendable {
        var rulesFiredByAction: [String: Int] = [:]
        var draftsGenerated: Int = 0
        var draftsSent: Int = 0
        /// Per-tone breakdown of `draftsGenerated`. Key is `Tone.rawValue`.
        var draftsGeneratedByTone: [String: Int] = [:]
        /// Per-tone breakdown of `draftsSent`. Key is `Tone.rawValue`.
        var draftsSentByTone: [String: Int] = [:]
        var messagesIndexed: Int = 0
        /// Per-channel breakdown of `messagesIndexed`. Key is `Channel.rawValue`.
        var messagesIndexedByChannel: [String: Int] = [:]
        /// Cumulative count of SmartRule entries skipped during rules.json
        /// load because they failed to decode. Non-zero means the file was
        /// partially corrupt; the app kept the valid portion.
        var ruleLoadSkips: Int = 0
        /// Cumulative evaluation calls where at least one rule matched.
        /// Match rate = rulesMatchedCount / total rule evaluations.
        var rulesMatchedCount: Int = 0

        // MARK: - Codable with forward/backward compatibility

        enum CodingKeys: String, CodingKey {
            case rulesFiredByAction, draftsGenerated, draftsSent
            case draftsGeneratedByTone, draftsSentByTone
            case messagesIndexed, messagesIndexedByChannel, ruleLoadSkips
            case rulesMatchedCount
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rulesFiredByAction = try c.decodeIfPresent([String: Int].self, forKey: .rulesFiredByAction) ?? [:]
            draftsGenerated = try c.decodeIfPresent(Int.self, forKey: .draftsGenerated) ?? 0
            draftsSent = try c.decodeIfPresent(Int.self, forKey: .draftsSent) ?? 0
            draftsGeneratedByTone = try c.decodeIfPresent([String: Int].self, forKey: .draftsGeneratedByTone) ?? [:]
            draftsSentByTone = try c.decodeIfPresent([String: Int].self, forKey: .draftsSentByTone) ?? [:]
            messagesIndexed = try c.decodeIfPresent(Int.self, forKey: .messagesIndexed) ?? 0
            messagesIndexedByChannel = try c.decodeIfPresent([String: Int].self, forKey: .messagesIndexedByChannel) ?? [:]
            ruleLoadSkips = try c.decodeIfPresent(Int.self, forKey: .ruleLoadSkips) ?? 0
            rulesMatchedCount = try c.decodeIfPresent(Int.self, forKey: .rulesMatchedCount) ?? 0
        }

        init(
            rulesFiredByAction: [String: Int] = [:],
            draftsGenerated: Int = 0,
            draftsSent: Int = 0,
            draftsGeneratedByTone: [String: Int] = [:],
            draftsSentByTone: [String: Int] = [:],
            messagesIndexed: Int = 0,
            messagesIndexedByChannel: [String: Int] = [:],
            ruleLoadSkips: Int = 0,
            rulesMatchedCount: Int = 0
        ) {
            self.rulesFiredByAction = rulesFiredByAction
            self.draftsGenerated = draftsGenerated
            self.draftsSent = draftsSent
            self.draftsGeneratedByTone = draftsGeneratedByTone
            self.draftsSentByTone = draftsSentByTone
            self.messagesIndexed = messagesIndexed
            self.messagesIndexedByChannel = messagesIndexedByChannel
            self.ruleLoadSkips = ruleLoadSkips
            self.rulesMatchedCount = rulesMatchedCount
        }
    }

    private let state: Locked<Snapshot>
    /// Nil disables all file I/O — used by tests that only care about
    /// in-memory state and must not touch the real app support directory.
    private let fileURL: URL?

    /// Serializes pending debounced writes. Two locks kept separate:
    /// `state` protects counter mutations; `writeLock` protects the
    /// pending DispatchWorkItem pointer so cancel/replace is race-free.
    private let writeLock = NSLock()
    private var pendingWrite: DispatchWorkItem?
    private static let writeQueue = DispatchQueue(label: "com.replyai.stats.write", qos: .utility)

    /// - Parameter fileURL: Persistence path. Nil disables file I/O entirely
    ///   (useful for tests that only verify in-memory counters). Non-nil paths
    ///   are seeded from disk on init and written with a 2 s debounce window.
    ///   Pass `Stats.defaultFileURL()` explicitly for the production path.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        self.state = Locked(fileURL.flatMap(Self.load(from:)) ?? Snapshot())
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

    /// A new draft stream started for a specific tone. Increments both the
    /// aggregate `draftsGenerated` counter and the per-tone breakdown.
    func recordDraftGenerated(tone: Tone) {
        state.withLock {
            $0.draftsGenerated += 1
            $0.draftsGeneratedByTone[tone.rawValue, default: 0] += 1
        }
        persist()
    }

    /// A staged draft dispatched for a specific tone. Increments both the
    /// aggregate `draftsSent` counter and the per-tone breakdown.
    func recordDraftSent(tone: Tone) {
        state.withLock {
            $0.draftsSent += 1
            $0.draftsSentByTone[tone.rawValue, default: 0] += 1
        }
        persist()
    }

    /// Fraction of generated drafts that were sent for a given tone.
    /// Returns nil when no drafts have been generated for that tone yet —
    /// avoids divide-by-zero and signals "no data" to callers.
    func acceptanceRate(for tone: Tone) -> Double? {
        let snap = snapshot()
        let generated = snap.draftsGeneratedByTone[tone.rawValue] ?? 0
        guard generated > 0 else { return nil }
        let sent = snap.draftsSentByTone[tone.rawValue] ?? 0
        return Double(sent) / Double(generated)
    }

    /// Bump the indexed-message counter by the size of a fresh rebuild
    /// batch. Cumulative — we accumulate re-index volume, not the
    /// current index size.
    func recordMessagesIndexed(_ count: Int) {
        guard count > 0 else { return }
        state.withLock { $0.messagesIndexed += count }
        persist()
    }

    /// Bump the per-channel indexed-message counter. Called from
    /// `SearchIndex.upsert` so automation logs can see which channel
    /// drives index growth. `count` defaults to 1 for per-message callers.
    func incrementIndexed(channel: Channel, count: Int = 1) {
        guard count > 0 else { return }
        state.withLock {
            $0.messagesIndexedByChannel[channel.rawValue, default: 0] += count
        }
        persist()
    }

    /// Record that `count` SmartRule entries were skipped during
    /// rules.json load due to decode failures.
    func recordRuleLoadSkips(_ count: Int) {
        guard count > 0 else { return }
        state.withLock { $0.ruleLoadSkips += count }
        persist()
    }

    /// Increment the matched-rules counter. Call after `RuleEvaluator.matching`
    /// returns a non-empty array — i.e., at least one rule fired for this context.
    /// Does nothing when no rules matched, keeping the counter meaningful.
    func incrementRulesMatched() {
        state.withLock { $0.rulesMatchedCount += 1 }
        persist()
    }

    // MARK: - Persistence

    /// Resolves the default on-disk path for production use.
    /// Call explicitly when constructing `Stats.shared` so that `init(fileURL: nil)`
    /// can mean "no persistence" rather than "use default".
    static func defaultFileURL() -> URL {
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

    /// Cancel the pending debounce write and flush current counters to
    /// disk synchronously. Call on app shutdown to avoid losing the last
    /// session's increments before the 2 s window expires.
    /// No-op when `fileURL` is nil.
    func flushNow() {
        writeLock.lock()
        pendingWrite?.cancel()
        pendingWrite = nil
        writeLock.unlock()
        guard let url = fileURL else { return }
        writeToDisk(to: url)
    }

    // MARK: - Weekly log

    /// Serializes current counters to a Markdown snapshot at `url`. Intended
    /// for planner/reviewer scripts that archive weekly stats to
    /// `.automation/logs/stats-YYYY-WW.md`. Zero-value counters are included
    /// so the file always reflects the full schema.
    func writeWeeklyLog(to url: URL) throws {
        let snap = snapshot()
        let dateString = ISO8601DateFormatter().string(from: Date()).prefix(10)
        var lines: [String] = ["# Stats week of \(dateString)", ""]

        let actionsSorted = snap.rulesFiredByAction.sorted { $0.key < $1.key }
        if actionsSorted.isEmpty {
            lines.append("- rulesFiredByAction: {}")
        } else {
            let pairs = actionsSorted.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            lines.append("- rulesFiredByAction: {\(pairs)}")
        }
        lines.append("- draftsGenerated: \(snap.draftsGenerated)")
        lines.append("- draftsSent: \(snap.draftsSent)")
        lines.append("- messagesIndexed: \(snap.messagesIndexed)")
        lines.append("- ruleLoadSkips: \(snap.ruleLoadSkips)")
        lines.append("")

        let content = lines.joined(separator: "\n")
        guard let data = content.data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Internal write helpers

    /// Schedules a debounced write: cancels any pending write and queues a
    /// new one 2 s from now. Rapid increments coalesce into a single I/O call.
    private func persist() {
        guard let url = fileURL else { return }
        writeLock.lock()
        pendingWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.writeToDisk(to: url)
        }
        pendingWrite = item
        writeLock.unlock()
        Self.writeQueue.asyncAfter(deadline: .now() + 2, execute: item)
    }

    /// Atomic write. Errors are swallowed — an observability failure
    /// must never break the caller.
    private func writeToDisk(to url: URL) {
        let snap = snapshot()
        guard let data = try? JSONEncoder().encode(snap) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
