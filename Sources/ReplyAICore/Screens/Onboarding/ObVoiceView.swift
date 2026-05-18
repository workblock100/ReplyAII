import SwiftUI

/// `ob-voice` — train voice profile from pasted messages.
struct ObVoiceView: View {
    @State private var pasted: String = """
    on my way, give me 10
    hahaha okay yes fine I'll send it
    can we push to tmrw? something came up
    sounds good — let me know how it lands
    oof. brutal week. coffee this weekend?
    ...
    """

    private struct ChannelCount { let label: String; let value: String }
    private let autoImports: [ChannelCount] = [
        .init(label: "iMessage", value: "1,204 msgs"),
        .init(label: "Slack",    value: "612 msgs"),
        .init(label: "WhatsApp", value: "184 msgs"),
    ]

    var body: some View {
        OnboardingStage(
            step: 6, total: 9,
            eyebrow: "Voice sample",
            title: Text("Teach ReplyAI how ") + Text("you").font(Theme.Font.serifItalic(38)) + Text(" text."),
            help: "About 200 of your messages is enough. We'll process them locally — this takes ~45 seconds."
        ) {
            HStack(alignment: .top, spacing: 16) {
                pasteCard
                autoImportCard
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Train voice profile", icon: "sparkles")
        } secondary: {
            GhostButton(title: "Skip — use generic voice")
        }
    }

    private var pasteCard: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste 20–30 messages you've sent recently")
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)

                TextEditor(text: $pasted)
                    .scrollContentBackground(.hidden)
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Color.fgDim)
                    .lineSpacing(5)
                    .padding(14)
                    .frame(minHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                            .fill(Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                            .stroke(Theme.Color.line, lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Text("214 messages detected")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Color.fgMute)
                    Text("·").font(Theme.Font.mono(11)).foregroundStyle(Theme.Color.fgMute)
                    Text("ready to train")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var autoImportCard: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Or let ReplyAI read them for you")
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
                Text("Pull the last 2,000 messages you sent across all connected channels. Locally.")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(autoImports, id: \.label) { row in
                        HStack(spacing: 10) {
                            Circle().fill(Theme.Color.accent).frame(width: 6, height: 6)
                            Text(row.label)
                                .font(Theme.Font.sans(12))
                                .foregroundStyle(Theme.Color.fgDim)
                            Spacer()
                            Text(row.value)
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Color.fgMute)
                        }
                    }
                }

                Button {} label: {
                    Text("Auto-import from connected channels")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Color.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                                .fill(Theme.Color.accent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                                .stroke(Theme.Color.accent.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 340)
    }
}
