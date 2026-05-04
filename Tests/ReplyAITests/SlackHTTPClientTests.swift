import XCTest
@testable import ReplyAI

// MARK: - Mock

/// Captures the URLRequest and returns a configured response without real network calls.
private final class MockHTTPSession: HTTPSessionProtocol, @unchecked Sendable {
    var capturedRequest: URLRequest?
    private let handler: (URLRequest) throws -> (Data, URLResponse)

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

    /// Returns a non-HTTPURLResponse so the client's `as? HTTPURLResponse`
    /// downcast fails — exercises the "didn't return a usable response" path.
    init(returnsNonHTTPURLResponse: Bool) {
        precondition(returnsNonHTTPURLResponse)
        self.handler = { request in
            let url = request.url ?? URL(string: "https://slack.com")!
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
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

    // MARK: - GET edge cases

    func testGetWithNoParamsOmitsQueryString() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.get(endpoint: "auth.test", token: "tok", params: [:])

        let url = session.capturedRequest?.url
        XCTAssertNil(url?.query, "no params should leave URL.query nil, not empty-string")
        XCTAssertEqual(url?.path, "/api/auth.test")
    }

    func testGetParamsAreSortedDeterministically() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.get(
            endpoint: "conversations.list",
            token: "tok",
            params: ["zeta": "z", "alpha": "a", "mid": "m"]
        )

        // The implementation sorts by key — query items must come back alphabetical
        // so request ordering is deterministic for cache lookups and test asserts.
        let items = URLComponents(url: session.capturedRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.map(\.name), ["alpha", "mid", "zeta"])
    }

    func testGetWith500ThrowsNetworkError() async throws {
        let session = MockHTTPSession(statusCode: 500)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.get(endpoint: "conversations.list", token: "tok", params: [:])
            XCTFail("Expected networkError")
        } catch let e as ChannelError {
            guard case .networkError(let msg) = e else {
                XCTFail("Expected ChannelError.networkError, got \(e)")
                return
            }
            XCTAssertTrue(msg.contains("500"), "5xx error message should include status code, got: \(msg)")
        }
    }

    func testGetWithNonHTTPResponseThrowsNetworkError() async throws {
        let session = MockHTTPSession(returnsNonHTTPURLResponse: true)
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

    // MARK: - POST path

    func testPostUsesPOSTMethod() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.post(
            endpoint: "chat.postMessage",
            token: "xoxb-tok",
            json: ["channel": "C123", "text": "hi"]
        )

        XCTAssertEqual(session.capturedRequest?.httpMethod, "POST")
    }

    func testPostSetsBearerAuthAndJSONContentType() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.post(
            endpoint: "chat.postMessage",
            token: "xoxb-my-token",
            json: ["channel": "C1"]
        )

        let req = session.capturedRequest
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer xoxb-my-token")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
    }

    func testPostSerializesJSONBody() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.post(
            endpoint: "chat.postMessage",
            token: "tok",
            json: ["channel": "C99", "text": "hello"]
        )

        let body = session.capturedRequest?.httpBody ?? Data()
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(decoded?["channel"], "C99")
        XCTAssertEqual(decoded?["text"], "hello")
    }

    func testPostHits401ThrowsAuthDenied() async throws {
        let session = MockHTTPSession(statusCode: 401)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.post(endpoint: "chat.postMessage", token: "bad", json: [:])
            XCTFail("Expected authorizationDenied")
        } catch ChannelError.authorizationDenied {
            // Expected
        }
    }

    func testPostHits429ThrowsNetworkError() async throws {
        let session = MockHTTPSession(statusCode: 429)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.post(endpoint: "chat.postMessage", token: "tok", json: [:])
            XCTFail("Expected networkError")
        } catch let e as ChannelError {
            guard case .networkError = e else {
                XCTFail("Expected ChannelError.networkError, got \(e)")
                return
            }
        }
    }

    func testPostHits500ThrowsNetworkError() async throws {
        let session = MockHTTPSession(statusCode: 503)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.post(endpoint: "chat.postMessage", token: "tok", json: [:])
            XCTFail("Expected networkError")
        } catch let e as ChannelError {
            guard case .networkError(let msg) = e else {
                XCTFail("Expected ChannelError.networkError, got \(e)")
                return
            }
            XCTAssertTrue(msg.contains("503"), "5xx error message should include status code, got: \(msg)")
        }
    }

    func testPostSuccessfulResponseReturnsBody() async throws {
        let expected = Data("""
        {"ok":true,"ts":"1234.5678"}
        """.utf8)
        let session = MockHTTPSession(statusCode: 200, body: expected)
        let client = URLSessionSlackClient(session: session)

        let data = try await client.post(endpoint: "chat.postMessage", token: "tok", json: [:])
        XCTAssertEqual(data, expected)
    }

    func testPostURLTargetsCorrectEndpoint() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)

        _ = try await client.post(endpoint: "conversations.archive", token: "tok", json: [:])

        let url = session.capturedRequest?.url
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "slack.com")
        XCTAssertEqual(url?.path, "/api/conversations.archive")
        XCTAssertNil(url?.query, "POST should never put params in the query string")
    }

    func testPostWithNonHTTPResponseThrowsNetworkError() async throws {
        let session = MockHTTPSession(returnsNonHTTPURLResponse: true)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.post(endpoint: "chat.postMessage", token: "tok", json: [:])
            XCTFail("Expected networkError")
        } catch let e as ChannelError {
            guard case .networkError = e else {
                XCTFail("Expected ChannelError.networkError, got \(e)")
                return
            }
        }
    }

    // MARK: - User-actionable copy (regression guards)

    func test429MessageNamesRateLimitAndAdvisesRetry() async throws {
        // The 429 path is the most-likely error a user will see in steady-state
        // use. The copy must (a) name Slack's rate-limit so the user knows it's
        // not their fault and (b) suggest waiting + retrying so the user has a
        // clear next step. A refactor that swaps in a generic "request failed"
        // would silently regress UX without this guard.
        let session = MockHTTPSession(statusCode: 429)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.get(endpoint: "conversations.list", token: "tok", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("rate-limit") || msg.localizedCaseInsensitiveContains("rate limit"),
                          "429 copy should name rate-limiting, got: \(msg)")
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("try again") || msg.localizedCaseInsensitiveContains("retry"),
                          "429 copy should advise retry, got: \(msg)")
        }
    }

    func testNonHTTPResponseMessagePromptsConnectionCheck() async throws {
        // The non-HTTPURLResponse path is rare but indicates a transport-level
        // breakdown (no DNS, captive portal, etc). Copy should point the user at
        // their connection rather than blaming Slack.
        let session = MockHTTPSession(returnsNonHTTPURLResponse: true)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.get(endpoint: "auth.test", token: "tok", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("connection"),
                          "non-HTTP response copy should mention checking the connection, got: \(msg)")
        }
    }

    func test5xxMessageEncouragesRetry() async throws {
        // 5xx means Slack is the problem, not the user. Copy should make that
        // implicit (suggest retry) rather than implying the user did something
        // wrong.
        let session = MockHTTPSession(statusCode: 502)
        let client = URLSessionSlackClient(session: session)

        do {
            _ = try await client.get(endpoint: "conversations.list", token: "tok", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("try again"),
                          "5xx copy should advise retry, got: \(msg)")
        }
    }
}
