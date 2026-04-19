import Foundation

/// Keys for every @AppStorage-persisted user preference. Namespaced so
/// they don't collide with anything macOS caches under our bundle id.
/// Factory reset wipes every default whose key starts with `pref.`.
enum PreferenceKey {
    static let crashReports   = "pref.privacy.crashReports"
    static let licenseUpdates = "pref.privacy.licenseUpdates"
    static let iCloudSync     = "pref.privacy.iCloudSync"
    static let defaultTone    = "pref.composer.defaultTone"
}

/// Ship-time defaults. Reset to these on factory wipe.
enum PreferenceDefaults {
    static let crashReports   = true
    static let licenseUpdates = true
    static let iCloudSync     = false
    static let defaultTone    = Tone.warm.rawValue
}

extension UserDefaults {
    static func registerReplyAIDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.crashReports:   PreferenceDefaults.crashReports,
            PreferenceKey.licenseUpdates: PreferenceDefaults.licenseUpdates,
            PreferenceKey.iCloudSync:     PreferenceDefaults.iCloudSync,
            PreferenceKey.defaultTone:    PreferenceDefaults.defaultTone,
        ])
    }

    /// Erase every preference ReplyAI owns. Used by "Factory reset" in
    /// set-privacy.
    static func wipeReplyAIDefaults() {
        let ud = UserDefaults.standard
        for key in ud.dictionaryRepresentation().keys where key.hasPrefix("pref.") {
            ud.removeObject(forKey: key)
        }
    }
}
