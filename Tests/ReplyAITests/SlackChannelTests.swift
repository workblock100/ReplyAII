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

    // MARK: - Identity

    func testSlackChannelIdentifiesAsSlack() {
        let channel = SlackChannel()
        XCTAssertEqual(channel.channel, .slack)
        XCTAssertEqual(channel.displayName, "Slack")
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
