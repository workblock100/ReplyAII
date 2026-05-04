import XCTest
@testable import ReplyAI

final class SlackChannelTests: XCTestCase {
    private var testService: String!

    override func setUpWithError() throws {
        testService = "co.replyai.test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        // SlackTokenStore writes one Keychain entry; clear it after each test.
        KeychainHelper(service: testService).delete(key: "slack-access-token")
    }

    // MARK: - Auth gate

    func testSlackChannelThrowsAuthDeniedWithNoToken() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        let channel = SlackChannel(tokenStore: store, http: NeverHTTP())

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // expected
        }
    }

    func testSlackChannelMessagesThrowsAuthDeniedWithNoToken() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        let channel = SlackChannel(tokenStore: store, http: NeverHTTP())

        do {
            _ = try await channel.messages(forThreadID: "C001", limit: 10)
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // expected
        }
    }

    // MARK: - Parsing — happy path

    func testRecentThreadsParsesConversationsList() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "C100", "name": "general", "is_channel": true, "unread_count": 3},
                {"id": "D200", "is_im": true, "user_display_name": "Maya Chen", "unread_count": 1}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 2)
        XCTAssertEqual(threads[0].name, "#general")
        XCTAssertEqual(threads[0].unread, 3)
        XCTAssertEqual(threads[1].name, "Maya Chen")
        XCTAssertEqual(threads[1].unread, 1)
        XCTAssertTrue(threads.allSatisfy { $0.channel == .slack })
        // The workspace name flows into preview so the row hints at the source.
        XCTAssertEqual(threads[0].preview, "Acme")
    }

    func testRecentThreadsThrowsWhenSlackReturnsErrorBody() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {"ok": false, "error": "invalid_auth", "channels": []}
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected networkError to be thrown")
        } catch ChannelError.networkError(let msg) {
            XCTAssertTrue(msg.contains("invalid_auth"), "unexpected error message: \(msg)")
        }
    }

    func testMessagesParsesConversationsHistory() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000020.0001", "user": "U999", "text": "second"},
                {"ts": "1700000010.0001", "user": "U999", "text": "first"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.count, 2)
        // Slack returns newest-first; we render oldest-first.
        XCTAssertEqual(msgs[0].text, "first")
        XCTAssertEqual(msgs[1].text, "second")
        XCTAssertTrue(msgs.allSatisfy { $0.from == .them })
    }

    func testSlackMessagesForThreadEmptyHistoryReturnsEmpty() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {"ok": true, "messages": []}
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertTrue(msgs.isEmpty)
    }

    func testSlackMessagesForThreadTimestampParsedCorrectly() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000000.0001", "user": "U999", "text": "hello"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.count, 1)
        let expected = Date(timeIntervalSince1970: 1700000000.0001)
        XCTAssertEqual(msgs[0].deliveredAt?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - Identity

    func testSlackChannelIdentifiesAsSlack() {
        let channel = SlackChannel()
        XCTAssertEqual(channel.channel, .slack)
        XCTAssertEqual(channel.displayName, "Slack")
    }

    // MARK: - REP-272: authorize() delegation to SlackOAuthFlow

    func testAuthorizeCallsOAuthFlowWithCorrectCredentials() async {
        let stub = StubSlackAuthorizing(result: .success(()))
        let channel = SlackChannel(
            tokenStore: SlackTokenStore(keychain: KeychainHelper(service: testService)),
            http: NeverHTTP(),
            oauthFlowFactory: { stub }
        )

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            channel.authorize(clientID: "client-abc", clientSecret: "secret-xyz") { _ in
                cont.resume()
            }
        }
        XCTAssertEqual(stub.observedClientID, "client-abc")
        XCTAssertEqual(stub.observedClientSecret, "secret-xyz")
    }

    func testAuthorizeSuccessCompletionCalled() async {
        let stub = StubSlackAuthorizing(result: .success(()))
        let channel = SlackChannel(
            tokenStore: SlackTokenStore(keychain: KeychainHelper(service: testService)),
            http: NeverHTTP(),
            oauthFlowFactory: { stub }
        )

        let result: Result<Void, OAuthError> = await withCheckedContinuation { cont in
            channel.authorize(clientID: "id", clientSecret: "secret") { cont.resume(returning: $0) }
        }
        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }
    }

    func testAuthorizeFailureCompletionCalled() async {
        let stub = StubSlackAuthorizing(
            result: .failure(.tokenExchangeFailed("nope"))
        )
        let channel = SlackChannel(
            tokenStore: SlackTokenStore(keychain: KeychainHelper(service: testService)),
            http: NeverHTTP(),
            oauthFlowFactory: { stub }
        )

        let result: Result<Void, OAuthError> = await withCheckedContinuation { cont in
            channel.authorize(clientID: "id", clientSecret: "secret") { cont.resume(returning: $0) }
        }
        guard case .failure(.tokenExchangeFailed(let msg)) = result else {
            return XCTFail("Expected failure(.tokenExchangeFailed), got \(result)")
        }
        XCTAssertEqual(msg, "nope")
    }

    // MARK: - send(text:toThreadID:) — auth gate + ack handling

    func testSendThrowsAuthDeniedWithNoToken() async {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        let channel = SlackChannel(tokenStore: store, http: NeverHTTP())

        do {
            try await channel.send(text: "hello", toThreadID: "C100")
            XCTFail("Expected authorizationDenied to be thrown")
        } catch ChannelError.authorizationDenied {
            // Expected
        } catch {
            XCTFail("Expected authorizationDenied, got \(error)")
        }
    }

    func testSendSucceedsWhenAckOk() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-abc", workspaceName: "Acme")
        let body = #"{ "ok": true }"#.data(using: .utf8)!
        let recorder = RecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        try await channel.send(text: "hi", toThreadID: "C200")

        XCTAssertEqual(recorder.lastPostEndpoint, "chat.postMessage")
        XCTAssertEqual(recorder.lastPostJSON?["channel"] as? String, "C200")
        XCTAssertEqual(recorder.lastPostJSON?["text"] as? String, "hi")
    }

    func testSendThrowsNetworkErrorWithSlackErrorString() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-abc", workspaceName: "Acme")
        let body = #"{ "ok": false, "error": "channel_not_found" }"#.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        do {
            try await channel.send(text: "hi", toThreadID: "C-bogus")
            XCTFail("Expected networkError to be thrown")
        } catch ChannelError.networkError(let msg) {
            XCTAssertEqual(msg, "channel_not_found",
                "send must surface Slack's error string when ok:false")
        } catch {
            XCTFail("Expected networkError, got \(error)")
        }
    }

    func testSendThrowsNetworkErrorWithFallbackWhenErrorMissing() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-abc", workspaceName: "Acme")
        // Slack ack with ok:false but no error string.
        let body = #"{ "ok": false }"#.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        do {
            try await channel.send(text: "hi", toThreadID: "C200")
            XCTFail("Expected networkError to be thrown")
        } catch ChannelError.networkError(let msg) {
            XCTAssertFalse(msg.isEmpty,
                "fallback message must not be empty when Slack omits error")
        } catch {
            XCTFail("Expected networkError, got \(error)")
        }
    }
}

// MARK: - Test doubles

/// HTTP client that always returns the same canned payload from both verbs.
private struct StubHTTP: SlackHTTPClient {
    let payload: Data
    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data {
        payload
    }
    func post(endpoint: String, token: String, json: [String: Any]) async throws -> Data {
        payload
    }
}

/// HTTP client that records the last POST it received and replays a canned
/// payload. Used by send() tests to verify the request shape.
private final class RecordingHTTP: SlackHTTPClient, @unchecked Sendable {
    let payload: Data
    private(set) var lastPostEndpoint: String?
    private(set) var lastPostJSON: [String: Any]?
    private let lock = NSLock()

    init(payload: Data) { self.payload = payload }

    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data {
        payload
    }
    func post(endpoint: String, token: String, json: [String: Any]) async throws -> Data {
        lock.lock()
        lastPostEndpoint = endpoint
        lastPostJSON = json
        lock.unlock()
        return payload
    }
}

/// HTTP client that fails the test if it's ever called — used for the auth-gate
/// paths that should refuse to make a request without a token.
private struct NeverHTTP: SlackHTTPClient {
    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data {
        XCTFail("HTTP must not be invoked when no token is stored")
        throw ChannelError.authorizationDenied
    }
    func post(endpoint: String, token: String, json: [String: Any]) async throws -> Data {
        XCTFail("HTTP must not be invoked when no token is stored")
        throw ChannelError.authorizationDenied
    }
}

/// Records `authorize` arguments and replays a canned `Result` so the
/// SlackChannel.authorize delegation can be unit-tested without binding
/// a real localhost OAuth listener.
private final class StubSlackAuthorizing: SlackAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _observedClientID: String?
    private var _observedClientSecret: String?
    private let result: Result<Void, OAuthError>

    var observedClientID: String? {
        lock.lock(); defer { lock.unlock() }
        return _observedClientID
    }
    var observedClientSecret: String? {
        lock.lock(); defer { lock.unlock() }
        return _observedClientSecret
    }

    init(result: Result<Void, OAuthError>) {
        self.result = result
    }

    func authorize(
        clientID: String,
        clientSecret: String,
        completion: @escaping (Result<Void, OAuthError>) -> Void
    ) {
        lock.lock()
        _observedClientID = clientID
        _observedClientSecret = clientSecret
        lock.unlock()
        completion(result)
    }
}
