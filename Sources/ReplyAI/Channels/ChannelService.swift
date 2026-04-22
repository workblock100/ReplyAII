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

extension ChannelService {
    /// Convenience overload: fetch at most 50 threads (the default page size).
    func recentThreads() async throws -> [MessageThread] {
        try await recentThreads(limit: 50)
    }

    /// Default shim so existing mocks/stubs don't have to implement the
    /// incremental fetch until they care about rule actions.
    func newIncomingMessages(forThreadID id: String, sinceRowID: Int64) async throws -> [Message] {
        []
    }
}

enum ChannelError: LocalizedError, Sendable {
    case permissionDenied(hint: String)
    case unavailable(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let hint): hint
        case .unavailable(let s):          s
        case .query(let s):                s
        }
    }
}
