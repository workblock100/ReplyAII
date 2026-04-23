import Foundation
import Observation

/// Versioned wrapper written by `RulesStore.export(to:)` so future rule
/// schema changes can be detected on import rather than silently corrupting.
struct RulesExport: Codable {
    let version: Int
    let rules: [SmartRule]
}

enum RulesStoreError: Error {
    /// The export file declares a schema version the running build doesn't know how to read.
    case unsupportedExportVersion(Int)
}

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

    /// Most-recent batch of (ruleID, action) pairs that fired during rule
    /// evaluation. In-memory only — not persisted. Reset to empty before
    /// each new evaluation batch. Intended for the Rules debug surface.
    private(set) var lastFiredActions: [(ruleID: UUID, action: RuleAction)] = []

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

    // MARK: - Rule evaluation with debug capture

    /// Evaluates `rules` against `ctx` via `RuleEvaluator`, captures the
    /// resulting (ruleID, action) pairs into `lastFiredActions`, and returns
    /// the matched rules. `lastFiredActions` is reset to empty before each
    /// call so callers always see the result of the most recent batch only.
    @discardableResult
    func evaluate(for ctx: RuleContext) -> [SmartRule] {
        let matched = RuleEvaluator.matching(rules, in: ctx)
        lastFiredActions = matched.map { (ruleID: $0.id, action: $0.then) }
        return matched
    }

    // MARK: - Export / Import

    /// Current export schema version written by `export(to:)`.
    static let exportVersion = 1

    /// Encodes all current rules to JSON inside a `RulesExport` envelope and
    /// writes the result atomically to `url`. The version field lets future
    /// builds detect schema mismatches on import.
    func export(to url: URL) throws {
        let envelope = RulesExport(version: Self.exportVersion, rules: rules)
        let data = try Self.encoder().encode(envelope)
        try data.write(to: url, options: .atomic)
    }

    /// Merges rules from a versioned JSON file at `url` into the store.
    /// - Rules with a UUID already in the store are updated in place.
    /// - Rules with a new UUID are appended.
    /// - Nothing is deleted from the store.
    /// - Malformed rule entries are silently skipped (same policy as REP-024).
    /// - Throws `RulesStoreError.unsupportedExportVersion` for unknown versions.
    /// - Throws `CocoaError(.fileReadCorruptFile)` if the JSON structure is invalid.
    func `import`(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let rawObj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = rawObj["version"] as? Int else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard version == Self.exportVersion else {
            throw RulesStoreError.unsupportedExportVersion(version)
        }
        guard let rawRules = rawObj["rules"] as? [Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Element-by-element decode preserves the malformed-skip policy from REP-024.
        let dec = Self.decoder()
        for element in rawRules {
            guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let incoming = try? dec.decode(SmartRule.self, from: elementData) else {
                continue
            }
            if let i = rules.firstIndex(where: { $0.id == incoming.id }) {
                rules[i] = incoming
            } else {
                rules.append(incoming)
            }
        }
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
