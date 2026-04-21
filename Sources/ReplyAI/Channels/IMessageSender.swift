import Foundation
import AppKit

/// Dispatches an iMessage through Messages.app via AppleScript.
///
/// First use triggers a TCC prompt ("ReplyAI wants to control Messages").
/// Grant it once and subsequent sends go through silently.
///
/// Sends to existing chats only. We prefer the full `chat.guid` projected
/// from chat.db (which encodes 1:1 vs group via `;-;` / `;+;`), falling
/// back to synthesizing `iMessage;-;<handle>` from `chat_identifier` for
/// legacy rows that somehow lack a guid.
enum IMessageSender {
    enum SendError: LocalizedError {
        case scriptFailure(String)
        case notAuthorized
        case unsupported

        var errorDescription: String? {
            switch self {
            case .scriptFailure(let s): s
            case .notAuthorized:        "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation."
            case .unsupported:          "This thread can't be sent to (unsupported channel)."
            }
        }
    }

    /// Send `text` to the given thread. Blocks the calling thread until
    /// AppleScript returns; call from a background task.
    static func send(_ text: String, to thread: MessageThread) throws {
        guard thread.channel == .imessage || thread.channel == .sms else {
            throw SendError.unsupported
        }
        let guid = chatGUID(for: thread)
        try sendRaw(text, chatGUID: guid)
    }

    /// Legacy by-identifier send — kept so existing call sites compile.
    /// New code should use `send(_:to:)`; this path can't reach group
    /// chats because it synthesizes a 1:1-shaped GUID.
    static func send(_ text: String, toChatIdentifier id: String, channel: Channel) throws {
        guard channel == .imessage || channel == .sms else {
            throw SendError.unsupported
        }
        let service = channel == .sms ? "SMS" : "iMessage"
        try sendRaw(text, chatGUID: "\(service);-;\(id)")
    }

    // MARK: - Internal

    /// Constructs the canonical chat GUID for a thread. If chat.db
    /// populated one, we use it verbatim. Otherwise synthesize a 1:1
    /// form from channel + chat_identifier (group sends will fail
    /// loudly from AppleScript, which is correct — the thread lacks a
    /// GUID to address).
    static func chatGUID(for thread: MessageThread) -> String {
        if let guid = thread.chatGUID, !guid.isEmpty { return guid }
        let service = thread.channel == .sms ? "SMS" : "iMessage"
        return "\(service);-;\(thread.id)"
    }

    private static func sendRaw(_ text: String, chatGUID: String) throws {
        let escapedText = escape(text)
        let escapedGUID = escape(chatGUID)

        // `chat id "<guid>"` matches an existing chat by its GUID. `send`
        // posts the message as the current user.
        let source = """
        tell application "Messages"
            set targetChat to a reference to chat id "\(escapedGUID)"
            send "\(escapedText)" to targetChat
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw SendError.scriptFailure("NSAppleScript failed to parse")
        }

        var errorDict: NSDictionary?
        let _ = script.executeAndReturnError(&errorDict)

        if let error = errorDict {
            // `errOSAScriptError = -1743` is the TCC denial code.
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                throw SendError.notAuthorized
            }
            let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            throw SendError.scriptFailure("AppleScript error \(code): \(msg)")
        }
    }

    /// Escape a string for embedding inside AppleScript double-quoted
    /// literals: backslash and quote need escaping. Exposed as `internal`
    /// so the test suite can exercise adversarial inputs without running
    /// a live AppleScript interpreter.
    static func escapeForAppleScriptLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func escape(_ s: String) -> String {
        escapeForAppleScriptLiteral(s)
    }
}
