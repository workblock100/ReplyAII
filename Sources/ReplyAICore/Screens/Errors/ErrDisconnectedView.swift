import SwiftUI

/// `err-disconnected` — channel socket dropped; surface only when it matters.
struct ErrDisconnectedView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                    .fill(Theme.Color.err.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                            .stroke(Theme.Color.err.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "bolt")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Color.err)
            }

            Text("Slack lost its grip.")
                .font(Theme.Font.sans(32))
                .tracking(-0.64)
                .foregroundStyle(Theme.Color.fg)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            Text("The Slack socket closed 4 minutes ago. Your other channels are fine — this one just needs a refresh.")
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Color.fgMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            HStack(spacing: 10) {
                PrimaryButton(title: "Reconnect Slack")
                GhostButton(title: "Hide until tomorrow")
            }

            Text("ERR_WS_CLOSED_1006 · if this keeps happening, check your firewall")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgFaint)
                .padding(.top, 18)
            Spacer()
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg1)
    }
}

