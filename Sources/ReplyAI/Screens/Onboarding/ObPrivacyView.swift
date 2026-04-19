import SwiftUI

/// `ob-privacy` — on-device trust framing with 4 promise cards.
struct ObPrivacyView: View {
    private struct Point { let t: String; let d: String }
    private let points: [Point] = [
        .init(t: "On-device inference",
              d: "A 7B-parameter model runs on Apple Silicon via Metal. Your messages never touch our servers."),
        .init(t: "No training on your data",
              d: "We never use your conversations to improve shared models. Your voice profile stays on your Mac."),
        .init(t: "One-click export & wipe",
              d: "Export your voice profile, or nuke everything ReplyAI has ever seen — from Settings → Privacy."),
        .init(t: "Open security docs",
              d: "Our threat model, model weights hash, and audit trail are public. Read them before you trust us."),
    ]

    var body: some View {
        OnboardingStage(
            step: 2, total: 9,
            eyebrow: "Privacy promise",
            title: Text("Everything happens on your Mac.\n")
                + Text("We didn't want a cloud, so we didn't build one.")
                    .font(Theme.Font.serifItalic(38))
                    .foregroundColor(Theme.Color.fgDim)
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(points, id: \.t) { p in
                    Card(padding: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                iconChip(name: "shield")
                                Text(p.t)
                                    .font(Theme.Font.sans(14, weight: .medium))
                                    .foregroundStyle(Theme.Color.fg)
                            }
                            Text(p.d)
                                .font(Theme.Font.sans(12))
                                .foregroundStyle(Theme.Color.fgMute)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "I understand", icon: "arrow.right")
        } secondary: {
            GhostButton(title: "Read security docs")
        }
    }
}

/// Accent-tinted 32×32 icon chip used across onboarding.
struct OnboardingIconChip: View {
    var name: String
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.Color.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 1)
                )
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
        }
        .frame(width: size, height: size)
    }
}

private func iconChip(name: String) -> some View { OnboardingIconChip(name: name) }
