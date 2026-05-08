import Foundation

/// Reads recent chats from Messages.app via AppleScript automation.
/// Requires macOS Automation permission (not FDA). Used as fallback when
/// chat.db is inaccessible due to Full Disk Access denial.
struct AppleScriptMessageReader: Sendable {
    /// Smallest useful `limit` arg to `messagesForChat(chatGUID:limit:)`. A
    /// caller passing 0 produces a degenerate AppleScript `startIdx = msgCount + 1`
    /// (zero rows on a healthy chat); a negative value produces `startIdx > msgCount`
    /// which the script then clamps to 1, silently returning the entire chat
    /// history — the opposite of what the caller intended. We clamp the
    /// caller-supplied limit up to 1 instead. Pinned by
    /// `AppleScriptMessageReaderTests.testMessagesForChatMinimumLimitIsOne`.
    static let minimumMessageLimit: Int = 1

    /// Inter-field delimiter for both AppleScript-emitted output rows and
    /// the Swift parser's `components(separatedBy:)` split. The AppleScript
    /// heredocs interpolate `\(rowDelimiter)` and the parser splits on the
    /// same constant — drift between the emitter and the parser would
    /// produce one-field rows containing the entire payload (parser sees
    /// no delimiter) or empty rows (parser splits on a different separator
    /// that doesn't appear). Either failure mode silently returns an
    /// empty thread/message list with no error path. Pinned by
    /// `AppleScriptMessageReaderTests.testRowDelimiterIsFrozen`.
    static let rowDelimiter: String = "||"

    /// AppleScript's `missing value` sentinel as it appears in the
    /// emitted text after `as text` coercion. Used by the Swift parser to
    /// drop rows where AppleScript leaked the sentinel through a script-
    /// side fallback gap (e.g. a message with no body, or a 1:1 chat
    /// whose `name` property is `missing value` and the participant
    /// fallback also produced nothing). Drift here surfaces literal
    /// "missing value" strings in inbox previews. Pinned by
    /// `AppleScriptMessageReaderTests.testMissingValueSentinelIsFrozen`.
    static let missingValueSentinel: String = "missing value"

    /// AppleScript message-direction value that maps to `Message.Author.me`.
    /// Anything else (typically "incoming") maps to `.them`. Drift in the
    /// expected literal flips authorship for every parsed message — the
    /// inbox would attribute every reply the user sent to the contact and
    /// vice versa. Pinned by
    /// `AppleScriptMessageReaderTests.testOutgoingDirectionLiteralIsFrozen`.
    static let outgoingDirectionValue: String = "outgoing"

    /// Executes an AppleScript source string and returns the result as text.
    /// Injectable so tests can verify the script string and return mock data
    /// without touching Messages.app.
    let executor: @Sendable (String) throws -> String

    /// Resolves a phone-or-email handle to a Contacts display name.
    /// Defaults to a no-op that returns nil; production passes a closure
    /// backed by `ContactsResolver` so threads display real contact names
    /// instead of raw handles when the user has the contact saved.
    let nameFor: @Sendable (String) -> String?

    init(
        executor: @escaping @Sendable (String) throws -> String = AppleScriptMessageReader.defaultExecutor,
        nameFor: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.executor = executor
        self.nameFor = nameFor
    }

    /// Returns recent chats from Messages.app sorted by displayName.
    /// Each thread gets the chat name when available, otherwise the first
    /// participant's handle (phone or email). For 1:1 chats Messages.app
    /// returns `missing value` for `name`, so we fall back to participants.
    func recentChats() throws -> [MessageThread] {
        // Query name + participant handle + chat id only. Reading message
        // bodies via `text messages of theChat` iterates the entire history
        // of every chat (200+ chats × N messages each) and times out the
        // AppleScript runtime — preview is left empty here and resolved
        // later via chat.db when FDA is granted.
        let script = """
        tell application "Messages"
            set output to ""
            repeat with theChat in every chat
                try
                    set chatName to ""
                    try
                        set rawName to name of theChat
                        if rawName is not missing value then set chatName to rawName as text
                    end try
                    if chatName is "" or chatName is "missing value" then
                        try
                            set theParticipants to participants of theChat
                            if (count of theParticipants) > 0 then
                                set firstP to item 1 of theParticipants
                                try
                                    set chatName to handle of firstP as text
                                end try
                            end if
                        end try
                    end if
                    set chatID to id of theChat as text
                    if chatName is "" then set chatName to chatID
                    set output to output & chatName & "||" & chatID & "\n"
                end try
            end repeat
            return output
        end tell
        """
        let raw = try executor(script)
        return parse(raw)
    }

    /// Returns the most recent messages for a single chat, in chronological
    /// order (oldest first, newest last). Limited to the most-recent `limit`
    /// messages to avoid iterating the chat's full history. Used as the
    /// FDA-free fallback for opening a thread when chat.db is inaccessible.
    ///
    /// AppleScript surface: walks `text messages of first chat whose id is …`
    /// and emits `body||direction` rows. The parser maps `outgoing` → `.me`
    /// and anything else → `.them`, so message authorship is preserved
    /// without requiring a Contacts lookup.
    func messagesForChat(chatGUID: String, limit: Int) throws -> [Message] {
        // AppleScript string interpolation: the GUID is embedded inside a
        // double-quoted string literal in the script. Escape any embedded
        // quotes or backslashes so a hostile or unusual GUID can't terminate
        // the string and inject syntax. Real chat GUIDs are ASCII-safe but
        // we don't trust the caller.
        let escapedGUID = chatGUID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Clamp limit to a sane positive value. Zero or negative would
        // produce a degenerate `startIdx` calculation in AppleScript and
        // return the whole history (or error). One is the smallest useful.
        let clampedLimit = max(Self.minimumMessageLimit, limit)

        let script = """
        tell application "Messages"
            set output to ""
            try
                set theChat to first chat whose id is "\(escapedGUID)"
                set theMsgs to text messages of theChat
                set msgCount to count of theMsgs
                if msgCount > 0 then
                    set startIdx to msgCount - \(clampedLimit) + 1
                    if startIdx < 1 then set startIdx to 1
                    repeat with i from startIdx to msgCount
                        try
                            set m to item i of theMsgs
                            set msgText to ""
                            try
                                set msgText to text of m as text
                            end try
                            set msgDir to "incoming"
                            try
                                set msgDir to direction of m as text
                            end try
                            set output to output & msgText & "||" & msgDir & "\n"
                        end try
                    end repeat
                end if
            end try
            return output
        end tell
        """
        let raw = try executor(script)
        return parseMessages(raw, limit: clampedLimit)
    }

    /// Parses newline-delimited "body||direction" rows from `messagesForChat`
    /// into `Message` values. `outgoing` maps to `.me`; any other direction
    /// (typically `incoming`) maps to `.them`. Empty bodies and `missing
    /// value` leakage are dropped. The `limit` cap is enforced here as well
    /// as in AppleScript so a misbehaving executor that returns more rows
    /// than requested still respects the contract.
    private func parseMessages(_ raw: String, limit: Int) -> [Message] {
        var out: [Message] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: Self.rowDelimiter)
            let body = parts.count > 0 ? parts[0] : ""
            let dir  = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "incoming"
            // AppleScript can leak "missing value" when a message has no
            // text body (e.g. a tapback or attachment-only message). Drop
            // those rather than surface a literal "missing value" string.
            if body.isEmpty || body == Self.missingValueSentinel { continue }
            let from: Message.Author = (dir.lowercased() == Self.outgoingDirectionValue) ? .me : .them
            out.append(Message(from: from, text: body, time: ""))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Parsing

    /// Parses newline-delimited "name||chatID||preview" rows into MessageThread values.
    /// Defensively filters out rows where AppleScript still leaked "missing value"
    /// past the script-side fallbacks.
    private func parse(_ raw: String) -> [MessageThread] {
        var threads: [MessageThread] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: Self.rowDelimiter)
            var name    = parts.count > 0 ? parts[0].trimmingCharacters(in: .whitespaces) : trimmed
            let chatID  = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            var preview = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            // Defensive: AppleScript can still leak "missing value" through edge paths.
            if name.isEmpty || name == Self.missingValueSentinel {
                if let id = chatID, !id.isEmpty {
                    name = Self.formatHandleFromChatID(id)
                } else {
                    continue
                }
            }
            // Upgrade phone/email handles to a real contact name when the user
            // has them saved. Falls back to the formatted handle if no match.
            if let resolved = Self.resolveContact(forName: name, chatID: chatID, using: nameFor) {
                name = resolved
            } else {
                // No contact match — at least format the phone number for
                // readability. `+12014623980` -> `+1 (201) 462-3980`.
                name = Self.prettyPhone(name)
            }
            if preview == Self.missingValueSentinel { preview = "" }
            if preview.isEmpty { preview = "—" }
            // Collapse newlines / extra whitespace in previews so they fit one row.
            preview = preview.replacingOccurrences(of: "\n", with: " ")
            threads.append(MessageThread(
                id: chatID ?? name,
                channel: .imessage,
                name: name,
                avatar: IMessageChannel.avatarInitial(for: name),
                preview: preview,
                time: "",
                chatGUID: chatID
            ))
        }
        return threads.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Best-effort: derive a human-ish label from an iMessage chat ID like
    /// `iMessage;-;+15551234567` or `iMessage;+;chat1234567890` when no
    /// participant name is available.
    private static func formatHandleFromChatID(_ chatID: String) -> String {
        let parts = chatID.split(separator: ";")
        guard let last = parts.last else { return chatID }
        let s = String(last)
        // If it's a phone number, return as-is; if it's an email, return as-is;
        // if it's a synthetic chat key (e.g. "chat1234567890"), label it generically.
        if s.hasPrefix("chat") { return "Group chat" }
        return s
    }

    /// Pretty-print a raw phone handle for display when no contact name is
    /// available. `+12014623980` → `+1 (201) 462-3980`. Non-phone strings
    /// (emails, group ids, names that have spaces or letters) pass through
    /// unchanged.
    static func prettyPhone(_ s: String) -> String {
        // Skip if it's already formatted, an email, a chat-key, or a real name.
        if s.contains(" ") || s.contains("@") || s.hasPrefix("chat") || s.contains("(") { return s }
        let digits = s.filter(\.isNumber)
        switch digits.count {
        case 11 where digits.hasPrefix("1"):
            // +1 NPA NXX XXXX
            let npa  = digits.dropFirst(1).prefix(3)
            let nxx  = digits.dropFirst(4).prefix(3)
            let last = digits.dropFirst(7).prefix(4)
            return "+1 (\(npa)) \(nxx)-\(last)"
        case 10:
            let npa  = digits.prefix(3)
            let nxx  = digits.dropFirst(3).prefix(3)
            let last = digits.dropFirst(6).prefix(4)
            return "(\(npa)) \(nxx)-\(last)"
        default:
            return s
        }
    }

    /// Try to upgrade a raw handle to a saved contact name via the injected
    /// `nameFor` closure. Looks up against the current name candidate first,
    /// then the suffix of the chat ID (the handle component). Returns nil if
    /// no resolution is possible — caller keeps the original name.
    private static func resolveContact(
        forName name: String,
        chatID: String?,
        using nameFor: (String) -> String?
    ) -> String? {
        // If the current name is already a phone or email, try resolving it.
        if let resolved = nameFor(name), !resolved.isEmpty, resolved != name {
            return resolved
        }
        // Otherwise try the suffix of the chatID (e.g. "+15551234567" from
        // "iMessage;-;+15551234567"). 1:1 chats have a usable handle here.
        guard let id = chatID, !id.isEmpty else { return nil }
        let parts = id.split(separator: ";")
        guard let suffix = parts.last else { return nil }
        let handle = String(suffix)
        if handle.hasPrefix("chat") { return nil }
        // Same guard as the first path: when ContactsResolver has access but
        // no match, it echoes the input handle back. Treat that as no match
        // so the caller's prettyPhone() formatter still runs.
        if let resolved = nameFor(handle), !resolved.isEmpty, resolved != handle {
            return resolved
        }
        return nil
    }

    // MARK: - Default executor

    /// Runs an AppleScript source string via NSAppleScript and returns the
    /// string value of the result descriptor. Throws if the script fails.
    static let defaultExecutor: @Sendable (String) throws -> String = { source in
        // NSAppleScript is not Sendable but we create it fresh on the calling
        // thread, use it immediately, and discard it — no shared state escapes.
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptReaderError.scriptCreationFailed
        }
        let descriptor = script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            let message = (err[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
            throw AppleScriptReaderError.executionError(message)
        }
        return descriptor.stringValue ?? ""
    }
}

/// Failures surfaced from the AppleScript-backed Messages.app reader.
/// Splits creation (NSAppleScript(source:) returned nil — almost always
/// indicates a bad script string we built ourselves) from execution
/// (Messages.app refused, Automation permission missing, or the script
/// raised a runtime error). The callers route both into the inbox banner.
enum AppleScriptReaderError: LocalizedError, Sendable {
    case scriptCreationFailed
    case executionError(String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:       "Failed to compile AppleScript."
        case .executionError(let msg):    "AppleScript failed: \(msg)"
        }
    }
}
