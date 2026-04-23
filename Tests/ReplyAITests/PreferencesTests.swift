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
