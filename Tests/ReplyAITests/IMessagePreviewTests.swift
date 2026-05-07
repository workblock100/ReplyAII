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

    /// Hosts arrive case-preserved from URL parsing; the implementation lowercases
    /// the whole host before checking the `www.` prefix so SHOUTY / mixed-case
    /// "WWW." in a pasted link strips the same as "www.". A future refactor that
    /// dropped the `.lowercased()` call (e.g. "we already trust URL to normalize")
    /// would silently regress: `WWW.GOOGLE.COM` would render as the full host
    /// instead of `google.com`. Pin both the SHOUTY and mixed-case forms.
    func testSingleURLHostStripsUppercaseAndMixedCaseWwwPrefix() {
        XCTAssertEqual(IMessagePreview.singleURLHost(in: "https://WWW.GOOGLE.COM/path"),
                       "google.com",
                       "uppercase WWW. prefix must be lowercased and stripped")
        XCTAssertEqual(IMessagePreview.singleURLHost(in: "https://Www.Example.org/x"),
                       "example.org",
                       "mixed-case Www. prefix must be lowercased and stripped")
    }

    /// The `🔗 ` link-prefix glyph is followed by exactly one ASCII space
    /// before the host. Pin the spacing so the preview never collapses to
    /// `🔗example.com` (no breathing room) or expands to a wider gap that
    /// breaks the sidebar's ThreadRow alignment.
    func testLinkPrefixIsExactlyOneAsciiSpace() {
        let preview = IMessagePreview.displayString(from: "https://example.com")
        XCTAssertEqual(preview, "🔗 example.com",
            "single-URL collapse must render as `🔗 <host>` with exactly one ASCII space; got: \(preview)")
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

    // MARK: - Pass-through preserves verbatim text

    /// `displayString` uses `trimmed` for the URL/attachment branch
    /// detection but returns the ORIGINAL `body` on plain-text
    /// pass-through — leading/trailing whitespace survives. Pin this
    /// because a "tidy up" refactor that returned `trimmed` instead
    /// would silently change every sidebar preview that arrived with
    /// surrounding whitespace, and cross-channel paste-from-clipboard
    /// flows commonly produce exactly that.
    func testPlainTextPassThroughPreservesLeadingAndTrailingWhitespace() {
        let body = "  hello world  "
        XCTAssertEqual(IMessagePreview.displayString(from: body), body,
            "plain-text pass-through must preserve leading/trailing whitespace verbatim")
    }

    /// Embedded newlines are part of the verbatim pass-through too —
    /// the sidebar trims for layout via SwiftUI's `.lineLimit(1)` and
    /// truncation rather than by mutating the source text. A refactor
    /// that pre-flattened newlines here would diverge the cached
    /// preview from the canonical message body and break any future
    /// `previewMatches(message:)` invariant.
    func testPlainTextPassThroughPreservesEmbeddedNewlines() {
        let body = "line one\nline two"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body,
            "plain-text pass-through must preserve embedded newlines verbatim")
    }

    /// Tab characters are pass-through too. `.whitespacesAndNewlines`
    /// includes `\t` (U+0009), so a tab-only body falls back to the
    /// non-text label (covered in the trimming tests), but a mixed
    /// "tab + content" body must survive intact.
    func testPlainTextPassThroughPreservesEmbeddedTabs() {
        let body = "col1\tcol2\tcol3"
        XCTAssertEqual(IMessagePreview.displayString(from: body), body,
            "plain-text pass-through must preserve embedded tabs verbatim")
    }

    // MARK: - URL component handling pins (singleURLHost edges)

    /// URLs with an explicit port — the host extraction must NOT include
    /// the `:port` suffix, since `URL.host` parses that into a separate
    /// `port` component. Pin so a refactor that switches to
    /// `url.absoluteString.dropFirst(scheme.count)` style parsing
    /// (which would include the port) surfaces here.
    func testSingleURLHostStripsExplicitPort() {
        let body = "https://example.com:8080/api"
        XCTAssertEqual(IMessagePreview.singleURLHost(in: body), "example.com",
            "URL.host returns the host without the port; pin so refactors don't accidentally include `:8080` in the sidebar label")
    }

    /// URLs with userinfo (username:password@host). `URL.host` returns
    /// just the host portion, dropping the credentials. Pin so a
    /// refactor that accidentally exposes user@example.com in a sidebar
    /// preview surfaces here. Real-world: chat.db can contain pasted
    /// admin / VPN URLs that include creds.
    func testSingleURLHostStripsUserinfo() {
        let body = "https://user:pass@example.com/dashboard"
        XCTAssertEqual(IMessagePreview.singleURLHost(in: body), "example.com",
            "URL.host omits userinfo; sidebar must never leak `user:pass@` to the visible preview")
    }

    /// `www.` prefix stripping is applied AFTER lowercasing the full
    /// host, so `WWW.API.EXAMPLE.COM` → `api.example.com`. Pin the
    /// double behavior (lowercase + prefix strip composed) since
    /// reordering them would silently break uppercase-www inputs.
    func testSingleURLHostStripsWwwAfterLowercasing() {
        let body = "https://WWW.API.EXAMPLE.COM/v1"
        XCTAssertEqual(IMessagePreview.singleURLHost(in: body), "api.example.com",
            "lowercase first, then strip `www.` — order matters; uppercase WWW. must still be detected and removed")
    }

    /// Subdomain immediately after a stripped `www.` is preserved.
    /// `www.api.example.com` → `api.example.com`, NOT `example.com`.
    /// Pin because a future change that interpreted the strip as
    /// "remove the leftmost label always" would silently shorten
    /// every subdomain URL the user pastes.
    func testSingleURLHostPreservesSubdomainAfterWwwStrip() {
        let body = "https://www.api.example.com/v1"
        XCTAssertEqual(IMessagePreview.singleURLHost(in: body), "api.example.com",
            "stripping `www.` removes only the literal four-char prefix; deeper subdomains must remain")
    }

    /// `https://www.<one-char>.com/` — the host is `www.x.com`, length
    /// 9, so the `count > 4` guard passes and the prefix is stripped
    /// to `x.com`. Pin the boundary (4 chars after `www.` for "x.com"
    /// = 5 chars total post-strip) so a refactor that tightens the
    /// guard to `count > 8` doesn't quietly stop stripping short hosts.
    func testSingleURLHostStripsWwwForShortHost() {
        let body = "https://www.x.com/"
        XCTAssertEqual(IMessagePreview.singleURLHost(in: body), "x.com",
            "host is `www.x.com` (9 chars), passes the count > 4 guard, strips to `x.com`")
    }

    /// `displayString` round-trips a URL through the full pipeline (not
    /// just `singleURLHost`), so a port-bearing URL must produce
    /// `🔗 example.com` — no port in the chip. Anchors the pin against
    /// the user-visible string, in case the rendering layer ever
    /// re-introduces port information for "display fidelity."
    func testDisplayStringWithPortShowsBareHost() {
        XCTAssertEqual(IMessagePreview.displayString(from: "https://example.com:8443/x"),
                       "🔗 example.com",
            "user-visible chip must show only the host; ports never round-trip into the sidebar")
    }
}
