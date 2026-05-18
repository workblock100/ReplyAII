import SwiftUI

/// `err-model-update` — new model downloading in the background.
struct ErrModelUpdateView: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("NEW MODEL READY")
                .font(Theme.Font.mono(11))
                .tracking(1.3)
                .foregroundStyle(Theme.Color.accent)

            titleWithSerif

            progressBar(fraction: 0.38)

            Text("1.6 GB of 4.2 GB · 38% · 2m 12s left")
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Color.fgMute)

            Text("You can keep using the current model while this downloads. The upgrade will apply the next time you quit and reopen ReplyAI.")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fgMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer()
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg1)
    }

    /// "ReplyAI-7B v34" in sans + "is downloading." in serif-italic, one line.
    private var titleWithSerif: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("ReplyAI-7B v34")
                .font(Theme.Font.sans(36))
                .tracking(-0.9)
                .foregroundStyle(Theme.Color.fg)
            Text("is downloading.")
                .font(Theme.Font.serifItalic(36))
                .foregroundStyle(Theme.Color.fgDim)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
    }

    private func progressBar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Theme.Color.accent)
                        .frame(width: geo.size.width * fraction)
                        .shadow(color: Theme.Color.accentGlow, radius: 5)
                }
        }
        .frame(width: 480, height: 6)
    }
}

