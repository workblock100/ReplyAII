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
}
