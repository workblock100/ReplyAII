import Foundation
import Observation

@Observable
@MainActor
final class InboxViewModel {
    var selectedThreadID: String = "t1"
    var activeFolder: Folder.Kind = .all
    var activeTone: Tone = .warm

    let threads: [MessageThread]
    let folders: [Folder]
    let channels: [Channel]

    init(
        threads: [MessageThread] = Fixtures.threads,
        folders: [Folder] = Fixtures.folders,
        channels: [Channel] = Fixtures.sidebarChannels
    ) {
        self.threads = threads
        self.folders = folders
        self.channels = channels
    }

    var selectedThread: MessageThread {
        threads.first(where: { $0.id == selectedThreadID }) ?? threads[0]
    }

    func selectThread(_ id: String) {
        selectedThreadID = id
    }

    func messages(for thread: MessageThread) -> [Message] {
        Fixtures.messages(forThread: thread.id, fallback: thread.preview, time: thread.time)
    }

    var folderLabel: String {
        folders.first(where: { $0.id == activeFolder })?.label ?? "Inbox"
    }

    var needsYouCount: Int {
        threads.filter { $0.unread > 0 }.count
    }

    var handledCount: Int {
        threads.count - needsYouCount
    }

    func cycleTone() {
        activeTone = activeTone.cycled()
    }
}
