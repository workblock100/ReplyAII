import XCTest
@testable import ReplyAI

final class WhatsAppChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: "whatsapp-token")
    }

    func testWhatsAppChannelThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = WhatsAppChannel(keychain: keychain)

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testWhatsAppChannelReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-session-token", for: "whatsapp-token")
        let channel = WhatsAppChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    func testWhatsAppChannelPropertyReturnsWhatsApp() {
        let channel = WhatsAppChannel()
        XCTAssertEqual(channel.channel, .whatsapp)
        XCTAssertEqual(channel.displayName, "WhatsApp")
    }
}
