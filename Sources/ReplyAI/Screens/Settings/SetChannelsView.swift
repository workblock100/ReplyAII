import SwiftUI

struct SetChannelsView: View {
    struct Row: Identifiable {
        let id = UUID()
        let channel: Channel
        let label: String
        let status: Status
        let last: String
        let threads: Int
        enum Status { case connected, error, disconnected
            var color: Color {
                switch self {
                case .connected:    Theme.Color.accent
                case .error:        Theme.Color.err
                case .disconnected: Theme.Color.fgMute
                }
            }
            var text: String {
                switch self {
                case .connected:    "CONNECTED"
                case .error:        "ERROR"
                case .disconnected: "DISCONNECTED"
                }
            }
        }
    }

    private let rows: [Row] = [
        .init(channel: .imessage, label: "iMessage",          status: .connected,    last: "3s ago",       threads: 42),
        .init(channel: .slack,    label: "Slack · acme-co",   status: .connected,    last: "just now",     threads: 118),
        .init(channel: .whatsapp, label: "WhatsApp",          status: .connected,    last: "12m ago",      threads: 28),
        .init(channel: .sms,      label: "SMS",               status: .connected,    last: "1m ago",       threads: 14),
        .init(channel: .teams,    label: "Microsoft Teams",   status: .error,        last: "auth expired", threads: 0),
        .init(channel: .telegram, label: "Telegram",          status: .disconnected, last: "never",        threads: 0),
    ]

    var body: some View {
        SettingsShell(active: .channels) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Channels")
                        .font(Theme.Font.sans(26))
                        .tracking(-0.52)
                        .foregroundStyle(Theme.Color.fg)
                    Spacer()
                    PrimaryButton(title: "+ Add channel")
                }

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        channelRow(row)
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    private func channelRow(_ row: Row) -> some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                .fill(row.channel.dotColor.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: channelSymbol(row.channel))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(row.channel.dotColor)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fg)
                Text("\(row.threads) threads · \(row.last)")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            Text(row.status.text)
                .font(Theme.Font.mono(11))
                .tracking(0.9)
                .foregroundStyle(row.status.color)
            MiniButton(title: "Settings")
            MiniButton(
                title: row.status == .connected ? "Disconnect" : "Reconnect",
                kind: row.status == .connected ? .secondary : .ghost
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
        .overlay(alignment: .bottom) {
            if row.id == rows.last?.id {
                Rectangle().fill(Theme.Color.line).frame(height: 1)
            }
        }
    }

    private func channelSymbol(_ c: Channel) -> String {
        switch c {
        case .imessage: "bubble.left.fill"
        case .slack:    "number"
        case .whatsapp: "message.fill"
        case .sms:      "message"
        case .teams:    "person.2.fill"
        case .telegram: "paperplane.fill"
        }
    }
}

