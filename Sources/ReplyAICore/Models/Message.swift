import Foundation

/// One bubble in a thread. The rule engine and search index reference
/// messages by `rowID` (chat.db's `message.ROWID`) rather than `id`, so
/// the in-memory `UUID` is safe to regenerate across launches —
/// stable identity lives on the chat.db side, not on this struct.
///
/// `public` (REP-500): used as a parameter type in `LLMService.draft`
/// which is public so `ReplyAIMLX.MLXDraftService` can conform.
public struct Message: Identifiable, Hashable, Sendable {
    /// Direction of the bubble — `me` is the user, `them` is the contact.
    /// Stored as a raw String so existing on-disk fixtures and any future
    /// JSON projections stay stable as the enum evolves.
    public enum Author: String, Sendable, Hashable { case them, me }

    public let id: UUID
    public let from: Author
    public let text: String
    public let time: String
    /// chat.db `message.ROWID`, used by the rule engine to track which
    /// messages we've already evaluated. Zero for fixtures / mocks that
    /// don't care about dedup.
    public let rowID: Int64
    /// Projected from `message.cache_has_attachments` (1 = true). False
    /// for fixtures and mocks that don't set it explicitly.
    public let hasAttachment: Bool
    /// Projected from `message.is_read`. False if the column is NULL or 0.
    public let isRead: Bool
    /// Projected from `message.date_delivered`. Nil when the column is 0
    /// (message not yet delivered, or a received message where the field
    /// isn't populated).
    public let deliveredAt: Date?

    public init(
        id: UUID = UUID(),
        from: Author,
        text: String,
        time: String,
        rowID: Int64 = 0,
        hasAttachment: Bool = false,
        isRead: Bool = false,
        deliveredAt: Date? = nil
    ) {
        self.id = id
        self.from = from
        self.text = text
        self.time = time
        self.rowID = rowID
        self.hasAttachment = hasAttachment
        self.isRead = isRead
        self.deliveredAt = deliveredAt
    }
}
