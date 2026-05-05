import Foundation

/// Telegram ChannelService stub. All operations gate on a Keychain bot token;
/// real API calls (getUpdates, sendMessage) land in a follow-up once the
/// bot-token onboarding flow stores a token.
final class TelegramChannel: ChannelService, @unchecked Sendable {
    /// Production keychain service name. **Note:** uses reverse-DNS form
    /// (`co.replyai.telegram`) rather than the `ReplyAI-<Channel>` convention
    /// the other channel stubs use — this is a known inconsistency. Renaming
    /// to match the others would orphan existing user bot tokens. Pinned by
    /// `ChannelStubKeychainContractTests`.
    static let keychainService = "co.replyai.telegram"
    /// Production keychain item key for the Telegram bot token.
    static let keychainTokenKey = "telegram-bot-token"

    let channel: Channel = .telegram
    let displayName: String = "Telegram"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: TelegramChannel.keychainService)) {
        self.keychain = keychain
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard keychain.get(key: Self.keychainTokenKey) != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard keychain.get(key: Self.keychainTokenKey) != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }
}
