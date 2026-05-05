import XCTest
@testable import ReplyAI

final class IMessagePreviewTests: XCTestCase {

    // MARK: - Empty / whitespace fallbacks

    func testNilBodyReturnsNonTextFallback() {
        XCTAssertEqual(IMessagePreview.displayString(from: nil),
                       IMessagePreview.nonTextFallback)
    }

    func testEmptyBodyReturnsNonTextFallback() {
        XCTAssertEqual(IMessagePreview.displayString(from: ""),
                       IMessagePreview.nonTextFallback)
    }

    func testWhitespaceOnlyBodyReturnsNonTextFallback() {
        XCTAssertEqual(IMessagePreview.displayString(from: "   "),
                       IMessagePreview.nonTextFallback)
        XCTAssertEqual(IMessagePreview.displayString(from: "\n\n\t"),
                       IMessagePreview.nonTextFallback)
    }

    // MARK: - Attachment-only bodies

    func testAttachmentMarkerOnlyReturnsAttachmentFallback() {
        XCTAssertEqual(IMessagePreview.displayString(from: "\u{FFFC}"),
                       IMessagePreview.attachmentFallback)
    }

    func testMultipleAttachmentMarkersOnlyReturnsAttachmentFallback() {
        XCTAssertEqual(IMessagePreview.displayString(from: "\u{FFFC}\u{FFFC}\u{FFFC}"),
                       IMessagePreview.attachmentFallback)
    }

    func testAttachmentMarkersWithWhitespaceReturnsAttachmentFallback() {
        XCTAssertEqual(IMessagePreview.displayString(from: " \u{FFFC} \u{FFFC} "),
                       IMessagePreview.attachmentFallback)
    }

    // MARK: - URL collapsing

    func testSingleHttpsURLCollapsesToHost() {
        XCTAssertEqual(IMessagePreview.displayString(from: "https://example.com/some/path"),
                       "🔗 example.com")
    }

    func testSingleHttpURLCollapsesToHost() {
        XCTAssertEqual(IMessagePreview.displayString(from: "http://example.com"),
                       "🔗 example.com")
    }

    func testSingleURLStripsWwwPrefix() {
        XCTAssertEqual(IMessagePreview.displayString(from: "https://www.nytimes.com/article"),
                       "🔗 nytimes.com")
    }

    func testSingleURLLowercasesHost() {
        XCTAssertEqual(IMessagePreview.displayString(from: "https://Example.COM/X"),
                       "🔗 example.com")
    }

    func testMultiTokenURLDoesNotCollapse() {
        let body = "check this out https://example.com"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    func testMailtoURLDoesNotCollapse() {
        let body = "mailto:foo@example.com"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    func testInvalidURLPassesThrough() {
        let body = "not://a real url"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    // MARK: - Plain text passthrough

    func testPlainTextPassesThrough() {
        let body = "Hey, are you free for lunch?"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    func testEmojiPassesThrough() {
        let body = "👍 sounds good"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    func testTextWithAttachmentMarkerPassesThroughVerbatim() {
        // Mixed text + attachment marker: rule 4 applies (rules 1-3 don't match)
        let body = "see attached \u{FFFC}"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    // MARK: - singleURLHost direct

    func testSingleURLHostNilForMultipleTokens() {
        XCTAssertNil(IMessagePreview.singleURLHost(in: "two tokens"))
    }

    func testSingleURLHostNilForBareWord() {
        XCTAssertNil(IMessagePreview.singleURLHost(in: "hello"))
    }

    func testSingleURLHostNilForNonHttpScheme() {
        XCTAssertNil(IMessagePreview.singleURLHost(in: "ftp://example.com"))
    }

    func testSingleURLHostKeepsShortWwwHostsIntact() {
        // "www." prefix only stripped when host has > 4 chars after it
        XCTAssertEqual(IMessagePreview.singleURLHost(in: "https://www./"), "www.")
    }

    // MARK: - Sentinel constants — UX copy contract
    //
    // The fallback strings render directly in the inbox sidebar where
    // they replace either a missing body (`[non-text message]`) or an
    // attachment-only body (`📎 Attachment`). Both strings double as
    // copy that ships to users — pin the literal values so a rename
    // of either constant shows up as a code-review diff. The
    // backlog still lists the glyph choice as a pending product
    // decision; pinning the current value gives the human a single
    // place to update both source + test when they pick.

    func testAttachmentFallbackLiteralIsPinned() {
        XCTAssertEqual(IMessagePreview.attachmentFallback, "📎 Attachment",
            "attachmentFallback ships verbatim to the sidebar — bump test + source together when changing the glyph or noun")
    }

    func testNonTextFallbackLiteralIsPinned() {
        XCTAssertEqual(IMessagePreview.nonTextFallback, "[non-text message]",
            "nonTextFallback ships verbatim to the sidebar — bump test + source together when changing the copy")
    }

    func testObjectReplacementCharacterIsU_FFFC() {
        // U+FFFC is the typedstream-emitted attachment marker; if the
        // constant ever drifts the attachment-only detection breaks
        // silently and every image/voice memo would render as the raw
        // marker character.
        XCTAssertEqual(IMessagePreview.objectReplacement, "\u{FFFC}",
            "objectReplacement must remain U+FFFC — the typedstream-emitted attachment sentinel")
    }

    func testLinkPrefixGlyphIsPinned() {
        // The link emoji "🔗 " prefixes any single-URL collapse —
        // pinning so a designer-led tweak (e.g. "↗ example.com")
        // surfaces here.
        let preview = IMessagePreview.displayString(from: "https://example.com/a/b/c")
        XCTAssertTrue(preview.hasPrefix("🔗 "),
            "single-URL preview must keep the 🔗 prefix; got: \(preview)")
    }

    // MARK: - Unicode whitespace contract

    /// Foundation's `.whitespacesAndNewlines` set includes Unicode
    /// whitespace beyond ASCII (NBSP U+00A0, EM SPACE U+2003, etc.).
    /// Pin the implementation choice because a future refactor that
    /// switched to `String.isASCII`-style trimming or a regex `\s` set
    /// (which doesn't match NBSP on every platform) would silently let
    /// NBSP-only payloads slip through as visible text instead of
    /// falling back to the non-text label.
    func testNonBreakingSpaceOnlyBodyTreatedAsEmpty() {
        // U+00A0 (NBSP) — common in pasted text from web sources.
        let nbspBody = "\u{00A0}\u{00A0}"
        XCTAssertEqual(IMessagePreview.displayString(from: nbspBody),
                       IMessagePreview.nonTextFallback,
                       "NBSP-only body must collapse to non-text fallback")
    }

    func testEmSpaceOnlyBodyTreatedAsEmpty() {
        // U+2003 (EM SPACE) — sometimes emitted by typography-aware
        // editors when copy-pasting.
        let emSpaceBody = "\u{2003}"
        XCTAssertEqual(IMessagePreview.displayString(from: emSpaceBody),
                       IMessagePreview.nonTextFallback,
                       "EM SPACE-only body must collapse to non-text fallback")
    }

    func testAttachmentMarkerWithUnicodeWhitespaceCollapsesToPaperclip() {
        // Mixed: attachment sentinel plus Unicode whitespace must still
        // resolve to the paperclip fallback. The sentinel-strip step
        // re-trims with the same `.whitespacesAndNewlines` set, so this
        // path also depends on Foundation including NBSP.
        let body = "\u{FFFC}\u{00A0}\u{FFFC}\u{2003}"
        XCTAssertEqual(IMessagePreview.displayString(from: body),
                       IMessagePreview.attachmentFallback,
                       "attachment markers + Unicode whitespace must collapse to paperclip")
    }

    /// `singleURLHost` must reject a URL string that has any non-ASCII
    /// whitespace character mixed in — those tokens aren't valid URLs
    /// and the preview should fall through to verbatim display, not
    /// crash and not collapse.
    func testSingleURLHostRejectsURLWithEmbeddedNBSP() {
        // NBSP between scheme and host — not a valid URL token.
        let weird = "https://exa\u{00A0}mple.com"
        XCTAssertNil(IMessagePreview.singleURLHost(in: weird),
            "URL with embedded NBSP must not be treated as a single-URL token")
    }
}
