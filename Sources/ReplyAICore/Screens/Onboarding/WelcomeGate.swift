import SwiftUI

/// First-launch welcome screen that gates the rest of the app. Renders a
/// brief intro + the existing `ObPermissionsView` permission cards, plus a
/// "Get started" CTA that flips `PreferenceKey.onboardingCompleted` and
/// dismisses the gate so the inbox appears.
///
/// Reusable as a Settings-side "Reset onboarding" path — flipping the
/// preference back to false will surface this view again at next launch.
struct WelcomeGate: View {
    @AppStorage(PreferenceKey.onboardingCompleted) private var completed = false

    var body: some View {
        ZStack {
            Theme.Color.bg1.ignoresSafeArea()
            VStack(spacing: 0) {
                heroBlock
                    .padding(.horizontal, 64)
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                Divider().background(Theme.Color.line)
                ObPermissionsView()
                    .frame(maxHeight: .infinity)
                Divider().background(Theme.Color.line)
                footer
                    .padding(.horizontal, 64)
                    .padding(.vertical, 18)
            }
        }
        .frame(minWidth: 1180, minHeight: 720)
        .preferredColorScheme(.dark)
    }

    private var heroBlock: some View {
        HStack(spacing: 28) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Color.accent)
                .frame(width: 64, height: 64)
                .overlay(
                    Text("R")
                        .font(Theme.Font.sans(34, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to ReplyAI")
                    .font(Theme.Font.sans(28, weight: .semibold))
                    .tracking(-0.7)
                    .foregroundStyle(Theme.Color.fg)
                Text("A unified, keyboard-first inbox for every channel you message in. Drafts in your voice, on-device. Your messages never leave this Mac.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Text("You can revisit any of this in Settings later.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
            Spacer()
            Button {
                completed = true
            } label: {
                HStack(spacing: 8) {
                    Text("Get started")
                        .font(Theme.Font.sans(13, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.Color.accent)
                )
                .foregroundStyle(Theme.Color.accentInk)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}
