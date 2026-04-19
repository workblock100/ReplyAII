import Foundation
import AppKit

/// Dispatches an iMessage through Messages.app via AppleScript.
///
/// First use triggers a TCC prompt ("ReplyAI wants to control Messages").
/// Grant it once and subsequent sends go through silently.
///
/// We only send to existing chats (identified by the `chat.chat_identifier`
/// pulled out of chat.db). Group-chat sends need the full `chat.guid`,
/// which we don't project yet — those fall through with an error.
enum IMessageSender {
    enum SendError: LocalizedError {
        case scriptFailure(String)
        case notAuthorized
        case unsupported

        var errorDescription: String? {
            switch self {
            case .scriptFailure(let s): s
            case .notAuthorized:        "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation."
            case .unsupported:          "This thread can't be sent to yet (group chats need their full GUID)."
            }
        }
    }

    /// Send `text` to the iMessage thread with the given chat identifier.
    /// Blocks the calling thread until AppleScript returns; call from a
    /// background task.
    static func send(_ text: String, toChatIdentifier id: String, channel: Channel) throws {
        // Only 1:1 iMessage + SMS supported in v1.
        guard channel == .imessage || channel == .sms else { throw SendError.unsupported }

        let service = channel == .sms ? "SMS" : "iMessage"
        let escapedText = escape(text)
        let escapedID   = escape(id)

        // The `chat id "iMessage;-;<handle>"` form matches existing threads
        // without creating a new one. `send` posts the message as the
        // current user.
        let source = """
        tell application "Messages"
            set targetChat to a reference to chat id "\(service);-;\(escapedID)"
            send "\(escapedText)" to targetChat
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw SendError.scriptFailure("NSAppleScript failed to parse")
        }

        var errorDict: NSDictionary?
        let _ = script.executeAndReturnError(&errorDict)

        if let error = errorDict {
            // `errOSAScriptError = -1743` is the TCC denial code. Everything
            // else we surface as-is so the user can see the Messages error.
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                throw SendError.notAuthorized
            }
            let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            throw SendError.scriptFailure("AppleScript error \(code): \(msg)")
        }
    }

    /// Escape a string for embedding inside AppleScript double-quoted
    /// literals: backslash and quote need escaping.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
