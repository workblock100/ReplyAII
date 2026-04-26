import Foundation

/// Reads recent chats from Messages.app via AppleScript automation.
/// Requires macOS Automation permission (not FDA). Used as fallback when
/// chat.db is inaccessible due to Full Disk Access denial.
struct AppleScriptMessageReader: Sendable {
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

    // MARK: - Parsing

    /// Parses newline-delimited "name||chatID||preview" rows into MessageThread values.
    /// Defensively filters out rows where AppleScript still leaked "missing value"
    /// past the script-side fallbacks.
    private func parse(_ raw: String) -> [MessageThread] {
        var threads: [MessageThread] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "||")
            var name    = parts.count > 0 ? parts[0].trimmingCharacters(in: .whitespaces) : trimmed
            let chatID  = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            var preview = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            // Defensive: AppleScript can still leak "missing value" through edge paths.
            if name.isEmpty || name == "missing value" {
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
            if preview == "missing value" { preview = "" }
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
