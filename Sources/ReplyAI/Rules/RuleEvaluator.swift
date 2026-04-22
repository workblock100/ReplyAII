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
    /// Raw chat identifier from chat.db — "chat1234567890" for group chats,
    /// "+14155551234" or "user@example.com" for 1:1 threads.
    var chatIdentifier: String
    /// True when the last message has `cache_has_attachments = 1` in chat.db.
    var hasAttachment: Bool = false
    /// Timestamp of the last message in the thread. Defaults to `Date()` when
    /// the thread source cannot supply a real date, so `messageAgeOlderThan`
    /// does not accidentally fire on threads with unknown ages.
    var lastMessageDate: Date = Date()

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
            },
            chatIdentifier: thread.id,
            hasAttachment: thread.hasAttachment
        )
    }
}

enum RuleEvaluator {
    /// True if the predicate holds against `ctx`.
    /// - Parameter currentDate: The reference "now" for time-based predicates.
    ///   Defaults to `Date()`. Pass a fixed value in tests to avoid clock
    ///   sensitivity.
    static func matches(
        _ predicate: RulePredicate,
        in ctx: RuleContext,
        currentDate: Date = Date()
    ) -> Bool {
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

        case .isGroupChat:
            return ctx.channel == .imessage && ctx.chatIdentifier.hasPrefix("chat")

        case .hasAttachment:
            return ctx.hasAttachment

        case .and(let clauses):
            return clauses.allSatisfy { matches($0, in: ctx, currentDate: currentDate) }

        case .or(let clauses):
            return clauses.contains { matches($0, in: ctx, currentDate: currentDate) }

        case .not(let clause):
            return !matches(clause, in: ctx, currentDate: currentDate)

        case .messageAgeOlderThan(let hours):
            return currentDate.timeIntervalSince(ctx.lastMessageDate) > Double(hours) * 3600
        }
    }

    /// Returns the subset of `rules` that are active AND whose predicate
    /// matches the context, sorted by priority DESC. Original insertion
    /// order is the tiebreaker for equal-priority rules (stable sort).
    static func matching(_ rules: [SmartRule], in ctx: RuleContext) -> [SmartRule] {
        // Enumerate first so we can use offset as a stable tiebreaker.
        rules
            .enumerated()
            .filter { _, rule in rule.active && matches(rule.when, in: ctx) }
            .sorted { lhs, rhs in
                lhs.element.priority != rhs.element.priority
                    ? lhs.element.priority > rhs.element.priority
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
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

    /// Evaluates `rules` against `ctx` and returns the (ruleID, action) pairs
    /// that fired — same result as `matching` but shaped for debug surfaces that
    /// need IDs rather than full `SmartRule` values.
    static func apply(rules: [SmartRule], to ctx: RuleContext) -> [(ruleID: UUID, action: RuleAction)] {
        matching(rules, in: ctx).map { (ruleID: $0.id, action: $0.then) }
    }
}
