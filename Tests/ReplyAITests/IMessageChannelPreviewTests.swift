import XCTest
@testable import ReplyAI

final class IMessageChannelPreviewTests: XCTestCase {

    // MARK: - Plain text passes through

    func testPlainTextUnchanged() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: "wanna grab dinner?"),
            "wanna grab dinner?"
        )
    }

    func testMultiWordWithURLIsNotCollapsed() {
        // If the body is more than a URL — e.g. "check this out
        // https://foo.com" — we keep the original text.
        let body = "check https://example.com out"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    // MARK: - URL collapse

    func testSingleHTTPSURLCollapsesToHost() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: "https://example.com/path?q=1"),
            "🔗 example.com"
        )
    }

    func testSingleHTTPURLCollapsesToHost() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: "http://example.com"),
            "🔗 example.com"
        )
    }

    func testURLStripsLeadingWWW() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: "https://www.nytimes.com/article"),
            "🔗 nytimes.com"
        )
    }

    func testNonHTTPSchemeDoesNotCollapse() {
        // ftp://, mailto:, tel: etc. aren't clickable links in the
        // ThreadRow's context; pass them through so the user sees
        // what they actually received.
        let body = "ftp://files.example.com/a.bin"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    func testURLWithoutHostIsNotCollapsed() {
        let body = "https://"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    // MARK: - Attachments

    func testAttachmentSentinelBecomesPaperclip() {
        let body = String(IMessagePreview.objectReplacement)
        XCTAssertEqual(IMessagePreview.displayString(from: body), "📎 Attachment")
    }

    func testAttachmentSentinelWithWhitespaceBecomesPaperclip() {
        // Real rich-text attachments sometimes decode as "\uFFFC "
        // or " \uFFFC\n" — whitespace around the sentinel shouldn't
        // block the detection.
        let body = " \u{FFFC} \n"
        XCTAssertEqual(IMessagePreview.displayString(from: body), "📎 Attachment")
    }

    func testMultipleAttachmentSentinelsCollapse() {
        let body = "\u{FFFC}\u{FFFC}\u{FFFC}"
        XCTAssertEqual(IMessagePreview.displayString(from: body), "📎 Attachment")
    }

    func testAttachmentPlusTextKeepsText() {
        // A caption alongside an attachment should surface the caption,
        // not the generic "📎 Attachment" label.
        let body = "\u{FFFC} look at this"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body)
    }

    // MARK: - Fallback

    func testNilBodyFallsBackToNonTextMessage() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: nil),
            "[non-text message]"
        )
    }

    func testEmptyBodyFallsBackToNonTextMessage() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: ""),
            "[non-text message]"
        )
    }

    func testWhitespaceOnlyBodyFallsBackToNonTextMessage() {
        XCTAssertEqual(
            IMessagePreview.displayString(from: "   \n\t "),
            "[non-text message]"
        )
    }
}
