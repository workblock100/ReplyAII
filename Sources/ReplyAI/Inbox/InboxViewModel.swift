import Foundation
import Observation

@Observable
@MainActor
final class InboxViewModel {
    enum SyncStatus: Equatable {
        case idle                 // showing fixtures, no sync attempted yet
        case syncing
        case live(at: Date)       // successful sync; fixtures replaced
        case denied(hint: String) // Full Disk Access needed
        case failed(String)       // some other problem
    }

    var selectedThreadID: String
    var activeFolder: Folder.Kind = .all
    var activeTone: Tone = .warm

    var threads: [MessageThread]
    let folders: [Folder]
    let channels: [Channel]

    var syncStatus: SyncStatus = .idle
    var liveMessages: [String: [Message]] = [:]   // threadID → messages, filled on sync

    /// Per-thread watermark. Incoming messages with `rowID > lastSeenRowID[tid]`
    /// are new since the last rule evaluation pass. Advances strictly upward.
    /// Persisted to UserDefaults so rule actions don't re-fire on relaunch.
    private var lastSeenRowID: [String: Int64] = [:] {
        didSet { InboxViewModel.saveLastSeenRowID(lastSeenRowID) }
    }

    /// Threads the user or a rule has hidden from the main list. Persisted
    /// to UserDefaults so the effect survives relaunches. Filtering lives
    /// in ThreadListView.
    var archivedThreadIDs: Set<String> = [] {
        didSet { InboxViewModel.saveArchivedIDs(archivedThreadIDs) }
    }

    /// Threads silently suppressed by a `silentlyIgnore` rule action.
    /// These are hidden from the menu-bar popover AND from future popover
    /// notifications. Semantically distinct from `archivedThreadIDs`:
    /// archived threads still appear in the menu-bar count; silently-ignored
    /// ones do not. Persisted to UserDefaults.
    var silentlyIgnoredThreadIDs: Set<String> = [] {
        didSet { InboxViewModel.saveSilentlyIgnoredIDs(silentlyIgnoredThreadIDs) }
    }

    /// Threads eligible for the menu-bar waiting list: unread and not
    /// silently ignored. Archived threads are still counted (archive is a
    /// user-visible action); silentlyIgnore suppresses the notification.
    var menuBarWaitingThreads: [MessageThread] {
        threads.filter { $0.unread > 0 && !silentlyIgnoredThreadIDs.contains($0.id) }
    }

    /// User edits to the composer, keyed by "{threadID}|{tone}". When a
    /// key has a non-nil value, it overrides whatever the DraftEngine
    /// stream last emitted. Regenerate (⌘J) clears its own key so the
    /// next stream can take over.
    var userEdits: [String: String] = [:]

    /// A pending send awaiting user confirmation. UI presents a sheet
    /// whenever this is non-nil; setting it back to nil cancels.
    var sendConfirmation: SendConfirmation?
    /// Transient toast shown in the composer for 2s after a send.
    var sendToast: String?

    struct SendConfirmation: Equatable {
        let threadID: String
        let recipient: String
        let channel: Channel
        let text: String
        let tone: Tone
        /// Full chat GUID from chat.db. Preferred over synthesizing a
        /// 1:1 GUID from the identifier, which would fail for groups.
        let chatGUID: String?
    }

    private var imessage: ChannelService
    let contacts = ContactsResolver()
    private var watcher: ChatDBWatcher?
    let rules: RulesStore
    let searchIndex = SearchIndex()
    let stats: Stats

    /// `true` once we've done the initial full rebuild of the FTS index.
    /// Subsequent syncs only upsert the threads that actually have
    /// updated message payloads, which is O(k) instead of O(n).
    private var didSeedSearchIndex = false

    init(
        threads: [MessageThread] = Fixtures.threads,
        folders: [Folder] = Fixtures.folders,
        channels: [Channel] = Fixtures.sidebarChannels,
        imessage: ChannelService? = nil,
        rules: RulesStore? = nil,
        stats: Stats? = nil
    ) {
        self.stats = stats ?? Stats()
        self.threads = threads
        self.folders = folders
        self.channels = channels
        self.selectedThreadID = threads.first?.id ?? "t1"
        self.rules = rules ?? RulesStore()
        self.archivedThreadIDs = InboxViewModel.loadArchivedIDs()
        self.silentlyIgnoredThreadIDs = InboxViewModel.loadSilentlyIgnoredIDs()
        self.lastSeenRowID = InboxViewModel.loadLastSeenRowID()
        // Resolver is NSLock-guarded and callable from any thread, so we
        // can hand a plain Sendable closure to the SQLite worker without
        // needing MainActor.assumeIsolated (which would crash on the
        // cooperative executor).
        let resolver = self.contacts
        self.imessage = imessage ?? IMessageChannel(nameFor: { handle in
            resolver.name(for: handle)
        })
    }

    var selectedThread: MessageThread {
        threads.first(where: { $0.id == selectedThreadID }) ?? threads[0]
    }

    func selectThread(_ id: String) {
        selectedThreadID = id
        applyRules(for: selectedThread)
    }

    /// Evaluate every active rule against the selected thread and apply
    /// the side effects that make sense on focus:
    ///   - setDefaultTone → switch the composer's active tone
    ///   - pin            → mark the thread pinned (best-effort; v1 has no
    ///                      pinned-first sort yet)
    ///
    /// archive / markDone / silentlyIgnore are list-mutation actions that
    /// only make sense on incoming messages, not on focus; the live
    /// FSEvents pipeline will invoke those separately when it lands.
    func applyRules(for thread: MessageThread) {
        let ctx = RuleContext.from(thread: thread)
        let matched = RuleEvaluator.matching(rules.rules, in: ctx)

        for rule in matched {
            switch rule.then {
            case .setDefaultTone(let tone):
                if activeTone != tone { activeTone = tone }
                stats.recordRuleFired(action: "setDefaultTone")
            case .pin:
                markPinned(thread.id)
                stats.recordRuleFired(action: "pin")
            case .archive, .markDone, .silentlyIgnore:
                // Deferred: these mutate the thread list; need the
                // incoming-message pipeline to fire them at the right
                // moment.
                continue
            }
        }
    }

    private func markPinned(_ threadID: String) {
        guard let i = threads.firstIndex(where: { $0.id == threadID }),
              !threads[i].pinned else { return }
        threads[i] = MessageThread(
            id: threads[i].id,
            channel: threads[i].channel,
            name: threads[i].name,
            avatar: threads[i].avatar,
            preview: threads[i].preview,
            time: threads[i].time,
            unread: threads[i].unread,
            pinned: true,
            contextCount: threads[i].contextCount,
            contextSummary: threads[i].contextSummary
        )
    }

    func messages(for thread: MessageThread) -> [Message] {
        if let live = liveMessages[thread.id] { return live }
        return Fixtures.messages(forThread: thread.id, fallback: thread.preview, time: thread.time)
    }

    var folderLabel: String {
        folders.first(where: { $0.id == activeFolder })?.label ?? "Inbox"
    }

    var needsYouCount: Int { threads.filter { $0.unread > 0 }.count }
    var handledCount: Int  { threads.count - needsYouCount }

    func cycleTone() { activeTone = activeTone.cycled() }

    // MARK: - Composer edits

    static func editKey(threadID: String, tone: Tone) -> String {
        "\(threadID)|\(tone.rawValue)"
    }

    /// Returns the user's edit if one exists, else the fallback (typically
    /// the live stream text from DraftEngine). Use this to render the well
    /// and as the send payload.
    func effectiveDraft(threadID: String, tone: Tone, fallback: String) -> String {
        if let edit = userEdits[Self.editKey(threadID: threadID, tone: tone)] { return edit }
        return fallback
    }

    func setEdit(threadID: String, tone: Tone, text: String) {
        userEdits[Self.editKey(threadID: threadID, tone: tone)] = text
    }

    func clearEdit(threadID: String, tone: Tone) {
        userEdits.removeValue(forKey: Self.editKey(threadID: threadID, tone: tone))
    }

    // MARK: - Live sync

    /// Replace fixture threads with the live iMessage inbox. Safe to call
    /// repeatedly — each call is a fresh snapshot. On a successful sync
    /// we also arm the file watcher so subsequent chat.db writes
    /// auto-resync without the user pressing ⌘R.
    func syncFromIMessage() async {
        syncStatus = .syncing
        await contacts.ensureAccess()   // prompts once, if .notDetermined
        do {
            let live = try await imessage.recentThreads(limit: 50)
            guard !live.isEmpty else {
                syncStatus = .failed("No conversations returned. chat.db may be empty on this account.")
                return
            }
            let currentSelection = selectedThreadID
            threads = live

            // Preserve the user's current selection if still present;
            // otherwise fall back to the top thread.
            if live.contains(where: { $0.id == currentSelection }) == false {
                selectedThreadID = live.first?.id ?? selectedThreadID
            }
            applyRules(for: selectedThread)

            // Drop cached messages for threads that no longer exist.
            liveMessages = liveMessages.filter { key, _ in live.contains(where: { $0.id == key }) }

            syncStatus = .live(at: Date())

            // Preload messages for the focused thread so the detail pane
            // is populated without a second permission round-trip.
            if let focus = live.first(where: { $0.id == selectedThreadID }),
               liveMessages[focus.id] == nil,
               let msgs = try? await imessage.messages(forThreadID: focus.id, limit: 40) {
                liveMessages[focus.id] = msgs
            }

            // Seed the FTS5 index once, then incrementally upsert per
            // thread on watcher refires. Full rebuilds do O(total
            // messages) work for each incoming iMessage; upserts do
            // O(messages-in-the-updated-thread).
            let snapshot = liveMessages
            let threadsSnapshot = live
            if !didSeedSearchIndex {
                await searchIndex.rebuild(from: snapshot, threads: threadsSnapshot)
                didSeedSearchIndex = true
            } else {
                for thread in threadsSnapshot {
                    guard let msgs = snapshot[thread.id] else { continue }
                    await searchIndex.upsert(thread: thread, messages: msgs)
                }
            }
            stats.recordMessagesIndexed(snapshot.values.reduce(0) { $0 + $1.count })

            // Process any incoming messages we haven't evaluated yet.
            // This covers first-run (every existing message is "new" to
            // ReplyAI; rules fire against each) and every watcher refire
            // after it.
            await processIncomingForRules(live)

            startWatchingIfNeeded()
        } catch let err as ChannelError {
            if case .permissionDenied(let hint) = err {
                syncStatus = .denied(hint: hint)
            } else {
                syncStatus = .failed(err.localizedDescription)
            }
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Rules on incoming

    /// For each visible thread, pull incoming messages with
    /// `rowID > lastSeenRowID[tid]` and run the rule engine against
    /// each. Applies the incoming-only actions (archive, silentlyIgnore,
    /// markDone); focus-time actions (setDefaultTone, pin) happen in
    /// applyRules(for:) on select.
    ///
    /// After processing, the watermark advances to the tail rowID of
    /// each thread's new batch.
    func processIncomingForRules(_ liveThreads: [MessageThread]) async {
        for thread in liveThreads {
            let since = lastSeenRowID[thread.id] ?? 0
            let newMessages: [Message]
            do {
                newMessages = try await imessage.newIncomingMessages(
                    forThreadID: thread.id, sinceRowID: since
                )
            } catch {
                continue
            }
            guard !newMessages.isEmpty else { continue }

            // Evaluate with the latest incoming's text — senders can
            // have multiple rules matching the same thread; we trust
            // the most recent as representative for a single sync pass.
            var ctx = RuleContext.from(thread: thread)
            if let latest = newMessages.last { ctx.lastMessageText = latest.text }

            let matched = RuleEvaluator.matching(rules.rules, in: ctx)
            for rule in matched {
                switch rule.then {
                case .archive:
                    archivedThreadIDs.insert(thread.id)
                    stats.recordRuleFired(action: "archive")
                case .silentlyIgnore:
                    silentlyIgnoredThreadIDs.insert(thread.id)
                    stats.recordRuleFired(action: "silentlyIgnore")
                case .markDone:
                    markUnreadZero(thread.id)
                    stats.recordRuleFired(action: "markDone")
                case .setDefaultTone, .pin:
                    // Focus-time actions — handled in applyRules(for:).
                    continue
                }
            }

            if let maxRow = newMessages.map(\.rowID).max() {
                lastSeenRowID[thread.id] = maxRow
            }
        }
    }

    private func markUnreadZero(_ threadID: String) {
        guard let i = threads.firstIndex(where: { $0.id == threadID }),
              threads[i].unread > 0 else { return }
        threads[i] = MessageThread(
            id: threads[i].id,
            channel: threads[i].channel,
            name: threads[i].name,
            avatar: threads[i].avatar,
            preview: threads[i].preview,
            time: threads[i].time,
            unread: 0,
            pinned: threads[i].pinned,
            contextCount: threads[i].contextCount,
            contextSummary: threads[i].contextSummary
        )
    }

    // MARK: - Archived persistence

    private static let archivedKey = "pref.inbox.archivedThreadIDs"

    private static func loadArchivedIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: archivedKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    private static func saveArchivedIDs(_ ids: Set<String>) {
        let data = (try? JSONEncoder().encode(Array(ids).sorted())) ?? Data()
        UserDefaults.standard.set(data, forKey: archivedKey)
    }

    // MARK: - silentlyIgnored persistence

    private static let silentlyIgnoredKey = "pref.inbox.silentlyIgnoredThreadIDs"

    private static func loadSilentlyIgnoredIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: silentlyIgnoredKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    private static func saveSilentlyIgnoredIDs(_ ids: Set<String>) {
        let data = (try? JSONEncoder().encode(Array(ids).sorted())) ?? Data()
        UserDefaults.standard.set(data, forKey: silentlyIgnoredKey)
    }

    // MARK: - lastSeenRowID persistence

    private static let lastSeenRowIDKey = "pref.inbox.lastSeenRowID"

    private static func loadLastSeenRowID() -> [String: Int64] {
        guard let data = UserDefaults.standard.data(forKey: lastSeenRowIDKey),
              let decoded = try? JSONDecoder().decode([String: Int64].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveLastSeenRowID(_ watermarks: [String: Int64]) {
        let data = (try? JSONEncoder().encode(watermarks)) ?? Data()
        UserDefaults.standard.set(data, forKey: lastSeenRowIDKey)
    }

    /// Undoes an archive — used for the future "Undo" UX in set-privacy /
    /// keyboard shortcut. Not called from anywhere yet but the shape is
    /// stable.
    func unarchive(_ threadID: String) {
        archivedThreadIDs.remove(threadID)
    }

    /// Arm the chat.db watcher once we've confirmed FDA is granted.
    /// Idempotent — second call is a no-op.
    private func startWatchingIfNeeded() {
        guard watcher == nil else { return }
        let w = ChatDBWatcher { [weak self] in
            Task { @MainActor [weak self] in
                await self?.syncFromIMessage()
                // Also refresh the focused thread's messages, since the
                // most likely cause of a write is a new message in the
                // currently-open thread.
                if let id = self?.selectedThreadID {
                    self?.liveMessages[id] = nil   // force re-pull
                    await self?.loadMessages(for: id)
                }
            }
        }
        w.start()
        watcher = w
    }

    // MARK: - Sending

    /// Stage a send for user review. Doesn't dispatch anything yet — the
    /// UI presents a confirm sheet and calls `confirmSend` on approval.
    func requestSend(text: String) {
        let thread = selectedThread
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sendConfirmation = SendConfirmation(
            threadID: thread.id,
            recipient: thread.name,
            channel: thread.channel,
            text: text,
            tone: activeTone,
            chatGUID: thread.chatGUID
        )
    }

    func cancelSend() {
        sendConfirmation = nil
    }

    /// Fire the staged AppleScript. Clears confirmation on success, leaves
    /// an error toast on failure.
    func confirmSend() async {
        guard let pending = sendConfirmation else { return }
        sendConfirmation = nil
        do {
            // Reconstruct a minimal thread so the sender can make the
            // guid-vs-synthesized decision using the chat.db-sourced
            // value when we have one.
            let threadForSend = MessageThread(
                id: pending.threadID,
                channel: pending.channel,
                name: pending.recipient,
                avatar: String(pending.recipient.prefix(1)),
                preview: "",
                time: "",
                chatGUID: pending.chatGUID
            )
            try await Task.detached(priority: .userInitiated) {
                try IMessageSender.send(pending.text, to: threadForSend)
            }.value
            stats.recordDraftSent()
            sendToast = "Sent to \(pending.recipient)"
            advanceToNextThread()
        } catch let err as IMessageSender.SendError {
            sendToast = err.localizedDescription
        } catch {
            sendToast = error.localizedDescription
        }

        // Auto-dismiss the toast after 2.5s.
        let deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { self?.sendToast = nil }
        }
        _ = deadline
    }

    /// After a successful send, jump to the next thread so ⌘↵ feels fast.
    private func advanceToNextThread() {
        guard let i = threads.firstIndex(where: { $0.id == selectedThreadID }) else { return }
        let next = threads[(i + 1) % threads.count].id
        selectedThreadID = next
    }

    /// Pull message history for a specific thread on demand.
    func loadMessages(for threadID: String) async {
        guard case .live = syncStatus else { return }
        if liveMessages[threadID] != nil { return }
        if let msgs = try? await imessage.messages(forThreadID: threadID, limit: 40) {
            liveMessages[threadID] = msgs
        }
    }
}
