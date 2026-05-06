import XCTest
@testable import ReplyAI

/// Pins the empty-string-token bypass behavior across the four non-iMessage
/// channel stubs (SMS, WhatsApp, Teams, Telegram). The auth gate in each
/// stub is `guard keychain.get(...) != nil else { throw .authorizationDenied }` —
/// an empty string is non-nil and therefore bypasses the gate. Two reasons
/// to pin it here:
///
/// 1. **Future Settings UI safety.** When the per-channel sign-in flow ships,
///    if it ever writes a placeholder empty token before the OAuth handshake
///    completes, `recentThreads()` will silently start returning `[]` instead
///    of throwing `.authorizationDenied`. That changes the inbox banner copy
///    from "Sign in to <channel>" to "No threads" — a worse UX. This test
///    documents the current behavior so a future tightening (`isEmpty`
///    rejection) is a deliberate change visible here, not a quiet drift.
///
/// 2. **Cross-stub uniformity.** All four stubs share the exact same gate,
///    so a refactor that hardens one (e.g. WhatsApp) without the others
///    would create asymmetric behavior — the rule engine would see different
///    error surfaces depending on which channel is misconfigured. Asserting
///    parity here surfaces that drift in CI.
///
/// The companion `ChannelStubKeychainContractTests` pins the keychain
/// service + token-key strings; this file pins the gate logic itself.
final class ChannelStubAuthGateEdgeTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-authgate-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        let keychain = KeychainHelper(service: testService)
        keychain.delete(key: "sms-token")
        keychain.delete(key: "whatsapp-token")
        keychain.delete(key: "teams-token")
        keychain.delete(key: "telegram-bot-token")
    }

    // MARK: - Empty-token bypass (pinned current behavior)

    func testSMSEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)

        // Empty string is non-nil → gate opens → recentThreads returns [] instead of throwing.
        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "empty token currently bypasses the auth gate — pin so a future isEmpty-tightening is deliberate")
    }

    func testWhatsAppEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: WhatsAppChannel.keychainTokenKey)
        let channel = WhatsAppChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "empty token currently bypasses the auth gate — pin so a future isEmpty-tightening is deliberate")
    }

    func testTeamsEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: TeamsChannel.keychainTokenKey)
        let channel = TeamsChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "empty token currently bypasses the auth gate — pin so a future isEmpty-tightening is deliberate")
    }

    func testTelegramEmptyTokenBypassesAuthGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: TelegramChannel.keychainTokenKey)
        let channel = TelegramChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertTrue(threads.isEmpty,
            "empty token currently bypasses the auth gate — pin so a future isEmpty-tightening is deliberate")
    }

    // MARK: - Empty-token bypass on messages() — symmetry with recentThreads

    func testSMSEmptyTokenBypassesMessagesGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)

        // messages() must mirror recentThreads()'s gate behavior — asymmetric gates would
        // surface as inconsistent error surfaces depending on which API the rule engine hits.
        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    func testWhatsAppEmptyTokenBypassesMessagesGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: WhatsAppChannel.keychainTokenKey)
        let channel = WhatsAppChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    func testTeamsEmptyTokenBypassesMessagesGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: TeamsChannel.keychainTokenKey)
        let channel = TeamsChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    func testTelegramEmptyTokenBypassesMessagesGate() async throws {
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "", for: TelegramChannel.keychainTokenKey)
        let channel = TelegramChannel(keychain: keychain)

        let messages = try await channel.messages(forThreadID: "any", limit: 10)
        XCTAssertTrue(messages.isEmpty)
    }

    // MARK: - Negative limit handling — pin the stub doesn't crash

    func testStubsAcceptNegativeLimitWithoutCrashing() async throws {
        // The stubs ignore `limit` entirely (early-return []), but that's a
        // contract that could regress if a future stub author adds a real
        // implementation that calls `Array.prefix(_:)` (which traps on
        // negative integers). Pin that the auth-gate path itself doesn't
        // crash on a negative limit so callers don't have to defensively
        // clamp before every call.
        let keychain = KeychainHelper(service: testService)
        try keychain.set(value: "ok", for: SMSChannel.keychainTokenKey)
        let channel = SMSChannel(keychain: keychain)

        let threads = try await channel.recentThreads(limit: -1)
        XCTAssertTrue(threads.isEmpty)
    }
}
