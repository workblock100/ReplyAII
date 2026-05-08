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
    /// User-visible failure cases for the AppleScript send path. Each
    /// `errorDescription` is the literal copy that surfaces in the inbox
    /// error toast — keep them actionable ("Re-grant in System Settings →
    /// …") rather than diagnostic. Adding a new case is a UI change
    /// because the toast renders these strings directly.
    enum SendError: LocalizedError {
        case scriptFailure(String)
        case notAuthorized
        case unsupported
        case timedOut
        case messageTooLong(Int)
        case invalidChatGUID(String)

        /// User-visible toast copy. Each constant is the exact string
        /// the inbox surfaces — keep them actionable ("Re-grant in
        /// System Settings → …") rather than diagnostic. Hoisted from
        /// the `errorDescription` switch so copy review lives in one
        /// place and a future "soften the wording" edit lands in
        /// clearly-named constants instead of a type-conformance
        /// method. Pinned by `IMessageSendErrorCopyTests`'
        /// `*ToastCopyIsFrozen` cluster.
        static let notAuthorizedToast = "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation."
        static let unsupportedToast   = "This thread can't be sent to (unsupported channel)."
        static let timedOutToast      = "Messages.app did not respond within the timeout. It may be busy with iCloud sync."

        var errorDescription: String? {
            switch self {
            case .scriptFailure(let s): s
            case .notAuthorized:        Self.notAuthorizedToast
            case .unsupported:          Self.unsupportedToast
            case .timedOut:             Self.timedOutToast
            case .messageTooLong(let n): "Message too long (\(n) chars, max \(IMessageSender.maxMessageLength))."
            case .invalidChatGUID(let g): "Invalid chat GUID '\(g)': must match iMessage;[+-];<identifier>."
            }
        }
    }

    /// Maximum message length accepted by the AppleScript send path.
    /// Strings beyond this limit fail silently or get truncated by Messages.app;
    /// we surface an error so the user sees a clear failure instead.
    static let maxMessageLength = 4096

    /// `errOSAScriptError` — TCC (Automation permission) denial. Messages
    /// returns this when the user has not granted ReplyAI Automation access.
    /// Maps to `SendError.notAuthorized` for the reconnect-CTA UI path.
    static let tccDeniedErrorCode = -1743

    /// AppleScript service identifier for iMessage chat GUIDs (the first
    /// `;`-separated segment of `iMessage;-;+15551234567`). Used by the
    /// 1:1 GUID synthesis path AND by `isValidIMessageGUID`. Drift breaks
    /// both: synthesis emits a GUID Messages.app rejects, and validation
    /// rejects every legitimate iMessage GUID. Pinned by
    /// `IMessageSenderTests.testServiceIDLiteralsAreIMessageAndSMS`.
    static let iMessageServiceID = "iMessage"

    /// AppleScript service identifier for SMS-relay chat GUIDs (the first
    /// `;`-separated segment of `SMS;-;+15551234567`). Same drift impact
    /// as `iMessageServiceID` but on the SMS-relay path.
    static let smsServiceID = "SMS"

    /// Field separator inside a chat GUID. Messages.app and chat.db both
    /// project chat GUIDs as `<service>;<style>;<identifier>` — semicolons
    /// at fixed positions. Used both for synthesis (joining the three
    /// fields back into a string) and for validation (splitting an
    /// incoming GUID before checking each field). Drift here means
    /// validation no longer accepts what synthesis produces. Pinned by
    /// `IMessageSenderTests.testChatGUIDDelimitersAreFrozen`.
    static let chatGUIDFieldSeparator: Character = ";"

    /// Style marker for a 1:1 chat GUID (e.g. `iMessage;-;+15551234567`).
    /// Used in validation to confirm a GUID's middle field; synthesis
    /// always emits 1:1-shaped GUIDs and therefore always uses this
    /// marker. Pinned by
    /// `IMessageSenderTests.testChatGUIDStyleMarkersAreFrozen`.
    static let chatGUID1to1Marker: Character = "-"

    /// Style marker for a group-chat GUID (e.g. `iMessage;+;chat1234567890`).
    /// Validation accepts either marker but synthesis only ever emits the
    /// 1:1 form — group sends require an existing chat.db-projected GUID.
    static let chatGUIDGroupMarker: Character = "+"

    /// Cached `;<1to1Marker>;` sandwich used by the synthesis path to
    /// build a 1:1 GUID. Routes both `send(_:toChatIdentifier:)` and
    /// `chatGUID(for:)` through one constant so a future syntax change
    /// (e.g. Messages drops the leading `iMessage;` prefix) lands once.
    static let chatGUID1to1Separator: String = ";-;"

    /// `errAEEventNotHandled` — transient. Messages.app accepted the
    /// AppleScript but couldn't dispatch the event (commonly during
    /// startup or iCloud sync). Triggers the `retryDelay` retry path.
    static let eventNotHandledErrorCode = -1708

    /// Production default for `sendTimeout`. Hoisted to a `let` constant
    /// so tests can pin the production cadence without round-tripping
    /// through the mutable `sendTimeout` (which other tests temporarily
    /// override and may not always restore in test-order edge cases).
    static let defaultSendTimeout: TimeInterval = 10

    /// Maximum wall-clock seconds to wait for NSAppleScript.executeAndReturnError.
    /// Defaults to 10 s in production; inject a shorter value in tests.
    nonisolated(unsafe) static var sendTimeout: TimeInterval = defaultSendTimeout

    /// Production default for `retryDelay`. Hoisted to a `let` constant so
    /// the production cadence can be pinned independently of the mutable
    /// `retryDelay` (see `defaultSendTimeout` rationale).
    static let defaultRetryDelay: TimeInterval = 0.5

    /// Format prefix for `SendError.scriptFailure` messages emitted from
    /// the NSAppleScript error path. The retry-on-transient logic uses
    /// `msg.contains("\(prefix)\(eventNotHandledErrorCode)")` to detect
    /// the -1708 case — drift between the emit-site format and the
    /// contains check would silently disable the retry path
    /// (`errAEEventNotHandled` is transient during iCloud sync; without
    /// retry, every send during sync fails to the user). Hoisting
    /// couples the two sites to one constant. Pinned by
    /// `IMessageSenderTests.testAppleScriptErrorPrefixIsFrozen`.
    static let appleScriptErrorPrefix = "AppleScript error "

    /// Failure copy emitted when `NSAppleScript(source:)` returns nil —
    /// the script source itself has a syntax error that the AppleScript
    /// compiler rejected before execution could even start. This is a
    /// developer-side bug (we generated a malformed script) rather than
    /// a runtime-side issue, so the copy doesn't need to be actionable
    /// for end users; it just needs to be greppable in support logs.
    /// Hoisted so a future copy edit lands on a named constant.
    static let scriptParseFailureCopy = "NSAppleScript failed to parse"

    /// Delay between a -1708 failure and the retry attempt.
    /// Defaults to 0.5 s in production; set to 0.0 in tests to avoid slow paths.
    nonisolated(unsafe) static var retryDelay: TimeInterval = defaultRetryDelay

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
        try sendRaw(text, chatGUID: guid, channel: thread.channel)
    }

    /// Legacy by-identifier send — kept so existing call sites compile.
    /// New code should use `send(_:to:)`; this path can't reach group
    /// chats because it synthesizes a 1:1-shaped GUID.
    static func send(_ text: String, toChatIdentifier id: String, channel: Channel) throws {
        guard channel == .imessage || channel == .sms else {
            throw SendError.unsupported
        }
        let service = channel == .sms ? Self.smsServiceID : Self.iMessageServiceID
        try sendRaw(text, chatGUID: "\(service)\(Self.chatGUID1to1Separator)\(id)", channel: channel)
    }

    // MARK: - Internal

    /// Constructs the canonical chat GUID for a thread. If chat.db
    /// populated one, we use it verbatim. Otherwise synthesize a 1:1
    /// form from channel + chat_identifier (group sends will fail
    /// loudly from AppleScript, which is correct — the thread lacks a
    /// GUID to address).
    static func chatGUID(for thread: MessageThread) -> String {
        if let guid = thread.chatGUID, !guid.isEmpty { return guid }
        let service = thread.channel == .sms ? Self.smsServiceID : Self.iMessageServiceID
        return "\(service)\(Self.chatGUID1to1Separator)\(thread.id)"
    }

    private static func sendRaw(_ text: String, chatGUID: String, channel: Channel) throws {
        // Validate before building the AppleScript so failures produce a clear
        // diagnostic rather than an opaque errOSAScriptError -1708 from Messages.
        try validateChatGUID(chatGUID, for: channel)
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
                throw SendError.scriptFailure(Self.scriptParseFailureCopy)
            }
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
            if let error = errorDict {
                // `errOSAScriptError = -1743` is the TCC denial code.
                // `errAEEventNotHandled = -1708` means Messages accepted the
                // send but couldn't dispatch — typically transient during
                // startup or iCloud sync. Signal it for the retry path.
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                if code == Self.tccDeniedErrorCode {
                    throw SendError.notAuthorized
                }
                let msg = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
                throw SendError.scriptFailure("\(Self.appleScriptErrorPrefix)\(code): \(msg)")
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
                if case .scriptFailure(let msg) = err,
                   msg.contains("\(Self.appleScriptErrorPrefix)\(Self.eventNotHandledErrorCode)") {
                    Thread.sleep(forTimeInterval: Self.retryDelay)
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

    /// Validates that `guid` matches the expected format for `channel`.
    /// Throws `SendError.invalidChatGUID` when the format doesn't match.
    /// Add a new `case` here as each channel gains write capability — this is
    /// the single place to add per-channel GUID format rules.
    static func validateChatGUID(_ guid: String, for channel: Channel) throws {
        let valid: Bool
        switch channel {
        case .imessage:
            valid = isValidIMessageGUID(guid)
        case .sms:
            valid = isValidSMSGUID(guid)
        default:
            // Channels without GUID-addressed sends don't have a valid format.
            throw SendError.invalidChatGUID(guid)
        }
        if !valid { throw SendError.invalidChatGUID(guid) }
    }

    private static func isValidIMessageGUID(_ guid: String) -> Bool {
        let parts = guid.split(separator: Self.chatGUIDFieldSeparator, maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        guard parts[0] == Substring(Self.iMessageServiceID) else { return false }
        guard parts[1].count == 1,
              let style = parts[1].first,
              style == Self.chatGUIDGroupMarker || style == Self.chatGUID1to1Marker
        else { return false }
        return !parts[2].isEmpty
    }

    private static func isValidSMSGUID(_ guid: String) -> Bool {
        let parts = guid.split(separator: Self.chatGUIDFieldSeparator, maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        guard parts[0] == Substring(Self.smsServiceID) else { return false }
        guard parts[1].count == 1,
              let style = parts[1].first,
              style == Self.chatGUIDGroupMarker || style == Self.chatGUID1to1Marker
        else { return false }
        return !parts[2].isEmpty
    }

    /// Escape a string for embedding inside AppleScript double-quoted literals.
    /// Handles backslash, double-quote, and newline — the three characters that
    /// would otherwise break the single-line `send "..." to ...` template.
    /// Exposed as `internal` so the test suite can exercise adversarial inputs
    /// without running a live AppleScript interpreter.
    static func escapeForAppleScriptLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func escape(_ s: String) -> String {
        escapeForAppleScriptLiteral(s)
    }
}
