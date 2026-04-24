import SwiftUI

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
