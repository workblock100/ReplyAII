import SwiftUI

/// Left-rail of the inbox window: brand row, search pill, folder nav,
/// channel filter, and the persistent connection-health pill at the
/// bottom. The 28-pt top spacer is load-bearing — without it the macOS
/// traffic-light buttons overlay the brand row when the window uses the
/// hidden title bar style. Folder selection writes through to
/// `Preferences.lastSelectedFolder` so cold launches restore the user's
/// last view.
struct SidebarView: View {
    @Bindable var model: InboxViewModel

    /// Honor System Settings → Accessibility → Display → Reduce Motion.
    /// Folder-switch and channel-filter `withAnimation` calls below gate
    /// on this flag so a Reduce Motion user gets instant cuts.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// REP-UI-STR-HOIST-001 view 2 of 5. Inline `Text("…")` literals
    /// hoisted to per-view constants so a copy review or i18n pass is a
    /// single-file diff with literal-pin test coverage. Brand strings
    /// ("R", "ReplyAI") and demo-only profile strings ("JS", "Jordan Song",
    /// "pro · mac") are intentionally left inline: brand strings get a
    /// `BrandStrings.swift` consolidation pass after every per-view hoist
    /// settles; demo profile data gets replaced with real user data when
    /// the account layer ships. `internal` access so `@testable import
    /// ReplyAICore` reaches the constants.
    enum Strings {
        /// Search shortcut hint displayed at the right of the brand row.
        /// Matches the global keyboard map (`Services/GlobalHotkey.swift`).
        static let searchShortcutHint = "⌘K"

        /// Placeholder in the search TextField. Verb-less noun phrase per
        /// the design system's long-form placeholder convention.
        static let searchPlaceholder = "Search anyone, anything"

        /// Section header above the inbox folder list. Plural noun.
        static let foldersSection = "Inboxes"

        /// Section header above the channel filter list. Plural noun.
        static let channelsSection = "Channels"

        /// Sync chip label when no real sync has happened — the inbox is
        /// displaying `Fixtures.demoChatThreads` and ⌘R will trigger a
        /// real sync. The middle character is U+00B7 (middle dot), not a
        /// hyphen.
        static let syncIdle = "fixtures · ⌘R to sync"

        /// Sync chip label while the sync is in flight. Trailing horizontal
        /// ellipsis (U+2026), not three periods.
        static let syncing = "syncing…"

        /// Sync chip label when iMessage `chat.db` access is denied — the
        /// user needs Full Disk Access in System Settings. Channel-agnostic
        /// per the 2026-04-23 pivot (Slack-only users see this for FDA).
        static let syncDenied = "needs full disk access"

        /// Prefix before the relative-time string in the live state.
        /// Composed as "live · <Ns ago>" or "live · <Nm ago>" — see
        /// `relativeString(for:)`.
        static let syncLivePrefix = "live · "

        /// Prefix before the truncated error string in the failed state.
        /// Composed as "error · <first 24 chars of msg>".
        static let syncFailedPrefix = "error · "

        /// Max characters of the underlying error message that we render
        /// in the failed sync state. Anything longer is truncated to keep
        /// the chip within the 220-pt sidebar width without wrapping.
        static let syncFailedMessageMaxLength = 24

        /// Relative-time string when the last sync was within 5 seconds ago.
        static let relativeJustNow = "just now"

        /// Suffix for seconds-ago strings (e.g. "12\(secondsAgoSuffix)").
        static let secondsAgoSuffix = "s ago"

        /// Suffix for minutes-ago strings (e.g. "5\(minutesAgoSuffix)").
        static let minutesAgoSuffix = "m ago"

        /// Suffix for hours-ago strings (e.g. "2\(hoursAgoSuffix)").
        static let hoursAgoSuffix = "h ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reserve vertical room for the macOS traffic lights that sit above us.
            Spacer().frame(height: 28)

            brandRow
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            searchPill
                .padding(.horizontal, 8)

            SectionLabel(text: Strings.foldersSection)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

            foldersNav
                .padding(.horizontal, 8)

            SectionLabel(text: Strings.channelsSection)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 6)

            channelsList
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            syncChip
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.05))
            userFooter
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 220, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.063, green: 0.071, blue: 0.090), // #101217
                    Color(red: 0.047, green: 0.051, blue: 0.067)  // #0c0d11
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Color.line).frame(width: 1)
        }
    }

    // MARK: - Sections

    private var brandRow: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.Color.accent)
                .frame(width: 22, height: 22)
                .overlay(
                    Text("R")
                        .font(Theme.Font.sans(13, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                )
            Text("ReplyAI")
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundStyle(Theme.Color.fg)
            Spacer()
            Text(Strings.searchShortcutHint)
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgFaint)
        }
    }

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.fgMute)
                .accessibilityHidden(true)
            TextField(Strings.searchPlaceholder, text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fg)
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.fgFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11yStrings.clearSearch)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var foldersNav: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.folders) { folder in
                folderRow(folder)
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        let active = folder.id == model.activeFolder
        return Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.std) { model.activeFolder = folder.id }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? Theme.Color.accent : Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text(folder.label)
                    .font(Theme.Font.sans(13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.Color.fg : Theme.Color.fgDim)
                Spacer()
                Text("\(model.count(for: folder.id))")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                    .fill(active ? Theme.Color.accent.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var channelsList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.channels) { channel in
                channelRow(channel)
            }
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let active = model.activeChannelFilter == channel
        return Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.std) {
                model.filterByChannel(active ? nil : channel)
            }
        } label: {
            HStack(spacing: 10) {
                ChannelDot(channel: channel, size: 8, cutout: .clear)
                Text(channel.label)
                    .font(Theme.Font.sans(13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.Color.fg : Theme.Color.fgDim)
                Spacer()
                Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? Theme.Color.accent : Theme.Color.fgFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                    .fill(active ? Theme.Color.accent.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(A11yStrings.channelFilter(active: active, channelLabel: channel.label))
        .accessibilityLabel(A11yStrings.channelFilter(active: active, channelLabel: channel.label))
    }

    /// REP-047 — wrap the sync chip in a 10s `TimelineView` so the
    /// "live · Ns ago" string auto-advances. Without this the relative
    /// time renders once on thread-select and silently goes stale until
    /// the next sync. 10s matches the design spec; CPU cost is negligible
    /// because only the chip's body re-renders, not the sidebar.
    private var syncChip: some View {
        TimelineView(.periodic(from: Date(), by: 10)) { _ in
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: dotColor.opacity(0.6), radius: 3)
                Text(syncLabel)
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
                Spacer()
            }
        }
    }

    private var dotColor: Color {
        switch model.syncStatus {
        case .live:                      return Theme.Color.accent
        case .syncing:                   return Theme.Color.warn
        case .denied, .failed:           return Theme.Color.err
        case .idle:                      return Theme.Color.fgFaint
        }
    }

    private var syncLabel: String {
        switch model.syncStatus {
        case .idle:               return Strings.syncIdle
        case .syncing:            return Strings.syncing
        case .live(let at):       return Strings.syncLivePrefix + relativeString(for: at)
        case .denied:             return Strings.syncDenied
        case .failed(let msg):    return Strings.syncFailedPrefix + msg.prefix(Strings.syncFailedMessageMaxLength)
        }
    }

    private func relativeString(for date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return Strings.relativeJustNow }
        if s < 60 { return "\(s)\(Strings.secondsAgoSuffix)" }
        let m = s / 60
        return m < 60 ? "\(m)\(Strings.minutesAgoSuffix)" : "\(m / 60)\(Strings.hoursAgoSuffix)"
    }

    private var userFooter: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.79, green: 0.64, blue: 1.00),
                             Color(red: 0.48, green: 0.36, blue: 1.00)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 26, height: 26)
                .overlay(
                    Text("JS")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Jordan Song")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
                Text("pro · mac")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }
}
