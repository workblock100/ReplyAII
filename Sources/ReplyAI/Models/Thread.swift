import Foundation

struct MessageThread: Identifiable, Hashable, Sendable {
    let id: String
    let channel: Channel
    let name: String
    let avatar: String
    let preview: String
    let time: String
    let unread: Int
    let pinned: Bool
    let contextCount: Int
    let contextSummary: String?

    init(
        id: String,
        channel: Channel,
        name: String,
        avatar: String,
        preview: String,
        time: String,
        unread: Int = 0,
        pinned: Bool = false,
        contextCount: Int = 41,
        contextSummary: String? = nil
    ) {
        self.id = id
        self.channel = channel
        self.name = name
        self.avatar = avatar
        self.preview = preview
        self.time = time
        self.unread = unread
        self.pinned = pinned
        self.contextCount = contextCount
        self.contextSummary = contextSummary
    }
}
