import XCTest
@testable import ReplyAI

final class TeamsChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: "teams-token")
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
        try keychain.set(value: "test-graph-token", for: "teams-token")
        let channel = TeamsChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    func testTeamsChannelPropertyReturnsTeams() {
        let channel = TeamsChannel()
        XCTAssertEqual(channel.channel, .teams)
        XCTAssertEqual(channel.displayName, "Teams")
    }
}
