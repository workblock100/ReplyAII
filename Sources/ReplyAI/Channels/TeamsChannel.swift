import Foundation

/// Microsoft Teams ChannelService stub. Gates on a Graph API token in Keychain;
/// real API integration (conversations via Microsoft Graph) ships in a follow-up.
final class TeamsChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .teams
    let displayName: String = "Teams"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: "ReplyAI-Teams")) {
        self.keychain = keychain
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard keychain.get(key: "teams-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard keychain.get(key: "teams-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }
}
