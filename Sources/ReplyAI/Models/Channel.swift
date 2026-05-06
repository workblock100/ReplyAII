import SwiftUI

/// One messaging surface ReplyAI unifies. The raw String values are the
/// on-disk identifier — they're persisted into rules.json, the search
/// index, per-channel Preferences keys, and the chat-list cache, so
/// renaming a case is a migration, not a refactor. Add a new case here
/// only when a corresponding `ChannelService` implementation lands;
/// otherwise the per-channel filter UI ends up offering toggles for
/// channels the inbox can't actually source threads from.
enum Channel: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case imessage
    case whatsapp
    case slack
    case teams
    case sms
    case telegram

    var id: String { rawValue }

    var label: String {
        switch self {
        case .imessage: "iMessage"
        case .whatsapp: "WhatsApp"
        case .slack:    "Slack"
        case .teams:    "Teams"
        case .sms:      "SMS"
        case .telegram: "Telegram"
        }
    }

    /// Human-readable channel name suitable for UI display.
    var displayName: String { label }

    /// SF Symbol name representing this channel.
    var iconName: String {
        switch self {
        case .imessage: "message.fill"
        case .whatsapp: "phone.bubble.fill"
        case .slack:    "number.square.fill"
        case .teams:    "person.3.fill"
        case .sms:      "bubble.left.fill"
        case .telegram: "paperplane.fill"
        }
    }

    /// Per-channel accent color rendered by `ChannelDot` (sidebar list rows,
    /// thread badges, the inbox header chip). Resolves to the
    /// `Theme.Color.channel*` token for the case so the theme owns the
    /// hex values and a future light-mode swap or rebrand only edits
    /// `Theme.swift`. Pinned by `ChannelTests.testDotColorMatchesThemeChannelToken`.
    var dotColor: Color {
        switch self {
        case .imessage: Theme.Color.channelIMessage
        case .whatsapp: Theme.Color.channelWhatsApp
        case .slack:    Theme.Color.channelSlack
        case .teams:    Theme.Color.channelTeams
        case .sms:      Theme.Color.channelSMS
        case .telegram: Theme.Color.channelTelegram
        }
    }
}
