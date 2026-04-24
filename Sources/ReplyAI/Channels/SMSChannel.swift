import Foundation

/// SMS ChannelService stub. SMS relay via CloudKit from iPhone is a future
/// feature; this stub gates on a relay token so the plumbing is in place
/// when the relay implementation ships.
final class SMSChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .sms
    let displayName: String = "SMS"

    private let keychain: KeychainHelper

    init(keychain: KeychainHelper = KeychainHelper(service: "ReplyAI-SMS")) {
        self.keychain = keychain
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard keychain.get(key: "sms-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard keychain.get(key: "sms-token") != nil else {
            throw ChannelError.authorizationDenied
        }
        return []
    }
}
