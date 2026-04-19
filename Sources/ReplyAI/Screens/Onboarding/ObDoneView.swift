import SwiftUI

/// `ob-done` — ready; hand off to main app.
struct ObDoneView: View {
    var body: some View {
        OnboardingStage(
            step: 9, total: 9,
            eyebrow: "You're ready",
            title: Text("That's it.\n")
                + Text("Your inbox is waiting.")
                    .font(Theme.Font.serifItalic(38))
                    .foregroundColor(Theme.Color.fgDim)
        ) {
            HStack(alignment: .top, spacing: 12) {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("READY")
                            .font(Theme.Font.mono(10))
                            .tracking(1.0)
                            .foregroundStyle(Theme.Color.accent)
                        Text("Voice profile trained on 2,000 of your messages. 4 channels connected. 9 shortcuts in your fingers.")
                            .font(Theme.Font.sans(14))
                            .foregroundStyle(Theme.Color.fgDim)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TIP")
                            .font(Theme.Font.mono(10))
                            .tracking(1.0)
                            .foregroundStyle(Theme.Color.fgMute)
                        Text("Try it on one real reply first. The first time ⌘↵ sends what you would've typed, you'll feel it.")
                            .font(Theme.Font.sans(14))
                            .foregroundStyle(Theme.Color.fgDim)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 12)
        } cta: {
            PrimaryButton(title: "Open ReplyAI", icon: "arrow.right", height: 46, fontSize: 14)
        } secondary: {
            Text("⌘⇧R works from anywhere now.")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }
}
