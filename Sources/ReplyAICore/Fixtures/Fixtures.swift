import Foundation

/// Seed data from design_reference/components/reply-app.jsx.
/// Kept verbatim so the SwiftUI surface renders 1:1 with the HTML prototype.
enum Fixtures {
    static let threads: [MessageThread] = [
        .init(id: "t1", channel: .slack,    name: "Maya Chen",         avatar: "MC", preview: "can you review the deck before 4?",        time: "2:41 PM",  unread: 2, pinned: true, contextCount: 41),
        .init(id: "t2", channel: .imessage, name: "Mom",               avatar: "M",  preview: "dont forget sundays dinner ♥",             time: "1:08 PM",  unread: 0,               contextCount: 22),
        .init(id: "t3", channel: .slack,    name: "Ravi (Linear)",     avatar: "RV", preview: "shipped the new billing flow",             time: "12:52 PM", unread: 1,               contextCount: 18),
        .init(id: "t4", channel: .sms,      name: "+1 (415) 555-0134", avatar: "☎",  preview: "verification code: 820193",                time: "11:30 AM", unread: 0,               contextCount: 1),
        .init(id: "t5", channel: .whatsapp, name: "Lena Fischer",      avatar: "LF", preview: "Are we still on for Berlin on the 24th?",  time: "Yesterday",unread: 0,               contextCount: 34),
        .init(id: "t6", channel: .slack,    name: "#design-crit",      avatar: "#",  preview: "jamie: honestly the v3 hero looks insane", time: "Yesterday",unread: 0,               contextCount: 127),
        .init(id: "t7", channel: .imessage, name: "Theo Park",         avatar: "TP", preview: "sending the keys thru the window 🙃",       time: "Mon",      unread: 0,               contextCount: 56),
        .init(id: "t8", channel: .teams,    name: "Nox Eng Standup",   avatar: "NE", preview: "standup in 5",                             time: "Mon",      unread: 0,               contextCount: 208),
    ]

    static let threadMessages: [String: [Message]] = [
        "t1": [
            .init(from: .them, text: "hey, design review happening at 4?", time: "2:31 PM"),
            .init(from: .them, text: "can you review the deck before then? slides 4–9 especially", time: "2:41 PM"),
        ],
        "t3": [
            .init(from: .them, text: "shipped the new billing flow — stripe webhooks are live", time: "12:48 PM"),
            .init(from: .them, text: "will send a loom tonight", time: "12:52 PM"),
        ],
    ]

    /// Ready-made drafts ReplyAI suggests. Match [reply-app.jsx:37].
    static let drafts: [String: [Tone: String]] = [
        "t1": [
            .warm:    "Yes! Looking at it now — I'll leave inline comments on 4–9 before the meeting.",
            .direct:  "On it. Comments incoming on 4–9 before 4.",
            .playful: "Already in the deck pretending to be helpful 🫡 — comments landing soon.",
        ],
        "t3": [
            .warm:    "Huge — thanks for pushing this through. Loom when you get a sec 🙏",
            .direct:  "Nice. Send the Loom whenever it's ready.",
            .playful: "Billing flow, finally unshackled. Will stare at the Loom lovingly.",
        ],
    ]

    static let folders: [Folder] = [
        .init(id: .all,      label: "Unified Inbox",   count: 14),
        .init(id: .priority, label: "Priority",        count: 3),
        .init(id: .awaiting, label: "Awaiting reply",  count: 6),
        .init(id: .snoozed,  label: "Snoozed",         count: 2),
        .init(id: .done,     label: "Replied",         count: 812),
    ]

    static let sidebarChannels: [Channel] = [.imessage, .whatsapp, .slack, .teams, .sms, .telegram]

    /// Demo threads shown when no real channel returns data.
    /// Lets a brand-new user see what the app looks like without granting any
    /// permissions. Replaced by real threads as soon as a sync returns ≥1 result.
    /// (REP-228 / 2026-04-23 pivot — channel-agnostic demo experience.)
    static let demoChatThreads: [MessageThread] = [
        .init(id: "demo-1", channel: .imessage, name: "ReplyAI",       avatar: "R",  preview: "Welcome — try ⌘K to open the palette, ⌘↵ to send, ⌘J to regenerate.", time: "now",     unread: 1, pinned: true, contextCount: 1),
        .init(id: "demo-2", channel: .imessage, name: "Sarah Klein",   avatar: "SK", preview: "still on for thursday? want to grab dinner around 7",                  time: "2 min",   unread: 1,               contextCount: 12),
        .init(id: "demo-3", channel: .slack,    name: "#design-crit",  avatar: "#",  preview: "jamie: pushed v3 of the hero — would love eyes before EOD",            time: "12 min",  unread: 2,               contextCount: 47),
        .init(id: "demo-4", channel: .imessage, name: "Mom",           avatar: "M",  preview: "Don't forget Sunday dinner ♥",                                          time: "1:08 PM", unread: 0,               contextCount: 22),
        .init(id: "demo-5", channel: .slack,    name: "Maya Chen",     avatar: "MC", preview: "thanks for the review notes — landing changes now",                    time: "Mon",     unread: 0,               contextCount: 41),
        .init(id: "demo-6", channel: .whatsapp, name: "Lena Fischer",  avatar: "LF", preview: "berlin trip — should we book the airbnb in mitte or kreuzberg?",       time: "Sun",     unread: 0,               contextCount: 34),
    ]

    static func messages(forThread threadID: String, fallback preview: String, time: String) -> [Message] {
        if let msgs = threadMessages[threadID] { return msgs }
        return [.init(from: .them, text: preview, time: time)]
    }

    /// Curated context summaries for the design-time fixture threads.
    /// Returns nil for any thread we don't have a hand-written summary for —
    /// the view layer treats nil as "hide the context card" so real chat.db
    /// threads don't render a placeholder ("Live thread — context will land
    /// once on-device summarization is wired.") that admits the feature is
    /// stubbed.
    static func contextSummary(for threadID: String) -> String? {
        switch threadID {
        case "t1": return "Design review is at 4pm. You have the deck open in Figma. Maya usually wants specific line-edits, not vibes."
        case "t3": return "Ravi shipped the billing flow yesterday; Stripe webhooks are live. He owes you a Loom."
        default:   return nil
        }
    }

    static func seedDraft(threadID: String, tone: Tone) -> String {
        if let d = drafts[threadID]?[tone] { return d }
        return genericAcknowledgment(tone: tone)
    }

    /// Tone-appropriate placeholder used for live threads until a real
    /// on-device model is wired. Avoids leaking fixture-specific text
    /// (like "review the deck") into unrelated real conversations.
    static func genericAcknowledgment(tone: Tone) -> String {
        switch tone {
        case .warm:    return "Thanks for the heads up — I'll circle back on this shortly."
        case .direct:  return "got it. back to you in a bit."
        case .playful: return "Consider it received. A thoughtful reply is compiling 🙃"
        }
    }

    /// Baseline confidence from the stub. cmp-lowconf only triggers for threads without context.
    static func seedConfidence(threadID: String, tone: Tone) -> Double {
        switch threadID {
        case "t1", "t3": return 0.86
        case "t4":       return 0.32   // just a verification code — refuse to guess
        default:         return 0.62
        }
    }

    /// Accumulates the "Learned from N of your {channel} replies" caption.
    /// Varies only by channel so the number stays stable while iterating.
    static func replyCount(for channel: Channel) -> Int {
        switch channel {
        case .imessage: return 3_411
        case .slack:    return 1_204
        case .whatsapp: return 612
        case .sms:      return 221
        case .teams:    return 184
        case .telegram: return 54
        }
    }
}
