import Foundation

/// Keys for every @AppStorage-persisted user preference. Namespaced so
/// they don't collide with anything macOS caches under our bundle id.
/// Factory reset wipes every default whose key starts with `pref.` —
/// EXCEPT keys listed in `PreferenceKey.wipeExemptions`.
enum PreferenceKey {
    /// Namespace prefix every ReplyAI-owned preference key starts with.
    /// `wipeReplyAIDefaults` matches on this prefix to scrub our keys
    /// without touching macOS-cached defaults under our bundle ID.
    /// Drift between the prefix used to *name* keys above and the
    /// prefix used to *match* keys at wipe time leaves stale state on
    /// disk after a factory reset — keys named with the new prefix
    /// remain orphaned because the wipe loop only sweeps the old. Pinned
    /// by `PreferencesTests.testWipeNamespacePrefixIsFrozen`.
    static let wipeNamespacePrefix = "pref."

    /// Privacy toggle for opt-in crash reports surfaced in `set-privacy`.
    /// Read by the crash-reporting hook at upload time, so flipping it
    /// takes effect without an app restart.
    static let crashReports   = "pref.privacy.crashReports"
    /// Toggles the license-server liveness probe. Defaults on so paid
    /// installs stay validated; the user can opt out (offline-only).
    static let licenseUpdates = "pref.privacy.licenseUpdates"
    /// Reserved — iCloud sync of drafts/rules is scoped out of v1; the
    /// key exists so the toggle in `set-privacy` has a stable backing
    /// store for when the feature lands. Reads as false today.
    static let iCloudSync     = "pref.privacy.iCloudSync"
    /// User's preferred composer tone. Persisted as `Tone.rawValue`
    /// ("Warm"/"Direct"/"Playful"). The composer falls back to `.warm`
    /// when the key is absent or its raw value drifts off
    /// `Tone.allCases` (handled in `Tone(rawValue:)` callers).
    static let defaultTone    = "pref.composer.defaultTone"
    /// Toggles whether the on-device MLX model loads on launch. Setting
    /// false pins the StubLLMService — currently the smoke-test workaround
    /// for REP-ALERT-260504-1650 (MLX dependency load path crashes the
    /// app on launch). The structural fix is REP-501→REP-505 SPM split.
    static let useMLX         = "pref.model.useMLX"
    /// Cap on the number of threads `recentThreads(limit:)` requests per
    /// sync. Tuned downward on slower Macs; default 50 matches the
    /// `ChannelService.recentThreads()` convenience overload.
    static let inboxThreadLimit = "pref.inbox.threadLimit"
    /// When true, opening a thread immediately kicks off draft generation
    /// in the user's default tone so the composer is hot when the user
    /// arrives at it. False burns less compute but adds latency to every
    /// thread visit.
    static let autoPrime        = "pref.drafts.autoPrime"
    /// When false, rules skip the bulk-sync path; only fire on thread select.
    static let autoApplyRulesOnSync = "pref.rules.autoApplyOnSync"
    /// Lifetime launch counter. Intentionally excluded from wipe() so
    /// first-run hints aren't shown again after a factory reset.
    static let launchCount = "pref.app.launchCount"
    /// Date of first ever launch. Set once on first init, never overwritten,
    /// excluded from wipe() so upgrade banners ("using ReplyAI since…") survive resets.
    static let firstLaunchDate = "pref.app.firstLaunchDate"
    /// Whether the app is showing demo fixture threads because no real sync has succeeded yet.
    /// Starts true; cleared to false after any sync returns ≥1 real thread. Exempt from wipe()
    /// so the user doesn't see demo mode re-appear after a factory reset.
    static let demoModeActive = "pref.inbox.demoModeActive"

    /// Set to true after the user clicks "Get started" on the welcome flow.
    /// Gates whether the main window opens to the inbox (true) or the
    /// welcome screen (false). Survives factory wipe via wipeExemptions
    /// so a returning user never has to re-onboard.
    static let onboardingCompleted = "pref.app.onboardingCompleted"

    /// Per-channel on/off switches. iMessage defaults on; Slack defaults off until OAuth.
    /// Both are wipe-eligible — factory reset should clear channel tokens and state.
    static let iMessageEnabled = "pref.channels.iMessageEnabled"
    static let slackEnabled    = "pref.channels.slackEnabled"

    /// Timestamp of the last successful inbox sync returning ≥1 thread.
    /// Nil if no successful sync has occurred (fresh install or post-wipe).
    static let inboxLastSyncDate = "pref.inbox.lastSyncDate"

    /// Short sample messages written in the user's voice, used by PromptBuilder to
    /// steer reply tone toward the user's natural style. Defaults to []. Max 20
    /// entries; each entry is capped at 500 chars — enforced at the setter.
    static let voiceExampleMessages = "pref.voice.exampleMessages"

    /// Keys that match the `pref.` prefix but must survive `wipeReplyAIDefaults`.
    static let wipeExemptions: Set<String> = [launchCount, firstLaunchDate, demoModeActive, onboardingCompleted]
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
    /// Starts true on fresh install; cleared after first successful real sync.
    static let demoModeActive = true
    /// iMessage channel enabled by default; opt-out via Settings.
    static let iMessageEnabled = true
    /// Slack channel disabled until the user completes OAuth.
    static let slackEnabled    = false
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

    /// Maximum number of voice-example messages persisted under
    /// `PreferenceKey.voiceExampleMessages`. The cap balances voice
    /// quality (more examples → better matching) against UserDefaults
    /// payload size (a single AppStorage write blocks the main
    /// run-loop) and prompt-builder budget (each example burns chars
    /// against `PromptBuilder.historyCharBudget`). Drift here changes
    /// every shipped user's voice-profile size.
    static let maxVoiceExamples = 20

    /// Maximum chars per individual voice-example message before
    /// `setVoiceExampleMessages(_:)` truncates. Drift up balloons
    /// UserDefaults; drift down silently clips legitimate examples.
    static let maxVoiceExampleLength = 500
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
            PreferenceKey.demoModeActive:       PreferenceDefaults.demoModeActive,
            PreferenceKey.iMessageEnabled:      PreferenceDefaults.iMessageEnabled,
            PreferenceKey.slackEnabled:         PreferenceDefaults.slackEnabled,
        ])
    }

    /// Returns the stored voice example messages, or [] if none set.
    func voiceExampleMessages() -> [String] {
        stringArray(forKey: PreferenceKey.voiceExampleMessages) ?? []
    }

    /// Stores voice example messages with enforcement: list capped at
    /// `PreferenceRange.maxVoiceExamples` entries, each entry truncated
    /// to `PreferenceRange.maxVoiceExampleLength` chars. Enforced at
    /// write time.
    func setVoiceExampleMessages(_ messages: [String]) {
        let sanitized = messages
            .prefix(PreferenceRange.maxVoiceExamples)
            .map {
                $0.count > PreferenceRange.maxVoiceExampleLength
                    ? String($0.prefix(PreferenceRange.maxVoiceExampleLength))
                    : $0
            }
        set(Array(sanitized), forKey: PreferenceKey.voiceExampleMessages)
    }

    /// Erase every preference ReplyAI owns. Used by "Factory reset" in
    /// set-privacy. Keys listed in `PreferenceKey.wipeExemptions` are
    /// preserved so lifetime metrics (e.g. launch count) survive resets.
    ///
    /// - Parameter defaults: UserDefaults instance to scrub. Defaults
    ///   to `.standard` in production; tests pass an isolated suite.
    static func wipeReplyAIDefaults(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(PreferenceKey.wipeNamespacePrefix)
            && !PreferenceKey.wipeExemptions.contains(key) {
            defaults.removeObject(forKey: key)
        }
    }
}
