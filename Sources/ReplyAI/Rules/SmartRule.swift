import Foundation

/// One if-this-then-that automation. Stored on disk at
/// `~/Library/Application Support/ReplyAI/rules.json`.
struct SmartRule: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String        // human-readable label shown in sfc-rules
    var when: RulePredicate
    var then: RuleAction
    var active: Bool
    /// Higher value wins when multiple rules conflict on the same action.
    /// Defaults to 0. Missing from older rules.json files decodes as 0.
    var priority: Int

    init(
        id: UUID = UUID(),
        name: String,
        when: RulePredicate,
        then: RuleAction,
        active: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.when = when
        self.then = then
        self.active = active
        self.priority = priority
    }
}

// MARK: - Codable (hand-written to keep priority backward-compatible)

extension SmartRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, when, then, active, priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,          forKey: .id)
        name     = try c.decode(String.self,        forKey: .name)
        when     = try c.decode(RulePredicate.self, forKey: .when)
        then     = try c.decode(RuleAction.self,    forKey: .then)
        active   = try c.decode(Bool.self,          forKey: .active)
        priority = try c.decodeIfPresent(Int.self,  forKey: .priority) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(name,     forKey: .name)
        try c.encode(when,     forKey: .when)
        try c.encode(then,     forKey: .then)
        try c.encode(active,   forKey: .active)
        try c.encode(priority, forKey: .priority)
    }
}

/// Composable predicate. Encoded with a `kind` discriminator so the
/// on-disk rules.json is legible and hand-editable.
indirect enum RulePredicate: Hashable, Sendable {
    case senderIs(String)
    case senderContains(String)
    case channelIs(Channel)
    case textContains(String)
    case textMatchesRegex(String)
    case isUnread
    case senderUnknown        // no matching Contact
    case and([RulePredicate])
    case or([RulePredicate])
    case not(RulePredicate)
}

/// Consequence of a rule matching. Intentionally small for v1 — we add
/// more once the basics are exercised.
enum RuleAction: Hashable, Sendable {
    case archive
    case pin
    case setDefaultTone(Tone)
    case silentlyIgnore
    case markDone
}

// MARK: - Codable (hand-written for readable JSON)

extension RulePredicate: Codable {
    private enum Kind: String, Codable {
        case senderIs         = "sender_is"
        case senderContains   = "sender_contains"
        case channelIs        = "channel_is"
        case textContains     = "text_contains"
        case textMatchesRegex = "text_matches_regex"
        case isUnread         = "is_unread"
        case senderUnknown    = "sender_unknown"
        case and, or, not
    }

    private enum CodingKeys: String, CodingKey { case kind, value, clauses, clause }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .senderIs:         self = .senderIs(try c.decode(String.self, forKey: .value))
        case .senderContains:   self = .senderContains(try c.decode(String.self, forKey: .value))
        case .channelIs:        self = .channelIs(try c.decode(Channel.self, forKey: .value))
        case .textContains:     self = .textContains(try c.decode(String.self, forKey: .value))
        case .textMatchesRegex: self = .textMatchesRegex(try c.decode(String.self, forKey: .value))
        case .isUnread:         self = .isUnread
        case .senderUnknown:    self = .senderUnknown
        case .and:              self = .and(try c.decode([RulePredicate].self, forKey: .clauses))
        case .or:               self = .or(try c.decode([RulePredicate].self, forKey: .clauses))
        case .not:              self = .not(try c.decode(RulePredicate.self, forKey: .clause))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .senderIs(let s):         try c.encode(Kind.senderIs, forKey: .kind);         try c.encode(s, forKey: .value)
        case .senderContains(let s):   try c.encode(Kind.senderContains, forKey: .kind);   try c.encode(s, forKey: .value)
        case .channelIs(let ch):       try c.encode(Kind.channelIs, forKey: .kind);        try c.encode(ch, forKey: .value)
        case .textContains(let s):     try c.encode(Kind.textContains, forKey: .kind);     try c.encode(s, forKey: .value)
        case .textMatchesRegex(let s): try c.encode(Kind.textMatchesRegex, forKey: .kind); try c.encode(s, forKey: .value)
        case .isUnread:                try c.encode(Kind.isUnread, forKey: .kind)
        case .senderUnknown:           try c.encode(Kind.senderUnknown, forKey: .kind)
        case .and(let xs):             try c.encode(Kind.and, forKey: .kind); try c.encode(xs, forKey: .clauses)
        case .or(let xs):              try c.encode(Kind.or, forKey: .kind);  try c.encode(xs, forKey: .clauses)
        case .not(let x):              try c.encode(Kind.not, forKey: .kind); try c.encode(x, forKey: .clause)
        }
    }
}

extension RuleAction: Codable {
    private enum Kind: String, Codable {
        case archive, pin, silentlyIgnore = "silently_ignore", markDone = "mark_done", setDefaultTone = "set_default_tone"
    }
    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .archive:        self = .archive
        case .pin:            self = .pin
        case .silentlyIgnore: self = .silentlyIgnore
        case .markDone:       self = .markDone
        case .setDefaultTone: self = .setDefaultTone(try c.decode(Tone.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .archive:                try c.encode(Kind.archive, forKey: .kind)
        case .pin:                    try c.encode(Kind.pin, forKey: .kind)
        case .silentlyIgnore:         try c.encode(Kind.silentlyIgnore, forKey: .kind)
        case .markDone:               try c.encode(Kind.markDone, forKey: .kind)
        case .setDefaultTone(let t):  try c.encode(Kind.setDefaultTone, forKey: .kind); try c.encode(t, forKey: .value)
        }
    }
}

// MARK: - Seed rules

extension SmartRule {
    /// First-run defaults — match the demo rules from sfc-rules in the
    /// design handoff so a fresh install shows something recognizable.
    static let seedRules: [SmartRule] = [
        SmartRule(
            name: "Any message contains a 2FA code",
            when: .textMatchesRegex(#"(?i)\b(\d{6}|verification code|2fa)\b"#),
            then: .archive
        ),
        SmartRule(
            name: #"Slack DM from @maya-chen with "deck""#,
            when: .and([
                .channelIs(.slack),
                .senderContains("maya"),
                .textContains("deck"),
            ]),
            then: .setDefaultTone(.direct)
        ),
        SmartRule(
            name: "WhatsApp voice memo > 30s",
            when: .and([
                .channelIs(.whatsapp),
                .textContains("[voice-memo"),
            ]),
            then: .pin
        ),
        SmartRule(
            name: "Newsletter from any @*substack.com",
            when: .senderContains("@substack.com"),
            then: .silentlyIgnore,
            active: false
        ),
    ]
}
