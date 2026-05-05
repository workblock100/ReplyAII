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
        try keychain.set(value: "not-valid-json{{{{", for: "slack-access-token")
        XCTAssertNil(corruptStore.get(), "malformed JSON should return nil without crashing")
        keychain.delete(key: "slack-access-token")
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
        defer { keychain.delete(key: "slack-access-token") }

        try testStore.set(token: "xoxb-shape-test", workspaceName: "Acme Corp")

        // 1. The store must write under exactly the "slack-access-token"
        //    Keychain account suffix (KeychainHelper prepends "ReplyAI-").
        let raw = keychain.get(key: "slack-access-token")
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
}
