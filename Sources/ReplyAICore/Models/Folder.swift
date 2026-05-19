import Foundation

/// One sidebar bucket. `count` is a denormalized snapshot — the inbox
/// recomputes it whenever threads change, so a `Folder` value is safe
/// to compare across syncs without worrying that two equal `Kind` values
/// represent stale state.
struct Folder: Identifiable, Hashable, Sendable {
    /// Sidebar bucket identity. Raw String values are persisted into
    /// `Preferences.lastSelectedFolder`, so renaming a case is a
    /// migration. Order here defines sidebar display order.
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

/// Composer voice register. Raw String values are persisted into
/// rules.json (`setDefaultTone` action) and the per-thread draft cache,
/// so renaming a case is a migration. The order in `allCases` drives
/// the ⌘/ cycle order — keep it stable.
public enum Tone: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case warm = "Warm"
    case direct = "Direct"
    case playful = "Playful"

    public var id: String { rawValue }

    /// Next item in the cycle for ⌘/. Wraps around at the end of
    /// `allCases` so the composer always lands on a valid tone.
    public func cycled() -> Tone {
        let all = Tone.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}
