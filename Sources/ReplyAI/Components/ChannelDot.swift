import SwiftUI

struct ChannelDot: View {
    var channel: Channel
    var size: CGFloat = 8
    /// Border cutout color — matches the surface the dot sits on.
    var cutout: Color = Theme.Color.bg1

    var body: some View {
        Circle()
            .fill(channel.dotColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(cutout, lineWidth: 2)
            )
    }
}
