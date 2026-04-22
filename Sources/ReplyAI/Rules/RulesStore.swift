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
    /// Hard cap preventing unbounded O(n) rule evaluation on every thread select.
    static let maxRules = 100

    private(set) var rules: [SmartRule] = []

    private let fileURL: URL

    init(fileURL: URL = RulesStore.defaultFileURL(), stats: Stats = Stats.shared) {
        self.fileURL = fileURL
        let (loaded, skips) = Self.loadOrSeed(from: fileURL)
        if skips > 0 { stats.recordRuleLoadSkips(skips) }
        self.rules = loaded
    }

    // MARK: - Mutations

    /// Appends `rule` to the store. Throws `RuleValidationError.tooManyRules`
    /// when `maxRules` has been reached.
    func add(_ rule: SmartRule) throws {
        guard rules.count < Self.maxRules else {
            throw RuleValidationError.tooManyRules(limit: Self.maxRules)
        }
        rules.append(rule)
        save()
    }

    /// Validates regex predicates in `rule.when` before storing. Use this
    /// path when the rule originates from user input; `add` is for
    /// programmatic/seed callers where patterns are known-good.
    func addValidating(_ rule: SmartRule) throws {
        try SmartRule.validatePredicateRegexes(rule.when)
        try add(rule)
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

    /// Returns loaded rules and a count of entries that failed to decode.
    /// Single malformed entries are skipped; the file must be valid JSON
    /// for any rules to load (invalid JSON falls back to seeds with 0
    /// skips because the file is treated as fully corrupt, not partial).
    nonisolated private static func loadOrSeed(from url: URL) -> ([SmartRule], skips: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let seeds = SmartRule.seedRules
            writeSync(seeds, to: url)
            return (seeds, skips: 0)
        }
        guard let data = try? Data(contentsOf: url) else {
            let seeds = SmartRule.seedRules
            writeSync(seeds, to: url)
            return (seeds, skips: 0)
        }
        // Decode element-by-element so one malformed entry doesn't
        // wipe the entire rules list.
        guard let rawArray = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            // File is not even valid JSON — treat as fully corrupt.
            let broken = url.appendingPathExtension("broken")
            try? FileManager.default.moveItem(at: url, to: broken)
            let seeds = SmartRule.seedRules
            writeSync(seeds, to: url)
            return (seeds, skips: 0)
        }
        var rules: [SmartRule] = []
        var skips = 0
        let dec = decoder()
        for element in rawArray {
            guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let rule = try? dec.decode(SmartRule.self, from: elementData) else {
                skips += 1
                continue
            }
            rules.append(rule)
        }
        return (rules, skips: skips)
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
