import Foundation

/// SMS ChannelService stub. SMS relay via CloudKit from iPhone is a future
/// feature; this stub gates on a relay token so the plumbing is in place
/// when the relay implementation ships.
final class SMSChannel: ChannelService, @unchecked Sendable {
    /// Production keychain service name. Persisted across launches; renaming
    /// orphans every existing user's relay token. Pinned by
    /// `ChannelStubKeychainContractTests`.
    static let keychainService = "ReplyAI-SMS"
    /// Production keychain item key for the relay token.
    static let keychainTokenKey = "sms-token"

    let channel: Channel = .sms
    let displayName: String = "SMS"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: SMSChannel.keychainService)) {
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
