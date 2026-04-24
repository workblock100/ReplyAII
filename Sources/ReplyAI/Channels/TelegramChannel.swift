import Foundation

/// Telegram ChannelService stub. All operations gate on a Keychain bot token;
/// real API calls (getUpdates, sendMessage) land in a follow-up once the
/// bot-token onboarding flow stores a token.
final class TelegramChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .telegram
    let displayName: String = "Telegram"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: "co.replyai.telegram")) {
        self.keychain = keychain
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard keychain.get(key: "telegram-bot-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard keychain.get(key: "telegram-bot-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }
}
