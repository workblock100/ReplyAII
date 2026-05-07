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

    // MARK: - Limit clamping (Slack rejects > 200, < 1)

    func testRecentThreadsClampsLimitAbove200ToSlackMaximum() async throws {
        // Slack's conversations.list rejects limit > 200 with invalid_arguments.
        // Without the clamp the user would see a confusing API error for what
        // looks like a sane request.
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "channels": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.recentThreads(limit: 1000)

        XCTAssertEqual(recorder.lastGetParams?["limit"], "200",
                       "limit > 200 must be clamped to Slack's documented max")
    }

    func testRecentThreadsClampsZeroLimitToOne() async throws {
        // limit < 1 makes no semantic sense; clamping to 1 keeps the request
        // valid rather than letting Slack reject "limit=0".
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "channels": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.recentThreads(limit: 0)

        XCTAssertEqual(recorder.lastGetParams?["limit"], "1",
                       "limit < 1 must be clamped to 1")
    }

    func testMessagesClampsLimitAbove200ToSlackMaximum() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "messages": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.messages(forThreadID: "C100", limit: 5000)

        XCTAssertEqual(recorder.lastGetParams?["limit"], "200")
        XCTAssertEqual(recorder.lastGetParams?["channel"], "C100")
    }

    /// Symmetric counterpart to `testRecentThreadsClampsZeroLimitToOne`. The
    /// `messages(forThreadID:limit:)` helper applies the same
    /// `min(max(limit, 1), 200)` clamp before forwarding to Slack. Pin the
    /// lower-bound branch so a future refactor that "simplifies" the clamp
    /// (e.g. dropping the `max(limit, 1)` half because callers always pass a
    /// positive value today) fails loudly here instead of letting Slack
    /// reject `limit=0` with `invalid_arguments` in the wild.
    func testMessagesClampsZeroLimitToOne() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "messages": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.messages(forThreadID: "C100", limit: 0)

        XCTAssertEqual(recorder.lastGetParams?["limit"], "1",
                       "limit < 1 must be clamped to 1 — Slack's conversations.history rejects limit=0")
        XCTAssertEqual(recorder.lastGetParams?["channel"], "C100",
                       "channel param must round-trip even when the limit is clamped")
    }

    /// Negative limits are the other side of the lower-bound clamp. A signed
    /// `Int` from a stale caller (e.g. `-1` as a sentinel for "unlimited")
    /// must still resolve to a Slack-legal request rather than serializing
    /// to `"limit=-1"` and 400-ing on Slack's side.
    func testMessagesClampsNegativeLimitToOne() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "messages": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.messages(forThreadID: "C100", limit: -1)

        XCTAssertEqual(recorder.lastGetParams?["limit"], "1",
                       "negative limit must be clamped to 1, not forwarded as -1")
    }

    /// `unread_count` is optional in Slack's `conversations.list` payload —
    /// channels without unreads omit the key entirely. The parser must
    /// surface that as `MessageThread.unread = 0`, not crash on a missing
    /// key. Existing happy-path tests always include `unread_count`, so
    /// the `?? 0` fallback isn't directly exercised.
    func testRecentThreadsMissingUnreadCountDefaultsToZero() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "C100", "name": "general", "is_channel": true}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].unread, 0,
            "missing unread_count key must default to 0 — drift to nil/-1 would render as a phantom badge in the sidebar")
    }

    /// Explicit JSON `null` for unread_count must also default to 0. This
    /// is a separate code path from "missing key" — the JSONDecoder
    /// produces `Optional<Int>.none` for both, but a future refactor that
    /// switches to a non-optional decode with a custom strategy could
    /// regress one without the other. Pin both.
    func testRecentThreadsNullUnreadCountDefaultsToZero() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "C100", "name": "general", "is_channel": true, "unread_count": null}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads[0].unread, 0,
            "explicit null unread_count must default to 0 — same as missing-key")
    }

    // MARK: - conversations.list `types` + `exclude_archived` contract

    /// The `types` parameter on `conversations.list` is what gates which Slack
    /// surfaces ReplyAI sees. Drop `im` and DMs disappear from the inbox; drop
    /// `mpim` and group DMs go silent; drop `private_channel` and the user
    /// loses every privately-shared channel. Pin the exact value so a quiet
    /// edit (e.g. trimming to "im,public_channel") fails loudly here instead
    /// of silently shrinking inbox coverage.

    func testRecentThreadsTypesParamIncludesAllFourSlackSurfaces() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "channels": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.recentThreads(limit: 50)

        XCTAssertEqual(
            recorder.lastGetParams?["types"],
            "im,mpim,public_channel,private_channel",
            "types must remain the four-surface coverage string — dropping any token silently hides that Slack surface from the inbox"
        )
    }

    func testRecentThreadsExcludesArchivedConversations() async throws {
        // Archived channels would balloon the sidebar with stale rooms the
        // user explicitly retired. The default `exclude_archived` is false on
        // Slack's side, so omitting the param surfaces every retired channel.
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "channels": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.recentThreads(limit: 50)

        XCTAssertEqual(recorder.lastGetParams?["exclude_archived"], "true",
                       "archived rooms must remain hidden from the inbox sidebar")
    }

    func testRecentThreadsHitsConversationsListEndpoint() async throws {
        // Pin the endpoint name. The Slack Web API distinguishes
        // `conversations.list` (channels) from `conversations.members`
        // (membership) and `users.conversations` (per-user view). Drift here
        // would silently change the response shape, breaking the parser.
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "channels": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.recentThreads(limit: 50)

        XCTAssertEqual(recorder.lastGetEndpoint, "conversations.list")
    }

    func testMessagesHitsConversationsHistoryEndpoint() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = #"{"ok": true, "messages": []}"#.data(using: .utf8)!
        let recorder = GetRecordingHTTP(payload: body)
        let channel = SlackChannel(tokenStore: store, http: recorder)

        _ = try await channel.messages(forThreadID: "C100", limit: 20)

        XCTAssertEqual(recorder.lastGetEndpoint, "conversations.history")
    }

    // MARK: - DM display name fallback

    func testRecentThreadsDMWithoutDisplayNameFallsBackToChannelID() async throws {
        // Slack DMs surface as `is_im: true` but `user_display_name` is fetched
        // out-of-band; until that resolution lands we fall back to the channel
        // id so the row at least renders something stable rather than blank.
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "D300", "is_im": true}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.first?.name, "D300")
    }

    // MARK: - Slack system messages (user == nil)

    func testMessagesWithNilUserAreAttributedToMe() async throws {
        // Slack's bot/system messages omit `user`. The current parser maps
        // user==nil to `from = .me` — pinned here so a refactor that flips
        // the fallback (which would surface system messages as if from a
        // contact) doesn't ship silently.
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000000.0001", "text": "channel created"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.first?.from, .me)
    }

    /// Sibling case: present-but-empty `user` value is currently classified
    /// as `.them` (the test predicate is `m.user != nil`, and `Some("")` is
    /// non-nil). This is INCONSISTENT with the missing-user path which maps
    /// to `.me`. Pinned because:
    ///   1. Slack's API typically omits `user` on bot/system messages
    ///      rather than sending an empty string, so this case is rare —
    ///      but the inconsistency is real and worth surfacing if it ever
    ///      starts firing in the wild (a malformed Slack payload, a bot
    ///      with a misbehaving SDK, a future Slack schema change).
    ///   2. A future "harden present-but-empty as missing" tightening
    ///      (parallel to the chatGUID/sender empty-string fixes) would
    ///      flip this behavior — pin so the change is deliberate.
    func testMessagesWithEmptyStringUserAreAttributedToThem() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000000.0002", "user": "", "text": "weirdly empty user"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.first?.from, .them,
            "present-but-empty `user` is currently classified as .them — pin so a future tightening to .me is deliberate")
    }

    /// Pin the empty-text round-trip: `text: ""` and `text: nil` both
    /// produce `Message.text == ""`. Realistic case: a Slack file-share
    /// or attachment-only post with no text body. Empty messages must
    /// survive the parser and reach the inbox so the user sees a
    /// "thread updated" signal even when there's no text to show.
    /// Companion to PromptBuilder's empty-text retention pin.
    func testMessagesWithEmptyOrMissingTextSurviveParsing() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000000.0003", "user": "U1", "text": ""},
                {"ts": "1700000001.0001", "user": "U2"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.count, 2, "both empty-text and missing-text messages survive parsing")
        // Slack returns newest-first; parser reverses to oldest-first, so order is U1 then U2.
        XCTAssertEqual(msgs.first?.text, "", "empty text round-trips as empty string")
        XCTAssertEqual(msgs.last?.text, "", "missing text defaults to empty string via `?? \"\"`")
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

    // MARK: - Fallback error copy — exact-literal pins
    //
    // Slack normally returns `{"ok": false, "error": "<reason>"}`, in which
    // case the user sees the Slack-supplied reason. When Slack misbehaves
    // and returns `{"ok": false}` with no error field, the parser falls
    // back to a hand-written copy. Those fallback strings ship to the
    // inbox banner verbatim — pin them so a designer-led rephrase
    // surfaces in code review, not as a silent UX drift.

    func testRecentThreadsFallbackCopyExactLiteral() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-abc", workspaceName: "Acme")
        let body = #"{"ok": false, "channels": []}"#.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        do {
            _ = try await channel.recentThreads(limit: 10)
            XCTFail("Expected networkError to be thrown")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack conversations.list failed",
                "recentThreads fallback copy is part of the inbox-banner UX contract")
        }
    }

    func testMessagesFallbackCopyExactLiteral() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-abc", workspaceName: "Acme")
        let body = #"{"ok": false, "messages": []}"#.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        do {
            _ = try await channel.messages(forThreadID: "C100", limit: 10)
            XCTFail("Expected networkError to be thrown")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack conversations.history failed",
                "messages fallback copy is part of the inbox-banner UX contract")
        }
    }

    func testSendFallbackCopyExactLiteral() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-abc", workspaceName: "Acme")
        let body = #"{"ok": false}"#.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        do {
            try await channel.send(text: "hi", toThreadID: "C200")
            XCTFail("Expected networkError to be thrown")
        } catch let ChannelError.networkError(msg) {
            XCTAssertEqual(msg, "Slack chat.postMessage failed",
                "send fallback copy is what users see when Slack acks failure without a reason")
        }
    }

    // MARK: - parseThreads — derived fields (chatGUID + avatar)

    /// Pin that the Slack conversation id flows through to `MessageThread.chatGUID`
    /// for every conversation type. ChatGUID is the routing key that the inbox
    /// hands back to `SlackChannel.send(text:toThreadID:)` — drift here (e.g.
    /// stripping a channel-id prefix or substituting the user id for DMs)
    /// silently breaks send-from-inbox even when the row renders correctly.
    func testRecentThreadsChatGUIDIsConversationID() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "C100", "name": "general", "is_channel": true},
                {"id": "D200", "is_im": true, "user_display_name": "Maya"},
                {"id": "G300", "name": "growth-team"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.count, 3)
        XCTAssertEqual(threads[0].chatGUID, "C100",
            "channel chatGUID must equal the Slack conversation id verbatim")
        XCTAssertEqual(threads[1].chatGUID, "D200",
            "DM chatGUID must equal the Slack conversation id, not the user id")
        XCTAssertEqual(threads[2].chatGUID, "G300",
            "fallback chatGUID must equal the Slack conversation id verbatim")
    }

    /// Pin avatar derivation: `String(display.prefix(1)).uppercased()` for every
    /// thread, where `display` is the rendered `name`. The "#" channel prefix
    /// flows into avatar as "#"; a DM display picks up the first letter of the
    /// human name; the channel-id fallback picks up the first letter of the id
    /// (e.g. "D" for a DM or "C" for a channel) — anything else would render
    /// a blank circle in the sidebar.
    func testRecentThreadsAvatarIsFirstCharOfDisplayName() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "C100", "name": "general", "is_channel": true},
                {"id": "D200", "is_im": true, "user_display_name": "maya chen"},
                {"id": "D300", "is_im": true}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads[0].avatar, "#",
            "channel avatar must equal `#` (first char of `#general`)")
        XCTAssertEqual(threads[1].avatar, "M",
            "DM avatar must equal first char of display name uppercased — `M` for `maya chen`")
        XCTAssertEqual(threads[2].avatar, "D",
            "fallback avatar must equal first char of channel id — `D` for `D300`")
    }

    /// Pin that messages with `files` non-empty surface `hasAttachment: true`
    /// on the resulting `Message`. The inbox shows an attachment glyph when
    /// this is true. A future refactor that drops the `files` decode (e.g.
    /// because Slack added `attachments` v2) would silently lose the glyph.
    func testMessagesWithFilesArrayMarksHasAttachment() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000010.0001", "user": "U999", "text": "see attached", "files": [{"id": "F1"}]},
                {"ts": "1700000020.0001", "user": "U999", "text": "no attachment"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.count, 2)
        let withFile = msgs.first { $0.text == "see attached" }
        let noFile   = msgs.first { $0.text == "no attachment" }
        XCTAssertEqual(withFile?.hasAttachment, true,
            "message with non-empty files array must have hasAttachment=true")
        XCTAssertEqual(noFile?.hasAttachment, false,
            "message without files key must have hasAttachment=false")
    }

    /// Pin that an empty `files: []` is treated the same as missing files —
    /// no attachment. Slack sometimes sends an empty array for messages
    /// that had attachments removed; ReplyAI must not show a misleading
    /// glyph for those.
    func testMessagesWithEmptyFilesArrayHasNoAttachment() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "1700000010.0001", "user": "U999", "text": "msg", "files": []}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].hasAttachment, false,
            "empty files array must produce hasAttachment=false; otherwise Slack's empty-array convention causes ghost-glyph rows")
    }

    // MARK: - Display-name fallback chain (parseThreads)

    /// `is_channel: true` with an empty `name` ("") must fall through past
    /// the channel branch's `!name.isEmpty` guard and end at the id fallback.
    /// Pinned so a refactor that drops the empty-string check (e.g. a
    /// `c.name ?? ""` collapse) doesn't ship a "#" row in the sidebar.
    func testRecentThreadsChannelWithEmptyNameFallsBackToID() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "C500", "is_channel": true, "name": ""}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.first?.name, "C500",
            "is_channel: true with empty name must fall through to the channel id, not '#'")
    }

    /// DM with `is_im: true` and a present-but-empty `user_display_name` must
    /// also fall through to the id fallback (the current branch uses
    /// `!user.isEmpty`, so empty strings cannot satisfy the DM branch).
    func testRecentThreadsDMWithEmptyDisplayNameFallsBackToChannelID() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "D700", "is_im": true, "user_display_name": ""}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.first?.name, "D700",
            "DM with empty user_display_name must fall through to the channel id rather than render a blank row")
    }

    /// Group DMs (`is_im` and `is_channel` both unset) reach the third branch
    /// of the display-name chain — `c.name ?? c.id` — and should surface the
    /// pre-formatted member list Slack returns in `name`. Without this branch
    /// covered, a refactor could silently start showing the channel id
    /// instead of "alice, bob, charlie" on group DMs.
    func testRecentThreadsGroupDMUsesNameField() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "G900", "name": "alice, bob, charlie"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.first?.name, "alice, bob, charlie")
        XCTAssertEqual(threads.first?.avatar, "A",
            "avatar is first uppercased character of the resolved display name")
    }

    /// Group DMs with neither `name` nor flags set fall through to the id —
    /// pin the absolute last-resort branch so it can't silently regress to
    /// returning an empty string.
    func testRecentThreadsConversationWithNoNameOrFlagsFallsBackToID() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test-token", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "channels": [
                {"id": "X404"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let threads = try await channel.recentThreads(limit: 10)
        XCTAssertEqual(threads.first?.name, "X404",
            "missing name + missing is_channel/is_im flags must surface the channel id rather than an empty row")
    }

    /// `parseMessages` parses Slack's `ts` (ISO Unix seconds string with a
    /// fractional ms suffix) via `Double(_:)`. A `ts` that isn't a number
    /// (e.g. corrupted JSON or a future schema breakage) must produce an
    /// empty `time` string rather than crash — pin the silent-fallback
    /// behaviour because `relativeFormatter()` is invoked unconditionally
    /// downstream and a NaN/inf would render as "in 0 seconds".
    func testMessagesWithUnparseableTimestampFallsBackToEmptyTime() async throws {
        let store = SlackTokenStore(keychain: KeychainHelper(service: testService))
        try store.set(token: "xoxb-test", workspaceName: "Acme")
        let body = """
        {
            "ok": true,
            "messages": [
                {"ts": "not-a-number", "user": "U001", "text": "hi"}
            ]
        }
        """.data(using: .utf8)!
        let channel = SlackChannel(tokenStore: store, http: StubHTTP(payload: body))

        let msgs = try await channel.messages(forThreadID: "C100", limit: 10)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].time, "",
            "unparseable timestamp must fall back to empty time, not crash or render a malformed relative string")
        XCTAssertNil(msgs[0].deliveredAt,
            "deliveredAt must be nil when the timestamp can't be parsed — downstream sort logic depends on this")
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

/// HTTP client that records the last GET it received and replays a canned
/// payload. Used by limit-clamp tests to verify the request shape.
private final class GetRecordingHTTP: SlackHTTPClient, @unchecked Sendable {
    let payload: Data
    private(set) var lastGetEndpoint: String?
    private(set) var lastGetParams: [String: String]?
    private let lock = NSLock()

    init(payload: Data) { self.payload = payload }

    func get(endpoint: String, token: String, params: [String: String]) async throws -> Data {
        lock.lock()
        lastGetEndpoint = endpoint
        lastGetParams = params
        lock.unlock()
        return payload
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
