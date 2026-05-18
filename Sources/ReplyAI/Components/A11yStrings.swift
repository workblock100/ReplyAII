import Foundation

/// Accessibility labels for icon-only tappable elements across the inbox UI.
/// Hoisted to a single namespace so VoiceOver copy stays consistent and
/// each label is unit-pinnable from `A11yStringsTests`. Icon-only buttons
/// without a visible `Text("…")` rely on `.accessibilityLabel(…)` to be
/// announced — otherwise VoiceOver speaks the SF Symbol name verbatim
/// ("xmark dot circle dot fill"), which is unusable.
///
/// Style: imperative verb-phrase, sentence-case first word, no trailing
/// punctuation, ≤ 24 characters so the announcement is snappy. When
/// adding a new entry, mirror the visual button's existing `.help()`
/// tooltip exactly when one exists — drift between the hover hint and
/// the VoiceOver label is itself an accessibility regression.
enum A11yStrings {
    /// Sidebar search field's trailing clear button (the
    /// "xmark.circle.fill" icon). Visible only when the search query is
    /// non-empty. Without this label, VoiceOver speaks the symbol name.
    static let clearSearch = "Clear search"

    /// Thread-list bulk-actions row, "mark all read" button
    /// ("checkmark.circle" icon). Disabled when zero unread; the label
    /// fires either way so VoiceOver users can confirm the button is
    /// present even when greyed out.
    static let markAllRead = "Mark all read"

    /// Thread-list bulk-actions row, "archive read threads" button
    /// ("archivebox" icon). Disabled when no read threads exist; same
    /// rationale as `markAllRead`.
    static let archiveRead = "Archive read"
}
