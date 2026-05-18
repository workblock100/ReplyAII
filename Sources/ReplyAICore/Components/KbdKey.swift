import SwiftUI

/// Styled <kbd> block — bigger than KbdChip, used in shortcut cheatsheets.
struct KbdKey: View {
    var text: String
    var minWidth: CGFloat = 44
    var size: CGFloat = 12

    var body: some View {
        Text(text)
            .font(Theme.Font.mono(size))
            .foregroundStyle(Theme.Color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: minWidth)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r6, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r6, style: .continuous)
                    .stroke(Theme.Color.lineStrong, lineWidth: 1)
            )
    }
}
