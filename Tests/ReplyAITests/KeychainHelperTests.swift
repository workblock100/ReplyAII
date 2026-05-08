import XCTest
import Security
@testable import ReplyAI

final class KeychainHelperTests: XCTestCase {
    private var keychain: KeychainHelper!

    override func setUpWithError() throws {
        // Unique service per test run prevents cross-test pollution.
        keychain = KeychainHelper(service: "co.replyai.test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        // Belt-and-suspenders cleanup so test Keychain entries don't pile up.
        keychain.delete(key: "key1")
        keychain.delete(key: "key2")
        keychain.delete(key: "token")
    }

    func testKeyValueRoundTrip() throws {
        try keychain.set(value: "secret-value", for: "token")
        XCTAssertEqual(keychain.get(key: "token"), "secret-value")
    }

    func testGetMissingKeyReturnsNil() {
        XCTAssertNil(keychain.get(key: "does-not-exist"))
    }

    func testDeleteRemovesKey() throws {
        try keychain.set(value: "to-be-deleted", for: "token")
        keychain.delete(key: "token")
        XCTAssertNil(keychain.get(key: "token"))
    }

    func testOverwriteReturnsNewValue() throws {
        try keychain.set(value: "first", for: "token")
        try keychain.set(value: "second", for: "token")
        XCTAssertEqual(keychain.get(key: "token"), "second")
    }

    func testDistinctKeysAreIsolated() throws {
        try keychain.set(value: "value1", for: "key1")
        try keychain.set(value: "value2", for: "key2")
        XCTAssertEqual(keychain.get(key: "key1"), "value1")
        XCTAssertEqual(keychain.get(key: "key2"), "value2")
    }

    // MARK: - deleteAll(prefix:)

    func testDeleteAllRemovesPrefixedKeys() throws {
        try keychain.set(value: "v1", for: "Slack-token")
        try keychain.set(value: "v2", for: "Slack-other")
        try keychain.set(value: "v3", for: "iMessage-token")

        keychain.deleteAll(prefix: "ReplyAI-")

        XCTAssertNil(keychain.get(key: "Slack-token"))
        XCTAssertNil(keychain.get(key: "Slack-other"))
        XCTAssertNil(keychain.get(key: "iMessage-token"))
    }

    func testDeleteAllLeavesNonPrefixedKeys() throws {
        // Add an item directly without the "ReplyAI-" prefix to verify selectivity.
        let unprefixed = "TestApp-unrelated"
        let addQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychain.service,
            kSecAttrAccount: unprefixed,
            kSecValueData:   Data("survivor".utf8)
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        defer {
            let del: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: keychain.service,
                kSecAttrAccount: unprefixed
            ]
            SecItemDelete(del as CFDictionary)
        }

        try keychain.set(value: "to-delete", for: "Slack-token")
        keychain.deleteAll(prefix: "ReplyAI-")

        XCTAssertNil(keychain.get(key: "Slack-token"))

        // The unprefixed item must still be in Keychain.
        let readQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychain.service,
            kSecAttrAccount: unprefixed,
            kSecMatchLimit:  kSecMatchLimitOne,
            kSecReturnData:  kCFBooleanTrue as Any
        ]
        var result: AnyObject?
        XCTAssertEqual(SecItemCopyMatching(readQuery as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, Data("survivor".utf8))
    }

    func testDeleteAllOnEmptyKeychainIsNoop() {
        // Must not throw or crash when no items exist for this service.
        keychain.deleteAll(prefix: "ReplyAI-")
    }

    /// Regression pin: empty prefix must be refused. `String.hasPrefix("")`
    /// returns true for every account, so a caller that accidentally passed
    /// an empty prefix (e.g. computed from missing config) would
    /// catastrophically wipe every item in this service. Guard against it.
    func testDeleteAllWithEmptyPrefixIsNoop() throws {
        try keychain.set(value: "v1", for: "Slack-token")
        try keychain.set(value: "v2", for: "Telegram-token")

        keychain.deleteAll(prefix: "")

        XCTAssertEqual(keychain.get(key: "Slack-token"), "v1",
            "empty prefix must NOT wipe every item — items must survive")
        XCTAssertEqual(keychain.get(key: "Telegram-token"), "v2",
            "empty prefix must NOT wipe every item — items must survive")
    }

    // MARK: - additional edge cases

    /// `KeychainError.errorDescription` must surface the OSStatus so logs +
    /// error UIs include something actionable (the raw status code lets a
    /// developer or a support engineer search Apple's error tables).
    func testKeychainErrorDescriptionIncludesStatus() {
        let err: Error = KeychainError.unhandledError(status: -34018)
        let desc = (err as? LocalizedError)?.errorDescription ?? ""
        XCTAssertTrue(desc.contains("-34018"),
            "errorDescription must include the OSStatus code for diagnostics, got: \(desc)")
    }

    /// Empty-string value must round-trip cleanly. Some upstream channel
    /// flows store "" to mark a token as explicitly cleared (vs deleted),
    /// which is semantically different — get() must distinguish empty-string
    /// from nil.
    func testEmptyStringValueRoundTripsAsEmpty() throws {
        try keychain.set(value: "", for: "token")
        let v = keychain.get(key: "token")
        XCTAssertEqual(v, "", "empty string round-trips as \"\", not nil")
        XCTAssertNotNil(v, "set+get of \"\" must return non-nil empty string, not nil")
    }

    /// Set after delete exercises the add-not-update path (SecItemUpdate
    /// returns errSecItemNotFound, then SecItemAdd succeeds). Without this
    /// the value couldn't be re-bound after a token rotation that deletes
    /// before re-setting.
    func testSetAfterDeleteSucceeds() throws {
        try keychain.set(value: "v1", for: "token")
        keychain.delete(key: "token")
        try keychain.set(value: "v2", for: "token")
        XCTAssertEqual(keychain.get(key: "token"), "v2")
    }

    /// Unicode value must round-trip byte-for-byte (UTF-8). Channel display
    /// names contain emoji / non-ASCII names.
    func testUnicodeValueRoundTrip() throws {
        let v = "Workspace 🚀 — Café \"quotes\" — 漢字"
        try keychain.set(value: v, for: "token")
        XCTAssertEqual(keychain.get(key: "token"), v)
    }

    /// Default `init()` resolves to the `"co.replyai.app"` service. SlackTokenStore
    /// and every channel that calls `KeychainHelper()` without an explicit service
    /// pivots on this default — renaming it (e.g. to `"co.replyai.legacy"`) would
    /// silently orphan every existing user's tokens with no visible compile error,
    /// because tokens written under the new service would simply not see the old
    /// items. Pin the literal so a refactor surfaces as a code-review diff.
    func testDefaultServiceLiteralIsPinned() throws {
        let helper = KeychainHelper()
        XCTAssertEqual(helper.service, KeychainHelper.defaultService,
            "default Keychain service must route through KeychainHelper.defaultService — drift means the constant became dead code while the init froze a stale literal")
        XCTAssertEqual(KeychainHelper.defaultService, "co.replyai.app",
            "default Keychain service must remain `co.replyai.app` — renaming silently orphans every existing token")
    }

    /// `ReplyAI-` is the contract prefix every account key gets — `deleteAll(prefix:)`
    /// in factory reset relies on it to scope the wipe to ReplyAI items only without
    /// touching unrelated keychain entries in the same service. Renaming the prefix
    /// (e.g. to `RA-`) without also updating the wipe sweep would leave new tokens
    /// surviving factory reset. Pin via a round-trip + a direct `kSecAttrAccount`
    /// lookup that asserts the prefix is exactly `ReplyAI-`.
    func testKeychainAccountPrefixContract() throws {
        try keychain.set(value: "prefix-test", for: "probe-key")
        defer { keychain.delete(key: "probe-key") }

        let lookupQuery: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychain.service,
            kSecAttrAccount:      "ReplyAI-probe-key",
            kSecMatchLimit:       kSecMatchLimitOne,
            kSecReturnData:       kCFBooleanTrue as Any
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess,
            "lookup with the literal `ReplyAI-` prefix must hit the item — changing the prefix breaks deleteAll/factory-reset")

        let data = try XCTUnwrap(result as? Data)
        XCTAssertEqual(String(data: data, encoding: .utf8), "prefix-test")
    }
}

// MARK: - KeychainError.errorDescription

/// `KeychainError` only ships a single case (`unhandledError(status:)`),
/// but its `errorDescription` switches on common `OSStatus` values to
/// translate raw integers into actionable user copy. Pin each known
/// status's recovery hint here so a future copy edit can't silently
/// regress to a bare integer (which the user can't act on) without
/// failing CI.
final class KeychainErrorTests: XCTestCase {

    func testKeychainErrorAuthFailedHasActionableCopy() throws {
        let desc = KeychainError.unhandledError(status: errSecAuthFailed).errorDescription
        let s = try XCTUnwrap(desc)
        XCTAssertFalse(s.contains("\(errSecAuthFailed)"),
            "errSecAuthFailed surface must be plain English, not a raw OSStatus")
        XCTAssertTrue(s.lowercased().contains("sign in"),
            "errSecAuthFailed copy must tell the user to sign in")
    }

    func testKeychainErrorUserCanceledHasActionableCopy() throws {
        let desc = KeychainError.unhandledError(status: errSecUserCanceled).errorDescription
        let s = try XCTUnwrap(desc)
        XCTAssertTrue(s.lowercased().contains("canceled"),
            "errSecUserCanceled copy must mention cancellation so the user knows nothing broke")
    }

    func testKeychainErrorInteractionNotAllowedMentionsUnlocking() throws {
        let desc = KeychainError.unhandledError(status: errSecInteractionNotAllowed).errorDescription
        let s = try XCTUnwrap(desc)
        XCTAssertTrue(s.lowercased().contains("locked"),
            "errSecInteractionNotAllowed (locked Keychain) must point the user at unlocking")
        XCTAssertTrue(s.contains("Keychain Access"),
            "Direct the user to Keychain Access by name so they can find the app")
    }

    func testKeychainErrorDuplicateItemPointsAtReconnect() throws {
        let desc = KeychainError.unhandledError(status: errSecDuplicateItem).errorDescription
        let s = try XCTUnwrap(desc)
        XCTAssertTrue(s.contains("Settings"),
            "errSecDuplicateItem copy must point the user at Settings → Channels for the disconnect path")
    }

    func testKeychainErrorItemNotFoundPointsAtReconnect() throws {
        let desc = KeychainError.unhandledError(status: errSecItemNotFound).errorDescription
        let s = try XCTUnwrap(desc)
        XCTAssertTrue(s.lowercased().contains("reconnect"),
            "errSecItemNotFound copy must direct the user to reconnect — that's the recovery path")
    }

    /// Unknown OSStatus values still need to surface the raw code so a
    /// support engineer can look it up against `SecBase.h`. The previous
    /// "Keychain error <n>" format is preserved as a fallback prefix so
    /// existing log-grep / support workflows keep working.
    func testKeychainErrorUnknownStatusFallsBackToRawCode() throws {
        let bogus: OSStatus = -99999
        let desc = KeychainError.unhandledError(status: bogus).errorDescription
        let s = try XCTUnwrap(desc)
        XCTAssertTrue(s.contains("\(bogus)"),
            "Unknown OSStatus values must still surface the raw code for support triage")
        XCTAssertTrue(s.contains("Settings"),
            "Unknown-code copy still points the user at Settings → Channels as the recovery path")
    }

    // MARK: - Hoisted-constant pins (REP-hoist 2026-05-07)
    //
    // The five known-status toasts live as `static let` on
    // `KeychainError`. Existing tests above (`*HasActionableCopy`)
    // use substring matching, which would silently agree with a
    // copy rewrite that drops the actionable verb. These pins are
    // the byte-for-byte contract.

    func testAuthFailedToastCopyIsFrozen() {
        XCTAssertEqual(KeychainError.authFailedToast,
                       "Keychain refused access. Sign in to your Mac and try again.",
            "authFailedToast literal must not drift — `Sign in to your Mac` is the actionable verb the user needs")
    }

    func testUserCanceledToastCopyIsFrozen() {
        XCTAssertEqual(KeychainError.userCanceledToast,
                       "Keychain access canceled. Try connecting again to retry.",
            "userCanceledToast literal must not drift — `Try connecting again` is the recovery path")
    }

    func testInteractionNotAllowedToastCopyIsFrozen() {
        XCTAssertEqual(KeychainError.interactionNotAllowedToast,
                       "Keychain is locked. Unlock your login keychain in Keychain Access and try again.",
            "interactionNotAllowedToast literal must not drift — `Keychain Access` is the app the user has to open")
    }

    func testDuplicateItemToastCopyIsFrozen() {
        XCTAssertEqual(KeychainError.duplicateItemToast,
                       "Keychain already has a saved entry for this account. Disconnect the account in Settings → Channels and reconnect.",
            "duplicateItemToast literal must not drift — `Disconnect the account in Settings → Channels` is the recovery path")
    }

    func testItemNotFoundToastCopyIsFrozen() {
        XCTAssertEqual(KeychainError.itemNotFoundToast,
                       "Keychain entry missing. Reconnect the account in Settings → Channels.",
            "itemNotFoundToast literal must not drift — `Reconnect the account` is the recovery path")
    }

    /// Routing pins: each translated status's `errorDescription`
    /// must equal the hoisted constant byte-for-byte. Catches a
    /// future refactor that defines the constant but rebuilds the
    /// inner switch with a slightly-different inline literal — every
    /// constant-only pin would still pass while every user toast
    /// silently desyncs from the documented copy.
    func testAuthFailedRoutesThroughHoistedConstant() {
        XCTAssertEqual(KeychainError.unhandledError(status: errSecAuthFailed).errorDescription,
                       KeychainError.authFailedToast,
            "errSecAuthFailed must surface the hoisted constant byte-for-byte — drift between switch and constant is silent")
    }

    func testUserCanceledRoutesThroughHoistedConstant() {
        XCTAssertEqual(KeychainError.unhandledError(status: errSecUserCanceled).errorDescription,
                       KeychainError.userCanceledToast,
            "errSecUserCanceled must surface the hoisted constant byte-for-byte")
    }

    func testInteractionNotAllowedRoutesThroughHoistedConstant() {
        XCTAssertEqual(KeychainError.unhandledError(status: errSecInteractionNotAllowed).errorDescription,
                       KeychainError.interactionNotAllowedToast,
            "errSecInteractionNotAllowed must surface the hoisted constant byte-for-byte")
    }

    func testDuplicateItemRoutesThroughHoistedConstant() {
        XCTAssertEqual(KeychainError.unhandledError(status: errSecDuplicateItem).errorDescription,
                       KeychainError.duplicateItemToast,
            "errSecDuplicateItem must surface the hoisted constant byte-for-byte")
    }

    func testItemNotFoundRoutesThroughHoistedConstant() {
        XCTAssertEqual(KeychainError.unhandledError(status: errSecItemNotFound).errorDescription,
                       KeychainError.itemNotFoundToast,
            "errSecItemNotFound must surface the hoisted constant byte-for-byte")
    }
}

// MARK: - SlackTokenStore (REP-274)

final class SlackTokenStoreTests: XCTestCase {
    private var store: SlackTokenStore!

    override func setUpWithError() throws {
        let keychain = KeychainHelper(service: "co.replyai.test-slack-\(UUID().uuidString)")
        store = SlackTokenStore(keychain: keychain)
    }

    override func tearDownWithError() throws {
        store.delete()
    }

    func testSlackTokenStoreRoundTrip() throws {
        try store.set(token: "xoxb-test-token", workspaceName: "Acme Corp")
        let result = store.get()
        XCTAssertEqual(result?.token, "xoxb-test-token")
        XCTAssertEqual(result?.workspaceName, "Acme Corp")
    }

    func testSlackTokenStoreDeleteRemovesEntry() throws {
        try store.set(token: "xoxb-delete-me", workspaceName: "Test WS")
        store.delete()
        XCTAssertNil(store.get())
    }

    func testSlackTokenStoreMissingEntryReturnsNil() {
        XCTAssertNil(store.get())
    }

    func testSlackTokenStoreMalformedJSONReturnsNil() throws {
        // Write raw non-JSON bytes under the store's key via the underlying KeychainHelper.
        let keychain = KeychainHelper(service: "co.replyai.test-slack-malformed-\(UUID().uuidString)")
        let corruptStore = SlackTokenStore(keychain: keychain)
        try keychain.set(value: "not-valid-json{{{{", for: SlackTokenStore.storageKey)
        XCTAssertNil(corruptStore.get(), "malformed JSON should return nil without crashing")
        keychain.delete(key: SlackTokenStore.storageKey)
    }

    /// Pin the on-Keychain storage key and JSON wire format. The store's
    /// private `storageKey` plus the `Entry` Codable fields together
    /// define the on-disk shape every shipped install reads from. A
    /// rename of either silently orphans every existing Slack token —
    /// the user appears to be signed out for no clear reason. Pin both
    /// here so a refactor surfaces as a code-review diff.
    func testSlackTokenStoreWriteToKeychainKeyAndJSONShape() throws {
        let keychain = KeychainHelper(service: "co.replyai.test-slack-shape-\(UUID().uuidString)")
        let testStore = SlackTokenStore(keychain: keychain)
        defer { keychain.delete(key: SlackTokenStore.storageKey) }

        try testStore.set(token: "xoxb-shape-test", workspaceName: "Acme Corp")

        // 1. The store must write under exactly the "slack-access-token"
        //    Keychain account suffix (KeychainHelper prepends "ReplyAI-").
        XCTAssertEqual(SlackTokenStore.storageKey, "slack-access-token",
            "SlackTokenStore.storageKey drift orphans every existing user's Slack token (Keychain identity is the literal account suffix)")
        let raw = keychain.get(key: SlackTokenStore.storageKey)
        XCTAssertNotNil(raw,
            "SlackTokenStore must persist under the `slack-access-token` Keychain key — renaming orphans existing tokens")

        // 2. Parse the raw JSON and assert both expected keys are present
        //    with their exact field names. A future rename ("token" →
        //    "accessToken", "workspaceName" → "workspace") must surface
        //    here, not at runtime when get() returns nil.
        let data = try XCTUnwrap(raw?.data(using: .utf8))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["token"] as? String, "xoxb-shape-test",
            "Entry must encode the access token under the `token` JSON key")
        XCTAssertEqual(json["workspaceName"] as? String, "Acme Corp",
            "Entry must encode the workspace under the `workspaceName` JSON key (not `workspace_name` or similar)")
        XCTAssertEqual(json.count, 2,
            "Entry shape must remain {token, workspaceName} — extra fields here would silently bloat every Keychain write")
    }

    /// A second `set(...)` call after a workspace-rotation or token-refresh
    /// must REPLACE the prior entry — not stack a duplicate Keychain row,
    /// which would leave `get()` racing between two values. Pin the
    /// last-write-wins contract here so a future Keychain-helper rewrite
    /// can't regress to "add" semantics without surfacing in CI.
    func testSlackTokenStoreSetReplacesExistingEntry() throws {
        try store.set(token: "xoxb-old", workspaceName: "Old Workspace")
        try store.set(token: "xoxb-new", workspaceName: "New Workspace")
        let result = store.get()
        XCTAssertEqual(result?.token, "xoxb-new",
            "second set() must overwrite the first — last write wins")
        XCTAssertEqual(result?.workspaceName, "New Workspace",
            "second set() must overwrite the workspace name too, not partially update")
    }

    /// Slack itself rejects empty `access_token` values upstream, but the
    /// store should still round-trip them faithfully — silently rewriting
    /// "" → some sentinel would mask a real authorization bug. The shape
    /// pin (above) checks the keys; this one checks the empty-value path.
    func testSlackTokenStoreEmptyTokenRoundTrips() throws {
        try store.set(token: "", workspaceName: "Some Workspace")
        let result = store.get()
        XCTAssertEqual(result?.token, "",
            "empty token must round-trip verbatim — masking it would hide upstream auth bugs")
        XCTAssertEqual(result?.workspaceName, "Some Workspace")
    }

    /// Workspace names commonly contain non-ASCII (emoji, accents, CJK)
    /// because Slack lets users type arbitrary Unicode. JSON encoding
    /// should preserve those bytes through the Keychain round-trip
    /// without mojibake or NFC/NFD normalization that would change the
    /// displayed string in Settings.
    func testSlackTokenStorePreservesUnicodeWorkspaceName() throws {
        let unicode = "Café 東京 🌮 — Eng"
        try store.set(token: "xoxb-unicode", workspaceName: unicode)
        let result = store.get()
        XCTAssertEqual(result?.workspaceName, unicode,
            "Unicode in workspace names must round-trip verbatim through Keychain JSON")
    }

    /// Pin the named-constant single-source-of-truth. Existing tests
    /// pin the literal `"ReplyAI-"` prefix at three call sites
    /// (set/get/delete) by direct kSecAttrAccount lookup. This pin
    /// ties those three uses to a single named constant so a refactor
    /// that bumped the prefix on two of three sites leaves the third
    /// orphaning every existing user's stored token. The named
    /// constant landing without the inline literals being updated
    /// (or vice versa) would surface here.
    func testAccountPrefixIsSingleSourceOfTruth() {
        XCTAssertEqual(KeychainHelper.accountPrefix, "ReplyAI-",
            "accountPrefix drift orphans every existing user's stored channel tokens — they appear `not connected` with no migration path")
    }
}
