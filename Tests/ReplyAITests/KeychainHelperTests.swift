import XCTest
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
}
