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
}
