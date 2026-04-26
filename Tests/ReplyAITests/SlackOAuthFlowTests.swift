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
        MockURLProtocol.capturedRequests.append(request)
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
}
