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
}
