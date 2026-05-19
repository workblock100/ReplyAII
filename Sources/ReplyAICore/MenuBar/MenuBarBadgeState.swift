import Foundation
import Observation

/// Shared observable state for the macOS menu-bar icon's unread-thread
/// count badge (REP-044). The MenuBarExtra's label observes this and
/// re-renders when the count changes; the InboxScreen pushes new counts
/// on every threads-array mutation via an .onChange modifier in its body.
///
/// Why this exists as its own object rather than reading from
/// InboxViewModel directly:
/// - InboxViewModel is internal to `ReplyAICore`; the MenuBarExtra label
///   lives in `ReplyAIApp` (a different module). Lifting InboxViewModel
///   to public + lifting its initialization to App scope would touch
///   every InboxScreen test path and surface a much wider public ABI
///   than this single Int.
/// - The MenuBarExtra label is materialized at scene creation time,
///   before any window scene has mounted. There's no InboxViewModel
///   instance to read from at that moment.
/// - One narrow observable Int avoids any of the above.
///
/// Update lifecycle:
/// - Reset to 0 on app launch (the default).
/// - Updated by InboxScreen's body via `.onChange(of: model.threads)`
///   whenever the inbox window is mounted.
/// - Stays at the last-seen value if the inbox window is closed; this
///   matches user expectation — the menu bar should reflect the most
///   recent known state of waiting threads, not silently zero out when
///   the user dismisses the inbox window.
@Observable
@MainActor
public final class MenuBarBadgeState {
    /// Process-wide singleton. ReplyAIApp grabs this via `@State` so the
    /// MenuBarExtra label subscribes to changes; InboxScreen updates it
    /// via the singleton accessor in its `.onChange` push.
    public static let shared = MenuBarBadgeState()

    /// Current unread-thread count surfaced on the menu-bar icon.
    /// Zero means "no badge" — the label suppresses the count text
    /// when this is 0 to avoid visual noise on empty inboxes.
    public var unreadCount: Int = 0

    private init() {}
}
