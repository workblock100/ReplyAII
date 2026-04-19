import Foundation

/// Abstracts a source of threads + messages for one channel (iMessage,
/// Slack, WhatsApp, …). Only iMessage is wired in v1; the rest are stubs.
protocol ChannelService: Sendable {
    /// Fetch the N most recently-active threads with enough detail to
    /// render the sidebar + thread list.
    func recentThreads(limit: Int) async throws -> [MessageThread]

    /// Fetch the full message history (or a window of it) for a thread.
    func messages(forThreadID id: String, limit: Int) async throws -> [Message]
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
