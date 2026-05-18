import SwiftUI

/// `sfc-notification` — UNNotification inline reply card on a blurred desktop.
struct SfcNotificationView: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            desktop
            notification
                .padding(.top, 44)
                .padding(.trailing, 44)
        }
        .frame(minWidth: 1180, minHeight: 720)
        .overlay(alignment: .bottomLeading) {
            Text("Reply inline from a notification. Never open the app.")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.leading, 40)
                .padding(.bottom, 40)
        }
    }

    private var desktop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.165, green: 0.188, blue: 0.251),
                Color(red: 0.039, green: 0.043, blue: 0.051),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var notification: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.Color.accent)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("R")
                            .font(Theme.Font.sans(11, weight: .bold))
                            .foregroundStyle(Theme.Color.accentInk)
                    )
                Text("REPLYAI")
                    .font(Theme.Font.sans(12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                Spacer()
                Text("now")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.bottom, 10)

            Text("Maya Chen · Slack")
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundStyle(.white)
            Text("can you review the deck before 4? slides 4–9 especially")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineSpacing(3)
                .padding(.top, 2)

            draftSuggestion
                .padding(.top, 10)

            HStack(spacing: 6) {
                actionButton("Send ↵", primary: true)
                actionButton("Edit",   primary: false)
                actionButton("⌥S",      primary: false, fixedWidth: true)
            }
            .padding(.top, 10)
        }
        .padding(14)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Color(red: 0.118, green: 0.125, blue: 0.141).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }

    private var draftSuggestion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DRAFT")
                .font(Theme.Font.mono(9))
                .tracking(1.0)
                .foregroundStyle(Theme.Color.accent)
            Text("On it — comments on 4–9 before 4.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                .fill(Theme.Color.accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func actionButton(_ title: String, primary: Bool, fixedWidth: Bool = false) -> some View {
        let bg: Color = primary ? Theme.Color.accent : Color.white.opacity(primary ? 0.08 : 0.04)
        let fg: Color = primary ? Theme.Color.accentInk : Color.white.opacity(0.85)
        return Text(title)
            .font(Theme.Font.sans(11, weight: primary ? .semibold : .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, fixedWidth ? 10 : 0)
            .frame(height: 28)
            .frame(maxWidth: fixedWidth ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                    .fill(bg)
            )
    }
}
