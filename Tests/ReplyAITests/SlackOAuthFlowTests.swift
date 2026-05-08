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
        keychain.delete(key: SlackTokenStore.storageKey)
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

        XCTAssertEqual(param(SlackOAuthFlow.FormField.clientID), "my-client-id")
        XCTAssertEqual(param(SlackOAuthFlow.FormField.redirectURI), SlackOAuthFlow.redirectURI)

        let scope = param(SlackOAuthFlow.FormField.scope) ?? ""
        XCTAssertTrue(scope.contains("channels:read"), "scope must include channels:read, got: \(scope)")
        XCTAssertTrue(scope.contains("chat:write"), "scope must include chat:write, got: \(scope)")
    }

    /// Exact-literal pin on the OAuth scope string. The existing
    /// `testSlackOAuthOpensCorrectAuthURL` test only asserts that the
    /// scope string `contains` the two expected scopes — it would still
    /// pass if a refactor added `groups:read,im:read,im:write,…` to the
    /// list. Pin the EXACT comma-separated value so a widening of the
    /// scope set (which forces re-consent for every existing user, and
    /// invalidates their currently stored token's capabilities) shows
    /// up here as a deliberate test change rather than a silent release.
    func testAuthURLScopeIsExactCommaSeparatedSet() {
        let opener = MockURLOpener()
        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: opener,
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "scope-pin-code") }
        )
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "xoxb-pin"]
        flow.authorize(clientID: "id", clientSecret: "sec") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3)

        guard let url = opener.openedURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            XCTFail("URLOpener was not called with a valid URL")
            return
        }
        let items = components.queryItems ?? []
        let scope = items.first(where: { $0.name == SlackOAuthFlow.FormField.scope })?.value ?? ""
        XCTAssertEqual(scope, SlackOAuthFlow.scope,
            "auth URL scope must route through SlackOAuthFlow.scope — drift means the constant became dead code while the URLQueryItem froze a stale literal")
        // Pin the literal value of the constant itself. The routing test
        // above only proves the auth URL goes through Self.scope; this
        // line proves the constant has the right ordered string. Both
        // matter — the URL could correctly route through a constant whose
        // value silently drifted to e.g. "channels:read,chat:write,users:read",
        // which would re-consent every existing user.
        XCTAssertEqual(SlackOAuthFlow.scope, "channels:read,chat:write",
            "SlackOAuthFlow.scope drift re-consents every existing user — Slack re-issues consent prompts on any scope-string change, including reorders")
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

    /// `team: { name: "" }` — Slack returns the key but the value is empty.
    /// The `as? String ?? ""` fallback in SlackOAuthFlow flattens this to
    /// an empty workspaceName, identical to "key absent". Per the
    /// "present-but-empty strings" gotcha in AGENTS.md, the safe behavior
    /// here is to land the same "" value as the missing-key path so
    /// downstream UI ("Connected: <name>") fails to a single empty-string
    /// state rather than two divergent ones. Pin the surprising-but-safe
    /// behavior so a future "Some(\"\") → nil filter" refactor surfaces as
    /// a deliberate change rather than silent drift.
    func testSlackOAuthTeamNameSomeEmptyDefaultsToEmpty() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            "team": ["id": "T123", "name": ""] // present-but-empty
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
        XCTAssertEqual(stored?.workspaceName, "",
            "team.name = \"\" must round-trip to workspaceName = \"\" — same as missing team or missing name; consolidating Some(\"\") with nil here would change downstream UI without a deliberate refactor")
        XCTAssertEqual(stored?.token, "xoxb-w",
            "empty team.name must NOT block token storage — only an empty access_token blocks; team.name is informational")
    }

    /// `team: NSNull()` — JSON `null` for the whole team key. The chained
    /// `(json[ResponseKey.team] as? [String: Any])?[…]` cast fails on
    /// NSNull (it is not a [String: Any]) and the optional-chain returns
    /// nil, so the `?? ""` fallback fires. Same shape as missing key.
    /// Pinning the JSON-null path separately from the missing-key path
    /// because NSNull is a distinct value JSONSerialization can produce.
    func testSlackOAuthTeamJSONNullDefaultsToEmpty() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            "team": NSNull() // JSON null
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

    /// `team: "ACME Corp"` (a JSON string instead of the expected
    /// `{ id, name }` object). Slack would never send this shape today,
    /// but a future Web API revision or a malformed proxy response could
    /// produce it. The `as? [String: Any]` cast fails, the chain returns
    /// nil, the `?? ""` fallback fires. Pin the wrong-type-tolerance
    /// behavior so a "stricter parsing" refactor doesn't accidentally
    /// hard-fail token exchange on what is otherwise a successful auth.
    func testSlackOAuthTeamWrongTypeDefaultsToEmpty() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            "team": "ACME Corp" // wrong shape — string, not dict
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
        XCTAssertEqual(stored?.workspaceName, "",
            "team-as-string must not parse as a dict; the wrong-type cast fails and workspaceName falls back to \"\"")
        XCTAssertEqual(stored?.token, "xoxb-w",
            "wrong-type team must not block successful token persistence — Slack's auth is informational about the workspace name")
    }

    /// `team: { id: "T123", name: NSNull() }` — JSON null for the name
    /// field specifically. The `as? String` cast against NSNull fails
    /// (NSNull is not a String), the chain returns nil, and the `?? ""`
    /// fallback fires. Different from the empty-string case (Some("")
    /// hits the cast successfully and produces ""); same observable
    /// outcome, different code path.
    func testSlackOAuthTeamNameJSONNullDefaultsToEmpty() {
        MockURLProtocol.stubbedResponseJSON = [
            "ok": true,
            "access_token": "xoxb-w",
            "team": ["id": "T123", "name": NSNull()] // JSON null name
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

    /// Code/clientID/clientSecret are percent-encoded in the form body so
    /// special characters can't corrupt the `application/x-www-form-urlencoded`
    /// payload. Slack's actual codes/IDs are alphanumeric so the encoding is
    /// usually a no-op, but a code containing `&`, `=`, `+`, or `%` would
    /// otherwise split the form body and silently send wrong values.
    func testSlackOAuthCodeWithSpecialCharsIsPercentEncoded() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": "xoxb-after-special-chars"]

        let exp = expectation(description: "authorize completes")
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            // Slack would never send this, but a faulty proxy or test harness might:
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "ab&cd=ef+gh") }
        )
        flow.authorize(clientID: "id&with=amp", clientSecret: "sec+plus%pct") { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        let bodyString = MockURLProtocol.capturedRequests.first?.httpBody
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // Verify each value is percent-encoded — `&` and `=` MUST be escaped
        // because they're form-body separators / key-value delimiters.
        XCTAssertFalse(bodyString.contains("code=ab&cd=ef+gh"),
            "raw `&` in code value would split the form body, corrupting subsequent fields")
        XCTAssertTrue(bodyString.contains("code=ab%26cd%3Def%2Bgh"),
            "code value must be percent-encoded; got body: \(bodyString)")
        XCTAssertTrue(bodyString.contains("client_id=id%26with%3Damp"),
            "client_id must be percent-encoded; got body: \(bodyString)")
        XCTAssertTrue(bodyString.contains("client_secret=sec%2Bplus%25pct"),
            "client_secret must be percent-encoded; got body: \(bodyString)")
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
        let redirect = items.first(where: { $0.name == SlackOAuthFlow.FormField.redirectURI })?.value
        XCTAssertEqual(redirect, SlackOAuthFlow.redirectURI)
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
            MockURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: SlackOAuthFlow.contentTypeHeaderField),
            SlackOAuthFlow.formURLEncodedContentType
        )
    }

    /// The token-exchange POST URL must be exactly
    /// `https://slack.com/api/oauth.v2.access`. Existing siblings only
    /// substring-check `oauth.v2.access`, so a refactor that "modernized"
    /// the host to `https://api.slack.com/oauth.v2.access` (or added a
    /// `/v2/` prefix, etc.) would slip past — and Slack's API surface
    /// answers different things at different hosts. Pin the exact URL.
    func testTokenExchangeURLIsExactSlackAPIEndpoint() {
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
            MockURLProtocol.capturedRequests.first?.url?.absoluteString,
            SlackOAuthFlow.tokenExchangeURL,
            "token-exchange URL must route through SlackOAuthFlow.tokenExchangeURL — drift means the constant became dead code while the call site froze a stale literal"
        )
        // Pin the literal value of the constant itself.
        XCTAssertEqual(SlackOAuthFlow.tokenExchangeURL,
                       "https://slack.com/api/oauth.v2.access",
            "Slack's API surface answers different things at different hosts — drift here surfaces as a generic tokenExchangeFailed with no UI feedback identifying the host as the cause")
    }

    /// Pin the literal value of `SlackOAuthFlow.authorizationURL`.
    /// Drift to e.g. `https://api.slack.com/oauth/v2/authorize` is a
    /// Slack-shaped but wrong host that silently breaks the entire flow.
    func testAuthorizationURLLiteralIsSlackOAuthV2Authorize() {
        XCTAssertEqual(SlackOAuthFlow.authorizationURL,
                       "https://slack.com/oauth/v2/authorize",
            "SlackOAuthFlow.authorizationURL drift breaks the OAuth flow at the auth-URL leg — Slack-shaped but wrong hosts silently 404 or 401")
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

    /// `OAuthError.tokenExchangeFailed(msg).errorDescription` is what users
    /// see verbatim in Settings → Channels when Slack returns ok:true but
    /// no access_token. The msg literal is constructed inside
    /// `SlackOAuthFlow.exchangeCode` and surfaced via the LocalizedError
    /// bridge ("Slack rejected the connection: <msg>"). Pin the exact
    /// string so a refactor that "improves" the wording (e.g. dropping
    /// the protocol details) lands as a deliberate code-review change
    /// rather than a silent UX regression.
    func testTokenExchangeMissingAccessTokenSurfacesPinnedMessage() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true] // no access_token

        let exp = expectation(description: "authorize completes")
        var captured: OAuthError?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { result in
            if case .failure(let err) = result { captured = err }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .tokenExchangeFailed(let msg) = captured else {
            XCTFail("Expected tokenExchangeFailed, got \(String(describing: captured))")
            return
        }
        XCTAssertEqual(msg, "response missing ok=true or access_token",
            "the inner msg literal is part of the user-visible OAuthError.errorDescription — pin against silent rephrasing")
        XCTAssertEqual(captured?.errorDescription,
            "Slack rejected the connection: response missing ok=true or access_token",
            "full LocalizedError surface must be the exact string the Settings banner renders")
    }

    /// Symmetric pin for the `{"ok":true,"access_token":""}` branch.
    /// The empty-token short-circuit lives in the same `guard` block as
    /// the missing-key path and produces the same `tokenExchangeFailed`
    /// message — guaranteeing a future refactor that splits the two
    /// branches keeps both arms surfacing the same user-visible copy.
    func testTokenExchangeEmptyAccessTokenSurfacesPinnedMessage() {
        MockURLProtocol.stubbedResponseJSON = ["ok": true, "access_token": ""]

        let exp = expectation(description: "authorize completes")
        var captured: OAuthError?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { result in
            if case .failure(let err) = result { captured = err }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .tokenExchangeFailed(let msg) = captured else {
            XCTFail("Expected tokenExchangeFailed, got \(String(describing: captured))")
            return
        }
        XCTAssertEqual(msg, "response missing ok=true or access_token",
            "the empty-token branch must produce the SAME message as the missing-key branch — splitting them risks divergent UX copy")
    }

    /// `{"ok":false}` (Slack rejects the code outright) carries no inner
    /// message string from the source — `exchangeCode` falls into the
    /// same guard as the missing-access_token case and produces
    /// `tokenExchangeFailed("response missing ok=true or access_token")`.
    /// That's intentional but easy to miss: the implementation reuses one
    /// guard for three distinct failure modes (no ok, ok:false, no
    /// token). Pin so a future refactor that splits the guards keeps
    /// the user-visible copy aligned.
    func testTokenExchangeOkFalseSurfacesSameMessage() {
        MockURLProtocol.stubbedResponseJSON = ["ok": false]

        let exp = expectation(description: "authorize completes")
        var captured: OAuthError?
        let flow = SlackOAuthFlow(
            keychain: keychain,
            urlOpener: MockURLOpener(),
            session: mockSession,
            listenerFactory: { _, _ in MockOAuthCallbackListener(code: "code") }
        )
        flow.authorize(clientID: "id", clientSecret: "sec") { result in
            if case .failure(let err) = result { captured = err }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)

        guard case .tokenExchangeFailed(let msg) = captured else {
            XCTFail("Expected tokenExchangeFailed, got \(String(describing: captured))")
            return
        }
        XCTAssertEqual(msg, "response missing ok=true or access_token",
            "ok:false reuses the same guard as missing-token; splitting the message would diverge copy across three failure modes")
    }

    // MARK: - redirectURI single-source-of-truth pin

    /// `SlackOAuthFlow.redirectURI` is the registered redirect URI on the
    /// Slack app side. Drift on either the auth-URL query-item leg or the
    /// token-exchange POST body leg would surface as Slack's opaque
    /// `redirect_uri_mismatch` error with no UI feedback. The two existing
    /// pins (the auth-URL `redirect_uri` query-item assertion and the
    /// token-exchange POST-body `redirect_uri=...` assertion in this file)
    /// verify each leg in isolation; this pin ensures both legs route
    /// through the *same* constant so a future "let's bump to a different
    /// path" lands once, not in two parallel edits that could silently
    /// desync.
    func testRedirectURIIsSingleSourceOfTruth() {
        XCTAssertEqual(SlackOAuthFlow.redirectURI,
                       "http://localhost:4242/callback",
                       "redirectURI drift breaks Slack OAuth with redirect_uri_mismatch — pin is the only line in the codebase that defines this URL")

        // Sanity: the port suffix matches the LocalhostOAuthListener
        // default port. If someone bumps the listener port without
        // updating this string (or vice versa), Slack will accept the
        // auth-URL leg but the listener won't be bound on the port the
        // browser actually hits — the OAuth flow hangs until the 120 s
        // listener timeout. Pin the cross-module invariant.
        XCTAssertTrue(SlackOAuthFlow.redirectURI.contains(":\(LocalhostOAuthListener.defaultPort)/"),
                      "redirectURI port suffix must match LocalhostOAuthListener.defaultPort — drift desyncs the auth URL the user is sent to from the listener actually bound for the callback")
    }

    // MARK: - Hoisted-constant pins (FormField + ResponseKey)
    //
    // The OAuth 2 form-body field names + response JSON keys used to be
    // raw string literals at every call site (auth URL leg + token-exchange
    // leg + response parsing). Drift between sites surfaces as
    // `redirect_uri_mismatch` (auth/exchange leg disagree on field name) or
    // a generic "response missing ok=true or access_token" (response key
    // typo silently downgrades every successful exchange). Hoisted to
    // `SlackOAuthFlow.FormField` and `.ResponseKey`.

    func testFormFieldNameLiteralsAreFrozen() {
        XCTAssertEqual(SlackOAuthFlow.FormField.clientID,     "client_id")
        XCTAssertEqual(SlackOAuthFlow.FormField.clientSecret, "client_secret")
        XCTAssertEqual(SlackOAuthFlow.FormField.scope,        "scope")
        XCTAssertEqual(SlackOAuthFlow.FormField.redirectURI,  "redirect_uri")
        XCTAssertEqual(SlackOAuthFlow.FormField.code,         "code")
    }

    func testResponseKeyLiteralsAreFrozen() {
        XCTAssertEqual(SlackOAuthFlow.ResponseKey.ok,          "ok")
        XCTAssertEqual(SlackOAuthFlow.ResponseKey.accessToken, "access_token")
        XCTAssertEqual(SlackOAuthFlow.ResponseKey.team,        "team")
        XCTAssertEqual(SlackOAuthFlow.ResponseKey.teamName,    "name")
    }

    // MARK: - Token-exchange request-shape pins (REP-hoist 2026-05-07)

    /// HTTP method for the token-exchange POST. Slack's `oauth.v2.access`
    /// rejects `GET` with `method_not_allowed` which surfaces as a
    /// generic `tokenExchangeFailed`. Pin the literal so a refactor
    /// can't quietly switch verbs.
    func testTokenExchangeHTTPMethodIsPOST() {
        XCTAssertEqual(SlackOAuthFlow.tokenExchangeHTTPMethod, "POST",
            "tokenExchangeHTTPMethod must be POST — `oauth.v2.access` rejects GET with `method_not_allowed`")
    }

    /// Content-Type for the token-exchange POST. The body is
    /// form-encoded; drift to `application/json` would have Slack
    /// parse the form bytes as JSON and return `invalid_form_data`.
    func testFormURLEncodedContentTypeIsFrozen() {
        XCTAssertEqual(SlackOAuthFlow.formURLEncodedContentType,
                       "application/x-www-form-urlencoded",
            "formURLEncodedContentType drift to e.g. application/json would have Slack parse the form bytes as JSON and fail with invalid_form_data")
    }

    /// Header field name for setting the request Content-Type.
    func testContentTypeHeaderFieldIsCanonicalCapitalization() {
        XCTAssertEqual(SlackOAuthFlow.contentTypeHeaderField, "Content-Type",
            "contentTypeHeaderField pinned to canonical capitalization so request shape matches AGENTS.md curl-based debugging artifacts")
    }

    // MARK: - TokenExchangeFailureReason freeze + invariants

    /// Pin the three failure-reason strings. Each is the only triage
    /// signal a user (or support engineer) has when the OAuth handshake
    /// breaks — the reason is concatenated with
    /// `tokenExchangeFailedPrefix` ("Slack rejected the connection: ")
    /// in the user toast. Drift collapses two failure modes into the
    /// same toast.
    func testTokenExchangeFailureReasonsAreFrozen() {
        XCTAssertEqual(SlackOAuthFlow.TokenExchangeFailureReason.invalidEndpointURL,
                       "invalid endpoint URL")
        XCTAssertEqual(SlackOAuthFlow.TokenExchangeFailureReason.emptyResponse,
                       "empty response")
        XCTAssertEqual(SlackOAuthFlow.TokenExchangeFailureReason.missingOkOrAccessToken,
                       "response missing ok=true or access_token")
    }

    /// Pin the partition invariant: the three reasons are pairwise
    /// distinct AND non-empty. Collision merges two failure modes
    /// into one toast (loses triage signal); an empty reason yields
    /// "Slack rejected the connection: " with a trailing-space dead-
    /// end toast that looks like a UI bug.
    func testTokenExchangeFailureReasonsArePairwiseDistinctAndNonEmpty() {
        let all = [
            SlackOAuthFlow.TokenExchangeFailureReason.invalidEndpointURL,
            SlackOAuthFlow.TokenExchangeFailureReason.emptyResponse,
            SlackOAuthFlow.TokenExchangeFailureReason.missingOkOrAccessToken,
        ]
        XCTAssertEqual(Set(all).count, all.count,
            "failure-reason constants must be pairwise distinct — collision merges two triage signals into one")
        for r in all {
            XCTAssertFalse(r.isEmpty,
                "failure reason must be non-empty — empty produces a trailing-space dead-end toast")
        }
    }

    // MARK: - Cross-file equality pins (OAuth + HTTP literals)

    /// `LocalhostOAuthListener.codeQueryParameterName` and
    /// `SlackOAuthFlow.FormField.code` are both `"code"` and refer to
    /// the same OAuth authorization-code identifier — the listener
    /// extracts it from the callback URL's query string, the flow
    /// posts it back as a form field on the token-exchange request.
    /// Drift between them would silently break the OAuth handshake
    /// at one of the two ends (listener captures `code` but flow
    /// looks for a different name when building the form body, or
    /// vice versa). The OAuth spec uses one literal in both places,
    /// so the two constants must agree. Pin asserts the cross-file
    /// equality so a future rename of either side surfaces here
    /// rather than at a production OAuth callback.
    func testListenerCodeQueryParameterEqualsFlowFormFieldCode() {
        XCTAssertEqual(LocalhostOAuthListener.codeQueryParameterName,
                       SlackOAuthFlow.FormField.code,
            "LocalhostOAuthListener.codeQueryParameterName must equal SlackOAuthFlow.FormField.code — both name the OAuth `code` parameter; drift breaks the handshake at the listener-extract or flow-rebuild step")
    }

    /// `URLSessionSlackClient.postHTTPMethod` and
    /// `SlackOAuthFlow.tokenExchangeHTTPMethod` are both `"POST"`
    /// and refer to the same HTTP verb. Drift would mean one Slack
    /// API endpoint receives a different method than the other,
    /// even though both endpoints (chat.postMessage and
    /// oauth.v2.access) require POST. Cross-pin so a future
    /// "consolidate the HTTP method literal" refactor is the only
    /// way the two stay in sync.
    func testHTTPClientPostMethodEqualsFlowTokenExchangeMethod() {
        XCTAssertEqual(URLSessionSlackClient.postHTTPMethod,
                       SlackOAuthFlow.tokenExchangeHTTPMethod,
            "URLSessionSlackClient.postHTTPMethod must equal SlackOAuthFlow.tokenExchangeHTTPMethod — both name the same HTTP POST verb; drift would silently downgrade either path to a wrong method")
    }

    /// `URLSessionSlackClient.Header.contentTypeField` and
    /// `SlackOAuthFlow.contentTypeHeaderField` are both
    /// `"Content-Type"` and refer to the same standard HTTP header
    /// name. The two paths use different content-type *values*
    /// (`application/json` for chat.postMessage, form-urlencoded
    /// for oauth.v2.access) but the *header name* is identical.
    /// Drift would silently break body negotiation on either path.
    func testHTTPClientContentTypeHeaderEqualsFlowContentTypeHeader() {
        XCTAssertEqual(URLSessionSlackClient.Header.contentTypeField,
                       SlackOAuthFlow.contentTypeHeaderField,
            "URLSessionSlackClient.Header.contentTypeField must equal SlackOAuthFlow.contentTypeHeaderField — both name the standard `Content-Type` HTTP header; drift breaks body negotiation on either Slack request path")
    }

    // MARK: - Token-exchange body shape pins

    /// Pin that `redirect_uri` is sent VERBATIM in the token-exchange
    /// body, NOT percent-encoded. The other three fields (`code`,
    /// `client_id`, `client_secret`) all route through the
    /// RFC-3986-strict `escape()` helper, but `redirect_uri` is
    /// concatenated raw because Slack's `redirect_uri_mismatch` check
    /// compares the token-exchange leg's value against the literal
    /// registered in the app config — drift to a percent-encoded form
    /// (`http%3A%2F%2Flocalhost%3A4242%2Fcallback`) silently fails the
    /// exchange even though the *decoded* values are identical. A
    /// future refactor that DRY'd all four fields through the same
    /// `escape()` helper would re-introduce the bug. Pin so the
    /// asymmetry is intentional and visible.
    func testTokenExchangeBodyDoesNotPercentEncodeRedirectURI() {
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
            "redirect_uri must appear verbatim with raw `:` and `/` — drift toward percent-encoding fails Slack's redirect_uri_mismatch check; got: \(body)"
        )
        XCTAssertFalse(
            body.contains("redirect_uri=http%3A"),
            "redirect_uri MUST NOT be percent-encoded (`http%3A%2F%2F…`) — Slack compares the literal against the registered URI; drift here surfaces as a generic tokenExchangeFailed with no UI hint pointing at encoding")
        XCTAssertFalse(
            body.contains("%2Fcallback"),
            "the trailing `/callback` must remain a raw forward slash, not `%2Fcallback` — pinning rules out a partial-escape regression from a future helper that touched the path slash")
    }

    /// Pin the form-body field ORDER. `bodyParts` builds `[code,
    /// client_id, client_secret, redirect_uri]` in exactly that
    /// sequence and joins on `&`. Slack accepts any order, but the
    /// curl-based debugging artifacts in AGENTS.md (and the captured
    /// request fixtures in this test file's MockURLProtocol) all
    /// assume this byte sequence. A future refactor to a
    /// `[String: String]` dict would yield a non-deterministic order
    /// (or alphabetical: `client_id, client_secret, code, redirect_uri`),
    /// changing every captured request byte-for-byte. Pin the index
    /// of each `field=` substring so the swap surfaces here, not as
    /// every-test-fixture drifting in lockstep.
    func testTokenExchangeBodyKeyOrderIsCodeClientIDClientSecretRedirectURI() {
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

        guard
            let codeRange         = body.range(of: "code="),
            let clientIDRange     = body.range(of: "client_id="),
            let clientSecretRange = body.range(of: "client_secret="),
            let redirectURIRange  = body.range(of: "redirect_uri=")
        else {
            XCTFail("body missing one of the four expected fields: \(body)")
            return
        }
        XCTAssertLessThan(codeRange.lowerBound, clientIDRange.lowerBound,
            "field order must be code → client_id → client_secret → redirect_uri; got: \(body)")
        XCTAssertLessThan(clientIDRange.lowerBound, clientSecretRange.lowerBound,
            "client_id must precede client_secret; got: \(body)")
        XCTAssertLessThan(clientSecretRange.lowerBound, redirectURIRange.lowerBound,
            "client_secret must precede redirect_uri; got: \(body)")
    }

    /// Pin the form-body field separator. `bodyParts.joined(separator: "&")`
    /// — `&` is the only correct delimiter for
    /// `application/x-www-form-urlencoded`. Drift to `;` (a legacy HTML5
    /// alternative) or `,` corrupts the body on Slack's side without a
    /// clear UI signal — Slack returns `invalid_form_data` which
    /// surfaces as a generic `tokenExchangeFailed`. Pin both the
    /// expected count of `&` separators and the negative `;` case.
    func testTokenExchangeBodySeparatorIsAmpersand() {
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

        // Four fields → exactly three `&` separators (none of `id`,
        // `sec`, `c` contain `&` after the unreserved-only escape).
        let ampersandCount = body.filter { $0 == "&" }.count
        XCTAssertEqual(ampersandCount, 3,
            "exactly 3 `&` separators expected for 4 form fields; got count=\(ampersandCount), body=\(body)")
        XCTAssertFalse(body.contains(";"),
            "form body must NOT use `;` as a separator — drift to RFC 1866 HTML5-style separator silently fails Slack's invalid_form_data check; got: \(body)")
    }
}
