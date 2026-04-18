import SwiftUI
import AppKit

struct Avatar: View {
    var text: String
    var channel: Channel
    var size: CGFloat = 34
    /// Surface color behind the avatar; used to cut out the channel dot border.
    var cutout: Color = Theme.Color.bg1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [channel.dotColor, channel.dotColor.mix(with: .black, amount: 0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        .blendMode(.plusLighter)
                )
                .frame(width: size, height: size)
                .overlay(alignment: .center) {
                    Text(text)
                        .font(Theme.Font.sans(size * 0.4, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .tracking(-0.3)
                }
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)

            ChannelDot(channel: channel, size: 10, cutout: cutout)
                .offset(x: 2, y: 2)
        }
        .frame(width: size + 2, height: size + 2, alignment: .topLeading)
    }
}

extension Color {
    /// Approximate `color-mix(in oklab, a x%, b)` for gradient endpoints.
    /// Not perceptual but close enough for avatar tint shading.
    func mix(with other: Color, amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .clear
        let t = CGFloat(max(0, min(1, amount)))
        return Color(
            red:   a.redComponent * (1 - t)   + b.redComponent * t,
            green: a.greenComponent * (1 - t) + b.greenComponent * t,
            blue:  a.blueComponent * (1 - t)  + b.blueComponent * t,
            opacity: a.alphaComponent * (1 - t) + b.alphaComponent * t
        )
    }
}
