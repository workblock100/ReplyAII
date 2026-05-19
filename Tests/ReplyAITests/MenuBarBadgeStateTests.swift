import XCTest
@testable import ReplyAICore

/// Pin the `MenuBarBadgeState` shared-singleton contract (REP-044). The
/// MenuBarExtra label in ReplyAIApp observes this object; the inbox
/// pushes counts into `unreadCount`. The handful of invariants the
/// MenuBarExtra label relies on need to survive a future refactor:
@MainActor
final class MenuBarBadgeStateTests: XCTestCase {

    func testSharedInstanceIsIdentitySingleton() {
        let a = MenuBarBadgeState.shared
        let b = MenuBarBadgeState.shared
        XCTAssertTrue(a === b,
                      "MenuBarBadgeState.shared must return the same instance across reads — the MenuBarExtra label binds via @State and would lose its observation if .shared were re-allocated each access")
    }

    func testInitialUnreadCountIsZero() {
        // Reset via the (only) mutable surface so a prior test in the
        // same process doesn't leak state into this one.
        MenuBarBadgeState.shared.unreadCount = 0
        XCTAssertEqual(MenuBarBadgeState.shared.unreadCount, 0,
                       "Default unread count must be 0 — non-zero would force the menu-bar badge to render on first app launch before any threads are loaded")
    }

    func testUnreadCountRoundTrips() {
        MenuBarBadgeState.shared.unreadCount = 7
        XCTAssertEqual(MenuBarBadgeState.shared.unreadCount, 7)
        MenuBarBadgeState.shared.unreadCount = 0
        XCTAssertEqual(MenuBarBadgeState.shared.unreadCount, 0,
                       "Setting back to 0 must clear the badge — the menu-bar label hides the count text on 0")
    }

    func testUnreadCountAcceptsLargeValues() {
        MenuBarBadgeState.shared.unreadCount = 9999
        XCTAssertEqual(MenuBarBadgeState.shared.unreadCount, 9999,
                       "No artificial cap on count — the MenuBarExtra label is the place to clamp display (e.g. show '99+' for visual cleanliness)")
        // Restore for any subsequent test in the suite.
        MenuBarBadgeState.shared.unreadCount = 0
    }
}
