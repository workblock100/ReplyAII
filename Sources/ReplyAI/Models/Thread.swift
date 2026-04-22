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
    /// Full AppleScript `chat id` value from chat.db's `chat.guid` column,
    /// e.g. `iMessage;-;+15551234567` for 1:1 or `iMessage;+;chat1234567890`
    /// for groups. When present, IMessageSender uses it verbatim;
    /// otherwise it falls back to synthesizing a 1:1-shaped GUID from
    /// the channel + chat_identifier, which only works for 1:1 threads.
    let chatGUID: String?
    /// True when the last message in this thread has `cache_has_attachments = 1`
    /// in chat.db. Used by the rule engine instead of the "📎 Attachment" sentinel.
    let hasAttachment: Bool

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
        contextSummary: String? = nil,
        chatGUID: String? = nil,
        hasAttachment: Bool = false
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
        self.chatGUID = chatGUID
        self.hasAttachment = hasAttachment
    }
}
