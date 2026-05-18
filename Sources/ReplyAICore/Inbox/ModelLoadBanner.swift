import SwiftUI

/// Banner shown above the inbox while the LLM service is loading.
/// Appears only when DraftEngine.modelLoadStatus is non-nil.
struct ModelLoadBanner: View {
    var status: DraftEngine.ModelLoadStatus

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            spinner

            VStack(alignment: .leading, spacing: 4) {
                Text("Loading on-device model")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text(status.message)
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }

            Spacer()
            progressBar
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.Color.accent.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.accent.opacity(0.25)).frame(height: 1)
        }
    }

    private var spinner: some View {
        TimelineView(.animation) { ctx in
            let angle = (ctx.date.timeIntervalSinceReferenceDate * 180)
                .truncatingRemainder(dividingBy: 360)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(angle))
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Theme.Color.accent)
                    .frame(width: max(4, geo.size.width * CGFloat(status.fraction)))
                    .shadow(color: Theme.Color.accentGlow, radius: 4)
                    .animation(Theme.Motion.std, value: status.fraction)
            }
        }
        .frame(width: 180, height: 4)
    }
}
