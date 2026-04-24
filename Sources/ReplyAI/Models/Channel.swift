import SwiftUI

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
