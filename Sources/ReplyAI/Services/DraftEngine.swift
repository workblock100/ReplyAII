import Foundation
import Observation

@Observable
@MainActor
final class DraftEngine {
    struct Key: Hashable {
        let threadID: String
        let tone: Tone
    }

    struct DraftState: Equatable {
        var text: String = ""
        var confidence: Double = 1.0
        var isStreaming: Bool = false
        var isDone: Bool = false
        var error: String?

        var isLowConfidence: Bool { confidence < 0.4 }
    }

    private(set) var drafts: [Key: DraftState] = [:]

    private let service: LLMService
    private var tasks: [Key: Task<Void, Never>] = [:]

    init(service: LLMService = StubLLMService()) {
        self.service = service
    }

    func state(threadID: String, tone: Tone) -> DraftState {
        drafts[Key(threadID: threadID, tone: tone)] ?? .init()
    }

    /// Kicks off generation if we don't already have a cached draft for the key.
    func prime(thread: MessageThread, tone: Tone, history: [Message]) {
        let key = Key(threadID: thread.id, tone: tone)
        if let existing = drafts[key], existing.isDone || existing.isStreaming { return }
        generate(thread: thread, tone: tone, history: history)
    }

    /// Force-reruns generation, busting the cache for this (thread, tone).
    func regenerate(thread: MessageThread, tone: Tone, history: [Message]) {
        generate(thread: thread, tone: tone, history: history, force: true)
    }

    /// Clears the in-flight task + state for a specific key (⌘.).
    func dismiss(threadID: String, tone: Tone) {
        let key = Key(threadID: threadID, tone: tone)
        tasks[key]?.cancel()
        tasks[key] = nil
        drafts[key] = nil
    }

    private func generate(thread: MessageThread, tone: Tone, history: [Message], force: Bool = false) {
        let key = Key(threadID: thread.id, tone: tone)
        if !force, let existing = drafts[key], !existing.text.isEmpty { return }

        tasks[key]?.cancel()
        drafts[key] = DraftState(text: "", confidence: 1.0, isStreaming: true, isDone: false, error: nil)

        let stream = service.draft(thread: thread, tone: tone, history: history)
        tasks[key] = Task { [weak self] in
            do {
                for try await chunk in stream {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    self.apply(chunk: chunk, to: key)
                }
            } catch {
                guard let self else { return }
                self.fail(key: key, message: error.localizedDescription)
            }
        }
    }

    private func apply(chunk: DraftChunk, to key: Key) {
        var s = drafts[key] ?? .init()
        switch chunk.kind {
        case .text(let t):        s.text.append(t)
        case .confidence(let c):  s.confidence = c
        case .done:
            s.isStreaming = false
            s.isDone = true
        }
        drafts[key] = s
    }

    private func fail(key: Key, message: String) {
        var s = drafts[key] ?? .init()
        s.error = message
        s.isStreaming = false
        drafts[key] = s
    }
}
