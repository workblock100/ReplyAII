import Foundation

/// Assembles the LLM prompt for a given thread + tone.
///
/// Exists so prompt tuning and truncation logic can be tested in isolation,
/// without wiring up async streaming machinery.
public struct PromptBuilder {
    /// Rough token budget for message history. 1 char ≈ 0.25 tokens; we
    /// cap at 2 000 chars to stay well inside a 4 096-token context window
    /// while leaving room for the system prompt and completion.
    static let historyCharBudget = 2_000

    /// Prompt-template vocabulary. These literals are load-bearing: each
    /// one frames how the model interprets a section of the prompt
    /// (`Template.recentMessagesHeader`'s "(oldest first)" parenthetical,
    /// `Template.emptyHistoryFallback`'s parenthesized form that signals
    /// "metadata, not user text", `Template.userInstructionSuffix`'s
    /// "Reply text only." that suppresses preamble). Re-typing these at
    /// every reader/writer is the kind of drift that quietly degrades
    /// completion quality on long threads. Hoisted to a `Template` enum
    /// so every reader threads through one source of truth and a
    /// deliberate copy edit shows up as a single-line diff. Pinned by
    /// `PromptBuilderTests.testPromptTemplateLiteralsAreFrozen`.
    enum Template {
        static let voiceExamplesHeader  = "Style examples from the user's prior messages:"
        static let recentMessagesHeader = "Recent messages (oldest first):"
        static let emptyHistoryFallback = "(no messages yet)"
        static let speakerSelf          = "me"
        static let userInstructionSuffix = " tone. Reply text only."

        /// User-prompt header format: thread name + channel label.
        /// Hoisted from the inline `lines.append(...)` in `build` so
        /// the prompt-shape contract that the LLM has been trained
        /// against doesn't drift as a side effect of an unrelated
        /// edit. Drift here changes the very first user-turn line the
        /// model sees on every draft. Pinned by `PromptBuilderTests`'
        /// `*HeaderFormat*` cluster.
        static func threadHeader(name: String, channelLabel: String) -> String {
            "Conversation with \(name) via \(channelLabel)."
        }

        /// Voice-example bullet format. The bullet style anchors the
        /// LLM into "list of examples" mode rather than "next reply"
        /// mode for the voice-examples block. Drift to a different
        /// bullet glyph (e.g. `"* "`, `"• "`) silently changes how
        /// in-context the examples feel to the model.
        static func voiceExampleBullet(_ example: String) -> String {
            "- \(example)"
        }

        /// Per-message line format inside the recent-messages block.
        /// The `<speaker>: <text>` shape is the conversation
        /// representation the LLM has been calibrated against — drift
        /// to e.g. `"<speaker> said: <text>"` or moving the colon
        /// would silently change how the model parses the role of
        /// each line.
        static func messageLine(speaker: String, text: String) -> String {
            "\(speaker): \(text)"
        }

        /// Final user-turn instruction line — the "tell the model
        /// what to do" prefix. Composes with `userInstructionSuffix`
        /// for the full instruction; the prefix part is the verb
        /// ("Write my next reply") that the model uses to anchor
        /// generation. Drift to "Compose" or "Draft" silently
        /// changes the model's framing of its own task.
        static func instructionLine(toneLowercased: String) -> String {
            "Write my next reply in a \(toneLowercased)\(userInstructionSuffix)"
        }
    }

    /// User-turn prompt: thread context + instruction line.
    ///
    /// Embedded newlines within individual message texts are collapsed to a
    /// single space so each `speaker: text` pair stays on one line and the
    /// instruction at the bottom is never accidentally continued mid-line.
    public static func build(
        thread: MessageThread,
        tone: Tone,
        history: [Message],
        voiceExamples: [String] = []
    ) -> String {
        var lines: [String] = []
        lines.append(Template.threadHeader(name: thread.name, channelLabel: thread.channel.label))
        lines.append("")

        if !voiceExamples.isEmpty {
            lines.append(Template.voiceExamplesHeader)
            for example in voiceExamples {
                lines.append(Template.voiceExampleBullet(example))
            }
            lines.append("")
        }

        lines.append(Template.recentMessagesHeader)

        let truncated = truncate(history, budget: Self.historyCharBudget)
        if truncated.isEmpty {
            lines.append(Template.emptyHistoryFallback)
        } else {
            for m in truncated {
                let speaker = m.from == .me ? Template.speakerSelf : thread.name
                let text = m.text.replacingOccurrences(of: "\n", with: " ")
                lines.append(Template.messageLine(speaker: speaker, text: text))
            }
        }

        lines.append("")
        lines.append(Template.instructionLine(toneLowercased: tone.rawValue.lowercased()))
        return lines.joined(separator: "\n")
    }

    /// Minimum chars reserved for message history even when the system prompt is large.
    static let minHistoryReserve = 200

    /// System-turn prompt describing the assistant's role and tone.
    /// If the raw instruction exceeds the history budget, it is truncated so at
    /// least `minHistoryReserve` chars remain for message context.
    public static func systemPrompt(tone: Tone) -> String {
        let raw = rawSystemPrompt(tone: tone)
        let cap = historyCharBudget - minHistoryReserve
        guard raw.count > cap else { return raw }
        return String(raw.prefix(cap))
    }

    // MARK: - Private

    /// System-prompt base + per-tone suffix vocabulary. Hoisted from
    /// the inline literals inside `rawSystemPrompt(tone:)`. The base
    /// instruction (output-only-the-reply-text, no preamble) is the
    /// most load-bearing copy in the entire app — the model's first-
    /// turn instructions determine whether the inbox sees raw replies
    /// or "Sure! Here's a reply:" preambles. Each tone suffix is the
    /// entire signal that distinguishes warm from direct from playful
    /// outputs at inference time. Drift in any of these silently
    /// changes draft style for every shipped user. Pinned by
    /// `PromptBuilderTests.testSystemPromptBaseIsFrozen` and
    /// `testSystemPromptToneSuffixesAreFrozen`.
    enum SystemPrompt {
        /// Common base attached to every tone variant. Sets the
        /// "output-only" contract that suppresses model preambles.
        static let base = """
        You are ReplyAI, a drafting assistant embedded in the user's messaging inbox. \
        You write the user's next reply in their own voice. Output ONLY the reply text \
        itself — no preamble, no apology, no meta-commentary. Keep replies concise and \
        conversational; these are text messages, not essays.
        """

        static let warmSuffix    = " Use a warm, friendly tone. Light emoji are fine. Avoid sounding corporate."
        static let directSuffix  = " Be direct. Short. Lowercase. Get to the point. No filler."
        static let playfulSuffix = " Be playful and witty with dry humor; occasional emoji are welcome."
    }

    private static func rawSystemPrompt(tone: Tone) -> String {
        switch tone {
        case .warm:    return SystemPrompt.base + SystemPrompt.warmSuffix
        case .direct:  return SystemPrompt.base + SystemPrompt.directSuffix
        case .playful: return SystemPrompt.base + SystemPrompt.playfulSuffix
        }
    }

    /// Trims the history from the oldest end so the total character count of
    /// all message texts stays at or below `budget` (defaults to `historyCharBudget`).
    /// The most-recent message (last in the array) is always retained when any
    /// messages survive truncation, so the model always sees the immediate context.
    static func truncate(_ messages: [Message], budget: Int = historyCharBudget) -> [Message] {
        var total = 0
        var result: [Message] = []
        for m in messages.reversed() {
            let chars = m.text.count
            if total + chars > budget { break }
            total += chars
            result.insert(m, at: 0)
        }
        return result
    }
}
