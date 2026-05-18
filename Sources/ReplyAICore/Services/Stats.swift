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

    /// Timestamp recorded at init time. Resets each session; not persisted.
    let sessionStartedAt: Date

    /// Injectable clock for deterministic tests. Defaults to `Date()`.
    let nowProvider: () -> Date

    /// Elapsed seconds since `sessionStartedAt`. Uses `nowProvider` for
    /// deterministic test overrides.
    var sessionDuration: TimeInterval { nowProvider().timeIntervalSince(sessionStartedAt) }

    /// Window between the most recent counter increment and the on-disk
    /// flush. Picked so a burst of rule fires + draft increments coalesces
    /// into a single I/O call rather than thrashing app-support disk on
    /// every event. Drift downward (e.g. 0.1) restores the thrash; drift
    /// upward (e.g. 30) means a crash within ~half a minute of the last
    /// counter bump silently loses that session's stats. Hoisted to a
    /// constant so it's pinnable independently of the inline arithmetic
    /// inside `persist()`.
    static let debounceWriteWindow: TimeInterval = 2

    /// On-disk filename for the stats persistence JSON. Drift here is
    /// a silent migration: the install's old stats.json stays on disk
    /// while the new build creates a fresh one, and every counter
    /// resets to zero on next launch (with the old data orphaned but
    /// recoverable). The existing
    /// `StatsDefaultFileURLTests.testDefaultFileURLEndsWithStatsJSON`
    /// asserts the lastPathComponent is `stats.json` against an inline
    /// literal — sibling to that pin, this hoist makes the filename
    /// greppable from the source side and discoverable in one place.
    /// Pinned by `StatsDefaultFileURLTests.testProductionFileNameIsStatsDotJSON`.
    static let productionFileName = "stats.json"

    /// Serializes pending debounced writes. Two locks kept separate:
    /// `state` protects counter mutations; `writeLock` protects the
    /// pending DispatchWorkItem pointer so cancel/replace is race-free.
    private let writeLock = NSLock()
    private var pendingWrite: DispatchWorkItem?

    /// Dispatch-queue label for the debounced stats writer. Visible
    /// in Instruments / sample traces. **Note**: this label uses the
    /// `com.replyai.` Java-style reverse-DNS prefix, while every other
    /// queue / Notification.Name / Keychain service in the codebase
    /// uses `co.replyai.` (e.g. `ChatDBWatcher.dispatchQueueLabel =
    /// "co.replyai.chatdb-watcher"`,
    /// `MessagesAppActivationObserver.dispatchQueueLabel =
    /// "co.replyai.messages-activation"`,
    /// `KeychainHelper.defaultService = "co.replyai.app"`,
    /// `GlobalHotkey.replyAIRequestSummonInbox =
    /// "co.replyai.summon.inbox"`). The Stats label is the only
    /// drifted one; harmonizing to `co.replyai.stats.write` is a
    /// trivial code change but would orphan any production
    /// Instruments-trace filter or external observability rule that
    /// keys off the literal `com.replyai.stats.write` string.
    /// Hoisted from the inline `DispatchQueue(label:)` so the
    /// drifted literal is greppable from the source side and
    /// pinnable in tests independently of the queue construction.
    /// Pinned by `StatsTests.testWriteQueueLabelIsFrozen` and the
    /// cross-file divergence by
    /// `testWriteQueueLabelDivergesFromCoReplyAIPrefix`.
    static let writeQueueLabel = "com.replyai.stats.write"

    private static let writeQueue = DispatchQueue(label: Stats.writeQueueLabel, qos: .utility)

    /// - Parameter fileURL: Persistence path. Nil disables file I/O entirely
    ///   (useful for tests that only verify in-memory counters). Non-nil paths
    ///   are seeded from disk on init and written with a 2 s debounce window.
    ///   Pass `Stats.defaultFileURL()` explicitly for the production path.
    /// - Parameter nowProvider: Override the current-time source for tests.
    init(fileURL: URL? = nil, nowProvider: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.nowProvider = nowProvider
        self.sessionStartedAt = nowProvider()
        self.state = Locked(fileURL.flatMap(Self.load(from:)) ?? Snapshot())
    }

    // MARK: - Reads

    /// Current counter values. Safe to call from any thread.
    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }

    // MARK: - Writes

    /// Stable action-discriminator vocabulary used as keys into
    /// `Snapshot.rulesFiredByAction`. Hoisted from the inline literals
    /// at every InboxViewModel call site so a typo in a new call site
    /// is a compile error rather than a silent split key (a string
    /// "Pin" instead of "pin" creates a new bucket and partitions the
    /// counter across two keys, only one of which is read by any
    /// downstream surface). Drift here also breaks any persisted
    /// stats from older builds — `Stats.persist()` writes the raw
    /// strings to disk and a key rename would orphan historical
    /// counters. Pinned by
    /// `StatsTests.testRuleActionConstantsAreFrozen` and the
    /// `*RoutesThroughRuleActionConstant` cluster.
    ///
    /// **Cross-vocabulary divergence**: this Stats vocabulary uses
    /// camelCase (`silentlyIgnore`, `markDone`, `setDefaultTone`),
    /// while `RuleAction`'s rules.json Codable form uses snake_case
    /// (`silently_ignore`, `mark_done`, `set_default_tone` — see
    /// `SmartRule.swift:RuleAction.Kind`). The two predate each other
    /// and serve different files; harmonizing would orphan every
    /// shipped user's persisted stats.json. The intentional
    /// divergence is pinned by
    /// `StatsTests.testStatsRuleActionConstantsDivergeFromRulesJSONSnakeCase`
    /// so a future "consistency fix" surfaces as a deliberate change
    /// with a migration plan, not a silent rename.
    enum RuleAction {
        static let archive          = "archive"
        static let silentlyIgnore   = "silentlyIgnore"
        static let markDone         = "markDone"
        static let setDefaultTone   = "setDefaultTone"
        static let pin              = "pin"
    }

    /// Record a rule firing by its action discriminator. Use the
    /// `Stats.RuleAction.*` constants at call sites — passing a free
    /// String works (any unknown string is tracked verbatim — a typo
    /// shows up in the stats rather than silently disappearing) but
    /// loses the typo-as-compile-error safety net.
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

    /// Acceptance rate across all tones combined. Returns nil when no drafts
    /// have been generated at all — distinguishes "no data" from a zero rate.
    func overallAcceptanceRate() -> Double? {
        let snap = snapshot()
        let totalGenerated = snap.draftsGeneratedByTone.values.reduce(0, +)
        guard totalGenerated > 0 else { return nil }
        let totalSent = snap.draftsSentByTone.values.reduce(0, +)
        return Double(totalSent) / Double(totalGenerated)
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

    /// Zeroes both the aggregate and per-channel indexed-message counters.
    /// Called by SearchIndex.clear() so the counter reflects current index
    /// content rather than cumulative history.
    func resetIndexedCounters() {
        state.withLock {
            $0.messagesIndexed = 0
            $0.messagesIndexedByChannel = [:]
        }
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
        let dir = base.appendingPathComponent(Preferences.appSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.productionFileName)
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

    /// Markdown vocabulary the planner/reviewer scripts parse out of
    /// the weekly log. Each field name maps to a documented stat
    /// counter; drift on any one would silently break the downstream
    /// `.automation/` script that aggregates these into the cumulative
    /// roll-up. The substring tests in `StatsTests` verify presence
    /// but accept any nearby drift (e.g. mis-pluralisation, casing
    /// changes); pinning the names here gives a single-edit surface
    /// for a future "switch to YAML" or "rename a counter" decision.
    enum WeeklyLogFormat {
        /// Heading prefix; the date string is appended after `of `.
        static let headingPrefix         = "# Stats week of "
        static let rulesFiredEmpty       = "- rulesFiredByAction: {}"
        static let rulesFiredFieldName   = "rulesFiredByAction"
        static let draftsGeneratedField  = "draftsGenerated"
        static let draftsSentField       = "draftsSent"
        static let messagesIndexedField  = "messagesIndexed"
        static let ruleLoadSkipsField    = "ruleLoadSkips"
        static let sessionDurationField  = "sessionDuration"

        /// Format: `- <field>: <value>`. Hoisted so every counter line
        /// flows through one shape — drift to e.g. `* <field>: ...`
        /// (asterisk bullet) would silently break the planner's
        /// dash-prefix line filter.
        static func line(_ field: String, value: String) -> String {
            "- \(field): \(value)"
        }
    }

    /// Serializes current counters to a Markdown snapshot at `url`. Intended
    /// for planner/reviewer scripts that archive weekly stats to
    /// `.automation/logs/stats-YYYY-WW.md`. Zero-value counters are included
    /// so the file always reflects the full schema.
    func writeWeeklyLog(to url: URL) throws {
        let snap = snapshot()
        let dateString = ISO8601DateFormatter().string(from: Date()).prefix(10)
        var lines: [String] = ["\(WeeklyLogFormat.headingPrefix)\(dateString)", ""]

        let actionsSorted = snap.rulesFiredByAction.sorted { $0.key < $1.key }
        if actionsSorted.isEmpty {
            lines.append(WeeklyLogFormat.rulesFiredEmpty)
        } else {
            let pairs = actionsSorted.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            lines.append(WeeklyLogFormat.line(WeeklyLogFormat.rulesFiredFieldName, value: "{\(pairs)}"))
        }
        lines.append(WeeklyLogFormat.line(WeeklyLogFormat.draftsGeneratedField, value: "\(snap.draftsGenerated)"))
        lines.append(WeeklyLogFormat.line(WeeklyLogFormat.draftsSentField, value: "\(snap.draftsSent)"))
        lines.append(WeeklyLogFormat.line(WeeklyLogFormat.messagesIndexedField, value: "\(snap.messagesIndexed)"))
        lines.append(WeeklyLogFormat.line(WeeklyLogFormat.ruleLoadSkipsField, value: "\(snap.ruleLoadSkips)"))
        lines.append(WeeklyLogFormat.line(WeeklyLogFormat.sessionDurationField, value: "\(sessionDuration)"))
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
        Self.writeQueue.asyncAfter(deadline: .now() + Self.debounceWriteWindow, execute: item)
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
