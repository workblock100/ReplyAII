import Foundation

/// Slack ChannelService stub. All operations gate on a Keychain token;
/// real API calls (conversations.list, Socket Mode) land in a follow-up
/// once the OAuth flow (REP-010) stores a token.
final class SlackChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .slack
    let displayName: String = "Slack"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper()) {
        self.keychain = keychain
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard keychain.get(key: "Slack-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard keychain.get(key: "Slack-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }
}
