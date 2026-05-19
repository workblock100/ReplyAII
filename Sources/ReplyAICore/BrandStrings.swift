import Foundation

/// Brand identity constants used across SwiftUI views.
///
/// REP-UI-STR-HOIST-002 — consolidation pass after REP-UI-STR-HOIST-001
/// landed per-view `Strings` enums on 5 views. The brand glyph "R" and the
/// standalone brand-name label "ReplyAI" repeat across 8 + 6 sites
/// respectively; centralising them here makes a future rebrand a single
/// edit and lets the test suite assert no inline drift via the
/// `BrandStringsConsistencyTests.testNoInlineBrandLiterals` enumeration.
///
/// `public` so SwiftUI views in both `ReplyAI` (app target) and
/// `ReplyAICore` (this module) can reach the constants; both targets are
/// internal to this repo so this is not a stability surface.
///
/// **Out of scope:** strings that *contain* "ReplyAI" inside a sentence
/// (e.g. "ReplyAI will type this into Messages as you.") — those stay
/// inline in their per-view `Strings` enums because the brand word is
/// part of natural-language copy, not a labelled brand element.
public enum BrandStrings {
    /// Brand glyph — single uppercase letter, rendered inside a coloured
    /// rounded-rectangle / circle as the app's compact identity mark.
    /// Used in: SidebarView header, MenuBarContent header, multiple
    /// gallery surfaces, WelcomeGate hero block, OnboardingStage header,
    /// InboxFrame, AppPrototypeView, SfcMenubarView, SfcNotificationView.
    public static let letter = "R"

    /// Brand wordmark — full product name when rendered as a standalone
    /// label adjacent to the brand glyph. Six sites today: SidebarView
    /// header, AppPrototypeView header, OnboardingStage header,
    /// SfcMenubarView header, InboxFrame header, plus the
    /// `ReplyAI draft · <tone>` composer caption.
    public static let name = "ReplyAI"
}
