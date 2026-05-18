import SwiftUI

/// `ob-welcome` — 3-point welcome grid after first open.
struct ObWelcomeView: View {
    private struct Step { let k: String; let t: String; let d: String }
    private let steps: [Step] = [
        .init(k: "01", t: "Connect your channels", d: "iMessage, Slack, WhatsApp, Teams, SMS. One app."),
        .init(k: "02", t: "Teach it your voice",   d: "A 60-second paste job. On-device, never uploaded."),
        .init(k: "03", t: "Reply faster than ever", d: "⌘↵ to send. ⌘J to regenerate. Your inbox, quietly handled."),
    ]

    var body: some View {
        OnboardingStage(
            step: 1, total: 9,
            eyebrow: "Welcome",
            title: Text("Your inbox is about to get a lot quieter.\n")
                + Text("Let's spend four minutes setting it up.")
                    .font(Theme.Font.serifItalic(38))
                    .foregroundColor(Theme.Color.fgDim)
        ) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(steps, id: \.k) { s in
                    Card(padding: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.k)
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Color.accent)
                            Text(s.t)
                                .font(Theme.Font.sans(16, weight: .medium))
                                .foregroundStyle(Theme.Color.fg)
                            Text(s.d)
                                .font(Theme.Font.sans(12))
                                .foregroundStyle(Theme.Color.fgMute)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 12)
        } cta: {
            PrimaryButton(title: "Get started", icon: "arrow.right")
        } secondary: {
            Text("macOS 14.4 · Apple Silicon · 48MB")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }
}
