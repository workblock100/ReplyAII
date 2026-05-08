import Foundation

/// Slack `ChannelService` — backed by the Slack Web API.
/// Uses `SlackTokenStore` for credential storage so OAuth and channel reads
/// share the exact same Keychain entry. Threads + message history come from
/// `conversations.list` and `conversations.history` respectively.
/// Factory closure for constructing a `SlackAuthorizing` flow per `authorize`
/// call. Per-call instances keep the localhost callback listener short-lived
/// (the listener binds a port for the duration of the OAuth round-trip).
typealias SlackOAuthFlowFactory = @Sendable () -> any SlackAuthorizing

/// Slack adapter wired through the Slack Web API. `recentThreads` and
/// `messages(forThreadID:limit:)` hit `conversations.list` /
/// `conversations.history` respectively; `authorize(...)` runs the
/// OAuth2 round-trip via `SlackOAuthFlow` and persists the resulting
/// token to `SlackTokenStore`. The class is `@unchecked Sendable`
/// because the injected `SlackHTTPClient` and `SlackTokenStore` are
/// already thread-safe and the only mutable state SlackChannel holds
/// is its constructor-set dependencies.
final class SlackChannel: ChannelService, @unchecked Sendable {
    let channel: Channel = .slack
    let displayName: String = "Slack"

    /// Slack's documented limit for both `conversations.list` and
    /// `conversations.history`. Sending `limit > 200` returns
    /// `invalid_arguments` from Slack; sending `limit < 1` produces
    /// either an error or unbounded results depending on the endpoint.
    /// Both `recentThreads(limit:)` and `messages(forThreadID:limit:)`
    /// clamp through `min(max(limit, 1), maxAPILimit)` — drift here
    /// surfaces opaque API errors to users for what looks like a sane
    /// request. Pinned by the existing clamp tests in `SlackChannelTests`
    /// (literal `200`); this constant ties the two clamp sites to a
    /// single named source so a future "let's bump to 500" lands once.
    static let maxAPILimit: Int = 200
    /// Lower bound on Slack API `limit` parameter — zero/negative values
    /// produce undefined behavior server-side.
    static let minAPILimit: Int = 1

    /// Slack Web API endpoint names embedded into `URLSessionSlackClient.get`/`.post`.
    /// Hoisted so the three call sites (recentThreads, messages, send) reference
    /// a single source of truth — drift at any one site quietly routes that
    /// operation to a wrong endpoint that returns `unknown_method` from Slack
    /// while the other two continue to work, a partial regression that's hard
    /// to spot in code review. Pinned by
    /// `SlackChannelTests.testEndpointNameLiteralsAreFrozen`.
    enum Endpoint {
        static let conversationsList    = "conversations.list"
        static let conversationsHistory = "conversations.history"
        static let chatPostMessage      = "chat.postMessage"
    }

    /// Slack Web API query-parameter vocabulary. Each key maps to a
    /// documented Slack parameter name (`conversations.list` accepts
    /// `limit`, `types`, `exclude_archived`; `conversations.history`
    /// accepts `channel`, `limit`; `chat.postMessage` accepts `channel`,
    /// `text`). Drift on these keys silently ignores the parameter
    /// (Slack accepts unknown query params and applies its defaults)
    /// — the listing returns archived channels, the limit reverts to
    /// 100, types defaults to public_channel only, etc. Hoisted so a
    /// future endpoint addition lands on the same vocabulary.
    enum Param {
        static let limit            = "limit"
        static let types            = "types"
        static let excludeArchived  = "exclude_archived"
        static let channel          = "channel"
        static let text             = "text"
    }

    /// Conversation-types filter passed to `conversations.list`.
    /// `im`=DMs, `mpim`=multi-person group DMs, `public_channel` and
    /// `private_channel`=workspace channels. The four-type combination
    /// is what surfaces ReplyAI's "all my conversations" semantics —
    /// drift drops a category from the inbox without any UX feedback
    /// (e.g. dropping `mpim` would silently hide every multi-person
    /// group DM from the sidebar). Pinned by
    /// `SlackChannelTests.testConversationTypesFilterIsFrozen`.
    static let conversationTypesFilter = "im,mpim,public_channel,private_channel"

    /// Slack `conversations.list` `exclude_archived` value. Pinned to
    /// the literal string `true` (Slack's API takes the value as a
    /// stringified bool, not a JSON bool). Drift to `"1"` or
    /// `Bool(true).description` would silently include every archived
    /// channel in the sidebar.
    static let excludeArchivedValue = "true"

    private let tokenStore: SlackTokenStore
    private let http: SlackHTTPClient
    private let oauthFlowFactory: SlackOAuthFlowFactory

    init(
        tokenStore: SlackTokenStore = SlackTokenStore(),
        http: SlackHTTPClient = URLSessionSlackClient(),
        oauthFlowFactory: @escaping SlackOAuthFlowFactory = { SlackOAuthFlow() }
    ) {
        self.tokenStore = tokenStore
        self.http = http
        self.oauthFlowFactory = oauthFlowFactory
    }

    /// Kick off Slack's OAuth2 flow. On success the access token + workspace
    /// name are written to `SlackTokenStore`, so the next `recentThreads` call
    /// returns real channels instead of throwing `authorizationDenied`.
    func authorize(
        clientID: String,
        clientSecret: String,
        completion: @escaping (Result<Void, OAuthError>) -> Void
    ) {
        oauthFlowFactory().authorize(
            clientID: clientID,
            clientSecret: clientSecret,
            completion: completion
        )
    }

    /// Returns the most-recent Slack channels (DMs + group DMs + open channels)
    /// the user is a member of. Threads have empty previews until
    /// `messages(forThreadID:limit:)` is called for them.
    func recentThreads(limit: Int) async throws -> [MessageThread] {
        guard let creds = tokenStore.get() else {
            throw ChannelError.authorizationDenied
        }
        let data = try await http.get(
            endpoint: Endpoint.conversationsList,
            token: creds.token,
            params: [
                Param.limit: String(min(max(limit, Self.minAPILimit), Self.maxAPILimit)),
                // im   = direct messages
                // mpim = multi-person group DMs
                // public_channel + private_channel = workspace channels
                Param.types: Self.conversationTypesFilter,
                Param.excludeArchived: Self.excludeArchivedValue,
            ]
        )
        return try Self.parseThreads(data, workspaceName: creds.workspaceName)
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        guard let creds = tokenStore.get() else {
            throw ChannelError.authorizationDenied
        }
        let data = try await http.get(
            endpoint: Endpoint.conversationsHistory,
            token: creds.token,
            params: [
                Param.channel: id,
                Param.limit: String(min(max(limit, Self.minAPILimit), Self.maxAPILimit)),
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
            endpoint: Endpoint.chatPostMessage,
            token: creds.token,
            json: [
                Param.channel: id,
                Param.text: text,
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
            // The final fallback also screens out empty strings so a
            // present-but-blank `name` can't render a literal empty sidebar row.
            let display: String = {
                if c.is_im == true, let user = c.user_display_name, !user.isEmpty { return user }
                if c.is_channel == true, let name = c.name, !name.isEmpty { return "#\(name)" }
                if let name = c.name, !name.isEmpty { return name }
                return c.id
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
