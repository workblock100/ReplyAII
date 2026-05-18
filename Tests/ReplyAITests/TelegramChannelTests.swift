import XCTest
@testable import ReplyAICore

final class TelegramChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: TelegramChannel.keychainTokenKey)
    }

    // MARK: - Auth gate

    func testTelegramChannelThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = TelegramChannel(keychain: keychain)

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testTelegramChannelReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-bot-token-12345", for: TelegramChannel.keychainTokenKey)
        let channel = TelegramChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    // MARK: - Identity

    func testTelegramChannelPropertyReturnsTelegram() {
        let channel = TelegramChannel()
        XCTAssertEqual(channel.channel, .telegram)
        XCTAssertEqual(channel.displayName, "Telegram")
    }

    // MARK: - messages() symmetry

    func testTelegramChannelMessagesThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = TelegramChannel(keychain: keychain)

        do {
            _ = try await channel.messages(forThreadID: "any", limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected — gate is symmetric with recentThreads, not silently bypassed.
        }
    }

    func testTelegramChannelMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-bot-token-12345", for: TelegramChannel.keychainTokenKey)
        let channel = TelegramChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    /// Mirrors the empty-token bypass pin shared across the four
    /// channel stubs (SMS, Teams, Telegram, WhatsApp). Auth gate uses
    /// `keychain.get(key:) != nil`, so empty-string token is treated
    /// as 'authorized'. Pin so a future `?.isEmpty == false` tightening
    /// surfaces consistently across the cluster.
    ///
    /// Telegram's keychain service uses the divergent `co.replyai.telegram`
    /// reverse-DNS form (vs the `ReplyAI-<Channel>` convention the
    /// other three use); the bypass behavior is identical regardless.
    func testTelegramChannelEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: TelegramChannel.keychainTokenKey)
        let channel = TelegramChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "Telegram stub treats empty-string bot token as 'authorized' — gate uses != nil despite the divergent reverse-DNS keychain service name")
        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty,
            "messages auth gate symmetric with recentThreads on empty-string token")
    }
}
