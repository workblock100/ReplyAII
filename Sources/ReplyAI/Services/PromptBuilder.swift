import Foundation

/// Assembles the LLM prompt for a given thread + tone.
///
/// Exists so prompt tuning and truncation logic can be tested in isolation,
/// without wiring up async streaming machinery.
struct PromptBuilder {
    /// Rough token budget for message history. 1 char ≈ 0.25 tokens; we
    /// cap at 2 000 chars to stay well inside a 4 096-token context window
    /// while leaving room for the system prompt and completion.
    static let historyCharBudget = 2_000

    /// User-turn prompt: thread context + instruction line.
    ///
    /// Embedded newlines within individual message texts are collapsed to a
    /// single space so each `speaker: text` pair stays on one line and the
    /// instruction at the bottom is never accidentally continued mid-line.
    static func build(thread: MessageThread, tone: Tone, history: [Message]) -> String {
        var lines: [String] = []
        lines.append("Conversation with \(thread.name) via \(thread.channel.label).")
        lines.append("")
        lines.append("Recent messages (oldest first):")

        let truncated = truncate(history)
        if truncated.isEmpty {
            lines.append("(no messages yet)")
        } else {
            for m in truncated {
                let speaker = m.from == .me ? "me" : thread.name
                let text = m.text.replacingOccurrences(of: "\n", with: " ")
                lines.append("\(speaker): \(text)")
            }
        }

        lines.append("")
        lines.append("Write my next reply in a \(tone.rawValue.lowercased()) tone. Reply text only.")
        return lines.joined(separator: "\n")
    }

    /// System-turn prompt describing the assistant's role and tone.
    static func systemPrompt(tone: Tone) -> String {
        let base = """
        You are ReplyAI, a drafting assistant embedded in the user's messaging inbox. \
        You write the user's next reply in their own voice. Output ONLY the reply text \
        itself — no preamble, no apology, no meta-commentary. Keep replies concise and \
        conversational; these are text messages, not essays.
        """
        switch tone {
        case .warm:
            return base + " Use a warm, friendly tone. Light emoji are fine. Avoid sounding corporate."
        case .direct:
            return base + " Be direct. Short. Lowercase. Get to the point. No filler."
        case .playful:
            return base + " Be playful and witty with dry humor; occasional emoji are welcome."
        }
    }

    // MARK: - Private

    /// Trims the history from the oldest end so the total character count of
    /// all message texts stays at or below `historyCharBudget`.
    private static func truncate(_ messages: [Message]) -> [Message] {
        var total = 0
        var result: [Message] = []
        for m in messages.reversed() {
            let chars = m.text.count
            if total + chars > historyCharBudget { break }
            total += chars
            result.insert(m, at: 0)
        }
        return result
    }
}
