import SwiftUI

struct SetModelView: View {
    private struct Upgrade: Identifiable {
        let id = UUID()
        let name: String
        let desc: String
        let status: String
        var installed: Bool { status == "installed" }
    }
    private let upgrades: [Upgrade] = [
        .init(name: "ReplyAI-13B · q4", desc: "Higher quality, 2.1× slower",    status: "download"),
        .init(name: "ReplyAI-7B · q8",  desc: "Marginally better, needs 9 GB RAM", status: "download"),
        .init(name: "ReplyAI-3B · q4",  desc: "Tiny, for older Macs",           status: "installed"),
    ]

    var body: some View {
        SettingsShell(active: .model) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Model")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                HStack(alignment: .top, spacing: 12) {
                    activeCard.frame(maxWidth: .infinity)
                    upgradesCard.frame(maxWidth: .infinity)
                }
                .padding(.top, 24)
            }
        }
    }

    private var activeCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVE MODEL")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.accent)
                Text("ReplyAI-7B · q4")
                    .font(Theme.Font.sans(22))
                    .tracking(-0.44)
                    .foregroundStyle(Theme.Color.fg)
                    .padding(.top, 8)
                Text("sha256: 7e9a…f4c1 · 4.2 GB · on-disk")
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Color.fgMute)

                HStack(spacing: 14) {
                    StatBlock(label: "Tokens/s",   value: "83.1")
                    StatBlock(label: "Cold start", value: "112ms")
                    StatBlock(label: "Memory",     value: "4.8GB")
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var upgradesCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("AVAILABLE UPGRADES")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)

                VStack(spacing: 0) {
                    ForEach(upgrades) { m in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                    .font(Theme.Font.sans(13))
                                    .foregroundStyle(Theme.Color.fg)
                                Text(m.desc)
                                    .font(Theme.Font.sans(11))
                                    .foregroundStyle(Theme.Color.fgMute)
                            }
                            Spacer()
                            Text(m.status)
                                .font(Theme.Font.sans(11, weight: .medium))
                                .foregroundStyle(m.installed ? Theme.Color.accent : Theme.Color.fgDim)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if m.id != upgrades.last?.id {
                                Rectangle().fill(Theme.Color.line).frame(height: 1)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

