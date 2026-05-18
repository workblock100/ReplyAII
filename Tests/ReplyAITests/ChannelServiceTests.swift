import XCTest
@testable import ReplyAICore

/// Pins the public surface of `ChannelService` (the per-channel adapter
/// contract) and `ChannelError` (the channel-agnostic error vocabulary
/// surfaced to inbox banners + Settings → Channels rows). Every adapter
/// — IMessageChannel, SlackChannel, WhatsAppChannel, the SMS/Teams/
/// Telegram stubs — funnels through these types, so a silent rename of
/// a case or a drift in user-visible copy is a wide blast radius.
final class ChannelServiceTests: XCTestCase {

    // MARK: - Default page sizes

    func testRecentThreadsDefaultsToFifty() async throws {
        let spy = SpyChannelService()
        _ = try await spy.recentThreads()
        XCTAssertEqual(spy.lastRecentThreadsLimit, ChannelServiceDefaults.recentThreadsLimit,
            "recentThreads() with no arg must route through ChannelServiceDefaults.recentThreadsLimit — drift means the constant became dead code while the convenience overload froze a stale literal")
    }

    func testMessagesDefaultsToTwenty() async throws {
        let spy = SpyChannelService()
        _ = try await spy.messages(forThreadID: "T1")
        XCTAssertEqual(spy.lastMessagesLimit, ChannelServiceDefaults.messagesLimit,
            "messages(forThreadID:) with no limit must route through ChannelServiceDefaults.messagesLimit — drift means context-builders silently get a different history window than the chat.db path")
    }

    /// Pin the literal value of `ChannelServiceDefaults.recentThreadsLimit`
    /// itself. The routing test above only proves the convenience overload
    /// goes through the constant; this test proves the constant has the
    /// right value. Drift up wastes per-channel API budget on threads the
    /// user can't see; drift down gives every adapter a smaller window
    /// than the chat.db path, so swapping channels feels like older
    /// threads have vanished.
    func testRecentThreadsLimitDefaultLiteralIsFifty() {
        XCTAssertEqual(ChannelServiceDefaults.recentThreadsLimit, 50,
            "ChannelServiceDefaults.recentThreadsLimit drift either oversubscribes API budget (too high) or shrinks the visible inbox (too low)")
    }

    /// Pin the literal value of `ChannelServiceDefaults.messagesLimit`
    /// itself. 20 is the documented PromptBuilder working budget — drift
    /// up oversubscribes the LLM context window; drift down silently
    /// shrinks prompt history and makes drafts feel less personalized.
    func testMessagesLimitDefaultLiteralIsTwenty() {
        XCTAssertEqual(ChannelServiceDefaults.messagesLimit, 20,
            "ChannelServiceDefaults.messagesLimit drift either oversubscribes the LLM context window (too high) or shrinks prompt history below the PromptBuilder budget (too low)")
    }

    func testRecentThreadsExplicitLimitIsForwarded() async throws {
        let spy = SpyChannelService()
        _ = try await spy.recentThreads(limit: 7)
        XCTAssertEqual(spy.lastRecentThreadsLimit, 7)
    }

    func testMessagesExplicitLimitIsForwarded() async throws {
        let spy = SpyChannelService()
        _ = try await spy.messages(forThreadID: "T1", limit: 3)
        XCTAssertEqual(spy.lastMessagesLimit, 3)
    }

    // MARK: - newIncomingMessages default

    func testNewIncomingMessagesDefaultReturnsEmpty() async throws {
        // Adapters that haven't opted into the rule-replay path inherit a
        // shim returning []. The rule engine treats "no new messages" as
        // a no-op — the empty default must remain so existing mocks keep
        // compiling.
        let bare = BareChannelService()
        let result = try await bare.newIncomingMessages(forThreadID: "any", sinceRowID: 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testNewIncomingMessagesDefaultIgnoresSinceRowID() async throws {
        // The default shim doesn't read sinceRowID — pin that so a future
        // change forcing all adapters to filter explicitly is visible.
        let bare = BareChannelService()
        let r1 = try await bare.newIncomingMessages(forThreadID: "X", sinceRowID: 0)
        let r2 = try await bare.newIncomingMessages(forThreadID: "X", sinceRowID: Int64.max)
        XCTAssertTrue(r1.isEmpty)
        XCTAssertTrue(r2.isEmpty)
    }

    // MARK: - ChannelError.errorDescription — user-visible strings

    func testPermissionDeniedDescriptionIsHintVerbatim() {
        // .permissionDenied carries adapter-specific copy (FDA hint, etc.);
        // the description must round-trip the hint verbatim so adapters
        // own the wording.
        let err = ChannelError.permissionDenied(hint: "Grant Full Disk Access in System Settings.")
        XCTAssertEqual(err.errorDescription,
                       "Grant Full Disk Access in System Settings.")
    }

    func testAuthorizationDeniedDescriptionIsPinned() {
        // Every OAuth-backed adapter (Slack, WhatsApp, Teams) throws this
        // case before any token-bearing call; the inbox banner shows this
        // exact string.
        let err = ChannelError.authorizationDenied
        XCTAssertEqual(err.errorDescription,
                       "This channel isn't connected yet. Open Settings to sign in.")
    }

    func testUnavailableDescriptionIsAssociatedValue() {
        let err = ChannelError.unavailable("iMessage is briefly unreachable.")
        XCTAssertEqual(err.errorDescription, "iMessage is briefly unreachable.")
    }

    func testQueryDescriptionIsAssociatedValue() {
        let err = ChannelError.query("malformed WHERE clause")
        XCTAssertEqual(err.errorDescription, "malformed WHERE clause")
    }

    func testDatabaseErrorDescriptionIsMessageOnly() {
        // Numeric code is preserved on the case for branching logic, but
        // the user-visible string is the message — code is for diagnostics.
        let err = ChannelError.databaseError(code: 5, message: "database is locked")
        XCTAssertEqual(err.errorDescription, "database is locked")
    }

    func testDatabaseErrorPreservesCode() {
        // SQLITE_BUSY (5) vs SQLITE_AUTH (23) — adapters branch on code, not message.
        let busy = ChannelError.databaseError(code: 5, message: "database is locked")
        if case .databaseError(let code, _) = busy {
            XCTAssertEqual(code, 5)
        } else {
            XCTFail("expected .databaseError, got \(busy)")
        }
    }

    func testDatabaseCorruptedDescriptionIsPinned() {
        // SQLITE_NOTADB (26) — surfaced after iCloud-sync crashes; the
        // recovery copy is part of the trust-the-app contract.
        let err = ChannelError.databaseCorrupted
        XCTAssertEqual(err.errorDescription,
                       "The Messages database appears corrupted. Try signing out of iCloud Messages and back in to rebuild it.")
    }

    func testNetworkErrorDescriptionIsAssociatedValue() {
        let err = ChannelError.networkError("Slack is rate-limiting us right now. Wait a moment, then try again.")
        XCTAssertEqual(err.errorDescription,
                       "Slack is rate-limiting us right now. Wait a moment, then try again.")
    }

    // MARK: - LocalizedError conformance

    func testEveryCaseHasNonEmptyErrorDescription() {
        // Localized error surfaces via NSError.localizedDescription too —
        // a nil errorDescription would fall back to a useless system string.
        let cases: [ChannelError] = [
            .permissionDenied(hint: "h"),
            .authorizationDenied,
            .unavailable("x"),
            .query("y"),
            .databaseError(code: 1, message: "m"),
            .databaseCorrupted,
            .networkError("n"),
        ]
        for c in cases {
            XCTAssertNotNil(c.errorDescription, "\(c) must surface a non-nil description")
            XCTAssertFalse(c.errorDescription!.isEmpty,
                           "\(c) must surface a non-empty description")
        }
    }
}

// MARK: - Test doubles

/// Records the limit values the protocol-extension defaults route through
/// so we can verify recentThreads()/messages(forThreadID:) call through
/// with 50/20.
private final class SpyChannelService: ChannelService, @unchecked Sendable {
    var lastRecentThreadsLimit: Int?
    var lastMessagesLimit: Int?

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        lastRecentThreadsLimit = limit
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        lastMessagesLimit = limit
        return []
    }
}

/// Doesn't override `newIncomingMessages` — exercises the protocol-extension
/// default shim that returns `[]`.
private struct BareChannelService: ChannelService {
    func recentThreads(limit: Int) async throws -> [MessageThread] { [] }
    func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
}
