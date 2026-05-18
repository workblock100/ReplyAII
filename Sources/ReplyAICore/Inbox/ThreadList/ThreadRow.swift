import SwiftUI

/// One row in the thread list. The 2-pt left accent bar is rendered
/// always-present (clear when unselected) rather than conditionally so
/// row height stays constant during selection animations — without it,
/// the list shifts horizontally as the bar appears/disappears.
struct ThreadRow: View {
    let thread: MessageThread
    let isSelected: Bool
    /// Shared namespace from the parent ThreadListView. The selected row's
    /// accent bar uses `matchedGeometryEffect` against the same id across
    /// every row, so SwiftUI animates the bar between rows on selection
    /// instead of snapping. Optional so callers/tests can omit it; without
    /// a namespace the bar still renders but doesn't slide. REP-082.
    var selectionNamespace: Namespace.ID? = nil
    /// When true, skip `matchedGeometryEffect` so reduced-motion users
    /// see a snap rather than a slide. REP-082 + REP-083.
    var reduceMotion: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left accent bar for selected state — 2px. With the
                // matchedGeometryEffect (namespace passed in), SwiftUI slides
                // the bar between rows on selection. Without it, it snaps —
                // which is what we want for reduce-motion or callers that
                // don't supply a namespace.
                accentBar
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

    /// Selected row's accent bar — extracted so the matchedGeometryEffect
    /// modifier can apply only when both a namespace is supplied AND
    /// reduce-motion is off. SwiftUI's `matchedGeometryEffect` requires
    /// the modified view exist on every row at the same z-position, so
    /// the unselected case still emits a transparent rectangle of the
    /// same shape — this is what makes the slide animation work.
    @ViewBuilder
    private var accentBar: some View {
        if let ns = selectionNamespace, !reduceMotion, isSelected {
            Rectangle()
                .fill(Theme.Color.accent)
                .matchedGeometryEffect(id: "thread-selection-bar", in: ns)
        } else {
            Rectangle()
                .fill(isSelected ? Theme.Color.accent : .clear)
        }
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
