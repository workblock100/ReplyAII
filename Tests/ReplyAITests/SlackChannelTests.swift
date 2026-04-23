import XCTest
@testable import ReplyAI

final class SlackChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: "Slack-token")
    }

    // MARK: - Auth gate

    func testSlackChannelThrowsAuthDeniedWithNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = SlackChannel(keychain: keychain)

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testSlackChannelReturnsEmptyThreadsWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "xoxb-test-token", for: "Slack-token")
        let channel = SlackChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    // MARK: - Identity

    func testSlackChannelIdentifiesAsSlack() {
        let channel = SlackChannel()
        XCTAssertEqual(channel.channel, .slack)
        XCTAssertEqual(channel.displayName, "Slack")
    }
}
