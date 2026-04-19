import Foundation
import Observation

/// On-disk rules store. JSON file at
/// `~/Library/Application Support/ReplyAI/rules.json`. Hand-editable.
///
/// Views mutate via `add`/`remove`/`toggle`; the store writes through
/// synchronously so a crash immediately after a toggle doesn't lose the
/// change. Loading on init: if the file doesn't exist, we seed with
/// `SmartRule.seedRules` so fresh installs have something on screen.
@Observable
@MainActor
final class RulesStore {
    private(set) var rules: [SmartRule] = []

    private let fileURL: URL

    init(fileURL: URL = RulesStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.rules = Self.loadOrSeed(from: fileURL)
    }

    // MARK: - Mutations

    func add(_ rule: SmartRule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: SmartRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[i] = rule
            save()
        }
    }

    func remove(_ id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func toggle(_ id: UUID) {
        if let i = rules.firstIndex(where: { $0.id == id }) {
            rules[i].active.toggle()
            save()
        }
    }

    /// Wipe to seed defaults. Used by "Factory reset" in set-privacy.
    func resetToSeeds() {
        rules = SmartRule.seedRules
        save()
    }

    // MARK: - IO

    nonisolated static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport?.appendingPathComponent("ReplyAI", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/ReplyAI", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("rules.json")
    }

    nonisolated private static func loadOrSeed(from url: URL) -> [SmartRule] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let seeds = SmartRule.seedRules
            writeSync(seeds, to: url)
            return seeds
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder().decode([SmartRule].self, from: data)
        } catch {
            // Corrupt file — fall back to seeds. Preserve the old file
            // with a ".broken" suffix so the user can recover it.
            let broken = url.appendingPathExtension("broken")
            try? FileManager.default.moveItem(at: url, to: broken)
            let seeds = SmartRule.seedRules
            writeSync(seeds, to: url)
            return seeds
        }
    }

    nonisolated private static func writeSync(_ rules: [SmartRule], to url: URL) {
        do {
            let data = try encoder().encode(rules)
            try data.write(to: url, options: .atomic)
        } catch {
            // Surface later; the in-memory copy is still correct.
        }
    }

    private func save() { Self.writeSync(rules, to: fileURL) }

    nonisolated private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    nonisolated private static func decoder() -> JSONDecoder { JSONDecoder() }
}
