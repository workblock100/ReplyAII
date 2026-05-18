import Foundation

/// Abstracts a source of threads + messages for one channel (iMessage,
/// Slack, WhatsApp, …). Only iMessage is wired in v1; the rest are stubs.
protocol ChannelService: Sendable {
    /// Fetch the N most recently-active threads with enough detail to
    /// render the sidebar + thread list.
    func recentThreads(limit: Int) async throws -> [MessageThread]

    /// Fetch the full message history (or a window of it) for a thread.
    func messages(forThreadID id: String, limit: Int) async throws -> [Message]

    /// Messages with `rowID > sinceRowID`, filtered to incoming only
    /// (`is_from_me = 0`). Returned oldest→newest so the rule engine
    /// can replay them in order and advance the high-water mark to
    /// the tail's rowID.
    ///
    /// `sinceRowID: 0` returns every incoming message in the thread.
    func newIncomingMessages(forThreadID id: String, sinceRowID: Int64) async throws -> [Message]
}

/// Default page sizes shared across every `ChannelService` adapter and used by
/// the no-arg convenience overloads on the protocol. Swift protocols can't
/// host static-let storage themselves, so the defaults live in this enum and
/// the convenience overloads + tests both reference them. Pinned by
/// `ChannelServiceTests.testRecentThreadsLimitDefaultLiteralIsFifty` and
/// `ChannelServiceTests.testMessagesLimitDefaultLiteralIsTwenty`.
enum ChannelServiceDefaults {
    /// Sidebar fetch size for the no-arg `recentThreads()` convenience.
    /// Drift up wastes per-channel API budget on threads the user can't see
    /// (the inbox sidebar tops out around 50 visible rows on the default
    /// window size); drift down gives every newly-added channel a smaller
    /// window than the chat.db path, so swapping channels feels like
    /// "where did my older threads go?".
    static let recentThreadsLimit: Int = 50

    /// Per-thread message cap for the no-arg `messages(forThreadID:)`
    /// convenience. 20 is the documented `PromptBuilder` working budget
    /// for context — drift up oversubscribes the LLM context window;
    /// drift down silently shrinks the prompt's available history and
    /// makes drafts feel less personalized for active conversations.
    static let messagesLimit: Int = 20
}

extension ChannelService {
    /// Convenience overload: fetch at most `ChannelServiceDefaults.recentThreadsLimit`
    /// threads (50 by default). Routes through the constant so a single
    /// edit there changes every adapter's default page size.
    func recentThreads() async throws -> [MessageThread] {
        try await recentThreads(limit: ChannelServiceDefaults.recentThreadsLimit)
    }

    /// Convenience overload: fetch the `ChannelServiceDefaults.messagesLimit`
    /// most recent messages (20 by default). Callers that need more for
    /// context-building should pass an explicit limit.
    func messages(forThreadID id: String) async throws -> [Message] {
        try await messages(forThreadID: id, limit: ChannelServiceDefaults.messagesLimit)
    }

    /// Default shim so existing mocks/stubs don't have to implement the
    /// incremental fetch until they care about rule actions.
    func newIncomingMessages(forThreadID id: String, sinceRowID: Int64) async throws -> [Message] {
        []
    }
}

/// Errors thrown by `ChannelService` implementations. The case set is
/// channel-agnostic on purpose — every backend (chat.db, Slack, future
/// Telegram/Teams adapters) maps its native failure modes onto these.
/// `errorDescription` is the user-visible string surfaced by inbox
/// banners and Settings → Channels rows; UI code should rely on the
/// case for branching (e.g. authorizationDenied → render reconnect CTA)
/// and on the description for display only.
enum ChannelError: LocalizedError, Sendable {
    case permissionDenied(hint: String)
    /// Channel requires an OAuth token that is not present in Keychain.
    case authorizationDenied
    case unavailable(String)
    case query(String)
    /// sqlite3_open_v2 returned a non-OK result code. Preserving the numeric
    /// code lets callers distinguish SQLITE_BUSY (5) from auth failures without
    /// string-matching on the message.
    case databaseError(code: Int32, message: String)
    /// sqlite3_open_v2 returned SQLITE_NOTADB (26): the file exists but is not
    /// a valid SQLite database. Can happen after a macOS crash during iCloud sync.
    /// Callers should surface a "re-sync from iCloud" recovery path.
    case databaseCorrupted
    /// An HTTP or transport-level failure from a remote channel API (e.g. Slack).
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let hint):           hint
        case .authorizationDenied:                  Self.authorizationDeniedCopy
        case .unavailable(let s):                   s
        case .query(let s):                         s
        case .databaseError(_, let message):        message
        case .databaseCorrupted:                    Self.databaseCorruptedCopy
        case .networkError(let s):                  s
        }
    }

    /// User-visible toast copy for `authorizationDenied`. Hoisted from
    /// the inline literal so a) onboarding/Settings UX copy review can
    /// land here without grepping a switch arm, b) tests can pin the
    /// exact string a returning user sees instead of re-typing it. The
    /// "Open Settings" verb assumes the inbox surfaces a tap-target
    /// that opens the channel-settings sheet — drift in either direction
    /// (asking the user to do something the UI no longer supports, or
    /// not asking when the UI does support it) is a copy/UX desync that
    /// only QA catches today. Pinned by
    /// `ChannelErrorTests.testAuthorizationDeniedCopyIsFrozen`.
    static let authorizationDeniedCopy =
        "This channel isn't connected yet. Open Settings to sign in."

    /// User-visible toast copy for `databaseCorrupted`. Same hoisting
    /// rationale as `authorizationDeniedCopy` — the recovery instruction
    /// ("sign out of iCloud Messages and back in") assumes the user
    /// understands they own that recovery path; copy review and the test
    /// pin both belong here, not in a switch arm.
    static let databaseCorruptedCopy =
        "The Messages database appears corrupted. Try signing out of iCloud Messages and back in to rebuild it."
}
