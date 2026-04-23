import Foundation

/// Keys for every @AppStorage-persisted user preference. Namespaced so
/// they don't collide with anything macOS caches under our bundle id.
/// Factory reset wipes every default whose key starts with `pref.` —
/// EXCEPT keys listed in `PreferenceKey.wipeExemptions`.
enum PreferenceKey {
    static let crashReports   = "pref.privacy.crashReports"
    static let licenseUpdates = "pref.privacy.licenseUpdates"
    static let iCloudSync     = "pref.privacy.iCloudSync"
    static let defaultTone    = "pref.composer.defaultTone"
    static let useMLX         = "pref.model.useMLX"
    static let inboxThreadLimit = "pref.inbox.threadLimit"
    static let autoPrime        = "pref.drafts.autoPrime"
    /// When false, rules skip the bulk-sync path; only fire on thread select.
    static let autoApplyRulesOnSync = "pref.rules.autoApplyOnSync"
    /// Lifetime launch counter. Intentionally excluded from wipe() so
    /// first-run hints aren't shown again after a factory reset.
    static let launchCount = "pref.app.launchCount"
    /// Date of first ever launch. Set once on first init, never overwritten,
    /// excluded from wipe() so upgrade banners ("using ReplyAI since…") survive resets.
    static let firstLaunchDate = "pref.app.firstLaunchDate"

    /// Keys that match the `pref.` prefix but must survive `wipeReplyAIDefaults`.
    static let wipeExemptions: Set<String> = [launchCount, firstLaunchDate]
}

/// Ship-time defaults. Reset to these on factory wipe.
enum PreferenceDefaults {
    static let crashReports   = true
    static let licenseUpdates = true
    static let iCloudSync     = false
    static let defaultTone    = Tone.warm.rawValue
    /// Opt-in; enabling triggers a ~2 GB model download on first draft.
    static let useMLX         = false
    /// How many threads to load from chat.db on each sync pass.
    static let inboxThreadLimit = 50
    /// When true, ReplyAI generates a draft as soon as the user selects a thread.
    static let autoPrime        = true
    /// When true, rules run during every `syncFromIMessage` pass.
    static let autoApplyRulesOnSync = true
}

/// File-system paths that ReplyAI reads or writes at runtime.
/// Distinct from `PreferenceKey` (UserDefaults) — these are plain file URLs.
enum Preferences {
    /// JSON cache of the last-known thread list. Written after every successful
    /// sync so InboxViewModel can show recognizable rows on cold launch even
    /// when all channels fail to connect.
    static var lastThreadsCacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ReplyAI/last-threads-cache.json")
    }
}

/// Valid range for `pref.inbox.threadLimit`. The lower bound prevents a zero
/// LIMIT clause that would return no rows; the upper bound avoids query hangs
/// on very large databases.
enum PreferenceRange {
    static let threadLimit = 1...200
}

extension UserDefaults {
    /// Returns the stored `inboxThreadLimit` clamped to [1, 200]. A value
    /// outside this range (e.g. 0 or -5 written by a bug or migration) would
    /// produce an empty result set or an unbounded SQL query respectively.
    func clampedThreadLimit() -> Int {
        let raw = integer(forKey: PreferenceKey.inboxThreadLimit)
        let lo = PreferenceRange.threadLimit.lowerBound
        let hi = PreferenceRange.threadLimit.upperBound
        return max(lo, min(hi, raw))
    }

    /// Seed every ReplyAI preference to its shipping default. Idempotent
    /// — `register(defaults:)` never overwrites a user-set value.
    ///
    /// - Parameter defaults: UserDefaults instance to seed. Defaults to
    ///   `.standard` in production; tests pass an isolated suite.
    static func registerReplyAIDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            PreferenceKey.crashReports:     PreferenceDefaults.crashReports,
            PreferenceKey.licenseUpdates:   PreferenceDefaults.licenseUpdates,
            PreferenceKey.iCloudSync:       PreferenceDefaults.iCloudSync,
            PreferenceKey.defaultTone:      PreferenceDefaults.defaultTone,
            PreferenceKey.useMLX:           PreferenceDefaults.useMLX,
            PreferenceKey.inboxThreadLimit: PreferenceDefaults.inboxThreadLimit,
            PreferenceKey.autoPrime:            PreferenceDefaults.autoPrime,
            PreferenceKey.autoApplyRulesOnSync: PreferenceDefaults.autoApplyRulesOnSync,
        ])
    }

    /// Erase every preference ReplyAI owns. Used by "Factory reset" in
    /// set-privacy. Keys listed in `PreferenceKey.wipeExemptions` are
    /// preserved so lifetime metrics (e.g. launch count) survive resets.
    ///
    /// - Parameter defaults: UserDefaults instance to scrub. Defaults
    ///   to `.standard` in production; tests pass an isolated suite.
    static func wipeReplyAIDefaults(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("pref.") && !PreferenceKey.wipeExemptions.contains(key) {
            defaults.removeObject(forKey: key)
        }
    }
}
