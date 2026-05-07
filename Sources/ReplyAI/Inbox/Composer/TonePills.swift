import SwiftUI

/// Horizontal segmented control over `Tone.allCases` — the source of
/// truth for the composer's voice register. Bound to a `@Binding` rather
/// than the view model directly so the same component renders in the
/// composer header and in onboarding's tone-preview without duplicating
/// the styling. The animation curve (`Theme.Motion.tone`) intentionally
/// matches the `⌘/` cycle animation in the composer so click-cycling and
/// keyboard-cycling feel like the same gesture.
struct TonePills: View {
    @Binding var selection: Tone

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tone.allCases) { tone in
                Button {
                    withAnimation(Theme.Motion.tone) { selection = tone }
                } label: {
                    Text(tone.rawValue)
                        .font(Theme.Font.mono(10))
                        .tracking(0.4)  // ≈ 0.04em at 10px
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(selection == tone ? Theme.Color.accent : Theme.Color.fgMute)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == tone ? Theme.Color.accent.opacity(0.12) : .clear)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tone.rawValue) tone")
            }
        }
    }
}
