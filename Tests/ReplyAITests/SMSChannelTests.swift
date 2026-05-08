import XCTest
@testable import ReplyAI

final class SMSChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: SMSChannel.keychainTokenKey)
    }

    func testSMSChannelThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = SMSChannel(keychain: keychain)

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testSMSChannelReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-relay-token", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    func testSMSChannelPropertyReturnsSMS() {
        let channel = SMSChannel()
        XCTAssertEqual(channel.channel, .sms)
        XCTAssertEqual(channel.displayName, "SMS")
    }

    func testSMSChannelMessagesThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = SMSChannel(keychain: keychain)

        do {
            _ = try await channel.messages(forThreadID: "any", limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected — gate is symmetric with recentThreads, not silently bypassed.
        }
    }

    func testSMSChannelMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-relay-token", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    /// Mirrors `WhatsAppChannelTests.testWhatsAppChannelEmptyTokenBypassesAuthGate`
    /// for the SMS-relay stub. The four channel stubs (SMS, Teams,
    /// Telegram, WhatsApp) share the auth-gate predicate
    /// `keychain.get(key:) != nil` — so an empty-string token, which
    /// KeychainHelper round-trips as Some(\"\") (per
    /// `KeychainHelperTests.testEmptyStringValueRoundTripsAsEmpty`),
    /// passes the gate on every stub. Pin the same surprising-but-safe
    /// behavior here so a future tightening to `?.isEmpty == false`
    /// surfaces as a deliberate change across the cluster, not just on
    /// one stub.
    func testSMSChannelEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "stub returns empty list for empty-token 'authorized' state — gate uses != nil, not ?.isEmpty == false")
        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty,
            "messages auth gate must mirror recentThreads — empty-string token authorizes both call sites symmetrically")
    }
}
