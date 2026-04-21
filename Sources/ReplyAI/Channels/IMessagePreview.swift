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

    /// Object-replacement character. `AttributedBodyDecoder` surfaces
    /// this for attachment blobs; UIKit/AppKit use it for inline
    /// attachments in `NSAttributedString`.
    static let objectReplacement: Character = "\u{FFFC}"

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
            return "🔗 \(host)"
        }

        return body
    }

    /// Returns the host of `input` iff the whole body is one URL with
    /// an http/https/mailto scheme. nil for anything else (plain text,
    /// text + URL, multi-line, invalid URL).
    static func singleURLHost(in input: String) -> String? {
        let tokens = input.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1 else { return nil }
        let token = String(tokens[0])

        guard let url = URL(string: token),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty
        else { return nil }

        // Strip a leading "www." — the host is more readable without it.
        let stripped = host.lowercased()
        if stripped.hasPrefix("www."), stripped.count > 4 {
            return String(stripped.dropFirst(4))
        }
        return stripped
    }
}
