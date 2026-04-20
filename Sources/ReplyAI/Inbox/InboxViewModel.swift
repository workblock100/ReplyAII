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
    }

    private var imessage: ChannelService
    let contacts = ContactsResolver()
    private var watcher: ChatDBWatcher?
    let rules: RulesStore
    let searchIndex = SearchIndex()

    init(
        threads: [MessageThread] = Fixtures.threads,
        folders: [Folder] = Fixtures.folders,
        channels: [Channel] = Fixtures.sidebarChannels,
        imessage: ChannelService? = nil,
        rules: RulesStore? = nil
    ) {
        self.threads = threads
        self.folders = folders
        self.channels = channels
        self.selectedThreadID = threads.first?.id ?? "t1"
        self.rules = rules ?? RulesStore()
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
            case .pin:
                markPinned(thread.id)
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

            // Rebuild the FTS5 search index so ⌘K searches the live
            // thread contents, not the fixture data.
            let snapshot = liveMessages
            let threadsSnapshot = live
            await searchIndex.rebuild(from: snapshot, threads: threadsSnapshot)

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
            tone: activeTone
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
            try await Task.detached(priority: .userInitiated) {
                try IMessageSender.send(pending.text, toChatIdentifier: pending.threadID, channel: pending.channel)
            }.value
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
