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
                    // **Do not call `dismiss()` here.** SwiftUI's
                    // `dismiss()` synchronously walks the sheet's
                    // `isPresented` binding back to `false`, which fires
                    // the setter in `InboxScreen.sendConfirmPresented()`
                    // that calls `model.cancelSend()` — nilling
                    // `sendConfirmation` BEFORE the `Task` below ever
                    // runs. The Task's first line is then
                    // `guard let pending = sendConfirmation else { return }`,
                    // and the guard fails: send never fires, no error
                    // toast, no AppleScript trip — user clicks Send and
                    // nothing happens. Fixed 2026-05-19 after Elijah hit
                    // it on the very first real send attempt.
                    //
                    // The sheet still auto-dismisses: `confirmSend()`
                    // sets `sendConfirmation = nil` on its second line,
                    // which makes the binding's `get` return false, and
                    // SwiftUI closes the sheet naturally on the next
                    // render pass. `cancelSend()` then fires from the
                    // setter, but it's a no-op (sendConfirmation already
                    // nil — `cancelSend()` is idempotent).
                    Task { await model.confirmSend() }
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
