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

    private var imessage: ChannelService
    let contacts = ContactsResolver()
    private var watcher: ChatDBWatcher?

    init(
        threads: [MessageThread] = Fixtures.threads,
        folders: [Folder] = Fixtures.folders,
        channels: [Channel] = Fixtures.sidebarChannels,
        imessage: ChannelService? = nil
    ) {
        self.threads = threads
        self.folders = folders
        self.channels = channels
        self.selectedThreadID = threads.first?.id ?? "t1"
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

    /// Pull message history for a specific thread on demand.
    func loadMessages(for threadID: String) async {
        guard case .live = syncStatus else { return }
        if liveMessages[threadID] != nil { return }
        if let msgs = try? await imessage.messages(forThreadID: threadID, limit: 40) {
            liveMessages[threadID] = msgs
        }
    }
}
