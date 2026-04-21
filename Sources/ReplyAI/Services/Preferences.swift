import Foundation

/// Keys for every @AppStorage-persisted user preference. Namespaced so
/// they don't collide with anything macOS caches under our bundle id.
/// Factory reset wipes every default whose key starts with `pref.`.
enum PreferenceKey {
    static let crashReports   = "pref.privacy.crashReports"
    static let licenseUpdates = "pref.privacy.licenseUpdates"
    static let iCloudSync     = "pref.privacy.iCloudSync"
    static let defaultTone    = "pref.composer.defaultTone"
    static let useMLX         = "pref.model.useMLX"
}

/// Ship-time defaults. Reset to these on factory wipe.
enum PreferenceDefaults {
    static let crashReports   = true
    static let licenseUpdates = true
    static let iCloudSync     = false
    static let defaultTone    = Tone.warm.rawValue
    /// Opt-in; enabling triggers a ~2 GB model download on first draft.
    static let useMLX         = false
}

extension UserDefaults {
    /// Seed every ReplyAI preference to its shipping default. Idempotent
    /// — `register(defaults:)` never overwrites a user-set value.
    ///
    /// - Parameter defaults: UserDefaults instance to seed. Defaults to
    ///   `.standard` in production; tests pass an isolated suite.
    static func registerReplyAIDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            PreferenceKey.crashReports:   PreferenceDefaults.crashReports,
            PreferenceKey.licenseUpdates: PreferenceDefaults.licenseUpdates,
            PreferenceKey.iCloudSync:     PreferenceDefaults.iCloudSync,
            PreferenceKey.defaultTone:    PreferenceDefaults.defaultTone,
            PreferenceKey.useMLX:         PreferenceDefaults.useMLX,
        ])
    }

    /// Erase every preference ReplyAI owns. Used by "Factory reset" in
    /// set-privacy.
    ///
    /// - Parameter defaults: UserDefaults instance to scrub. Defaults
    ///   to `.standard` in production; tests pass an isolated suite.
    static func wipeReplyAIDefaults(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pref.") {
            defaults.removeObject(forKey: key)
        }
    }
}
