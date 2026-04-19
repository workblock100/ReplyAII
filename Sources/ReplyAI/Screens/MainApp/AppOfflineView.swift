import SwiftUI

/// `app-offline` — degraded-but-drafting-still-works state.
struct AppOfflineView: View {
    var body: some View {
        InboxFrame(sidebarBadge: .offline) {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                        .fill(Theme.Color.warn.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                                .stroke(Theme.Color.warn.opacity(0.3), lineWidth: 1)
                        )
                    Image(systemName: "bolt")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Color.warn)
                }

                Text("You're offline.")
                    .font(Theme.Font.sans(24))
                    .tracking(-0.48)
                    .foregroundStyle(Theme.Color.fg)

                Text("Drafts still work — ReplyAI's model is on your Mac. New messages will sync when you're back.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fgMute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                HStack(spacing: 8) {
                    PrimaryButton(title: "Retry connection", height: 36, fontSize: 13)
                    GhostButton(title: "Work offline", height: 36, fontSize: 13)
                }
                .padding(.top, 10)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

