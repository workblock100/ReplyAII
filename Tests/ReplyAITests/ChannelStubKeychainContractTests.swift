import XCTest
@testable import ReplyAI

/// Pins the production keychain service + token-key strings used by the four
/// non-iMessage channel stubs (SMS, Teams, Telegram, WhatsApp). These strings
/// are the persistent identity of each channel's stored credential — once a
/// user authorizes, renaming either string orphans the existing token and
/// silently re-prompts for credentials at next launch. Telegram in particular
/// uses a reverse-DNS service name (`co.replyai.telegram`) that diverges from
/// the `ReplyAI-<Channel>` convention the other stubs follow; a well-meaning
/// "consistency" refactor would break every authorized user. These tests
/// fail loud the moment that drift happens.
final class ChannelStubKeychainContractTests: XCTestCase {

    // MARK: - SMS

    func testSMSKeychainServiceIsStable() {
        XCTAssertEqual(SMSChannel.keychainService, "ReplyAI-SMS")
    }

    func testSMSKeychainTokenKeyIsStable() {
        XCTAssertEqual(SMSChannel.keychainTokenKey, "sms-token")
    }

    // MARK: - Teams

    func testTeamsKeychainServiceIsStable() {
        XCTAssertEqual(TeamsChannel.keychainService, "ReplyAI-Teams")
    }

    func testTeamsKeychainTokenKeyIsStable() {
        XCTAssertEqual(TeamsChannel.keychainTokenKey, "teams-token")
    }

    // MARK: - Telegram

    func testTelegramKeychainServiceIsReverseDNS() {
        // Telegram intentionally diverges from the `ReplyAI-<Channel>` convention.
        // Do NOT "normalize" this — existing user bot tokens live at this exact
        // service identifier in the macOS keychain.
        XCTAssertEqual(TelegramChannel.keychainService, "co.replyai.telegram")
    }

    func testTelegramKeychainTokenKeyIsStable() {
        XCTAssertEqual(TelegramChannel.keychainTokenKey, "telegram-bot-token")
    }

    // MARK: - WhatsApp

    func testWhatsAppKeychainServiceIsStable() {
        XCTAssertEqual(WhatsAppChannel.keychainService, "ReplyAI-WhatsApp")
    }

    func testWhatsAppKeychainTokenKeyIsStable() {
        XCTAssertEqual(WhatsAppChannel.keychainTokenKey, "whatsapp-token")
    }

    // MARK: - Cross-channel invariants

    func testServicesAreUnique() {
        // Two channels sharing a service identifier would mean their keys live
        // in the same macOS keychain "namespace" — a token write for one could
        // be read by the other if they used the same token-key by mistake.
        let services = [
            SMSChannel.keychainService,
            TeamsChannel.keychainService,
            TelegramChannel.keychainService,
            WhatsAppChannel.keychainService,
        ]
        XCTAssertEqual(Set(services).count, services.count,
                       "channel keychain service identifiers must be unique per channel")
    }

    func testTokenKeysAreUnique() {
        let keys = [
            SMSChannel.keychainTokenKey,
            TeamsChannel.keychainTokenKey,
            TelegramChannel.keychainTokenKey,
            WhatsAppChannel.keychainTokenKey,
        ]
        XCTAssertEqual(Set(keys).count, keys.count,
                       "channel keychain token keys must be unique per channel")
    }
}
