import SwiftUI

/// `ob-channel-detail` — Slack OAuth loopback flow.
struct ObChannelDetailView: View {
    @State private var rotation: Double = 0

    var body: some View {
        OnboardingStage(
            step: 5, total: 9,
            eyebrow: "Connecting · Slack",
            title: Text("Sign in to your Slack workspace")
        ) {
            HStack(alignment: .top, spacing: 24) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                waitingCard
                    .frame(width: 380)
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Open Slack in browser", icon: "arrow.up.right")
        } secondary: {
            GhostButton(title: "Use a different workspace")
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Concatenate inline spans as Text (only Text-returning modifiers
            // compose via `+`); apply view-level spacing once on the outer.
            (Text("We'll use Slack's OAuth + Socket Mode to read new messages in real-time. The bot identity is ")
                .font(Theme.Font.sans(14))
                .foregroundColor(Theme.Color.fgDim)
             + Text("@replyai-assistant")
                .font(Theme.Font.mono(13))
                .foregroundColor(Theme.Color.accent)
             + Text(" — it only reads threads you've joined, and posts nothing on its own.")
                .font(Theme.Font.sans(14))
                .foregroundColor(Theme.Color.fgDim))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("SCOPES REQUESTED")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                Text("channels:history · groups:history · im:history · mpim:history\nusers:read · team:read")
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Color.fgDim)
                    .lineSpacing(8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                    .stroke(Theme.Color.line, lineWidth: 1)
            )
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var waitingCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("WAITING FOR AUTHORIZATION")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                HStack(spacing: 12) {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                    Text("Listening on localhost:4242…")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.fgDim)
                }
                (Text("A browser window should have opened. If not, ")
                    .font(Theme.Font.sans(11))
                    .foregroundColor(Theme.Color.fgMute)
                 + Text("click here to retry")
                    .font(Theme.Font.sans(11))
                    .foregroundColor(Theme.Color.accent)
                    .underline()
                 + Text(".")
                    .font(Theme.Font.sans(11))
                    .foregroundColor(Theme.Color.fgMute))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
