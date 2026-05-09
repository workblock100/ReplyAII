import XCTest
@testable import ReplyAI

/// Pin the user-visible empty-state copy on the menu-bar popover.
/// Both literals were hoisted from `MenuBarContent`'s SwiftUI body
/// to `MenuBarContent.Strings` so this is the first surface where a
/// copy edit (e.g. "Inbox zero." → "All caught up." for marketing
/// reasons) lands in code review with named tests rather than as a
/// silent SwiftUI-body diff that escapes the eye.
///
/// Sibling rationale: `OAuthError`'s timeoutToast / listenerFailedPrefix /
/// tokenExchangeFailedPrefix are pinned the same way (see
/// `LocalhostOAuthListenerTests.testOAuthError*CopyIsFrozen`). The
/// inbox / composer / sidebar UI strings still need the same hoist
/// before they can grow analogous pins.
final class MenuBarContentStringsTests: XCTestCase {

    func testInboxZeroHeaderIsFrozen() {
        XCTAssertEqual(MenuBarContent.Strings.inboxZeroHeader,
                       "Inbox zero.",
            "menu-bar empty-state header literal must not drift — `Inbox zero.` is the affirmative, brand-aligned phrasing the design calls for")
    }

    func testInboxZeroSubheadIsFrozen() {
        XCTAssertEqual(MenuBarContent.Strings.inboxZeroSubhead,
                       "Nothing needs you right now.",
            "menu-bar empty-state subhead literal must not drift — phrasing reassures the user the app is working, not stalled")
    }

    /// Header + subhead must read as a complete two-sentence thought
    /// — both endpunctuated, both starting with capital, neither too
    /// long for the 380pt-wide popover. Pinning the format invariants
    /// catches a copy edit that, say, drops the period off one or
    /// both lines.
    func testInboxZeroCopyShapeInvariants() {
        let header = MenuBarContent.Strings.inboxZeroHeader
        let subhead = MenuBarContent.Strings.inboxZeroSubhead

        XCTAssertTrue(header.hasSuffix("."),
            "header must end with a period — drift breaks the visual rhythm against the subhead")
        XCTAssertTrue(subhead.hasSuffix("."),
            "subhead must end with a period — drift breaks the visual rhythm against the header")
        XCTAssertTrue(header.first?.isUppercase ?? false,
            "header must start with an uppercase letter")
        XCTAssertTrue(subhead.first?.isUppercase ?? false,
            "subhead must start with an uppercase letter")
        XCTAssertLessThan(header.count, 30,
            "header must fit in the 380pt popover with the 14pt font; > 30 chars wraps awkwardly")
        XCTAssertLessThan(subhead.count, 60,
            "subhead must fit in the popover; > 60 chars forces a second visual line in 12pt")
    }
}
