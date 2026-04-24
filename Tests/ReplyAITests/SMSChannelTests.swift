import XCTest
@testable import ReplyAI

final class SMSChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: "sms-token")
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
        try keychain.set(value: "test-relay-token", for: "sms-token")
        let channel = SMSChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    func testSMSChannelPropertyReturnsSMS() {
        let channel = SMSChannel()
        XCTAssertEqual(channel.channel, .sms)
        XCTAssertEqual(channel.displayName, "SMS")
    }
}
