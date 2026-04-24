import Foundation

/// WhatsApp ChannelService stub. Gates on a session token in Keychain;
/// real API integration (WhatsApp Business API or WebView relay) ships
/// in a follow-up once the auth flow is established.
final class WhatsAppChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .whatsapp
    let displayName: String = "WhatsApp"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: "ReplyAI-WhatsApp")) {
        self.keychain = keychain
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard keychain.get(key: "whatsapp-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard keychain.get(key: "whatsapp-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }
}
