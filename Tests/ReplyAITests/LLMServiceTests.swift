import XCTest
@testable import ReplyAI

final class LLMServiceTests: XCTestCase {
    func testTokenizerPreservesContent() {
        let input = "hello world how are you"
        let tokens = StubLLMService.tokenize(input)
        XCTAssertEqual(tokens.joined(), input)
    }

    func testTokenizerSplitsOnWhitespace() {
        let tokens = StubLLMService.tokenize("a b c")
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens, ["a ", "b ", "c"])
    }

    func testTokenizerHandlesEmpty() {
        XCTAssertEqual(StubLLMService.tokenize(""), [])
    }

    func testTokenizerPreservesNewlines() {
        let tokens = StubLLMService.tokenize("a\nb")
        XCTAssertEqual(tokens, ["a\n", "b"])
    }

    func testStreamEmitsConfidenceFirst() async throws {
        let svc = StubLLMService(tokenDelay: 0...0, initialDelay: 0)
        let thread = Fixtures.threads[0]
        var chunks: [DraftChunk.Kind] = []
        let sample = Fixtures.seedDraft(threadID: thread.id, tone: .warm)
        for try await chunk in svc.draft(thread: thread, tone: .warm, history: []) {
            if case .text = chunk.kind, chunks.count > 8 { break }
            chunks.append(chunk.kind)
        }
        guard case .confidence = chunks.first else {
            XCTFail("expected first chunk to be .confidence; got \(chunks.first.map(String.init(describing:)) ?? "nil")")
            return
        }
        XCTAssertFalse(sample.isEmpty, "fixture draft for first thread should not be empty")
    }

    // MARK: - tokenizer edge cases

    func testTokenizerHandlesLeadingWhitespace() {
        // Leading whitespace must surface as its own token so the streamed
        // draft preserves intentional indentation rather than swallowing it.
        XCTAssertEqual(StubLLMService.tokenize(" abc"), [" ", "abc"])
    }

    func testTokenizerHandlesConsecutiveSpaces() {
        // Each space terminates the current token; a run of N spaces between
        // words yields N space-only tokens. Keeps `joined()` round-trip exact
        // — important because the composer appends tokens directly to the
        // draft string as they arrive from the stream.
        XCTAssertEqual(StubLLMService.tokenize("a  b"), ["a ", " ", "b"])
        XCTAssertEqual(StubLLMService.tokenize("a  b").joined(), "a  b",
                       "consecutive spaces must round-trip exactly")
    }

    func testTokenizerHandlesTrailingNewline() {
        // A trailing whitespace char closes the final token and leaves no
        // dangling empty-string token in the output (the function explicitly
        // skips appending empty `current` at the end).
        XCTAssertEqual(StubLLMService.tokenize("a\n"), ["a\n"])
        XCTAssertEqual(StubLLMService.tokenize("ab "), ["ab "])
    }

    func testStreamEndsWithDoneChunk() async throws {
        // The composer relies on `.done` arriving before the stream finishes
        // so it can flip from "drafting" to "ready"; without this the UI
        // would stay in the loading state until the next user action.
        let svc = StubLLMService(tokenDelay: 0...0, initialDelay: 0)
        let thread = Fixtures.threads[0]
        var lastKind: DraftChunk.Kind?
        for try await chunk in svc.draft(thread: thread, tone: .direct, history: []) {
            lastKind = chunk.kind
        }
        guard let lastKind, case .done = lastKind else {
            XCTFail("expected final chunk to be .done; got \(lastKind.map(String.init(describing:)) ?? "nil")")
            return
        }
    }

    func testStreamConfidenceMatchesFixtureSeed() async throws {
        // The confidence emitted on the first chunk must equal what the rest
        // of the app derives from `Fixtures.seedConfidence(threadID:tone:)` —
        // otherwise the confidence pill the composer shows during streaming
        // would disagree with the value the UI uses elsewhere.
        let svc = StubLLMService(tokenDelay: 0...0, initialDelay: 0)
        let thread = Fixtures.threads[0]
        let expected = Fixtures.seedConfidence(threadID: thread.id, tone: .warm)

        var observed: Double?
        for try await chunk in svc.draft(thread: thread, tone: .warm, history: []) {
            if case .confidence(let v) = chunk.kind {
                observed = v
                break
            }
        }
        XCTAssertEqual(observed, expected,
                       "confidence emitted by stream must match the fixture seed")
    }

    func testStreamTextChunksConcatenateToSeedDraft() async throws {
        // The composer appends text chunks directly as they arrive. The full
        // concatenation must equal the fixture seed so what the user sees in
        // the composer matches what `Fixtures.seedDraft` returned.
        let svc = StubLLMService(tokenDelay: 0...0, initialDelay: 0)
        let thread = Fixtures.threads[0]
        let expected = Fixtures.seedDraft(threadID: thread.id, tone: .direct)

        var assembled = ""
        for try await chunk in svc.draft(thread: thread, tone: .direct, history: []) {
            if case .text(let t) = chunk.kind { assembled.append(t) }
        }
        XCTAssertEqual(assembled, expected,
                       "concatenated text chunks must equal the fixture seed exactly")
    }

    /// Tab characters are NOT delimiters — the implementation only splits
    /// on space (`" "`) and newline (`"\n"`). This is intentional: a tab
    /// inside a code-formatted reply or pasted snippet should stay glued
    /// to the surrounding word so the composer renders the tab as part of
    /// one token. Pin the behavior here so a future "make whitespace
    /// uniform" refactor surfaces as a deliberate edit rather than a
    /// silent change to streaming chunk shape.
    func testTokenizerKeepsTabsInsideTokens() {
        XCTAssertEqual(StubLLMService.tokenize("a\tb"), ["a\tb"],
            "tabs are not split delimiters — only space and newline are")
        XCTAssertEqual(StubLLMService.tokenize("a\t\tb"), ["a\t\tb"],
            "consecutive tabs must also stay glued to the surrounding tokens")
    }

    /// Single character with no whitespace must surface as one token —
    /// not split on every char, not return an empty array. The implementation
    /// has an `if !current.isEmpty { out.append(current) }` tail clause
    /// that handles this case; pin it explicitly so a refactor that drops
    /// the tail (e.g. only-on-delimiter-emit) shows up here.
    func testTokenizerSingleCharWithoutDelimiterEmitsOneToken() {
        XCTAssertEqual(StubLLMService.tokenize("a"), ["a"],
            "single non-whitespace char must produce exactly one token")
        XCTAssertEqual(StubLLMService.tokenize("hello"), ["hello"],
            "single word with no delimiters must emit one token, not split per-char")
    }

    /// All-delimiter inputs (a string consisting entirely of split chars)
    /// must produce one single-character token per delimiter, NOT collapse
    /// to a single multi-char token and NOT drop empty tokens. The contract
    /// matters for the streaming composer: each yielded chunk arrives in
    /// the user's pacing, so a 3-space prefix should arrive as three
    /// successive space chunks rather than as a single instant 3-space
    /// blob (or, worse, get swallowed entirely). The existing consecutive-
    /// space pin covers the *between-words* case ("a  b"); this fills the
    /// pure-whitespace gap. A future "merge consecutive whitespace" or
    /// "strip leading delimiters" refactor flips this and should surface
    /// here as a deliberate edit.
    func testTokenizerAllSpacesProducesOneTokenPerSpace() {
        XCTAssertEqual(StubLLMService.tokenize("   "), [" ", " ", " "],
            "an all-spaces input must emit N single-space tokens, not collapse to one")
        XCTAssertEqual(StubLLMService.tokenize("   ").joined(), "   ",
            "joined() must round-trip the original byte-for-byte (chunk-pacing UX depends on this)")
        XCTAssertEqual(StubLLMService.tokenize(" "), [" "],
            "a one-space input must emit exactly one single-space token")
    }

    func testTokenizerAllNewlinesProducesOneTokenPerNewline() {
        XCTAssertEqual(StubLLMService.tokenize("\n\n"), ["\n", "\n"],
            "an all-newlines input must emit N single-newline tokens, not collapse to one")
        XCTAssertEqual(StubLLMService.tokenize("\n\n").joined(), "\n\n",
            "joined() must round-trip the original byte-for-byte")
        XCTAssertEqual(StubLLMService.tokenize("\n"), ["\n"],
            "a one-newline input must emit exactly one single-newline token")
    }

    // MARK: - Production timing defaults
    //
    // `StubLLMService(tokenDelay:initialDelay:)` defaults control the
    // demo composer's perceived "typing speed". Tests routinely override
    // both to zero for deterministic timing, which means a regression
    // that doubles either default (a copy-paste bug, an accidental
    // unit-conversion error) would never surface in test output. Pin
    // the production literals so a perceived-latency drift in demo
    // mode (the only path StubLLMService runs in production) shows up
    // here as a deliberate edit.

    /// 180 ms cold-start "thinking" pause before the first token streams.
    /// Faster looks fake; slower looks broken. Pin the literal.
    func testInitialDelayDefaultIs180Ms() {
        let svc = StubLLMService()
        XCTAssertEqual(svc.initialDelay, 180_000_000,
            "initialDelay default is the perceived 'thinking' beat before tokens stream — drift here changes demo-composer cadence")
    }

    /// 22–58 ms per-token jitter range. Both ends matter: 22 ms is the
    /// floor that keeps tokens visible as separate words; 58 ms is the
    /// ceiling that prevents the composer from feeling stalled.
    func testTokenDelayDefaultIs22To58Ms() {
        let svc = StubLLMService()
        XCTAssertEqual(svc.tokenDelay.lowerBound, 22_000_000,
            "tokenDelay lower bound — drift below ~22ms makes streaming look instant; above stalls perceived word emission")
        XCTAssertEqual(svc.tokenDelay.upperBound, 58_000_000,
            "tokenDelay upper bound — drift above ~58ms makes the composer feel slow")
    }

    /// Constants pin: the named statics that build the production
    /// defaults must match the inline literals the existing instance
    /// pins assert against. The instance pins are the contract from
    /// the production-instantiation path; this pin is the contract
    /// from the named-constant path. Drift on either alone is
    /// caught — the no-arg StubLLMService init must route through
    /// `defaultInitialDelay` / `defaultTokenDelay`, otherwise the
    /// statics become dead code while inline literals live on in the
    /// init signature.
    func testDefaultInitialDelayConstantIs180Ms() {
        XCTAssertEqual(StubLLMService.defaultInitialDelay, 180_000_000,
            "defaultInitialDelay drift changes demo-composer cadence — pin so refactors that 'simplify' the constant land in code review")
    }

    func testDefaultTokenDelayConstantIs22To58Ms() {
        XCTAssertEqual(StubLLMService.tokenDelayLowerBoundNanoseconds, 22_000_000,
            "tokenDelayLowerBoundNanoseconds drift breaks the per-token streaming feel")
        XCTAssertEqual(StubLLMService.tokenDelayUpperBoundNanoseconds, 58_000_000,
            "tokenDelayUpperBoundNanoseconds drift makes the composer feel slow")
        XCTAssertEqual(StubLLMService.defaultTokenDelay,
                       StubLLMService.tokenDelayLowerBoundNanoseconds...StubLLMService.tokenDelayUpperBoundNanoseconds,
            "defaultTokenDelay must compose from the named lower/upper bounds — drift between them mixes a hardcoded range with the bound constants")
    }

    /// Round-trip: the no-arg init must route the default args
    /// through the named static constants, not through inline
    /// literals. Otherwise the statics become dead code while the
    /// init signature silently keeps a different value.
    func testNoArgInitRoutesThroughNamedDefaults() {
        let svc = StubLLMService()
        XCTAssertEqual(svc.initialDelay, StubLLMService.defaultInitialDelay,
            "no-arg StubLLMService init must route initialDelay through defaultInitialDelay")
        XCTAssertEqual(svc.tokenDelay, StubLLMService.defaultTokenDelay,
            "no-arg StubLLMService init must route tokenDelay through defaultTokenDelay")
    }

    /// Pin the Swift-grapheme-cluster CRLF behavior. `tokenize` iterates
    /// over `text` as `Character`s, and Swift's `Character` is an extended
    /// grapheme cluster — `"\r\n"` parses as a SINGLE `Character`, not two.
    /// That cluster is `!= " "` and `!= "\n"`, so the equality check
    /// `ch == " " || ch == "\n"` fails on it: a CRLF-laced body produces
    /// ONE token, not the LF-split shape a byte-level tokenizer would
    /// emit. This is "surprising-but-safe" — pasted Windows / RFC-822
    /// content stays glued, but a future swap to `text.unicodeScalars`
    /// (which DOES emit `\r` and `\n` as separate scalars) would silently
    /// start splitting CRLF input mid-stream. Pin the cluster behavior so
    /// the scalar-iteration swap surfaces here, not as a token-cadence
    /// flicker for every pasted-from-Windows draft.
    func testTokenizerTreatsCRLFAsSingleGraphemeAndDoesNotSplit() {
        XCTAssertEqual(StubLLMService.tokenize("hi\r\nthere"),
                       ["hi\r\nthere"],
                       "Swift `Character` clusters CRLF — `\"\\r\\n\"` is one Character, not two; tokenize must keep CRLF input as ONE token. Drift toward `text.unicodeScalars` would split mid-cluster")
        XCTAssertEqual(StubLLMService.tokenize("hi\rthere"),
                       ["hi\rthere"],
                       "bare `\\r` (no `\\n`) is NOT a delimiter — pinning the lone-CR case rules out a future `\\r||\\n` widening that would silently flip Mac classic-style line endings into split tokens")
        // Sanity: the LF-only path (no CR) still splits.
        XCTAssertEqual(StubLLMService.tokenize("hi\nthere"),
                       ["hi\n", "there"],
                       "control: bare `\\n` IS still a delimiter — the cluster-only behavior above is specific to the CRLF compound, not a regression of LF splitting")
    }

    /// Pin the ASCII-space-only delimiter contract — Unicode whitespace
    /// (NBSP, em-space, ideographic space, etc.) is NOT a delimiter.
    /// `tokenize` checks `ch == " "`, which matches U+0020 verbatim and
    /// rejects U+00A0 NO-BREAK SPACE, U+2003 EM SPACE, U+3000 IDEOGRAPHIC
    /// SPACE, etc. Drafts that include emoji, Asian punctuation, or
    /// rich text containing non-breaking spaces (e.g. when the composer
    /// pastes from Pages / Notion) must keep their whitespace glued to
    /// the surrounding token so `joined()` round-trips losslessly. Drift
    /// toward `ch.isWhitespace` would split on every Unicode-class
    /// whitespace char — the joined-stream content stays the same but
    /// the inter-token cadence the composer animates against changes
    /// silently for every Unicode-rich draft. Pin three specific
    /// whitespace chars to guard the contract.
    func testTokenizerDoesNotSplitOnUnicodeWhitespace() {
        // U+00A0 NO-BREAK SPACE — heavily used in French typography, in
        // common rich-text editors, and as the byte AppleScript inserts
        // when escaping certain message bodies.
        XCTAssertEqual(StubLLMService.tokenize("a\u{00A0}b"),
                       ["a\u{00A0}b"],
                       "U+00A0 NO-BREAK SPACE must NOT split — only U+0020 ASCII SPACE does")
        // U+2003 EM SPACE — used in typographic layout and pasted from
        // word-processor sources.
        XCTAssertEqual(StubLLMService.tokenize("a\u{2003}b"),
                       ["a\u{2003}b"],
                       "U+2003 EM SPACE must NOT split — pin so a future `Character.isWhitespace` swap surfaces here")
        // U+3000 IDEOGRAPHIC SPACE — CJK content, common in pasted
        // drafts from Japanese/Chinese chat clients.
        XCTAssertEqual(StubLLMService.tokenize("a\u{3000}b"),
                       ["a\u{3000}b"],
                       "U+3000 IDEOGRAPHIC SPACE must NOT split — CJK content stays one token")
    }
}
