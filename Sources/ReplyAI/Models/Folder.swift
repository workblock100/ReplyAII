import Foundation

struct Folder: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable, Hashable, CaseIterable {
        case all
        case priority
        case awaiting
        case snoozed
        case done
    }
    let id: Kind
    let label: String
    let count: Int
}

enum Tone: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case warm = "Warm"
    case direct = "Direct"
    case playful = "Playful"

    var id: String { rawValue }

    /// Previous item in the cycle for ⌘/.
    func cycled() -> Tone {
        let all = Tone.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}
