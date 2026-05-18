import SwiftUI

/// Matches `PrimaryBtn` from app-primitives.jsx — 40px pill with accent fill.
struct PrimaryButton: View {
    var title: String
    var icon: String? = nil       // SF Symbol
    var height: CGFloat = 40
    var fontSize: CGFloat = 13
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.Font.sans(fontSize, weight: .semibold))
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.Color.accentInk)
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(Capsule(style: .continuous).fill(Theme.Color.accent))
        }
        .buttonStyle(.plain)
    }
}

/// Matches `GhostBtn` — outlined, transparent fill, secondary color.
struct GhostButton: View {
    var title: String
    var icon: String? = nil
    var height: CGFloat = 40
    var fontSize: CGFloat = 13
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.Font.sans(fontSize))
                if let icon {
                    Image(systemName: icon).font(.system(size: 12))
                }
            }
            .foregroundStyle(Theme.Color.fgDim)
            .padding(.horizontal, 16)
            .frame(height: height)
            .overlay(
                Capsule(style: .continuous).stroke(Theme.Color.lineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
