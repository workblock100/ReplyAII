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

    func testFooterOpenInboxLabelIsFrozen() {
        XCTAssertEqual(MenuBarContent.Strings.footerOpenInboxLabel,
                       "Open inbox",
            "footer primary CTA must remain `Open inbox` to match the keyboard-shortcut summon's verb-form; drift here means the rendered button label silently diverges from `⌘⇧O`'s mental model")
    }

    func testFooterQuitLabelIsFrozen() {
        XCTAssertEqual(MenuBarContent.Strings.footerQuitLabel,
                       "Quit",
            "footer secondary CTA must remain `Quit` (single word, capital Q) — softer styling of macOS's top-level Quit menu item; longer copy doesn't fit the 380pt popover")
    }

    /// The footer's two CTAs render side-by-side and parallel; ensuring
    /// they remain short keeps them visually balanced. Pinning the
    /// length invariants catches a copy edit that, say, expands "Quit"
    /// to "Quit ReplyAI" and breaks the layout.
    func testFooterLabelLengthInvariants() {
        XCTAssertLessThanOrEqual(MenuBarContent.Strings.footerOpenInboxLabel.count, 12,
            "footer primary CTA must be ≤ 12 chars — popover width minus padding leaves room for both buttons in parallel")
        XCTAssertLessThanOrEqual(MenuBarContent.Strings.footerQuitLabel.count, 6,
            "footer secondary CTA must be ≤ 6 chars — single-word styling per the design")
        XCTAssertTrue(MenuBarContent.Strings.footerOpenInboxLabel.first?.isUppercase ?? false,
            "footer primary CTA must start with an uppercase letter")
        XCTAssertTrue(MenuBarContent.Strings.footerQuitLabel.first?.isUppercase ?? false,
            "footer secondary CTA must start with an uppercase letter")
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

    func testBrandLetterIsCapitalR() {
        XCTAssertEqual(MenuBarContent.Strings.brandLetter, "R",
            "menu-bar header brand letter must remain `R` — same identity glyph used in 7 other shipping views and BACKLOG references; rebrand here without coordinating the others would render mismatched logos across screens")
        XCTAssertEqual(MenuBarContent.Strings.brandLetter.count, 1,
            "brand letter must remain exactly one Unicode scalar — drift to e.g. `R.` or `Re` overflows the 22pt accent square at 13pt font weight")
    }

    func testBrandNameIsPascalCaseReplyAI() {
        XCTAssertEqual(MenuBarContent.Strings.brandName, "ReplyAI",
            "brand name must remain Pascal-cased `ReplyAI` (no space, no lowercase) — drift to `Reply AI` or `replyai` orphans dozens of references in BACKLOG and AGENTS.md")
        XCTAssertFalse(MenuBarContent.Strings.brandName.contains(" "),
            "brand name must not contain a space — `Reply AI` is a separate marketing form not used in v1")
    }

    func testWaitingChipSuffixHasLeadingSpaceAndSingularNoun() {
        XCTAssertEqual(MenuBarContent.Strings.waitingChipSuffix, " waiting",
            "waiting-chip suffix must remain ` waiting` (with leading space, single word) so the rendered chip reads e.g. `3 waiting` not `3waiting` or `3 waiting threads`")
        XCTAssertTrue(MenuBarContent.Strings.waitingChipSuffix.hasPrefix(" "),
            "leading space is what visually separates the count from the noun")
        XCTAssertFalse(MenuBarContent.Strings.waitingChipSuffix.contains("threads") ||
                       MenuBarContent.Strings.waitingChipSuffix.contains("messages"),
            "suffix must remain single-word `waiting` — pluralizing or expanding overflows the 380pt header on macOS at default font size")
    }
}
