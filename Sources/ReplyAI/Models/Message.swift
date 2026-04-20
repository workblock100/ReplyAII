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

    init(
        id: UUID = UUID(),
        from: Author,
        text: String,
        time: String,
        rowID: Int64 = 0
    ) {
        self.id = id
        self.from = from
        self.text = text
        self.time = time
        self.rowID = rowID
    }
}
