import Foundation

/// Slack `ChannelService` — backed by the Slack Web API.
/// Uses `SlackTokenStore` for credential storage so OAuth and channel reads
/// share the exact same Keychain entry. Threads + message history come from
/// `conversations.list` and `conversations.history` respectively.
final class SlackChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .slack
    let displayName: String = "Slack"

    private let tokenStore: SlackTokenStore
    private let http: SlackHTTPClient

    init(
        tokenStore: SlackTokenStore = SlackTokenStore(),
        http: SlackHTTPClient = URLSessionSlackClient()
    ) {
        self.tokenStore = tokenStore
        self.http = http
    }

    /// Returns the most-recent Slack channels (DMs + group DMs + open channels)
    /// the user is a member of. Threads have empty previews until
    /// `messages(forThreadID:limit:)` is called for them.
    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard let creds = tokenStore.get() else {
            throw ChannelError.authorizationDenied
        }
        let data = try await http.get(
            endpoint: "conversations.list",
            token: creds.token,
            params: [
                "limit": String(min(max(limit, 1), 200)),
                // im   = direct messages
                // mpim = multi-person group DMs
                // public_channel + private_channel = workspace channels
                "types": "im,mpim,public_channel,private_channel",
                "exclude_archived": "true",
            ]
        )
        return try Self.parseThreads(data, workspaceName: creds.workspaceName)
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard let creds = tokenStore.get() else {
            throw ChannelError.authorizationDenied
        }
        let data = try await http.get(
            endpoint: "conversations.history",
            token: creds.token,
            params: [
                "channel": id,
                "limit": String(min(max(limit, 1), 200)),
            ]
        )
        return try Self.parseMessages(data)
    }

    /// Post `text` to a Slack channel/DM via `chat.postMessage`. Returns
    /// silently on Slack's `ok: true` and throws `ChannelError` otherwise so
    /// `InboxViewModel.confirmSend` can surface the error in a toast.
    func send(text: String, toThreadID id: String) async throws {
        guard let creds = tokenStore.get() else {
            throw ChannelError.authorizationDenied
        }
        let data = try await http.post(
            endpoint: "chat.postMessage",
            token: creds.token,
            json: [
                "channel": id,
                "text": text,
            ]
        )
        // Slack acks 200 OK even when the API call failed; the body has
        // `ok: false` + an error string. Decode and surface.
        struct Ack: Decodable { let ok: Bool; let error: String? }
        let ack = try JSONDecoder().decode(Ack.self, from: data)
        if !ack.ok {
            throw ChannelError.networkError(ack.error ?? "Slack chat.postMessage failed")
        }
    }

    // MARK: - Parsing

    private static func parseThreads(_ data: Data, workspaceName: String) throws -> [MessageThread] {
        let payload = try JSONDecoder().decode(ConversationsListResponse.self, from: data)
        guard payload.ok else {
            throw ChannelError.networkError(payload.error ?? "Slack conversations.list failed")
        }
        return payload.channels.map { c in
            // DMs use the user's real name; channels use #name; group DMs use a
            // synthesized list of members (Slack returns it pre-formatted in `name`).
            let display: String = {
                if c.is_im == true, let user = c.user_display_name, !user.isEmpty { return user }
                if c.is_channel == true, let name = c.name, !name.isEmpty { return "#\(name)" }
                return c.name ?? c.id
            }()
            return MessageThread(
                id: c.id,
                channel: .slack,
                name: display,
                avatar: String(display.prefix(1)).uppercased(),
                preview: workspaceName,
                time: "",
                unread: c.unread_count ?? 0,
                pinned: false,
                contextCount: 0,
                contextSummary: nil,
                chatGUID: c.id,
                hasAttachment: false
            )
        }
    }

    private static func parseMessages(_ data: Data) throws -> [Message] {
        let payload = try JSONDecoder().decode(ConversationsHistoryResponse.self, from: data)
        guard payload.ok else {
            throw ChannelError.networkError(payload.error ?? "Slack conversations.history failed")
        }
        // Slack returns newest-first; ReplyAI views render oldest-first.
        let formatter = relativeFormatter()
        return payload.messages.reversed().map { m in
            let date: Date? = Double(m.ts ?? "").map { Date(timeIntervalSince1970: $0) }
            return Message(
                from: (m.user != nil) ? .them : .me,
                text: m.text ?? "",
                time: date.map { formatter.localizedString(for: $0, relativeTo: Date()) } ?? "",
                rowID: 0,
                hasAttachment: (m.files?.isEmpty == false),
                isRead: true,
                deliveredAt: date
            )
        }
    }

    private static func relativeFormatter() -> RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }

    // MARK: - Slack response shapes (only the fields we read)

    private struct ConversationsListResponse: Decodable {
        let ok: Bool
        let error: String?
        let channels: [ConvSummary]
    }

    private struct ConvSummary: Decodable {
        let id: String
        let name: String?
        let is_im: Bool?
        let is_channel: Bool?
        let unread_count: Int?
        // For DMs Slack returns `user` (an ID); we fetch the display name out-of-band
        // — for now we leave it nil and fall back to the channel id.
        let user_display_name: String?
    }

    private struct ConversationsHistoryResponse: Decodable {
        let ok: Bool
        let error: String?
        let messages: [SlackMessage]
    }

    private struct SlackMessage: Decodable {
        let ts: String?
        let user: String?
        let text: String?
        let files: [SlackFile]?
    }

    private struct SlackFile: Decodable {
        let id: String?
    }
}
