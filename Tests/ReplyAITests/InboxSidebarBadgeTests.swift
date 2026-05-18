import XCTest
@testable import ReplyAICore

/// Pins the raw values on `InboxSidebarBadge`. Both raw values render verbatim
/// in `SimpleSidebar` via `Text(badge.rawValue)`, so a refactor that quietly
/// renamed `case sync = "SYNC"` to `case sync = "Sync"` would silently flip
/// every degraded-state chip from the design's all-caps mono treatment to
/// title case without touching a UI file.
final class InboxSidebarBadgeTests: XCTestCase {

    func testRawValuesRenderAsAllCapsLabels() {
        // Design treatment is uppercase mono. Lowercased rendering would
        // visibly break the chip without anyone editing a view.
        XCTAssertEqual(InboxSidebarBadge.sync.rawValue,    "SYNC")
        XCTAssertEqual(InboxSidebarBadge.offline.rawValue, "OFFLINE")
    }

    func testRawRoundTripCoversBothCases() {
        // Defense against silent rename: if either raw value drifts, the
        // round-trip via init?(rawValue:) catches it even if a per-case
        // assertion above were missed.
        for badge: InboxSidebarBadge in [.sync, .offline] {
            XCTAssertEqual(InboxSidebarBadge(rawValue: badge.rawValue), badge,
                           "round-trip failed for \(badge)")
        }
    }

    func testColorIsTheWarnToken() {
        // Both badges currently share `Theme.Color.warn` — pinning so a
        // future split (one warn, one accent) shows up as a deliberate test
        // edit rather than a quiet visual regression.
        XCTAssertEqual(InboxSidebarBadge.sync.color,    Theme.Color.warn)
        XCTAssertEqual(InboxSidebarBadge.offline.color, Theme.Color.warn)
    }
}
