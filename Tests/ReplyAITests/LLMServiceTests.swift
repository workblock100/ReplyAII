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
}
