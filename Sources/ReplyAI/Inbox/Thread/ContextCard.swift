import SwiftUI

struct ContextCard: View {
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.Color.accent)
                    .frame(width: 20, height: 20)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentInk)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Context")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
                Text(summary)
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Theme.Color.accentSofter)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(Theme.Color.accentRule, lineWidth: 1)
        )
    }
}
