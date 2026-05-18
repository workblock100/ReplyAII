import SwiftUI

/// Small channel-identity badge — a colored circle with a cutout-color
/// border so it visually pops off whatever surface it's overlaid on.
/// Used in `Avatar` (corner badge), `SidebarView` (channel filter chip),
/// and message rows. The `cutout` parameter must match the underlying
/// surface color so the border reads as a "hole" through the dot rather
/// than as an extra ring; defaults to `Theme.Color.bg1` because that's
/// the most common host surface.
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
