import SwiftUI

/// First-launch welcome screen that gates the rest of the app. Renders a
/// brief intro + the existing `ObPermissionsView` permission cards, plus a
/// "Get started" CTA that flips `PreferenceKey.onboardingCompleted` and
/// dismisses the gate so the inbox appears.
///
/// Reusable as a Settings-side "Reset onboarding" path — flipping the
/// preference back to false will surface this view again at next launch.
public struct WelcomeGate: View {
    public init() {}

    @AppStorage(PreferenceKey.onboardingCompleted) private var completed = false

    /// REP-UI-STR-HOIST-001 view 3 of 5. The literals below are the
    /// first thing every new user reads, so pinning them catches a
    /// copy-edit that silently rebrands the app's promise. The single
    /// brand glyph "R" at line ~42 stays inline — `BrandStrings.swift`
    /// will absorb it after every per-view hoist settles.
    public enum Strings {
        /// Hero title. Brand word "ReplyAI" is intentionally part of the
        /// title literal — the line reads as a sentence, not as "[brand]
        /// welcome screen". A future BrandStrings pass may split it.
        public static let heroTitle = "Welcome to ReplyAI"

        /// Hero subtitle. The product's brand promise — three independent
        /// clauses separated by periods: scope ("unified inbox"), control
        /// surface ("keyboard-first"), trust ("on-device, never leaves
        /// this Mac"). Edits here are marketing-grade and need product
        /// review; the pin keeps that gate explicit.
        public static let heroSubtitle = "A unified, keyboard-first inbox for every channel you message in. Drafts in your voice, on-device. Your messages never leave this Mac."

        /// Footer reassurance — the user can defer permission grants and
        /// pick this back up in Settings. Period-terminated; matches the
        /// design system's secondary-text terminal punctuation.
        public static let footerSettingsHint = "You can revisit any of this in Settings later."

        /// Primary CTA. Two words, lowercase second word — matches the
        /// rest of the onboarding-flow primary CTAs ("Get started", not
        /// "Get Started" / "Start" / "Continue").
        public static let getStartedLabel = "Get started"
    }

    public var body: some View {
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
                Text(Strings.heroTitle)
                    .font(Theme.Font.sans(28, weight: .semibold))
                    .tracking(-0.7)
                    .foregroundStyle(Theme.Color.fg)
                Text(Strings.heroSubtitle)
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
            Text(Strings.footerSettingsHint)
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
            Spacer()
            Button {
                completed = true
            } label: {
                HStack(spacing: 8) {
                    Text(Strings.getStartedLabel)
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
            .accessibilityIdentifier(ReplyAIUITestID.Onboarding.welcomeGateGetStartedButton)
        }
    }
}
