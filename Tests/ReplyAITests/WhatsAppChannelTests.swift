import XCTest
@testable import ReplyAI

final class WhatsAppChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        KeychainHelper(service: testService).delete(key: WhatsAppChannel.keychainTokenKey)
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
        try keychain.set(value: "test-session-token", for: WhatsAppChannel.keychainTokenKey)
        let channel = WhatsAppChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty)
    }

    func testWhatsAppChannelPropertyReturnsWhatsApp() {
        let channel = WhatsAppChannel()
        XCTAssertEqual(channel.channel, .whatsapp)
        XCTAssertEqual(channel.displayName, "WhatsApp")
    }

    func testWhatsAppChannelMessagesThrowsWhenNoToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = WhatsAppChannel(keychain: keychain)

        do {
            _ = try await channel.messages(forThreadID: "any", limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected — gate is symmetric with recentThreads, not silently bypassed.
        }
    }

    func testWhatsAppChannelMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-session-token", for: WhatsAppChannel.keychainTokenKey)
        let channel = WhatsAppChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    /// Pin a surprising-but-safe contract on the auth gate: an EMPTY-STRING
    /// token currently passes the `keychain.get(key:) != nil` predicate
    /// because `KeychainHelper.set(value: "", ...)` round-trips as
    /// `Some("")` rather than nil (pinned by
    /// `KeychainHelperTests.testEmptyStringValueRoundTripsAsEmpty`).
    /// So a stub channel with `""` stored under its keychain key is
    /// "authorized" from the gate's perspective and proceeds to the
    /// (currently-empty) recentThreads/messages return path.
    ///
    /// Drift toward `(keychain.get(key:)?.isEmpty == false)` would
    /// silently flip every malformed-but-stored credential into
    /// `authorizationDenied`, which is REASONABLE tightening once real
    /// API calls land (an empty token would just fail server-side
    /// anyway), but for the stub today it would change the
    /// "no-throw on a present-but-empty token" surface.
    ///
    /// Pin so the tightening lands as a deliberate change with a clear
    /// before/after rather than a silent gate change. Mirrors the
    /// cross-keychain-stub class — same pattern would apply to
    /// SMS/Teams/Telegram if they grew real auth.
    func testWhatsAppChannelEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: WhatsAppChannel.keychainTokenKey)
        let channel = WhatsAppChannel(keychain: keychain)

        // Both gated calls must NOT throw — the gate uses `!= nil`, not
        // `?.isEmpty == false`. An empty stored token surfaces as
        // "authorized" and the stub returns its empty list verbatim.
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "stub returns empty list for any 'authorized' state — pin so a future drift toward authorizationDenied on empty-string surfaces here")
        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty,
            "messages auth gate must mirror recentThreads — empty-string token is authorized for both call sites")
    }
}
