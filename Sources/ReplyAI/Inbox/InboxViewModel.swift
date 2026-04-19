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
    /// repeatedly — each call is a fresh snapshot.
    func syncFromIMessage() async {
        syncStatus = .syncing
        await contacts.ensureAccess()   // prompts once, if .notDetermined
        do {
            let live = try await imessage.recentThreads(limit: 50)
            guard !live.isEmpty else {
                syncStatus = .failed("No conversations returned. chat.db may be empty on this account.")
                return
            }
            threads = live
            selectedThreadID = live.first?.id ?? selectedThreadID
            syncStatus = .live(at: Date())

            // Preload messages for the focused thread so the detail pane
            // is populated without a second permission round-trip.
            if let top = live.first,
               let msgs = try? await imessage.messages(forThreadID: top.id, limit: 40) {
                liveMessages[top.id] = msgs
            }
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

    /// Pull message history for a specific thread on demand.
    func loadMessages(for threadID: String) async {
        guard case .live = syncStatus else { return }
        if liveMessages[threadID] != nil { return }
        if let msgs = try? await imessage.messages(forThreadID: threadID, limit: 40) {
            liveMessages[threadID] = msgs
        }
    }
}
