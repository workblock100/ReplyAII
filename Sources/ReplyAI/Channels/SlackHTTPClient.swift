import Foundation

/// Seam for URLSession so Slack HTTP tests can inject a mock without live network calls.
protocol HTTPSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSessionProtocol {}

/// HTTP layer for Slack Web API GET requests.
/// Injectable via `HTTPSessionProtocol` for test isolation.
protocol SlackHTTPClient: Sendable {
    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data
}

/// URLSession-backed `SlackHTTPClient`. Sends `GET https://slack.com/api/<endpoint>?<params>`
/// with `Authorization: Bearer <token>` and maps HTTP error codes to `ChannelError`.
struct URLSessionSlackClient: SlackHTTPClient {
    private static let apiBase = "https://slack.com/api/"

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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChannelError.networkError("Non-HTTP response from Slack API")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw ChannelError.authorizationDenied
        case 429:
            throw ChannelError.networkError("Slack API rate limited (HTTP 429)")
        default:
            throw ChannelError.networkError("Slack API returned HTTP \(http.statusCode)")
        }
    }
}
