import XCTest
@testable import ReplyAI

// MARK: - Mock

/// Captures the URLRequest and returns a configured response without real network calls.
private final class MockHTTPSession: HTTPSessionProtocol, @unchecked Sendable {
    var capturedRequest: URLRequest?
    private let handler: (URLRequest) throws -> (Data, HTTPURLResponse)

    init(statusCode: Int, body: Data = Data()) {
        self.handler = { request in
            let url = request.url ?? URL(string: "https://slack.com")!
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode,
                httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request
        let (data, response) = try handler(request)
        return (data, response)
    }
}

// MARK: - Tests

final class SlackHTTPClientTests: XCTestCase {

    func testAuthHeaderIsBearerToken() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.get(endpoint: "conversations.list", token: "xoxb-my-token", params: [:])

        XCTAssertEqual(
            session.capturedRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer xoxb-my-token"
        )
    }

    func testCorrectEndpointURLConstructed() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.get(
            endpoint: "conversations.list",
            token: "tok",
            params: ["limit": "10", "exclude_archived": "true"]
        )

        let url = session.capturedRequest?.url
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "slack.com")
        XCTAssertEqual(url?.path, "/api/conversations.list")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "limit", value: "10")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "exclude_archived", value: "true")))
    }

    func testHTTP401ThrowsAuthDenied() async throws {
        let session = MockHTTPSession(statusCode: 401)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.get(endpoint: "conversations.list", token: "bad", params: [:])
            XCTFail("Expected authorizationDenied")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testHTTP429ThrowsNetworkError() async throws {
        let session = MockHTTPSession(statusCode: 429)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.get(endpoint: "conversations.list", token: "tok", params: [:])
            XCTFail("Expected networkError")
        } catch let e as ChannelError {
            guard case .networkError = e else {
                XCTFail("Expected ChannelError.networkError, got \(e)")
                return
            }
        }
    }

    func testSuccessfulResponseReturnsData() async throws {
        let expected = Data("""
        {"ok":true,"channels":[]}
        """.utf8)
        let session = MockHTTPSession(statusCode: 200, body: expected)
        let client = URLSessionSlackClient(session: session)

        let data = try await client.get(endpoint: "conversations.list", token: "tok", params: [:])
        XCTAssertEqual(data, expected)
    }
}
