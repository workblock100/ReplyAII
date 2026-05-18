import SwiftUI

/// Small chip shown in the sidebar header during degraded / loading states.
enum InboxSidebarBadge: String {
    case sync = "SYNC"
    case offline = "OFFLINE"

    var color: Color { Theme.Color.warn }
}

/// Simplified three-column shell used by main-app variant screens
/// (`app-inbox-empty`, `app-inbox-loading`, `app-offline`, and the
/// background for surfaces like palette / snooze). Mirrors the
/// `InboxFrame` helper in app-screens.jsx.
struct InboxFrame<Right: View>: View {
    var sidebarBadge: InboxSidebarBadge? = nil
    var threadListOverride: AnyView? = nil
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(spacing: 0) {
            SimpleSidebar(badge: sidebarBadge)
                .frame(width: 220)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.Color.line).frame(width: 1)
                }

            Group {
                if let override = threadListOverride {
                    override
                } else {
                    SimpleThreadList()
                }
            }
            .frame(width: 320)
            .background(Color(red: 0.043, green: 0.047, blue: 0.058))
            .overlay(alignment: .trailing) {
                Rectangle().fill(Theme.Color.line).frame(width: 1)
            }

            right()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.039, green: 0.043, blue: 0.051))
        }
        .frame(minWidth: 1180, minHeight: 720)
    }
}

/// Stripped-down sidebar without live folder/channel state.
/// The first folder is always marked active.
private struct SimpleSidebar: View {
    var badge: InboxSidebarBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 28)   // traffic-light space

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
                if let badge {
                    Text(badge.rawValue)
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(badge.color.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(["Unified Inbox","Priority","Awaiting reply","Snoozed","Replied"].enumerated()), id: \.offset) { i, f in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(i == 0 ? Theme.Color.accent : Color.white.opacity(0.25))
                            .frame(width: 6, height: 6)
                        Text(f)
                            .font(Theme.Font.sans(13, weight: i == 0 ? .medium : .regular))
                            .foregroundStyle(i == 0 ? Theme.Color.fg : Theme.Color.fgDim)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                            .fill(i == 0 ? Theme.Color.accent.opacity(0.10) : .clear)
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.063, green: 0.071, blue: 0.090),
                    Color(red: 0.047, green: 0.051, blue: 0.067)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

/// Default thread list (used when no threadListOverride is passed).
private struct SimpleThreadList: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Unified Inbox")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.lineFaint).frame(height: 1) }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Fixtures.threads) { t in
                        HStack(spacing: 12) {
                            Avatar(text: t.avatar, channel: t.channel, cutout: Color(red: 0.043, green: 0.047, blue: 0.058))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(t.name)
                                        .font(Theme.Font.sans(13, weight: t.unread > 0 ? .semibold : .medium))
                                        .foregroundStyle(Theme.Color.fg)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(t.time)
                                        .font(Theme.Font.mono(10))
                                        .foregroundStyle(Theme.Color.fgFaint)
                                }
                                Text(t.preview)
                                    .font(Theme.Font.sans(12))
                                    .foregroundStyle(Theme.Color.fgMute)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.lineFaint).frame(height: 1) }
                    }
                }
            }
        }
    }
}
