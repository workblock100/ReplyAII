import Foundation

struct Message: Identifiable, Hashable, Sendable {
    enum Author: String, Sendable, Hashable { case them, me }

    let id: UUID
    let from: Author
    let text: String
    let time: String
    /// chat.db `message.ROWID`, used by the rule engine to track which
    /// messages we've already evaluated. Zero for fixtures / mocks that
    /// don't care about dedup.
    let rowID: Int64
    /// Projected from `message.cache_has_attachments` (1 = true). False
    /// for fixtures and mocks that don't set it explicitly.
    let hasAttachment: Bool
    /// Projected from `message.is_read`. False if the column is NULL or 0.
    let isRead: Bool
    /// Projected from `message.date_delivered`. Nil when the column is 0
    /// (message not yet delivered, or a received message where the field
    /// isn't populated).
    let deliveredAt: Date?

    init(
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
