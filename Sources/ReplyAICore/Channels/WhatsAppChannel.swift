import Foundation

/// WhatsApp ChannelService stub. Gates on a session token in Keychain;
/// real API integration (WhatsApp Business API or WebView relay) ships
/// in a follow-up once the auth flow is established.
final class WhatsAppChannel: ChannelService, @unchecked Sendable {
    /// Production keychain service name. Persisted across launches; renaming
    /// orphans every existing user's session token. Pinned by
    /// `ChannelStubKeychainContractTests`.
    static let keychainService = "ReplyAI-WhatsApp"
    /// Production keychain item key for the session token.
    static let keychainTokenKey = "whatsapp-token"

    let channel: Channel = .whatsapp
    let displayName: String = "WhatsApp"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: WhatsAppChannel.keychainService)) {
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
