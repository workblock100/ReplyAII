import Foundation

/// Transforms a decoded iMessage body into the short string shown in
/// the sidebar ThreadRow. Pure display logic — no data changes.
///
/// Rules, in order:
///   1. A single-URL body collapses to `🔗 <host>` so link spam
///      doesn't flood the sidebar with raw scheme + path.
///   2. A body consisting entirely of the Unicode object-replacement
///      character (U+FFFC, the attachment sentinel typedstream inlines
///      into `NSAttributedString` for images/voice/stickers) renders
///      as `📎 Attachment` instead of the generic fallback.
///   3. A nil, empty, or whitespace-only body falls back to
///      `[non-text message]` — same as before this file existed.
///   4. Everything else passes through verbatim.
enum IMessagePreview {
    static let attachmentFallback = "📎 Attachment"
    static let nonTextFallback    = "[non-text message]"

    /// Prefix used by `displayString` when a body collapses to a single
    /// URL — the resulting preview is `linkPrefix + " " + host`. Hoisted
    /// alongside `attachmentFallback`/`nonTextFallback` so all three
    /// sidebar-preview presentation tokens live in one place. Drift here
    /// silently changes how every link-only message renders in the
    /// sidebar (and how `Stats` would categorize "link" rows if a future
    /// counter splits them out). Pinned by
    /// `IMessagePreviewTests.testLinkPrefixIsLinkEmoji`.
    static let linkPrefix = "🔗"

    /// Object-replacement character. `AttributedBodyDecoder` surfaces
    /// this for attachment blobs; UIKit/AppKit use it for inline
    /// attachments in `NSAttributedString`.
    static let objectReplacement: Character = "\u{FFFC}"

    /// URL schemes that the single-URL collapse path actually displays
    /// as `🔗 <host>`. Anything else (mailto, tel, ftp, custom-scheme
    /// deeplinks) passes through verbatim — see
    /// `testNonHTTPSchemeDoesNotCollapse`. Hoisted so a future "let's
    /// also collapse `ftp` URLs" decision is a single-edit + test
    /// change rather than buried inside a multi-clause guard expression.
    /// Pinned by `IMessagePreviewTests.testCollapseSchemesAreFrozen`.
    static let collapseSchemes: Set<String> = ["http", "https"]

    /// Leading host-prefix that's stripped before display. `www.` is
    /// noise on every modern domain; the host is more readable without
    /// it. Hoisted so a future stripping policy (also strip `m.` or
    /// `mobile.`?) lands on this constant rather than re-typed inside
    /// `singleURLHost`. Pinned by
    /// `IMessagePreviewTests.testWWWPrefixIsFrozen`.
    static let strippedHostPrefix = "www."

    /// Derive the sidebar preview from a decoded body.
    static func displayString(from body: String?) -> String {
        guard let body, !body.isEmpty else { return nonTextFallback }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nonTextFallback }

        // Attachment: strip U+FFFC then check if anything meaningful
        // remained. A body that's only attachment markers plus
        // whitespace becomes "📎 Attachment".
        let withoutAttachmentMarkers = trimmed
            .filter { $0 != objectReplacement }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if withoutAttachmentMarkers.isEmpty {
            return attachmentFallback
        }

        // URL: exactly one token, parses as an absolute URL with a
        // host. Strip the scheme and path — the host is the signal.
        if let host = singleURLHost(in: trimmed) {
            return "\(linkPrefix) \(host)"
        }

        return body
    }

    /// Returns the host of `input` iff the whole body is one URL with
    /// an http or https scheme. nil for anything else (plain text,
    /// text + URL, multi-line, invalid URL, or non-clickable schemes
    /// like mailto/tel/ftp — those pass through verbatim per
    /// `testNonHTTPSchemeDoesNotCollapse`).
    static func singleURLHost(in input: String) -> String? {
        let tokens = input.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1 else { return nil }
        let token = String(tokens[0])

        guard let url = URL(string: token),
              let scheme = url.scheme?.lowercased(),
              collapseSchemes.contains(scheme),
              let host = url.host, !host.isEmpty
        else { return nil }

        // Strip the leading prefix — the host is more readable without it.
        let stripped = host.lowercased()
        if stripped.hasPrefix(strippedHostPrefix), stripped.count > strippedHostPrefix.count {
            return String(stripped.dropFirst(strippedHostPrefix.count))
        }
        return stripped
    }
}
