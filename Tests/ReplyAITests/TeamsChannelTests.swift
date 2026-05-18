import XCTest
@testable import ReplyAICore

final class TeamsChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: TeamsChannel.keychainTokenKey)
    }

    func testTeamsChannelThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = TeamsChannel(keychain: keychain)

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testTeamsChannelReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-graph-token", for: TeamsChannel.keychainTokenKey)
        let channel = TeamsChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    func testTeamsChannelPropertyReturnsTeams() {
        let channel = TeamsChannel()
        XCTAssertEqual(channel.channel, .teams)
        XCTAssertEqual(channel.displayName, "Teams")
    }

    func testTeamsChannelMessagesThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = TeamsChannel(keychain: keychain)

        do {
            _ = try await channel.messages(forThreadID: "any", limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected — gate is symmetric with recentThreads, not silently bypassed.
        }
    }

    func testTeamsChannelMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-graph-token", for: TeamsChannel.keychainTokenKey)
        let channel = TeamsChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    /// Mirrors `WhatsAppChannelTests.testWhatsAppChannelEmptyTokenBypassesAuthGate`
    /// and `SMSChannelTests.testSMSChannelEmptyTokenBypassesAuthGate`
    /// for the Teams stub. The four channel stubs share the auth-gate
    /// predicate `keychain.get(key:) != nil` — empty-string token
    /// passes. Pin the cluster so a future `?.isEmpty == false`
    /// tightening surfaces consistently across all four stubs.
    func testTeamsChannelEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: TeamsChannel.keychainTokenKey)
        let channel = TeamsChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "Teams stub treats empty-string token as 'authorized' — gate uses != nil")
        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty,
            "messages auth gate symmetric with recentThreads on empty-string token")
    }
}
