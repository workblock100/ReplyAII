import Foundation

/// Microsoft Teams ChannelService stub. Gates on a Graph API token in Keychain;
/// real API integration (conversations via Microsoft Graph) ships in a follow-up.
final class TeamsChannel: ChannelService, @unchecked Sendable {
    /// Production keychain service name. Persisted across launches; renaming
    /// orphans every existing user's Graph token. Pinned by
    /// `ChannelStubKeychainContractTests`.
    static let keychainService = "ReplyAI-Teams"
    /// Production keychain item key for the Graph API token.
    static let keychainTokenKey = "teams-token"

    let channel: Channel = .teams
    let displayName: String = "Teams"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: TeamsChannel.keychainService)) {
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
