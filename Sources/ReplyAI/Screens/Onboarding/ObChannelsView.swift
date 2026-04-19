import SwiftUI

/// `ob-channels` — per-channel connect entry points.
struct ObChannelsView: View {
    private struct Entry { let channel: Channel; let label: String; let tag: String; let desc: String; let status: Status
        enum Status { case connected, pending, idle
            var color: Color {
                switch self {
                case .connected: Theme.Color.accent
                case .pending:   Theme.Color.warn
                case .idle:      Theme.Color.fgMute
                }
            }
            var label: String {
                switch self {
                case .connected: "Connected"
                case .pending:   "Authenticating…"
                case .idle:      "Connect"
                }
            }
        }
    }

    private let channels: [Entry] = [
        .init(channel: .imessage, label: "iMessage",  tag: "Stable", desc: "Via local chat.db",       status: .connected),
        .init(channel: .slack,    label: "Slack",     tag: "Stable", desc: "OAuth + Socket Mode",     status: .pending),
        .init(channel: .whatsapp, label: "WhatsApp",  tag: "Stable", desc: "Multi-device pairing",    status: .idle),
        .init(channel: .sms,      label: "SMS",       tag: "Stable", desc: "Via Messages forwarding", status: .connected),
        .init(channel: .teams,    label: "MS Teams",  tag: "Beta",   desc: "Graph API",               status: .idle),
        .init(channel: .telegram, label: "Telegram",  tag: "Beta",   desc: "TDLib",                   status: .idle),
    ]

    var body: some View {
        OnboardingStage(
            step: 4, total: 9,
            eyebrow: "Connect channels",
            title: Text("Pick the places people actually text you.\n")
                + Text("You can always add more later.")
                    .font(Theme.Font.serifItalic(38))
                    .foregroundColor(Theme.Color.fgDim),
            help: "Connecting a channel lets ReplyAI read threads on your Mac. Nothing is uploaded."
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(channels, id: \.label) { entry in
                    channelCard(entry)
                }
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Continue", icon: "arrow.right")
        } secondary: {
            GhostButton(title: "Skip — connect later")
        }
    }

    private func channelCard(_ e: Entry) -> some View {
        Card(
            padding: 20,
            borderColor: e.status == .connected ? Theme.Color.accent.opacity(0.25) : Theme.Color.line
        ) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [e.channel.dotColor, e.channel.dotColor.mix(with: .black, amount: 0.45)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: channelSymbol(e.channel))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(e.label)
                            .font(Theme.Font.sans(14, weight: .medium))
                            .foregroundStyle(Theme.Color.fg)
                        Text(e.tag.uppercased())
                            .font(Theme.Font.mono(10))
                            .tracking(0.9)
                            .foregroundStyle(Theme.Color.fgMute)
                    }
                    Text(e.desc)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Color.fgMute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if e.status == .connected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(e.status.color)
                    }
                    Text(e.status.label)
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(e.status.color)
                }
            }
        }
    }

    private func channelSymbol(_ c: Channel) -> String {
        switch c {
        case .imessage: "bubble.left.fill"
        case .slack:    "number"
        case .whatsapp: "phone.fill"
        case .sms:      "message.fill"
        case .teams:    "person.2.fill"
        case .telegram: "paperplane.fill"
        }
    }
}
