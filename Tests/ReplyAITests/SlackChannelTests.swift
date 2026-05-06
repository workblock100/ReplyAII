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
