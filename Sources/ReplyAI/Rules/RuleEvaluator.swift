import Foundation

/// The bundle of facts a rule predicate is evaluated against. Populated
/// from a MessageThread plus whatever auxiliary state we have (e.g.
/// contact-known from ContactsResolver).
struct RuleContext: Sendable {
    var senderName: String
    var senderHandle: String
    var channel: Channel
    var lastMessageText: String
    var isUnread: Bool
    var senderKnown: Bool

    /// Build a context from a thread + its latest preview. `senderKnown`
    /// is true when the thread's display name differs from its raw
    /// handle — a reasonable proxy for "this is a contact you have" that
    /// doesn't require re-querying Contacts at evaluation time.
    static func from(thread: MessageThread) -> RuleContext {
        RuleContext(
            senderName: thread.name,
            senderHandle: thread.name,
            channel: thread.channel,
            lastMessageText: thread.preview,
            isUnread: thread.unread > 0,
            senderKnown: !thread.name.hasPrefix("+") && !thread.name.contains("@") || !thread.name.allSatisfy {
                "+0123456789 ()-".contains($0)
            }
        )
    }
}

enum RuleEvaluator {
    /// True if the predicate holds against `ctx`.
    static func matches(_ predicate: RulePredicate, in ctx: RuleContext) -> Bool {
        switch predicate {
        case .senderIs(let s):
            return ctx.senderName.caseInsensitiveCompare(s) == .orderedSame

        case .senderContains(let s):
            return ctx.senderName.range(of: s, options: .caseInsensitive) != nil
                || ctx.senderHandle.range(of: s, options: .caseInsensitive) != nil

        case .channelIs(let ch):
            return ctx.channel == ch

        case .textContains(let s):
            return ctx.lastMessageText.range(of: s, options: .caseInsensitive) != nil

        case .textMatchesRegex(let pattern):
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(ctx.lastMessageText.startIndex..., in: ctx.lastMessageText)
            return regex.firstMatch(in: ctx.lastMessageText, range: range) != nil

        case .isUnread:
            return ctx.isUnread

        case .senderUnknown:
            return !ctx.senderKnown

        case .and(let clauses):
            return clauses.allSatisfy { matches($0, in: ctx) }

        case .or(let clauses):
            return clauses.contains { matches($0, in: ctx) }

        case .not(let clause):
            return !matches(clause, in: ctx)
        }
    }

    /// Returns the subset of `rules` that are active AND whose predicate
    /// matches the context, preserving input order.
    static func matching(_ rules: [SmartRule], in ctx: RuleContext) -> [SmartRule] {
        rules.filter { $0.active && matches($0.when, in: ctx) }
    }

    /// Convenience: does any active rule with a `setDefaultTone` action
    /// fire on this context? If so, return that tone — useful for the
    /// composer to pre-select when a user opens the thread.
    static func defaultTone(for rules: [SmartRule], in ctx: RuleContext) -> Tone? {
        for rule in matching(rules, in: ctx) {
            if case .setDefaultTone(let tone) = rule.then { return tone }
        }
        return nil
    }
}
