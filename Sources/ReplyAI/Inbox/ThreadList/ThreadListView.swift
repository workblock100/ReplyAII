import SwiftUI

/// Middle-column of the inbox: header chip + the scrolling list of
/// `ThreadRow`s for the currently-selected folder/channel filter.
/// `LazyVStack` is deliberate — the inbox can hold thousands of threads
/// and `List` was rejected during design review for the keyboard-nav
/// quirks it imposes on `selection:` on macOS 14+.
struct ThreadListView: View {
    @Bindable var model: InboxViewModel
    /// Drives the matchedGeometryEffect on the selected-row accent bar so
    /// SwiftUI slides the bar between rows on selection instead of
    /// snapping. REP-082.
    @Namespace private var selectionNamespace
    /// Reduced-motion users get a snap instead of a slide. We feed this
    /// flag down into ThreadRow which then opts out of
    /// `matchedGeometryEffect` entirely (REP-082) and also skip the
    /// `withAnimation(Theme.Motion.std)` envelope around `selectThread`
    /// so thread switching is an instant cut (REP-083).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedThreads) { thread in
                        ThreadRow(
                            thread: thread,
                            isSelected: thread.id == model.selectedThreadID,
                            selectionNamespace: selectionNamespace,
                            reduceMotion: reduceMotion
                        ) {
                            // Wrap the model mutation so the highlight bar
                            // slides between rows via matchedGeometryEffect —
                            // without `withAnimation`, SwiftUI matches the
                            // geometry but renders instantly. Skipped under
                            // reduce-motion so the state change is a cut.
                            if reduceMotion {
                                model.selectThread(thread.id)
                            } else {
                                withAnimation(Theme.Motion.std) {
                                    model.selectThread(thread.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .background(Color(red: 0.043, green: 0.047, blue: 0.058)) // #0b0c0f
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Color.line).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.folderLabel)
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("\(model.needsYouCount) need you · \(model.handledCount) handled")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            bulkActions
            aiOnPill
        }
    }

    /// Pinned threads float to the top; within each bucket the caller's
    /// original order (usually last-message-date DESC) is preserved via
    /// a stable sort. Archived threads are filtered out entirely — they
    /// still exist in model.threads, just hidden from the main list.
    private var sortedThreads: [MessageThread] {
        let visible = model.filteredThreads.enumerated()
        return visible.sorted { lhs, rhs in
            if lhs.element.pinned != rhs.element.pinned {
                return lhs.element.pinned && !rhs.element.pinned
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private var bulkActions: some View {
        HStack(spacing: 5) {
            Button {
                model.bulkMarkAllRead()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.totalUnreadCount == 0 ? Theme.Color.fgFaint : Theme.Color.fgMute)
            .disabled(model.totalUnreadCount == 0)
            .help("Mark all read")

            Button {
                model.bulkArchiveRead()
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(hasReadThreads ? Theme.Color.fgMute : Theme.Color.fgFaint)
            .disabled(!hasReadThreads)
            .help("Archive read")
        }
    }

    private var hasReadThreads: Bool {
        model.filteredThreads.contains { $0.unread == 0 }
    }

    private var aiOnPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 5, height: 5)
                .shadow(color: Theme.Color.accentGlow, radius: 4)
            Text("AI on")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.Color.accent.opacity(0.3), lineWidth: 1)
        )
    }
}
