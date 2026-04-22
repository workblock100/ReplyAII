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
        case timedOut
        case messageTooLong(Int)

        var errorDescription: String? {
            switch self {
            case .scriptFailure(let s): s
            case .notAuthorized:        "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation."
            case .unsupported:          "This thread can't be sent to (unsupported channel)."
            case .timedOut:             "Messages.app did not respond within the timeout. It may be busy with iCloud sync."
            case .messageTooLong(let n): "Message too long (\(n) chars, max \(IMessageSender.maxMessageLength))."
            }
        }
    }

    /// Maximum message length accepted by the AppleScript send path.
    /// Strings beyond this limit fail silently or get truncated by Messages.app;
    /// we surface an error so the user sees a clear failure instead.
    static let maxMessageLength = 4096

    /// Maximum wall-clock seconds to wait for NSAppleScript.executeAndReturnError.
    /// Defaults to 10 s in production; inject a shorter value in tests.
    nonisolated(unsafe) static var sendTimeout: TimeInterval = 10

    /// Test-only hook: when non-nil, replaces the real NSAppleScript execution.
    /// Receives the compiled AppleScript source string; runs synchronously on a
    /// background thread; may throw a SendError to simulate script failures.
    nonisolated(unsafe) static var executeHook: ((String) throws -> Void)? = nil

    /// Returns a no-op hook that succeeds immediately without executing AppleScript.
    /// Set `IMessageSender.executeHook = IMessageSender.dryRunHook()` in tests that
    /// need to exercise the send path without messaging anyone.
    static func dryRunHook() -> (String) throws -> Void { { _ in } }

    /// Send `text` to the given thread. Blocks the calling thread until
    /// AppleScript returns (or the timeout fires); call from a background task.
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
        guard text.count <= maxMessageLength else {
            throw SendError.messageTooLong(text.count)
        }
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

        // Capture executor once so test hooks can't be swapped mid-flight.
        let executor: (String) throws -> Void = executeHook ?? { src in
            guard let script = NSAppleScript(source: src) else {
                throw SendError.scriptFailure("NSAppleScript failed to parse")
            }
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
            if let error = errorDict {
                // `errOSAScriptError = -1743` is the TCC denial code.
                // `errAEEventNotHandled = -1708` means Messages accepted the
                // send but couldn't dispatch — typically transient during
                // startup or iCloud sync. Signal it for the retry path.
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                if code == -1743 {
                    throw SendError.notAuthorized
                }
                let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
                throw SendError.scriptFailure("AppleScript error \(code): \(msg)")
            }
        }

        // NSAppleScript.executeAndReturnError is synchronous and blocks the
        // calling thread. If Messages.app hangs (e.g. during iCloud sync) the
        // call never returns. Run it on a background thread and time it out
        // with a DispatchSemaphore so the caller is never stranded indefinitely.
        let semaphore = DispatchSemaphore(value: 0)
        var capturedError: Error? = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try executor(source)
            } catch let err as SendError {
                // -1708 (errAEEventNotHandled) is transient — retry once after
                // a short wait. All other errors propagate immediately.
                if case .scriptFailure(let msg) = err, msg.contains("AppleScript error -1708") {
                    Thread.sleep(forTimeInterval: 0.5)
                    do {
                        try executor(source)
                    } catch {
                        capturedError = error
                    }
                } else {
                    capturedError = err
                }
            } catch {
                capturedError = error
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + sendTimeout) == .success else {
            throw SendError.timedOut
        }
        if let err = capturedError { throw err }
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
