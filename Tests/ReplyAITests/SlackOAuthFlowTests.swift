import XCTest
@testable import ReplyAI

// MARK: - Test doubles

private final class MockURLOpener: URLOpener, @unchecked Sendable {
    private(set) var openedURL: URL?
    func open(_ url: URL) { openedURL = url }
}

/// Delivers a preset code (or error) immediately when start() is called.
private final class MockOAuthCallbackListener: OAuthCallbackListener, @unchecked Sendable {
    let actualPort: UInt16? = 4242
    private let result: Result<String, OAuthError>

    init(code: String) { self.result = .success(code) }
    init(error: OAuthError) { self.result = .failure(error) }

    func start(
        completion: @escaping (Result<String, OAuthError>) -> Void,
        onReady: (() -> Void)?
    ) {
        onReady?()
        completion(result)
    }

    func stop() {}
}

/// Stubs URLSession data-task responses without touching the network.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var stubbedResponseJSON: [String: Any] = [:]
    static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession converts httpBody → httpBodyStream when going through custom protocols.
        // Read the stream back into httpBody so assertions against req.httpBody work.
        var mutable = request
        if mutable.httpBody == nil, let stream = mutable.httpBodyStream {
            stream.open()
            var body = Data()
            var buf = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n > 0 { body.append(buf, count: n) }
            }
            stream.close()
            mutable.httpBody = body
        }
        MockURLProtocol.capturedRequests.append(mutable)
        let data = try! JSONSerialization.data(withJSONObject: MockURLProtocol.stubbedResponseJSON)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - SlackOAuthFlowTests

final class SlackOAuthFlowTests: XCTestCase {
    private var testService: String!
    private var keychain: KeychainHelper!
    private var mockSession: URLSession!

    override func setUpWithError() throws {
        testService = "co.replyai.test-oauth-\(UUID().uuidString)"
        keychain = KeychainHelper(service: testService)
        MockURLProtocol.stubbedResponseJSON = [:]
        MockURLProtocol.capturedRequests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }

    override func tearDownWithError() throws {
        keychain.delete(key: "slack-access-token")
    }

    // MARK: - testSlackOAuthOpensCorrectAuthURL

    /// Listener fires onReady → URLOpener receives the correct Slack auth URL.
    func testSlackOAuthOpensCorrectAuthURL() {
        let opener = MockURLOpener()
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "xoxb-stub"]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: opener,
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "testcode") }
        )
        flow.authorize(clientID: "my-client-id", clientSecret: "secret") { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard let url = opener.openedURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            XCTFail("URLOpener was not called with a valid URL")
            return
        }

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "slack.com")
        XCTAssertEqual(components.path, "/oauth/v2/authorize")

        let items = components.queryItems ?? []
        func param(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        XCTAssertEqual(param("client_id"), "my-client-id")
        XCTAssertEqual(param("redirect_uri"), "http://localhost:4242/callback")

        let scope = param("scope") ?? ""
        XCTAssertTrue(scope.contains("channels:read"), "scope must include channels:read, got: \(scope)")
        XCTAssertTrue(scope.contains("chat:write"), "scope must include chat:write, got: \(scope)")
    }

    // MARK: - testSlackOAuthExchangesCodeForToken

    /// Listener delivers code → URLSession POST contains correct code, client_id, client_secret.
    func testSlackOAuthExchangesCodeForToken() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "xoxb-exchange"]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "testcode") }
        )
        flow.authorize(clientID: "cid123", clientSecret: "sec456") { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
        guard let req = MockURLProtocol.capturedRequests.first else { return }

        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.url?.absoluteString.contains("oauth.v2.access") == true)

        let bodyString = req.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(bodyString.contains("code=testcode"), "body must contain code=testcode, got: \(bodyString)")
        XCTAssertTrue(bodyString.contains("client_id=cid123"), "body must contain client_id=cid123, got: \(bodyString)")
        XCTAssertTrue(bodyString.contains("client_secret=sec456"), "body must contain client_secret=sec456, got: \(bodyString)")
    }

    // MARK: - testSlackOAuthStoresTokenInKeychain

    /// Successful exchange stores the access_token in Keychain under "slack-access-token".
    func testSlackOAuthStoresTokenInKeychain() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "xoxb-stored-token"]

        let exp = expectation(description: "authorize completes")
        var result: Result<Void, OAuthError>?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code42") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .success = result else {
            XCTFail("Expected success, got \(String(describing: result))")
            return
        }
        // SlackTokenStore writes the token + workspace name as a JSON blob
        // under "slack-access-token". Decode via the store rather than reading
        // raw so the assertion survives schema tweaks.
        let stored = SlackTokenStore(keychain: keychain).get()
        XCTAssertEqual(stored?.token, "xoxb-stored-token")
    }

    // MARK: - testSlackOAuthFailedExchangeThrows

    /// `{"ok":false}` response propagates as OAuthError.tokenExchangeFailed.
    func testSlackOAuthFailedExchangeThrows() {
        MockURLProtocol.stubbedResponseJSON = ["ok": false, "error": "invalid_code"]

        let exp = expectation(description: "authorize completes")
        var result: Result<Void, OAuthError>?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "badcode") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(String(describing: result))")
            return
        }
        guard case .tokenExchangeFailed = error else {
            XCTFail("Expected tokenExchangeFailed, got \(error)")
            return
        }
    }

    // MARK: - testSlackOAuthListenerTimeoutPropagates

    /// Listener timeout propagates as OAuthError.timeout to the authorize completion.
    func testSlackOAuthListenerTimeoutPropagates() {
        let exp = expectation(description: "authorize completes")
        var result: Result<Void, OAuthError>?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(error: .timeout) }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(error, .timeout)
    }

    // MARK: - Workspace name extraction

    /// Slack's `oauth.v2.access` response embeds `team: {id, name}`.
    /// The workspace name should be plumbed into SlackTokenStore so the inbox
    /// can show "Connected: ACME". Without this test, a regression that drops
    /// `team.name` would only surface in the UI.
    func testSlackOAuthExtractsWorkspaceNameFromTeamObject() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            "team": ["id": "T123", "name": "ACME Corp"]
        ]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let stored = SlackTokenStore(keychain: keychain).get()
        XCTAssertEqual(stored?.workspaceName, "ACME Corp")
    }

    /// Slack's response without `team.name` falls back to empty string — never crash,
    /// never write garbage. Regression guard for a UI label that would otherwise
    /// say "Connected: <whatever .description> Slack returns".
    func testSlackOAuthMissingTeamNameDefaultsToEmpty() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            // Note: no `team` key at all.
        ]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let stored = SlackTokenStore(keychain: keychain).get()
        XCTAssertEqual(stored?.workspaceName, "")
        XCTAssertEqual(stored?.token, "xoxb-w")
    }

    /// `team` present but no `name` key — same fallback as missing `team`.
    func testSlackOAuthTeamObjectWithoutNameDefaultsToEmpty() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            "team": ["id": "T123"] // name missing
        ]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let stored = SlackTokenStore(keychain: keychain).get()
        XCTAssertEqual(stored?.workspaceName, "")
    }

    // MARK: - Token-exchange edge cases

    /// `{"ok":true}` response missing `access_token` must surface as
    /// tokenExchangeFailed — never silently store an empty token.
    func testSlackOAuthOKResponseWithoutAccessTokenFails() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true] // no access_token

        let exp = expectation(description: "authorize completes")
        var result: Result<Void, OAuthError>?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .failure(let error) = result, case .tokenExchangeFailed = error else {
            XCTFail("Expected tokenExchangeFailed, got \(String(describing: result))")
            return
        }
        // And keychain must NOT contain a token.
        XCTAssertNil(SlackTokenStore(keychain: keychain).get())
    }

    /// `{"ok":true,"access_token":""}` (present-but-empty token) is symmetric
    /// to the missing-key case — Slack should never reach this state, but a
    /// future Web API change or a proxy that strips secrets could produce
    /// the empty value, and silently storing it would result in every
    /// subsequent API call returning 401 and looking like a stale token.
    /// Pin the failure path so the empty-token short-circuit can't drift.
    func testSlackOAuthOKResponseWithEmptyAccessTokenFails() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": ""]

        let exp = expectation(description: "authorize completes")
        var result: Result<Void, OAuthError>?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") {
            result = $0
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .failure(let error) = result, case .tokenExchangeFailed = error else {
            XCTFail("Expected tokenExchangeFailed for empty access_token, got \(String(describing: result))")
            return
        }
        XCTAssertNil(SlackTokenStore(keychain: keychain).get(),
            "empty access_token must not be persisted to Keychain — every later API call would 401 and look like a stale token")
    }

    /// Auth URL must include redirect_uri matching the listener port (4242).
    /// Regression guard: changing the listener port without changing the URL
    /// would break Slack's redirect.
    func testAuthURLRedirectURIMatchesListenerPort() {
        let opener = MockURLOpener()
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "x"]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: opener,
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "c") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let items = URLComponents(url: opener.openedURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let redirect = items.first(where: { $0.name == "redirect_uri" })?.value
        XCTAssertEqual(redirect, "http://localhost:4242/callback")
    }

    /// Token-exchange POST body uses x-www-form-urlencoded content type.
    /// Slack's oauth.v2.access rejects JSON bodies — this guards against
    /// someone "modernizing" the POST to JSON and breaking the exchange.
    func testTokenExchangePOSTUsesFormURLEncodedContentType() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "x"]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "c") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        XCTAssertEqual(
            MockURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
    }

    /// Token-exchange body includes the redirect_uri so Slack can validate it
    /// against the registered app's redirect (must match exactly).
    func testTokenExchangeBodyIncludesRedirectURI() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "x"]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "c") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let body = MockURLProtocol.capturedRequests.first?.httpBody
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(
            body.contains("redirect_uri=http://localhost:4242/callback"),
            "POST body must include redirect_uri exactly matching the listener URL, got: \(body)"
        )
    }

    // MARK: - listenerFactory(port, timeout) production defaults

    /// `SlackOAuthFlow.authorize` constructs the listener via
    /// `listenerFactory(4242, 120)`. Both values are part of the OAuth UX
    /// contract: 4242 must match the redirect_uri registered in the Slack
    /// app (already pinned via redirect_uri tests), and 120s is the wait
    /// window the user has to complete the authorize-redirect dance before
    /// the listener gives up. Capture the values via the factory closure so
    /// a quiet edit to `listenerFactory(4242, 60)` (too short for users
    /// reading carefully) or `listenerFactory(4242, 600)` (listener sits
    /// open ten minutes if the user abandons) fails loudly here.
    func testAuthorizePassesProductionPortAndTimeoutToListenerFactory() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "x"]

        // Capture-by-reference: the factory writes the args into these vars.
        final class Capture: @unchecked Sendable {
            var port: UInt16?
            var timeout: TimeInterval?
        }
        let capture = Capture()

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { port, timeout in
                capture.port = port
                capture.timeout = timeout
                return MockOAuthCallbackListener(code: "c")
            }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        XCTAssertEqual(capture.port, 4242,
                       "listener port must remain 4242 to match the redirect_uri registered in the Slack app")
        XCTAssertEqual(capture.timeout, 120,
                       "listener timeout must remain 120s — shorter starves users who read carefully, longer leaves the loopback open after abandonment")
    }
}
