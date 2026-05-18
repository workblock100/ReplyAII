import SwiftUI

/// Translates `cardPad` from the JSX — a subtly top-lit fill with a hairline
/// border and radius 14. Used everywhere a generic info block is needed.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var borderColor: Color = Theme.Color.line
    /// Optional solid fill override. When nil, the default top-to-bottom
    /// white-tinted gradient is applied.
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var background: some View {
        if let tint {
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(tint)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.025), Color.white.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}
