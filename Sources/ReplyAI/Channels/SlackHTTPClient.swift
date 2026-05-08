import Foundation

/// Seam for URLSession so Slack HTTP tests can inject a mock without live network calls.
protocol HTTPSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSessionProtocol {}

/// HTTP layer for Slack Web API GET + POST requests.
/// Injectable via `HTTPSessionProtocol` for test isolation.
protocol SlackHTTPClient: Sendable {
    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data
    /// Slack's POST endpoints (chat.postMessage, conversations.archive, etc.)
    /// take a JSON body with the bearer token in the Authorization header.
    func post(endpoint: String, token: String, json: [String: Any]) async throws -> Data
}

/// URLSession-backed `SlackHTTPClient`. Sends `GET https://slack.com/api/<endpoint>?<params>`
/// with `Authorization: Bearer <token>` and maps HTTP error codes to `ChannelError`.
struct URLSessionSlackClient: SlackHTTPClient {
    private static let apiBase = "https://slack.com/api/"

    /// User-visible error copy reused by both `get` and `post` for identical
    /// failure modes (no usable response, 429, non-2xx default). Hoisted so
    /// drift between the two call paths can't leave `get` saying one thing
    /// and `post` saying another for the same condition. Pinned by
    /// `SlackHTTPClientTests.testErrorMessageLiteralsAreFrozen`.
    enum ErrorMessage {
        static let unusableResponse = "Slack didn't return a usable response. Check your connection and try again."
        static let rateLimited      = "Slack is rate-limiting us right now. Wait a moment, then try again."
        static func unexpected(status: Int) -> String {
            "Slack returned an unexpected error (status \(status)). Try again shortly."
        }
    }

    /// HTTP request header constants. The bearer-token authorization header
    /// is built by every Slack request; the content-type header is only used
    /// by POST. Hoisting keeps the field name + value formatting consistent
    /// across `get` and `post`. Pinned by
    /// `SlackHTTPClientTests.testHeaderLiteralsAreFrozen`.
    enum Header {
        static let authorizationField = "Authorization"
        static let contentTypeField   = "Content-Type"
        static let contentTypeJSON    = "application/json; charset=utf-8"
        static func bearer(_ token: String) -> String { "Bearer \(token)" }
    }

    private let session: HTTPSessionProtocol

    init(session: HTTPSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data {
        guard var components = URLComponents(string: Self.apiBase + endpoint) else {
            throw ChannelError.networkError("Invalid Slack endpoint: \(endpoint)")
        }
        if !params.isEmpty {
            components.queryItems = params
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw ChannelError.networkError("Could not build Slack API URL for endpoint: \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.setValue(Header.bearer(token), forHTTPHeaderField: Header.authorizationField)

        let (data, response) = try await session.data(for: request)
        return try Self.handle(response: response, data: data)
    }

    func post(endpoint: String, token: String, json: [String: Any]) async throws -> Data {
        guard let url = URL(string: Self.apiBase + endpoint) else {
            throw ChannelError.networkError("Invalid Slack endpoint: \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Header.bearer(token), forHTTPHeaderField: Header.authorizationField)
        request.setValue(Header.contentTypeJSON, forHTTPHeaderField: Header.contentTypeField)
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await session.data(for: request)
        return try Self.handle(response: response, data: data)
    }

    /// Shared status-code dispatcher for `get` and `post`. Both endpoints
    /// route 401 to `authorizationDenied`, 429 to a rate-limit message, and
    /// other non-2xx codes to a generic message — keeping that decision in
    /// one place ensures the two paths can't drift.
    private static func handle(response: URLResponse, data: Data) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw ChannelError.networkError(ErrorMessage.unusableResponse)
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw ChannelError.authorizationDenied
        case 429:
            throw ChannelError.networkError(ErrorMessage.rateLimited)
        default:
            throw ChannelError.networkError(ErrorMessage.unexpected(status: http.statusCode))
        }
    }
}
