import SwiftUI

/// Pill-shaped secondary action button — matches `miniBtnStyle` from reply-app.jsx.
struct MiniButton: View {
    enum Kind { case secondary, primary, ghost }

    var title: String
    var kind: Kind = .secondary
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.sans(11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(foreground)
                .background(
                    Capsule(style: .continuous).fill(fill)
                )
                .overlay(
                    Capsule(style: .continuous).stroke(stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        switch kind {
        case .secondary: Color.white.opacity(0.03)
        case .primary:   Theme.Color.accent
        case .ghost:     .clear
        }
    }
    private var stroke: Color {
        switch kind {
        case .secondary: Color.white.opacity(0.14)
        case .primary:   Theme.Color.accent
        case .ghost:     Color.white.opacity(0.08)
        }
    }
    private var foreground: Color {
        switch kind {
        case .secondary: Theme.Color.fgDim
        case .primary:   Theme.Color.accentInk
        case .ghost:     Theme.Color.fgMute
        }
    }
}
