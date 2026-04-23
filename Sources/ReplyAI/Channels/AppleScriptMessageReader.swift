import Foundation

/// Reads recent chats from Messages.app via AppleScript automation.
/// Requires macOS Automation permission (not FDA). Used as fallback when
/// chat.db is inaccessible due to Full Disk Access denial.
struct AppleScriptMessageReader: Sendable {
    /// Executes an AppleScript source string and returns the result as text.
    /// Injectable so tests can verify the script string and return mock data
    /// without touching Messages.app.
    let executor: @Sendable (String) throws -> String

    init(executor: @escaping @Sendable (String) throws -> String = AppleScriptMessageReader.defaultExecutor) {
        self.executor = executor
    }

    /// Returns recent chats from Messages.app sorted by displayName.
    /// Each thread gets a placeholder preview because AppleScript's automation
    /// permission does not expose message content — only chat identity.
    func recentChats() throws -> [MessageThread] {
        let script = """
        tell application "Messages"
            set output to ""
            repeat with theChat in every chat
                try
                    set chatName to name of theChat
                    set chatID to id of theChat
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

    /// Parses newline-delimited "name||chatID" pairs into MessageThread values.
    private func parse(_ raw: String) -> [MessageThread] {
        var threads: [MessageThread] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "||")
            let name   = parts.count > 0 ? parts[0].trimmingCharacters(in: .whitespaces) : trimmed
            let chatID = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            guard !name.isEmpty else { continue }
            threads.append(MessageThread(
                id: chatID ?? name,
                channel: .imessage,
                name: name,
                avatar: IMessageChannel.avatarInitial(for: name),
                preview: "Tap to view conversation",
                time: "",
                chatGUID: chatID
            ))
        }
        return threads.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
