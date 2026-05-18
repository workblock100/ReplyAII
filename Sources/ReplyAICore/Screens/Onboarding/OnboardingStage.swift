import SwiftUI

/// Shared layout for the 9 onboarding screens. Mirrors `OnboardingStage`
/// from app-primitives.jsx:
///   - 260px progress rail on the left (brand + step indicator + rail rows)
///   - flex content area with optional eyebrow, large title, scrollable
///     body, and a footer row of CTAs
struct OnboardingStage<Content: View, Cta: View, Secondary: View>: View {
    var step: Int
    var total: Int
    var eyebrow: String
    var title: Text
    var help: String = "You can change any of this later in Settings."
    @ViewBuilder var content: () -> Content
    @ViewBuilder var cta: () -> Cta
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        HStack(spacing: 0) {
            progressRail
                .frame(width: 260)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.Color.lineFaint).frame(width: 1)
                }

            VStack(alignment: .leading, spacing: 0) {
                eyebrowRow
                title
                    .font(Theme.Font.sans(38))
                    .tracking(-0.95)   // ≈ -0.025em at 38px
                    .lineSpacing(1)
                    .foregroundStyle(Theme.Color.fg)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.bottom, 28)

                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: .infinity)

                HStack(spacing: 10) {
                    cta()
                    secondary()
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 1180, minHeight: 720)
        .background(Theme.Color.bg1)
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Brand
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Color.accent)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Text("R")
                            .font(Theme.Font.sans(14, weight: .bold))
                            .foregroundStyle(Theme.Color.accentInk)
                    )
                Text("ReplyAI")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
            }

            Text("Step \(String(format: "%02d", step)) / \(String(format: "%02d", total))")
                .font(Theme.Font.mono(10))
                .tracking(1.2)
                .foregroundStyle(Theme.Color.fgMute)

            VStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i < step ? Theme.Color.accent : Color.white.opacity(0.08))
                        .opacity(i == step - 1 ? 1 : (i < step ? 0.7 : 1))
                        .frame(height: 3)
                }
            }

            Spacer(minLength: 0)

            Text(help)
                .font(Theme.Font.sans(11))
                .foregroundStyle(Theme.Color.fgMute)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [Theme.Color.accent.opacity(0.03), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var eyebrowRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.Color.accentGlow, radius: 4)
            Text(eyebrow.uppercased())
                .font(Theme.Font.mono(11))
                .tracking(1.5)
                .foregroundStyle(Theme.Color.fgMute)
        }
        .padding(.bottom, 18)
    }
}

/// Convenience initializer when you don't need a secondary action.
extension OnboardingStage where Secondary == EmptyView {
    init(
        step: Int, total: Int, eyebrow: String, title: Text,
        help: String = "You can change any of this later in Settings.",
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder cta: @escaping () -> Cta
    ) {
        self.step = step
        self.total = total
        self.eyebrow = eyebrow
        self.title = title
        self.help = help
        self.content = content
        self.cta = cta
        self.secondary = { EmptyView() }
    }
}
