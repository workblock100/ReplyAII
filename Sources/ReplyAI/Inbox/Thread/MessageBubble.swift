import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.from == .me { Spacer(minLength: 0) }
            bubble
            if message.from == .them { Spacer(minLength: 0) }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(Theme.Font.sans(13))
                .foregroundStyle(message.from == .me ? Theme.Color.accentInk : Theme.Color.fg)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(message.time)
                .font(Theme.Font.mono(10))
                .opacity(0.6)
                .foregroundStyle(message.from == .me ? Theme.Color.accentInk : Theme.Color.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(message.from == .me ? Theme.Color.accent : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(message.from == .them ? Color.white.opacity(0.06) : .clear, lineWidth: 1)
        )
        .frame(maxWidth: 380, alignment: message.from == .me ? .trailing : .leading)
    }
}
