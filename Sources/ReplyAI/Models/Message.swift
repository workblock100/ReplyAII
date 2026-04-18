import Foundation

struct Message: Identifiable, Hashable, Sendable {
    enum Author: String, Sendable, Hashable { case them, me }

    let id: UUID
    let from: Author
    let text: String
    let time: String

    init(id: UUID = UUID(), from: Author, text: String, time: String) {
        self.id = id
        self.from = from
        self.text = text
        self.time = time
    }
}
