import SwiftUI

/// Two-button confirmation sheet presented before we AppleScript into
/// Messages.app. Required gate for v1 — the stub LLM can generate
/// nonsense, so every send goes through a deliberate click.
struct SendConfirmSheet: View {
    @Bindable var model: InboxViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pending = model.sendConfirmation

        return VStack(alignment: .leading, spacing: 18) {
            header

            if let pending {
                Text(pending.text)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fg)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text("ReplyAI will type this into Messages as you. The first send asks you to allow automation of Messages in System Settings.")
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                GhostButton(title: "Cancel") {
                    model.cancelSend()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                PrimaryButton(title: "Send ↵", icon: "paperplane.fill") {
                    Task { await model.confirmSend() }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.Color.bg2)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        let pending = model.sendConfirmation
        return VStack(alignment: .leading, spacing: 6) {
            Text("Send to \(pending?.recipient ?? "…")")
                .font(Theme.Font.sans(17, weight: .semibold))
                .tracking(-0.17)
                .foregroundStyle(Theme.Color.fg)
            if let pending {
                Text("via \(pending.channel.label) · tone \(pending.tone.rawValue)")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }
        }
    }
}
