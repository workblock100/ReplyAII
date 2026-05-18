import XCTest
@testable import ReplyAICore

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
            session.capturedRequest?.value(forHTTPHeaderField: URLSessionSlackClient.Header.authorizationField),
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

        XCTAssertEqual(session.capturedRequest?.httpMethod, URLSessionSlackClient.postHTTPMethod)
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
        XCTAssertEqual(req?.value(forHTTPHeaderField: URLSessionSlackClient.Header.authorizationField), URLSessionSlackClient.Header.bearer("xoxb-my-token"))
        XCTAssertEqual(req?.value(forHTTPHeaderField: URLSessionSlackClient.Header.contentTypeField), URLSessionSlackClient.Header.contentTypeJSON)
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

    // MARK: - Exact-copy pins
    //
    // The `contains` checks above keep tests resilient to small wording
    // tweaks, but the copy here is the entire user-visible banner — a
    // designer-led rephrasing should land as a code-review diff, not
    // slip in unnoticed. Pin the full literals so any rewording surfaces
    // here. When the copy intentionally changes, update both the source
    // string and this test in the same commit.

    func test429CopyExactLiteral() async throws {
        let session = MockHTTPSession(statusCode: 429)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.get(endpoint: "conversations.list", token: "t", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack is rate-limiting us right now. Wait a moment, then try again.")
        }
    }

    func test5xxCopyExactLiteralIncludesStatusCode() async throws {
        let session = MockHTTPSession(statusCode: 503)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.get(endpoint: "conversations.list", token: "t", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack returned an unexpected error (status 503). Try again shortly.")
        }
    }

    /// 4xx codes other than 401 (auth) and 429 (rate-limit) fall to the
    /// default arm with the same "unexpected error" copy + interpolated
    /// status code. Pin so a future "treat 403 as authorizationDenied"
    /// or "swallow 404 as empty" refactor surfaces here as a deliberate
    /// status-mapping change rather than silent UX drift.
    func test403FallsToUnexpectedDefaultArm() async throws {
        let session = MockHTTPSession(statusCode: 403)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.get(endpoint: "conversations.list", token: "t", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack returned an unexpected error (status 403). Try again shortly.",
                "403 must NOT route to authorizationDenied — that's reserved for 401. Default-arm copy with the literal status code is the contract.")
        }
    }

    /// 404 is also a default-arm case — Slack uses 404 for unknown
    /// endpoints / deleted resources, NOT for "empty result". Pin the
    /// default-arm routing so a "treat 404 as empty Data" shortcut
    /// surfaces here. Empty data from a successful 200 already hits
    /// the success path; 404 is genuinely unexpected.
    func test404FallsToUnexpectedDefaultArm() async throws {
        let session = MockHTTPSession(statusCode: 404)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.get(endpoint: "no.such.endpoint", token: "t", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack returned an unexpected error (status 404). Try again shortly.",
                "404 must hit the default arm; do not silently coerce to empty data")
        }
    }

    func testNonHTTPResponseCopyExactLiteral() async throws {
        let session = MockHTTPSession(returnsNonHTTPURLResponse: true)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.get(endpoint: "auth.test", token: "t", params: [:])
            XCTFail("Expected networkError")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack didn't return a usable response. Check your connection and try again.")
        }
    }

    func testGet401MapsToAuthorizationDeniedNotNetworkError() async throws {
        // 401 is special: it routes to .authorizationDenied so the inbox
        // can render the "open Settings to reconnect" banner instead of
        // a transient network error. A future refactor that lumps it in
        // with .networkError("…") would silently break that surface.
        let session = MockHTTPSession(statusCode: 401)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.get(endpoint: "conversations.list", token: "t", params: [:])
            XCTFail("Expected authorizationDenied")
        } catch ChannelError.authorizationDenied {
            // expected
        } catch {
            XCTFail("Expected .authorizationDenied, got \(error)")
        }
    }

    func testPost401MapsToAuthorizationDenied() async throws {
        let session = MockHTTPSession(statusCode: 401)
        let client = URLSessionSlackClient(session: session)
        do {
            _ = try await client.post(endpoint: "chat.postMessage", token: "t", json: ["channel": "C123"])
            XCTFail("Expected authorizationDenied")
        } catch ChannelError.authorizationDenied {
            // expected
        } catch {
            XCTFail("Expected .authorizationDenied, got \(error)")
        }
    }

    // MARK: - 2xx success boundary

    /// 204 No Content is part of the 200…299 success range that the client
    /// treats as OK. Slack's `chat.delete` and `conversations.archive` happen
    /// to return 200 with an empty body, but defensive coding around the
    /// boundary matters because any future endpoint Slack adds (or any
    /// proxy in front of it) could legitimately return 204. The test pins
    /// the contract: empty 204 response data passes through unchanged
    /// instead of throwing.
    func test204SuccessReturnsEmptyDataWithoutThrowing() async throws {
        let session = MockHTTPSession(statusCode: 204, body: Data())
        let client = URLSessionSlackClient(session: session)
        let data = try await client.get(endpoint: "anything.endpoint", token: "t", params: [:])
        XCTAssertEqual(data, Data(),
            "204 No Content must yield empty Data() without throwing")
    }

    func test299SuccessBoundaryReturnsBody() async throws {
        // Last status code in the 2xx switch range. If a future refactor
        // narrows the success arm to 200..<299 or similar, this asserts
        // 299 still passes.
        let body = Data("{\"ok\":true}".utf8)
        let session = MockHTTPSession(statusCode: 299, body: body)
        let client = URLSessionSlackClient(session: session)
        let data = try await client.get(endpoint: "anything", token: "t", params: [:])
        XCTAssertEqual(data, body,
            "299 must remain in the success arm of the status switch")
    }

    // MARK: - URL-encoding contract for query params

    /// Slack workspace IDs and channel IDs don't include reserved chars,
    /// but Slack search queries (`search.messages` `query=...`) routinely
    /// contain spaces, ampersands, plus signs, etc. URLComponents must
    /// percent-encode those into the query string — passing them raw
    /// would either land at the wrong endpoint or confuse Slack's parser.
    func testGetParamsAreURLEncodedForReservedCharacters() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)
        _ = try await client.get(
            endpoint: "search.messages",
            token: "t",
            params: ["query": "hello world & more"]
        )
        let urlString = session.capturedRequest?.url?.absoluteString ?? ""
        // The exact percent-encoding URLComponents picks is "hello%20world..."
        // for spaces and "%26" for ampersand — assert the raw chars don't
        // leak through.
        XCTAssertFalse(urlString.contains("hello world"),
            "raw spaces must not appear unencoded in the URL: \(urlString)")
        XCTAssertFalse(urlString.contains(" & "),
            "raw ampersand must not appear unencoded — would be parsed as a separator: \(urlString)")
        XCTAssertTrue(urlString.contains("query="),
            "query parameter name must be present: \(urlString)")
    }

    /// POST endpoints set Content-Type to `application/json; charset=utf-8`
    /// — pinned exactly because Slack's API docs reject `application/json`
    /// alone for some endpoints, and a refactor that drops the charset
    /// would surface as 400 errors only in production.
    func testPostContentTypeIncludesUTF8Charset() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)
        _ = try await client.post(endpoint: "chat.postMessage", token: "t", json: ["text": "hi"])
        XCTAssertEqual(
            session.capturedRequest?.value(forHTTPHeaderField: URLSessionSlackClient.Header.contentTypeField),
            "application/json; charset=utf-8",
            "Content-Type must include charset=utf-8 — Slack rejects bare application/json on some endpoints"
        )
    }

    // MARK: - apiBase exact-string pin
    //
    // The private `URLSessionSlackClient.apiBase = "https://slack.com/api/"`
    // is the load-bearing constant for every Slack request. It's currently
    // checked piecewise (scheme/host/path) but never as the full literal
    // prefix. A subtle drift — say, dropping the trailing slash so the
    // first endpoint character collides with `api`, or swapping in
    // `slack.com/api/v2/` to "support a future API version" — would land
    // every request at the wrong path. Pin the full noQuery URL string
    // for both verbs.

    func testGetURLAbsoluteStringMatchesSlackApiPrefix() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)
        _ = try await client.get(endpoint: "auth.test", token: "tok", params: [:])

        let url = session.capturedRequest?.url?.absoluteString ?? ""
        XCTAssertEqual(url, "https://slack.com/api/auth.test",
            "GET URL with no params must equal the apiBase + endpoint exactly — drift in the prefix lands every request at the wrong path")
    }

    func testPostURLAbsoluteStringMatchesSlackApiPrefix() async throws {
        let session = MockHTTPSession(statusCode: 200, body: Data("{}".utf8))
        let client = URLSessionSlackClient(session: session)
        _ = try await client.post(endpoint: "chat.postMessage", token: "tok", json: [:])

        let url = session.capturedRequest?.url?.absoluteString ?? ""
        XCTAssertEqual(url, "https://slack.com/api/chat.postMessage",
            "POST URL must equal the apiBase + endpoint exactly — drift here would surface as 404 errors in production only")
    }

    // MARK: - Hoisted-constant pins
    //
    // The user-visible error copy + auth headers used to be inlined twice
    // (once in `get`, once in `post`). They've been hoisted to
    // `URLSessionSlackClient.ErrorMessage` and `.Header` so the two verbs
    // share one source of truth. These tests pin the literal values so
    // a typo in either struct can't silently degrade only one verb's
    // user-facing copy or auth scheme.

    func testErrorMessageLiteralsAreFrozen() {
        XCTAssertEqual(
            URLSessionSlackClient.ErrorMessage.unusableResponse,
            "Slack didn't return a usable response. Check your connection and try again."
        )
        XCTAssertEqual(
            URLSessionSlackClient.ErrorMessage.rateLimited,
            "Slack is rate-limiting us right now. Wait a moment, then try again."
        )
        XCTAssertEqual(
            URLSessionSlackClient.ErrorMessage.unexpected(status: 503),
            "Slack returned an unexpected error (status 503). Try again shortly."
        )
    }

    func testHeaderLiteralsAreFrozen() {
        XCTAssertEqual(URLSessionSlackClient.Header.authorizationField, "Authorization")
        XCTAssertEqual(URLSessionSlackClient.Header.contentTypeField,   "Content-Type")
        XCTAssertEqual(URLSessionSlackClient.Header.contentTypeJSON,    "application/json; charset=utf-8")
        XCTAssertEqual(URLSessionSlackClient.Header.bearer("xoxb-abc"), "Bearer xoxb-abc")
    }

    func testGetAndPostShareSameUnusableResponseCopy() async {
        // Both verbs go through the same `handle(response:data:)` helper, so the
        // exact error.localizedDescription emitted on a non-HTTPURLResponse must
        // be identical for `get` and `post`. This is the regression class hoisting
        // was meant to prevent (a typo in only one verb's copy).
        let session = MockHTTPSession(returnsNonHTTPURLResponse: true)
        let client = URLSessionSlackClient(session: session)

        var getMessage: String?
        var postMessage: String?
        do { _ = try await client.get(endpoint: "auth.test", token: "t", params: [:]) }
        catch let ChannelError.networkError(msg) { getMessage = msg }
        catch { XCTFail("expected networkError, got \(error)") }
        do { _ = try await client.post(endpoint: "chat.postMessage", token: "t", json: [:]) }
        catch let ChannelError.networkError(msg) { postMessage = msg }
        catch { XCTFail("expected networkError, got \(error)") }

        XCTAssertNotNil(getMessage)
        XCTAssertEqual(getMessage, postMessage,
            "GET and POST must surface the same user-visible copy for the unusable-response failure mode")
        XCTAssertEqual(getMessage, URLSessionSlackClient.ErrorMessage.unusableResponse)
    }

    // MARK: - Request-shape vocabulary pins (REP-hoist 2026-05-07)

    /// Pin the HTTP method for the `post` overload. Drift to a wrong
    /// verb (e.g. `PUT`) silently routes every Slack chat send to a
    /// `method_not_allowed` 405.
    func testPostHTTPMethodIsPOST() {
        XCTAssertEqual(URLSessionSlackClient.postHTTPMethod, "POST",
            "postHTTPMethod must be POST — Slack's chat.postMessage rejects every other verb")
    }

    /// Pin the URL-construction failure prefixes. Drift on either
    /// changes the format of every URL-construction error toast and
    /// breaks any support engineer's grep on `Invalid Slack endpoint:`
    /// or `Could not build Slack API URL for endpoint:`.
    func testInvalidEndpointPrefixIsFrozen() {
        XCTAssertEqual(URLSessionSlackClient.invalidEndpointPrefix,
                       "Invalid Slack endpoint: ",
            "invalidEndpointPrefix drift breaks support-engineer grep on the URLComponents-failure log line")
    }

    func testURLBuildFailedPrefixIsFrozen() {
        XCTAssertEqual(URLSessionSlackClient.urlBuildFailedPrefix,
                       "Could not build Slack API URL for endpoint: ",
            "urlBuildFailedPrefix drift breaks support-engineer grep on the components-to-URL failure log line")
    }
}
