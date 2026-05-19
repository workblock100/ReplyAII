import SwiftUI

/// Real `MenuBarExtra` popover — the shipping counterpart to the
/// `sfc-menubar` design mock. Renders the same list of waiting threads,
/// but driven by the live `InboxViewModel` instead of fixture snapshots.
public struct MenuBarContent: View {
    /// User-visible string vocabulary for the menu-bar popover. Hoisted
    /// from inline `Text("…")` literals in the view body so a copy review
    /// can edit one place and so each string can be pinned by a unit test.
    /// Sibling views (Inbox/Composer/Sidebar) still hold their literals
    /// inline; this is the first foothold for the broader hoist suggested
    /// by the 2026-05-09-0811 fire log. `internal` (default access) so
    /// `@testable import ReplyAI` can reach the constants.
    enum Strings {
        /// Empty-state header when there are no waiting threads — short,
        /// affirmative, doesn't yell at the user. The verb-less ".'"
        /// keeps it gentle vs "You have nothing to do."
        static let inboxZeroHeader = "Inbox zero."
        /// Empty-state subhead — the explanation under the header.
        /// Reassures the user the app is working; matches the design's
        /// tone of voice elsewhere ("Nothing needs you right now.").
        static let inboxZeroSubhead = "Nothing needs you right now."

        /// Footer primary CTA. Same verb-form as `MenuBarContent.swift`'s
        /// keyboard-shortcut summon (`⌘⇧O`); preserved on hoist so the
        /// rendered button label still says "Open inbox", not a renamed
        /// variant. Sibling site that uses the same string: the gallery
        /// toolbar's "Open inbox →" (with the trailing arrow glyph) lives
        /// inline in `AppPrototypeView` and is intentionally distinct
        /// from this footer label per the design — DO NOT consolidate.
        static let footerOpenInboxLabel = "Open inbox"

        /// Footer secondary action. Quits the whole app, not just the
        /// menu-bar popover. Single word per the design's tight-popover
        /// tone of voice (parallel to the top-level menu-bar item that
        /// macOS provides for free; ours is a softer styling).
        static let footerQuitLabel = "Quit"

        /// Brand letter rendered inside the 22pt accent square in the
        /// header. Shared identity glyph across MenuBarContent,
        /// AppPrototypeView, SidebarView, OnboardingStage, WelcomeGate,
        /// and InboxFrame — eight call sites in current main, all
        /// inline `Text(BrandStrings.letter)`. THIS hoist intentionally only changes
        /// the local-to-MenuBarContent rendering; the other seven sites
        /// keep their inline literal until a future fire migrates them
        /// (would touch every shipping screen and warrant a
        /// `Sources/ReplyAI/BrandStrings.swift` consolidation rather
        /// than a per-file enum).
        static let brandLetter = "R"

        /// Brand name rendered next to the brand letter in the header.
        /// Capital R + lowercase eply + capital A + capital I — keep the
        /// Pascal-case `ReplyAI` form, not `Reply AI` (with space) or
        /// `replyai` (lowercase). Drift here orphans tests and screen
        /// references in BACKLOG.
        static let brandName = "ReplyAI"

        /// Header right-aligned waiting-count chip. Format string takes
        /// `Int` and produces `"<N> waiting"` — singular and zero are
        /// also formatted as `"0 waiting"` / `"1 waiting"`. Pinning
        /// the suffix (`" waiting"` exactly, single word, leading space)
        /// catches a copy edit that pluralizes (`" waiting threads"`)
        /// and overflows the 380pt header on macOS at default font size.
        static let waitingChipSuffix = " waiting"
    }

    @State private var model = InboxViewModel()
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

            waitingList

            footerActions
        }
        .frame(width: 380)
        .background(Theme.Color.bg3)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.Color.accent)
                .frame(width: 22, height: 22)
                .overlay(
                    Text(Strings.brandLetter)
                        .font(Theme.Font.sans(13, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                )
            Text(Strings.brandName)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundStyle(Theme.Color.fg)
            Spacer()
            Text("\(waitingThreads.count)\(Strings.waitingChipSuffix)")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgMute)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var waitingThreads: [MessageThread] {
        model.menuBarWaitingThreads
    }

    @ViewBuilder
    private var waitingList: some View {
        if waitingThreads.isEmpty {
            VStack(spacing: 4) {
                Text(Strings.inboxZeroHeader)
                    .font(Theme.Font.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
                Text(Strings.inboxZeroSubhead)
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        } else {
            VStack(spacing: 0) {
                ForEach(waitingThreads) { t in
                    Button {
                        model.selectThread(t.id)
                        openWindow(id: ReplyAIWindowSummoner.inboxWindowID)
                    } label: {
                        threadRow(t)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func threadRow(_ t: MessageThread) -> some View {
        HStack(spacing: 10) {
            Avatar(text: t.avatar, channel: t.channel, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(Theme.Font.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text(t.preview)
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineLimit(1)
            }
            Spacer()
            if t.unread > 0 {
                Text("\(t.unread)")
                    .font(Theme.Font.sans(9, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule(style: .continuous).fill(Theme.Color.accent))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.lineFaint).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: ReplyAIWindowSummoner.inboxWindowID)
            } label: {
                Text(Strings.footerOpenInboxLabel)
                    .font(Theme.Font.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(Capsule(style: .continuous).fill(Theme.Color.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text(Strings.footerQuitLabel)
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgDim)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .overlay(
                        Capsule(style: .continuous).stroke(Theme.Color.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
}
