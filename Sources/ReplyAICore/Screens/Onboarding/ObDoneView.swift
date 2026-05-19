import SwiftUI

/// `ob-done` — ready; hand off to main app.
///
/// REP-259: when `Preferences.demoModeActive == true` after onboarding
/// (no real channel has surfaced threads — typical when the user skipped
/// FDA / Slack / Contacts), this screen acknowledges that state and
/// presents a Limited Mode CTA + clarifying copy instead of the
/// full-permission "Open ReplyAI" hand-off. The user still lands in the
/// inbox; the inbox itself renders LimitedModeBanner explaining demo
/// data and how to grant permissions.
struct ObDoneView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.demoModeActive) private var demoModeActive = PreferenceDefaults.demoModeActive

    /// Pinned copy. The Limited Mode variant lives next to the default
    /// so a copy review covers both states at once.
    enum Strings {
        static let defaultEyebrow      = "You're ready"
        static let defaultTitleLead    = "That's it.\n"
        static let defaultTitleTail    = "Your inbox is waiting."
        static let defaultReadyDetail  = "Voice profile trained on 2,000 of your messages. 4 channels connected. 9 shortcuts in your fingers."
        static let defaultCTA          = "Open ReplyAI"
        static let defaultSecondary    = "⌘⇧R works from anywhere now."

        static let limitedEyebrow      = "You're set up — for now"
        static let limitedTitleLead    = "Try it on "
        static let limitedTitleTail    = "demo conversations."
        static let limitedReadyDetail  = "You skipped some permissions, so ReplyAI will start in Limited Mode with sample threads. Grant access from Settings any time to see your real messages."
        static let limitedCTA          = "Continue in Limited Mode"
        static let limitedSecondary    = "You can grant permissions later in Settings."
    }

    var body: some View {
        OnboardingStage(
            step: 9, total: 9,
            eyebrow: demoModeActive ? Strings.limitedEyebrow : Strings.defaultEyebrow,
            title: demoModeActive
                ? Text(Strings.limitedTitleLead)
                    + Text(Strings.limitedTitleTail)
                        .font(Theme.Font.serifItalic(38))
                        .foregroundColor(Theme.Color.fgDim)
                : Text(Strings.defaultTitleLead)
                    + Text(Strings.defaultTitleTail)
                        .font(Theme.Font.serifItalic(38))
                        .foregroundColor(Theme.Color.fgDim)
        ) {
            HStack(alignment: .top, spacing: 12) {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(demoModeActive ? "LIMITED" : "READY")
                            .font(Theme.Font.mono(10))
                            .tracking(1.0)
                            .foregroundStyle(demoModeActive ? Theme.Color.warn : Theme.Color.accent)
                        Text(demoModeActive ? Strings.limitedReadyDetail : Strings.defaultReadyDetail)
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
            PrimaryButton(
                title: demoModeActive ? Strings.limitedCTA : Strings.defaultCTA,
                icon: "arrow.right",
                height: 46,
                fontSize: 14
            ) {
                openWindow(id: ReplyAIWindowSummoner.inboxWindowID)
            }
        } secondary: {
            Text(demoModeActive ? Strings.limitedSecondary : Strings.defaultSecondary)
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }
}
