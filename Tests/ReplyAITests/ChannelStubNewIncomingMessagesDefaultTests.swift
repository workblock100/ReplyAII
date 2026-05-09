import XCTest
@testable import ReplyAI

/// Pins the asymmetry of the four non-iMessage channel stubs (SMS, Teams,
/// Telegram, WhatsApp): `recentThreads` and `messages` throw
/// `ChannelError.authorizationDenied` when no Keychain token is present,
/// but `newIncomingMessages` returns `[]` *without* throwing — even when
/// no token is set — because none of the stubs override the protocol
/// extension's empty shim in `ChannelService.swift`.
///
/// This is intentional, not an oversight. The rule engine's incoming-
/// message replay loop calls `newIncomingMessages` against every
/// configured channel on watcher refire; throwing from an unauthorized
/// stub would noisily abort the loop on every cycle for users who simply
/// haven't connected Slack/Telegram yet. The empty default lets the loop
/// be polymorphic across all channels.
///
/// Pin per-stub so a future override that adds rule-replay support to
/// any one of these stubs surfaces here. Two failure modes are caught:
/// (a) override without an auth gate — silently misses messages; this
/// test still passes, but the SUITE-WIDE pattern of "all four behave the
/// same" breaks visibly. (b) override WITH an auth gate — this test
/// flips from passing-empty to throwing, demanding a deliberate update
/// to the rule-replay loop's error handling.
///
/// `BareChannelService` in `ChannelServiceTests` already pins the
/// protocol-extension default's behavior in isolation; this file pins
/// that each *concrete stub* inherits that behavior unchanged.
final class ChannelStubNewIncomingMessagesDefaultTests: XCTestCase {

    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        // Clean up any token the test may have written under the per-test
        // service so nothing leaks into the next test class's namespace.
        let helper = KeychainHelper(service: testService)
        helper.delete(key: SMSChannel.keychainTokenKey)
        helper.delete(key: TeamsChannel.keychainTokenKey)
        helper.delete(key: TelegramChannel.keychainTokenKey)
        helper.delete(key: WhatsAppChannel.keychainTokenKey)
    }

    // MARK: - SMS

    func testSMSNewIncomingMessagesReturnsEmptyWithoutToken() async throws {
        // No token in Keychain ⇒ `recentThreads` would throw
        // `ChannelError.authorizationDenied`. `newIncomingMessages` must
        // *not* throw — it inherits the empty shim. Drift here would
        // make the rule engine's polymorphic replay loop abort on the
        // first unauthorized stub channel.
        let keychain = KeychainHelper(service: testService)
        let channel = SMSChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "SMS stub must inherit the empty-shim default — overriding with a real implementation requires an explicit decision about auth-gating, not a silent change")
    }

    func testSMSNewIncomingMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-token", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "SMS stub default returns empty regardless of auth state — drift means the stub gained a real implementation")
    }

    // MARK: - Teams

    func testTeamsNewIncomingMessagesReturnsEmptyWithoutToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = TeamsChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "Teams stub must inherit the empty-shim default")
    }

    func testTeamsNewIncomingMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-token", for: TeamsChannel.keychainTokenKey)
        let channel = TeamsChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "Teams stub default returns empty regardless of auth state")
    }

    // MARK: - Telegram

    func testTelegramNewIncomingMessagesReturnsEmptyWithoutToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = TelegramChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "Telegram stub must inherit the empty-shim default")
    }

    func testTelegramNewIncomingMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-token", for: TelegramChannel.keychainTokenKey)
        let channel = TelegramChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "Telegram stub default returns empty regardless of auth state")
    }

    // MARK: - WhatsApp

    func testWhatsAppNewIncomingMessagesReturnsEmptyWithoutToken() async throws {
        let keychain = KeychainHelper(service: testService)
        let channel = WhatsAppChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "WhatsApp stub must inherit the empty-shim default")
    }

    func testWhatsAppNewIncomingMessagesReturnsEmptyWithToken() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "test-token", for: WhatsAppChannel.keychainTokenKey)
        let channel = WhatsAppChannel(keychain: keychain)
        let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty,
            "WhatsApp stub default returns empty regardless of auth state")
    }

    // MARK: - Cross-stub asymmetry contract

    /// The asymmetry itself: the same Keychain-empty state that makes
    /// `recentThreads` throw is silent for `newIncomingMessages`. Pin
    /// per-stub so a future "throw consistently across all entry points"
    /// hardening shows up as four failures, not one.
    func testRecentThreadsThrowsButNewIncomingMessagesDoesNotForEveryStub() async throws {
        let keychain = KeychainHelper(service: testService)

        // Each row: stub factory + its keychain token key. The token key
        // is captured but unused on this path — it documents which key
        // each stub gates on so the asymmetry is obvious in the test.
        let cases: [(name: String, build: () -> any ChannelService)] = [
            ("SMS",      { SMSChannel(keychain: keychain) }),
            ("Teams",    { TeamsChannel(keychain: keychain) }),
            ("Telegram", { TelegramChannel(keychain: keychain) }),
            ("WhatsApp", { WhatsAppChannel(keychain: keychain) }),
        ]

        for (name, build) in cases {
            let channel = build()

            // recentThreads must throw authorizationDenied with no token.
            do {
                _ = try await channel.recentThreads(limit: 10)
                XCTFail("\(name): recentThreads must throw without a token")
            } catch ChannelError.authorizationDenied {
                // expected
            }

            // newIncomingMessages must NOT throw — empty-shim default.
            let result = try await channel.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
            XCTAssertTrue(result.isEmpty,
                "\(name): newIncomingMessages must inherit the empty-shim default and not throw, even when recentThreads is auth-gated — the rule-engine replay loop depends on this asymmetry")
        }
    }
}
