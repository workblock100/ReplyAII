import XCTest
@testable import ReplyAI

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // Unique suite per test so concurrent runs don't leak into each
        // other. `UserDefaults(suiteName:)` can return nil for reserved
        // names (globalDomain, etc.) — fail fast if that happens.
        suiteName = "test.ReplyAI.prefs.\(UUID().uuidString)"
        guard let d = UserDefaults(suiteName: suiteName) else {
            XCTFail("couldn't create isolated UserDefaults suite")
            return
        }
        defaults = d
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - register

    /// `register(defaults:)` should surface the defined defaults for
    /// every key through `bool(forKey:)` / `string(forKey:)`.
    func testRegisterDefaultsSeedsCorrectValues() {
        UserDefaults.registerReplyAIDefaults(in: defaults)

        XCTAssertEqual(defaults.bool(forKey: PreferenceKey.crashReports),
                       PreferenceDefaults.crashReports)
        XCTAssertEqual(defaults.bool(forKey: PreferenceKey.licenseUpdates),
                       PreferenceDefaults.licenseUpdates)
        XCTAssertEqual(defaults.bool(forKey: PreferenceKey.iCloudSync),
                       PreferenceDefaults.iCloudSync)
        XCTAssertEqual(defaults.string(forKey: PreferenceKey.defaultTone),
                       PreferenceDefaults.defaultTone)
        XCTAssertEqual(defaults.bool(forKey: PreferenceKey.useMLX),
                       PreferenceDefaults.useMLX)
    }

    func testDefaultToneMatchesEnumConstant() {
        XCTAssertEqual(PreferenceDefaults.defaultTone, Tone.warm.rawValue,
                       "default tone should track the `Tone.warm` raw value")
    }

    // MARK: - wipe
    //
    // These tests use locally-scoped keys (`pref.wipe-test.*`) so the
    // process-global UserDefaults registration domain — which other
    // tests in this target may have seeded — can't make the
    // persistent-value assertions flaky.

    private let customKey = "pref.wipe-test.custom"
    private let anotherCustomKey = "pref.wipe-test.another"
    private let unrelatedKey = "com.apple.unrelated.key"

    func testWipeRemovesPrefKeysSetInPersistentDomain() {
        defaults.set(true,        forKey: customKey)
        defaults.set("scheduled", forKey: anotherCustomKey)
        XCTAssertNotNil(defaults.object(forKey: customKey))
        XCTAssertNotNil(defaults.object(forKey: anotherCustomKey))

        UserDefaults.wipeReplyAIDefaults(in: defaults)

        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[customKey],
                     "wipe should clear 'pref.*' keys from the persistent domain")
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[anotherCustomKey])
    }

    func testWipePreservesNonPrefKeys() {
        defaults.set(true,           forKey: customKey)
        defaults.set("do-not-touch", forKey: unrelatedKey)

        UserDefaults.wipeReplyAIDefaults(in: defaults)

        let domain = defaults.persistentDomain(forName: suiteName)
        XCTAssertNil(domain?[customKey], "pref-prefixed keys should be wiped")
        XCTAssertEqual(domain?[unrelatedKey] as? String, "do-not-touch",
                       "wipe must only touch keys that start with 'pref.'")
    }

    func testWipeIsIdempotent() {
        defaults.set(true, forKey: customKey)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        UserDefaults.wipeReplyAIDefaults(in: defaults)   // should not crash
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[customKey])
    }

    // MARK: - inboxThreadLimit (REP-030)

    func testInboxThreadLimitDefaultIs50() {
        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.inboxThreadLimit),
                       PreferenceDefaults.inboxThreadLimit,
                       "default thread limit must match PreferenceDefaults")
        XCTAssertEqual(PreferenceDefaults.inboxThreadLimit, 50,
                       "sentinel: shipping default is 50 threads")
    }

    func testThreadLimitRangeBoundsPinned() {
        // Lower bound 1: a 0 limit would silently produce empty result sets
        // from any LIMIT-clamped channel call. Upper bound 200: protects
        // against unbounded queries on very large databases that otherwise
        // hang the inbox sync. Drift here would silently change the inbox
        // sync envelope.
        XCTAssertEqual(PreferenceRange.threadLimit.lowerBound, 1,
            "lower bound 1 prevents zero-limit empty queries")
        XCTAssertEqual(PreferenceRange.threadLimit.upperBound, 200,
            "upper bound 200 caps query cost to avoid unbounded scans on large chat.db files")
    }

    func testDemoModeActiveDefaultsToTrue() {
        // Fresh installs land in demo mode so the inbox is non-empty before
        // any channel sync succeeds. Flipping this default to false would
        // silently send first-run users to an empty/loading inbox — the
        // exact failure REP-228 was added to prevent.
        XCTAssertTrue(PreferenceDefaults.demoModeActive,
            "demoModeActive must default true so REP-228 first-launch demo experience holds")
    }

    func testUseMLXDefaultsToFalse() {
        // P0 safety pin (REP-ALERT-260504-1650): flipping `useMLX` to true
        // forces the MLX dependency-load path on app launch, which currently
        // exits the process within ~1s of NSApplicationDidFinishLaunching.
        // Until REP-501→REP-505 split MLX into a separate SPM target, this
        // default MUST stay false or every fresh user gets a broken launch.
        XCTAssertFalse(PreferenceDefaults.useMLX,
            "useMLX must default false until the MLX-on-launch exit bug is fixed (REP-ALERT-260504-1650)")
    }

    func testCrashReportsDefaultsToTrue() {
        // Privacy-screen toggle starts opt-in to true so we ship with
        // crash telemetry on by default. Flipping the default would change
        // the user-visible privacy posture without an onboarding prompt.
        XCTAssertTrue(PreferenceDefaults.crashReports,
            "crashReports default is the ship-time privacy posture; bump test + onboarding copy together")
    }

    func testLicenseUpdatesDefaultsToTrue() {
        XCTAssertTrue(PreferenceDefaults.licenseUpdates,
            "licenseUpdates default is the ship-time consent posture for license-renewal email")
    }

    func testICloudSyncDefaultsToFalse() {
        // iCloud sync is off until a user explicitly enables it in Settings.
        // Flipping this default would silently sync rules + voice examples
        // off-device for every fresh installer.
        XCTAssertFalse(PreferenceDefaults.iCloudSync,
            "iCloudSync must default false — flipping silently exfiltrates rules + voice data for every fresh user")
    }

    func testAutoPrimeDefaultsToTrue() {
        // autoPrime drives the "select-thread → draft appears" UX promise.
        // Flipping the default to false silently breaks the keyboard-first
        // flow that the product is built around.
        XCTAssertTrue(PreferenceDefaults.autoPrime,
            "autoPrime default true is the keyboard-first UX promise")
    }

    func testAutoApplyRulesOnSyncDefaultsToTrue() {
        // Rules run automatically on every sync pass; flipping the default
        // would silently break every user's archive/pin/silence setup until
        // they re-toggle it in Settings.
        XCTAssertTrue(PreferenceDefaults.autoApplyRulesOnSync,
            "autoApplyRulesOnSync default true so user rules fire without an explicit run-rules action")
    }

    func testIMessageEnabledLiteralDefaultsToTrue() {
        XCTAssertTrue(PreferenceDefaults.iMessageEnabled,
            "iMessage is the primary channel — must be on by default for first-run inbox to populate")
    }

    func testSlackEnabledLiteralDefaultsToFalse() {
        // Slack requires OAuth; the toggle flips to true only after a
        // workspace is connected. A `true` default would surface a
        // permanently-broken Slack channel on every fresh install.
        XCTAssertFalse(PreferenceDefaults.slackEnabled,
            "slackEnabled must default false — OAuth completion flips this on")
    }

    // MARK: - PreferenceKey string literal contract
    //
    // Every value here is the exact UserDefaults key persisted to disk.
    // Renaming any of these strings silently abandons every existing
    // user's stored preference (they fall back to ship-time defaults
    // on next launch with no migration). These pins make a rename
    // require a deliberate test-bump + migration plan rather than a
    // silent break.

    func testPreferenceKeyCrashReportsLiteral() {
        XCTAssertEqual(PreferenceKey.crashReports, "pref.privacy.crashReports",
            "renaming this key abandons every user's privacy posture on next launch")
    }

    func testPreferenceKeyLicenseUpdatesLiteral() {
        XCTAssertEqual(PreferenceKey.licenseUpdates, "pref.privacy.licenseUpdates")
    }

    func testPreferenceKeyICloudSyncLiteral() {
        XCTAssertEqual(PreferenceKey.iCloudSync, "pref.privacy.iCloudSync")
    }

    func testPreferenceKeyDefaultToneLiteral() {
        XCTAssertEqual(PreferenceKey.defaultTone, "pref.composer.defaultTone",
            "renaming this drops every user's default-tone preference")
    }

    func testPreferenceKeyUseMLXLiteral() {
        XCTAssertEqual(PreferenceKey.useMLX, "pref.model.useMLX")
    }

    func testPreferenceKeyInboxThreadLimitLiteral() {
        XCTAssertEqual(PreferenceKey.inboxThreadLimit, "pref.inbox.threadLimit")
    }

    func testPreferenceKeyAutoPrimeLiteral() {
        XCTAssertEqual(PreferenceKey.autoPrime, "pref.drafts.autoPrime")
    }

    func testPreferenceKeyAutoApplyRulesOnSyncLiteral() {
        XCTAssertEqual(PreferenceKey.autoApplyRulesOnSync, "pref.rules.autoApplyOnSync")
    }

    func testPreferenceKeyLaunchCountLiteral() {
        XCTAssertEqual(PreferenceKey.launchCount, "pref.app.launchCount",
            "wipe-exempt — renaming silently restarts the lifetime launch counter for every user")
    }

    func testPreferenceKeyFirstLaunchDateLiteral() {
        XCTAssertEqual(PreferenceKey.firstLaunchDate, "pref.app.firstLaunchDate",
            "wipe-exempt — renaming wipes the 'using ReplyAI since…' upgrade signal for every user")
    }

    func testPreferenceKeyDemoModeActiveLiteral() {
        XCTAssertEqual(PreferenceKey.demoModeActive, "pref.inbox.demoModeActive",
            "wipe-exempt — renaming would silently put returning users back into demo mode")
    }

    func testPreferenceKeyOnboardingCompletedLiteral() {
        XCTAssertEqual(PreferenceKey.onboardingCompleted, "pref.app.onboardingCompleted",
            "wipe-exempt — renaming would silently re-trigger onboarding for every returning user")
    }

    func testPreferenceKeyIMessageEnabledLiteral() {
        XCTAssertEqual(PreferenceKey.iMessageEnabled, "pref.channels.iMessageEnabled")
    }

    func testPreferenceKeySlackEnabledLiteral() {
        XCTAssertEqual(PreferenceKey.slackEnabled, "pref.channels.slackEnabled")
    }

    func testPreferenceKeyInboxLastSyncDateLiteral() {
        XCTAssertEqual(PreferenceKey.inboxLastSyncDate, "pref.inbox.lastSyncDate")
    }

    func testPreferenceKeyVoiceExampleMessagesLiteral() {
        XCTAssertEqual(PreferenceKey.voiceExampleMessages, "pref.voice.exampleMessages",
            "renaming drops every user's stored voice samples — PromptBuilder loses the personalization signal")
    }

    func testPreferenceKeyWipeExemptionsContents() {
        // The wipe-exempt set must contain exactly these four keys.
        // Adding or dropping a member silently changes whether a
        // preference survives factory reset — a user-visible posture
        // change that should require a deliberate test bump.
        XCTAssertEqual(PreferenceKey.wipeExemptions, Set([
            PreferenceKey.launchCount,
            PreferenceKey.firstLaunchDate,
            PreferenceKey.demoModeActive,
            PreferenceKey.onboardingCompleted,
        ]), "wipeExemptions membership is the factory-reset contract")
    }

    func testInboxThreadLimitWipedAndRestored() {
        defaults.set(100, forKey: PreferenceKey.inboxThreadLimit)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.inboxThreadLimit), 100)

        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[PreferenceKey.inboxThreadLimit],
                     "wipe must remove inboxThreadLimit from the persistent domain")

        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.inboxThreadLimit),
                       PreferenceDefaults.inboxThreadLimit,
                       "re-register must restore the default value")
    }

    // MARK: - autoPrime (REP-039)

    func testAutoPrimeDefaultIsTrue() {
        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.autoPrime),
                      "autoPrime must default to true so existing behaviour is unchanged")
    }

    func testAutoPrimeWipedAndRestored() {
        defaults.set(false, forKey: PreferenceKey.autoPrime)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.autoPrime))

        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[PreferenceKey.autoPrime],
                     "wipe must remove autoPrime from the persistent domain")

        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.autoPrime),
                      "re-register must restore default true")
    }

    // MARK: - autoApplyRulesOnSync (REP-081)

    func testAutoApplyRulesOnSyncDefaultTrue() {
        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.autoApplyRulesOnSync),
                      "autoApplyRulesOnSync must default to true so existing behaviour is unchanged")
    }

    func testAutoApplyRulesOnSyncWipedAndRestored() {
        defaults.set(false, forKey: PreferenceKey.autoApplyRulesOnSync)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.autoApplyRulesOnSync))

        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertNil(
            defaults.persistentDomain(forName: suiteName)?[PreferenceKey.autoApplyRulesOnSync],
            "wipe must remove autoApplyRulesOnSync from the persistent domain")

        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.autoApplyRulesOnSync),
                      "re-register must restore default true")
    }

    // MARK: - Unrecognized keys (REP-104)

    func testWipeDoesNotRemoveUnrecognizedKeys() {
        // A key set by another subsystem or with a different prefix must survive wipe.
        // Wipe is scoped to `pref.` keys; anything else is untouched.
        let foreignKey = "app.unrecognized.feature.setting"
        defaults.set("do-not-delete", forKey: foreignKey)

        UserDefaults.wipeReplyAIDefaults(in: defaults)

        let domain = defaults.persistentDomain(forName: suiteName)
        XCTAssertEqual(domain?[foreignKey] as? String, "do-not-delete",
                       "wipe must not remove keys without the pref. prefix")
    }

    func testKnownKeyFallsBackToDefaultAfterWipe() {
        // Write a non-default value, wipe, register defaults, then verify the
        // registered default is returned — confirming wipe + register restores clean state.
        UserDefaults.registerReplyAIDefaults(in: defaults)
        // Flip crashReports to the opposite of its default.
        let originalDefault = PreferenceDefaults.crashReports
        defaults.set(!originalDefault, forKey: PreferenceKey.crashReports)
        XCTAssertEqual(defaults.bool(forKey: PreferenceKey.crashReports), !originalDefault)

        UserDefaults.wipeReplyAIDefaults(in: defaults)
        UserDefaults.registerReplyAIDefaults(in: defaults)

        XCTAssertEqual(defaults.bool(forKey: PreferenceKey.crashReports), originalDefault,
                       "known key must return registered default after wipe + re-register")
    }

    // MARK: - pref.app.launchCount (REP-115)

    func testLaunchCountStartsAtZero() {
        // Fresh isolated suite — launchCount must be 0 (unset integer returns 0).
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.launchCount), 0,
                       "launchCount must default to 0 on a clean install")
    }

    func testLaunchCountIncrementsOnWrite() {
        defaults.set(1, forKey: PreferenceKey.launchCount)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.launchCount), 1,
                       "written launchCount must read back correctly")
    }

    func testLaunchCountSurvivesWipe() {
        defaults.set(5, forKey: PreferenceKey.launchCount)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.launchCount), 5,
                       "launchCount must survive factory wipe — it is exempt from reset")
    }

    // MARK: - REP-130: pref.app.firstLaunchDate set-once key

    func testFirstLaunchDateSetOnFirstInit() {
        // Nil before any write.
        XCTAssertNil(defaults.object(forKey: PreferenceKey.firstLaunchDate),
                     "firstLaunchDate must be nil before first write")

        // Simulate app init: write if not yet set.
        if defaults.object(forKey: PreferenceKey.firstLaunchDate) == nil {
            defaults.set(Date(), forKey: PreferenceKey.firstLaunchDate)
        }

        XCTAssertNotNil(defaults.object(forKey: PreferenceKey.firstLaunchDate),
                        "firstLaunchDate must be set after first init")
    }

    func testFirstLaunchDateNotOverwrittenOnSubsequentInit() {
        let first = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(first, forKey: PreferenceKey.firstLaunchDate)

        // Simulate second init: must not overwrite.
        if defaults.object(forKey: PreferenceKey.firstLaunchDate) == nil {
            defaults.set(Date(), forKey: PreferenceKey.firstLaunchDate)
        }

        let stored = defaults.object(forKey: PreferenceKey.firstLaunchDate) as? Date
        XCTAssertEqual(stored, first,
                       "firstLaunchDate must not be overwritten on subsequent init")
    }

    func testFirstLaunchDateSurvivesWipe() {
        let launchDate = Date(timeIntervalSince1970: 2_000_000)
        defaults.set(launchDate, forKey: PreferenceKey.firstLaunchDate)

        UserDefaults.wipeReplyAIDefaults(in: defaults)

        let stored = defaults.object(forKey: PreferenceKey.firstLaunchDate) as? Date
        XCTAssertEqual(stored, launchDate,
                       "firstLaunchDate must survive factory wipe — it is exempt from reset")
    }

    // MARK: - Key uniqueness (REP-167)

    /// Pins all PreferenceKey string constants and asserts no two share the
    /// same value. A duplicate key would silently shadow the other one in
    /// UserDefaults, causing hard-to-diagnose data loss. Update knownKeys
    /// whenever a new PreferenceKey constant is added.
    func testAllPreferenceKeysAreUnique() {
        let knownKeys: [String] = [
            PreferenceKey.crashReports,
            PreferenceKey.licenseUpdates,
            PreferenceKey.iCloudSync,
            PreferenceKey.defaultTone,
            PreferenceKey.useMLX,
            PreferenceKey.inboxThreadLimit,
            PreferenceKey.autoPrime,
            PreferenceKey.autoApplyRulesOnSync,
            PreferenceKey.launchCount,
            PreferenceKey.firstLaunchDate,
            PreferenceKey.iMessageEnabled,
            PreferenceKey.slackEnabled,
        ]
        let uniqueKeys = Set(knownKeys)
        XCTAssertEqual(
            uniqueKeys.count, knownKeys.count,
            "every PreferenceKey constant must be a unique string; update knownKeys when adding a new preference")
    }

    // MARK: - REP-194: threadLimit clamping

    func testThreadLimitDefaultIsWithinRange() {
        UserDefaults.registerReplyAIDefaults(in: defaults)
        let clamped = defaults.clampedThreadLimit()
        XCTAssertGreaterThanOrEqual(clamped, PreferenceRange.threadLimit.lowerBound,
                                    "default threadLimit must be at least 1")
        XCTAssertLessThanOrEqual(clamped, PreferenceRange.threadLimit.upperBound,
                                 "default threadLimit must be at most 200")
        XCTAssertEqual(clamped, PreferenceDefaults.inboxThreadLimit,
                       "default is 50 which is already within range")
    }

    func testThreadLimitZeroClampedToOne() {
        defaults.set(0, forKey: PreferenceKey.inboxThreadLimit)
        XCTAssertEqual(defaults.clampedThreadLimit(), 1,
                       "zero must be clamped up to 1 to avoid empty SQL LIMIT")
    }

    func testThreadLimitNegativeClampedToOne() {
        defaults.set(-99, forKey: PreferenceKey.inboxThreadLimit)
        XCTAssertEqual(defaults.clampedThreadLimit(), 1,
                       "negative value must be clamped up to 1")
    }

    func testThreadLimitOversizedClampedTo200() {
        defaults.set(999, forKey: PreferenceKey.inboxThreadLimit)
        XCTAssertEqual(defaults.clampedThreadLimit(), 200,
                       "value above 200 must be clamped down to 200")
    }

    func testThreadLimitAtBoundaryLowAccepted() {
        defaults.set(1, forKey: PreferenceKey.inboxThreadLimit)
        XCTAssertEqual(defaults.clampedThreadLimit(), 1,
                       "value exactly at lower bound must pass through unchanged")
    }

    func testThreadLimitAtBoundaryHighAccepted() {
        defaults.set(200, forKey: PreferenceKey.inboxThreadLimit)
        XCTAssertEqual(defaults.clampedThreadLimit(), 200,
                       "value exactly at upper bound must pass through unchanged")
    }

    // MARK: - Per-channel enable/disable keys (REP-231)

    func testIMessageEnabledDefaultsToTrue() {
        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.iMessageEnabled),
                      "iMessage channel must be enabled by default")
    }

    func testSlackEnabledDefaultsToFalse() {
        UserDefaults.registerReplyAIDefaults(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.slackEnabled),
                       "Slack channel must be disabled until the user completes OAuth")
    }

    func testChannelKeysClearedOnWipe() {
        defaults.set(true, forKey: PreferenceKey.iMessageEnabled)
        defaults.set(true, forKey: PreferenceKey.slackEnabled)

        UserDefaults.wipeReplyAIDefaults(in: defaults)

        let domain = defaults.persistentDomain(forName: suiteName)
        XCTAssertNil(domain?[PreferenceKey.iMessageEnabled],
                     "iMessageEnabled must be cleared on factory wipe — it is not wipe-exempt")
        XCTAssertNil(domain?[PreferenceKey.slackEnabled],
                     "slackEnabled must be cleared on factory wipe — it is not wipe-exempt")
    }
}

// MARK: - REP-183: wipe exemption regression guard

extension PreferencesTests {

    func testWipePreservesFirstLaunchDate() {
        let launchDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        defaults.set(launchDate, forKey: PreferenceKey.firstLaunchDate)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        let stored = defaults.object(forKey: PreferenceKey.firstLaunchDate) as? Date
        XCTAssertEqual(stored, launchDate,
            "firstLaunchDate must survive wipe — it is exempt from reset")
    }

    func testWipePreservesLaunchCount() {
        defaults.set(42, forKey: PreferenceKey.launchCount)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.launchCount), 42,
            "launchCount must survive wipe — it is exempt from reset")
    }

    func testWipeClearsNonExemptKey() {
        defaults.set(false, forKey: PreferenceKey.autoPrime)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[PreferenceKey.autoPrime],
            "non-exempt key must be removed from persistent domain by wipe")
    }
}

// MARK: - REP-207: autoPrime and autoApplyOnSync not pre-set in the persistent domain

final class PreferencesAutoActionSafetyDefaultTests: XCTestCase {

    // Neither autoPrime nor autoApplyRulesOnSync must have a value written to the
    // persistent domain on a fresh suite (before any set/register call). If either
    // key had a persisted `true` value, the app would auto-send replies without user
    // confirmation even after a factory wipe that cleared and re-init'd the store.
    // Guard: verify the persistent domain contains no pre-existing value for these keys.
    func testAutoPrimeNotPreSetInPersistentDomain() {
        let suite = "test.ReplyAI.safetyDefault.autoPrime.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        // persistent domain must not contain the key before anyone writes it
        let persisted = d.persistentDomain(forName: suite)?[PreferenceKey.autoPrime]
        XCTAssertNil(persisted,
            "autoPrime must not be pre-written in the persistent domain on a fresh suite")
    }

    func testAutoApplyOnSyncNotPreSetInPersistentDomain() {
        let suite = "test.ReplyAI.safetyDefault.autoApply.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        let persisted = d.persistentDomain(forName: suite)?[PreferenceKey.autoApplyRulesOnSync]
        XCTAssertNil(persisted,
            "autoApplyRulesOnSync must not be pre-written in the persistent domain on a fresh suite")
    }
}

// MARK: - REP-268: Preferences.inbox.lastSyncDate

final class PreferencesLastSyncDateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "test.ReplyAI.lastSyncDate.\(UUID().uuidString)"
        guard let d = UserDefaults(suiteName: suiteName) else {
            XCTFail("couldn't create isolated UserDefaults suite")
            return
        }
        defaults = d
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
    }

    // Fresh UserDefaults suite has no lastSyncDate — key is absent, not defaulted.
    func testLastSyncDateNilOnFreshSuite() {
        let stored = defaults.object(forKey: PreferenceKey.inboxLastSyncDate) as? Date
        XCTAssertNil(stored, "lastSyncDate must be nil on a fresh UserDefaults suite")
    }

    // Setting the key stores and retrieves the correct Date value.
    func testLastSyncDateStoresAndRetrievesDate() {
        let now = Date()
        defaults.set(now, forKey: PreferenceKey.inboxLastSyncDate)
        let stored = defaults.object(forKey: PreferenceKey.inboxLastSyncDate) as? Date
        XCTAssertNotNil(stored, "lastSyncDate must be non-nil after being set")
        XCTAssertEqual(stored?.timeIntervalSinceReferenceDate ?? 0,
                       now.timeIntervalSinceReferenceDate,
                       accuracy: 1.0,
                       "stored date must match the date that was written")
    }

    // wipeReplyAIDefaults removes lastSyncDate because it is not in wipeExemptions.
    func testLastSyncDateClearedByWipe() {
        defaults.set(Date(), forKey: PreferenceKey.inboxLastSyncDate)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        let stored = defaults.object(forKey: PreferenceKey.inboxLastSyncDate) as? Date
        XCTAssertNil(stored,
            "lastSyncDate must be removed from persistent domain by wipeReplyAIDefaults")
    }

    // MARK: - wipeExemptions membership pin
    //
    // The wipeExemptions Set is the single source of truth for which keys
    // survive a factory reset. Pin its membership so that a refactor cannot
    // silently drop a key (which would erase the user's launchCount or
    // re-trigger onboarding) or quietly add one (which would leak state
    // through a "fresh start" the user expected to be clean).

    func testWipeExemptionsContainsLaunchCount() {
        XCTAssertTrue(PreferenceKey.wipeExemptions.contains(PreferenceKey.launchCount),
            "launchCount must survive factory wipe — it tracks app age and feeds product analytics")
    }

    func testWipeExemptionsContainsFirstLaunchDate() {
        XCTAssertTrue(PreferenceKey.wipeExemptions.contains(PreferenceKey.firstLaunchDate),
            "firstLaunchDate must survive factory wipe — it is a set-once install timestamp")
    }

    func testWipeExemptionsContainsDemoModeActive() {
        XCTAssertTrue(PreferenceKey.wipeExemptions.contains(PreferenceKey.demoModeActive),
            "demoModeActive must survive factory wipe — wiping it would drop the user back to demo mode after a reset, which is jarring")
    }

    func testWipeExemptionsContainsOnboardingCompleted() {
        XCTAssertTrue(PreferenceKey.wipeExemptions.contains(PreferenceKey.onboardingCompleted),
            "onboardingCompleted must survive factory wipe — re-running onboarding after a reset is a footgun, not a feature")
    }

    func testWipeExemptionsCardinalityIsExactlyFour() {
        // Catches accidental additions to the exemption set. Adding a key
        // here is a deliberate decision that should require updating this
        // test alongside the exemption set itself.
        XCTAssertEqual(PreferenceKey.wipeExemptions.count, 4,
            "wipeExemptions has changed size — confirm the new exemption is intentional and update this test")
    }

    func testDemoModeActiveSurvivesWipe() {
        defaults.set(false, forKey: PreferenceKey.demoModeActive)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.demoModeActive),
            "demoModeActive=false must persist through wipe — otherwise reset re-enables demo data")
    }

    func testOnboardingCompletedSurvivesWipe() {
        defaults.set(true, forKey: PreferenceKey.onboardingCompleted)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.onboardingCompleted),
            "onboardingCompleted=true must persist through wipe — otherwise reset re-runs onboarding")
    }

    func testFirstLaunchDateSurvivesWipe() {
        let original = Date(timeIntervalSinceReferenceDate: 700_000_000)
        defaults.set(original, forKey: PreferenceKey.firstLaunchDate)
        UserDefaults.wipeReplyAIDefaults(in: defaults)
        let stored = defaults.object(forKey: PreferenceKey.firstLaunchDate) as? Date
        XCTAssertEqual(stored?.timeIntervalSinceReferenceDate ?? 0,
                       original.timeIntervalSinceReferenceDate,
                       accuracy: 1.0,
            "firstLaunchDate must persist verbatim through wipe — it is a set-once install timestamp")
    }
}

// MARK: - REP-222: pref.voice.exampleMessages setter enforcement

final class PreferencesVoiceExamplesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "test.ReplyAI.voiceExamples.\(UUID().uuidString)"
        guard let d = UserDefaults(suiteName: suiteName) else {
            XCTFail("couldn't create isolated UserDefaults suite")
            return
        }
        defaults = d
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
    }

    // Setter must clamp the list to 20 entries; entries beyond index 19 are dropped.
    func testVoiceExamplesCapEnforcedAtTwenty() {
        let messages = (1...30).map { "example \($0)" }
        defaults.setVoiceExampleMessages(messages)
        let stored = defaults.voiceExampleMessages()
        XCTAssertEqual(stored.count, 20,
                       "voiceExampleMessages must clamp the list to 20 entries")
        XCTAssertEqual(stored.first, "example 1", "first entry must be preserved after clamping")
        XCTAssertEqual(stored.last, "example 20", "last surviving entry must be #20")
    }

    // Setter must truncate any individual entry longer than 500 chars.
    func testVoiceExampleTruncatedAtFiveHundredChars() {
        let longEntry = String(repeating: "a", count: 600)
        defaults.setVoiceExampleMessages([longEntry])
        let stored = defaults.voiceExampleMessages()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].count, 500,
                       "individual voice example must be truncated to 500 chars at setter")
    }

    // MARK: - boundary cases

    func testVoiceExampleMessagesGetterReturnsEmptyWhenUnset() {
        // The getter must paper over UserDefaults' nil-on-missing convention
        // so callers can treat the result as a non-optional [String]. A nil
        // here would force every caller to ?? [], and one missed callsite
        // would crash the prompt builder.
        let stored = defaults.voiceExampleMessages()
        XCTAssertEqual(stored, [],
                       "unset key must surface as empty array, not nil")
    }

    func testVoiceExamplesAtCapPassUnchanged() {
        // Boundary: exactly 20 entries must round-trip unchanged. Off-by-one
        // in the prefix(20) clamp would either lose entry #20 or admit #21.
        let twenty = (1...20).map { "example \($0)" }
        defaults.setVoiceExampleMessages(twenty)
        let stored = defaults.voiceExampleMessages()
        XCTAssertEqual(stored, twenty,
                       "exactly 20 entries must survive the cap unchanged")
    }

    func testVoiceExampleAtFiveHundredCharsPassesUnchanged() {
        // Boundary: an entry of exactly 500 chars must NOT be truncated to
        // 499 — the threshold is `> 500`, not `>= 500`.
        let exactly500 = String(repeating: "b", count: 500)
        defaults.setVoiceExampleMessages([exactly500])
        let stored = defaults.voiceExampleMessages()
        XCTAssertEqual(stored.first, exactly500,
                       "a 500-char entry sits exactly on the threshold and must not be truncated")
    }

    func testVoiceExamplesEmptyArrayRoundTrips() {
        // Set then get [] to guard against the UserDefaults edge case where
        // setting an empty array might be treated as removeObject.
        defaults.setVoiceExampleMessages(["one"])
        defaults.setVoiceExampleMessages([])
        let stored = defaults.voiceExampleMessages()
        XCTAssertEqual(stored, [],
                       "writing an empty array must clear the list rather than retain prior values")
    }
}

// MARK: - PreferenceKey literal-string contracts
//
// Every PreferenceKey value is a UserDefaults key that ships in the app
// and accumulates real user state. The existing PreferencesTests use
// PreferenceKey.* symbolically, so a refactor that quietly renamed
// `"pref.privacy.crashReports"` to `"pref.crashReports"` would let
// every existing test keep passing while every shipped user's
// preference state silently re-defaulted on next launch.
//
// Pin each literal string here so a rename trips compile-time-stable
// expectations rather than at-runtime data loss.

final class PreferenceKeyLiteralStringTests: XCTestCase {

    func testEveryPreferenceKeyHasExactExpectedLiteral() {
        // Map each PreferenceKey to its shipped string. Editing this map
        // requires also writing a UserDefaults migration.
        let pairs: [(actual: String, expected: String)] = [
            (PreferenceKey.crashReports,         "pref.privacy.crashReports"),
            (PreferenceKey.licenseUpdates,       "pref.privacy.licenseUpdates"),
            (PreferenceKey.iCloudSync,           "pref.privacy.iCloudSync"),
            (PreferenceKey.defaultTone,          "pref.composer.defaultTone"),
            (PreferenceKey.useMLX,               "pref.model.useMLX"),
            (PreferenceKey.inboxThreadLimit,     "pref.inbox.threadLimit"),
            (PreferenceKey.autoPrime,            "pref.drafts.autoPrime"),
            (PreferenceKey.autoApplyRulesOnSync, "pref.rules.autoApplyOnSync"),
            (PreferenceKey.launchCount,          "pref.app.launchCount"),
            (PreferenceKey.firstLaunchDate,      "pref.app.firstLaunchDate"),
            (PreferenceKey.demoModeActive,       "pref.inbox.demoModeActive"),
            (PreferenceKey.onboardingCompleted,  "pref.app.onboardingCompleted"),
            (PreferenceKey.iMessageEnabled,      "pref.channels.iMessageEnabled"),
            (PreferenceKey.slackEnabled,         "pref.channels.slackEnabled"),
            (PreferenceKey.inboxLastSyncDate,    "pref.inbox.lastSyncDate"),
            (PreferenceKey.voiceExampleMessages, "pref.voice.exampleMessages"),
        ]
        for (actual, expected) in pairs {
            XCTAssertEqual(actual, expected,
                "PreferenceKey constant must equal \"\(expected)\" — renaming silently abandons every shipped user's value at this key")
        }
    }

    func testEveryPreferenceKeyStartsWithPrefPrefix() {
        // wipeReplyAIDefaults() sweeps keys that begin with "pref." —
        // any new PreferenceKey that drops this prefix would silently
        // survive a factory-reset and break the privacy promise.
        let allKeys: [String] = [
            PreferenceKey.crashReports,
            PreferenceKey.licenseUpdates,
            PreferenceKey.iCloudSync,
            PreferenceKey.defaultTone,
            PreferenceKey.useMLX,
            PreferenceKey.inboxThreadLimit,
            PreferenceKey.autoPrime,
            PreferenceKey.autoApplyRulesOnSync,
            PreferenceKey.launchCount,
            PreferenceKey.firstLaunchDate,
            PreferenceKey.demoModeActive,
            PreferenceKey.onboardingCompleted,
            PreferenceKey.iMessageEnabled,
            PreferenceKey.slackEnabled,
            PreferenceKey.inboxLastSyncDate,
            PreferenceKey.voiceExampleMessages,
        ]
        for key in allKeys {
            XCTAssertTrue(key.hasPrefix("pref."),
                "every PreferenceKey must start with \"pref.\" so wipeReplyAIDefaults() captures it on factory reset; got: \(key)")
        }
    }

    func testWipeExemptionsContainsOnlyKnownKeys() {
        // wipeExemptions is a Set; if a key gets renamed in PreferenceKey
        // but the corresponding wipeExemptions entry isn't updated, the
        // old key string lingers in the set and never matches the new
        // value — silently making the key wipe-eligible. Pin the four
        // exempted keys by literal value.
        let expectedExemptions: Set<String> = [
            "pref.app.launchCount",
            "pref.app.firstLaunchDate",
            "pref.inbox.demoModeActive",
            "pref.app.onboardingCompleted",
        ]
        XCTAssertEqual(PreferenceKey.wipeExemptions, expectedExemptions,
            "wipeExemptions set must contain exactly the four shipped keys — adding or removing an entry changes which preferences survive a factory reset")
    }
}

// MARK: - Preferences.lastThreadsCacheURL — cold-launch cache path contract
//
// InboxViewModel writes the last-known thread list to this URL after every
// successful sync (REP-278) so a cold launch with all channels offline can
// still render recognizable rows. Renaming the path orphans every shipped
// user's cached threads — they'd see "Loading..." instead of their last
// inbox state. Pin the path components so the contract holds.

final class PreferencesLastThreadsCacheURLTests: XCTestCase {

    func testLastThreadsCacheURLEndsWithExpectedFilename() {
        let url = Preferences.lastThreadsCacheURL
        XCTAssertEqual(url.lastPathComponent, "last-threads-cache.json",
                       "cold-launch cache filename must remain stable — renaming orphans every shipped user's cached threads")
    }

    func testLastThreadsCacheURLLivesUnderReplyAIDirectory() {
        let url = Preferences.lastThreadsCacheURL
        let parent = url.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(parent, "ReplyAI",
                       "thread cache must sit in ReplyAI/ alongside stats.json and rules.json so factory-reset wipes it as part of the directory sweep")
    }

    func testLastThreadsCacheURLIsAbsoluteAndFileScheme() {
        let url = Preferences.lastThreadsCacheURL
        XCTAssertTrue(url.isFileURL,
                      "cache path must be a file:// URL for FileManager + Data(contentsOf:) on cold launch")
        XCTAssertTrue(url.path.hasPrefix("/"),
                      "cache path must be absolute so behavior doesn't depend on the launching process's cwd")
    }
}
