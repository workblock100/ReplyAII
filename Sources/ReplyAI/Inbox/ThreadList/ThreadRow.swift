import SwiftUI

struct ThreadRow: View {
    let thread: MessageThread
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left accent bar for selected state — 2px, slides on select.
                Rectangle()
                    .fill(isSelected ? Theme.Color.accent : .clear)
                    .frame(width: 2)

                Avatar(text: thread.avatar, channel: thread.channel, cutout: rowBg)
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if thread.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.Color.accent)
                                .accessibilityLabel("Pinned")
                        }
                        Text(thread.name)
                            .font(Theme.Font.sans(13, weight: thread.unread > 0 ? .semibold : .medium))
                            .foregroundStyle(Theme.Color.fg)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(thread.time)
                            .font(Theme.Font.mono(10))
                            .foregroundStyle(Theme.Color.fgFaint)
                    }
                    Text(thread.preview)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(thread.unread > 0 ? Theme.Color.fgDim : Theme.Color.fgMute)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if thread.unread > 0 {
                    unreadBadge
                        .padding(.trailing, 16)
                } else {
                    Spacer().frame(width: 16)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Color.lineFaint).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowBg: Color {
        isSelected ? Theme.Color.accent.opacity(0.07) : Color(red: 0.043, green: 0.047, blue: 0.058)
    }

    private var unreadBadge: some View {
        Text("\(thread.unread)")
            .font(Theme.Font.sans(10, weight: .bold))
            .foregroundStyle(Theme.Color.accentInk)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule(style: .continuous).fill(Theme.Color.accent))
    }
}
