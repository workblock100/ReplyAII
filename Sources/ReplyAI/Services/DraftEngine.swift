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

    /// Non-nil while the LLM service is loading weights (downloading or
    /// warming them into memory). Cleared when a real token arrives.
    var modelLoadStatus: ModelLoadStatus?

    struct ModelLoadStatus: Equatable, Sendable {
        var fraction: Double  // 0.0 – 1.0
        var message: String
    }

    private let service: LLMService
    private var tasks: [Key: Task<Void, Never>] = [:]
    /// Tracks the most-recently-started prime task per (threadID, tone) so
    /// rapid re-selection cancels the stale in-flight stream instead of
    /// silently accumulating dangling tasks.
    private var primingTasks: [String: Task<Void, Never>] = [:]
    private let stats: Stats?
    let store: DraftStore?

    init(service: LLMService = StubLLMService(), stats: Stats? = nil, store: DraftStore? = nil) {
        self.service = service
        self.stats = stats
        self.store = store
    }

    func state(threadID: String, tone: Tone) -> DraftState {
        drafts[Key(threadID: threadID, tone: tone)] ?? .init()
    }

    /// Kicks off generation if we don't already have a completed draft for
    /// the key. A second call for the same (threadID, tone) before the first
    /// completes cancels the prior in-flight stream and restarts — at most
    /// one stream is ever live per key.
    func prime(thread: MessageThread, tone: Tone, history: [Message]) {
        let key = Key(threadID: thread.id, tone: tone)
        if let existing = drafts[key], existing.isDone || !existing.text.isEmpty { return }
        let primingKey = "\(thread.id):\(tone.rawValue)"
        primingTasks[primingKey]?.cancel()
        generate(thread: thread, tone: tone, history: history)
        primingTasks[primingKey] = tasks[key]
    }

    /// Force-reruns generation, busting the cache for this (thread, tone).
    func regenerate(thread: MessageThread, tone: Tone, history: [Message]) {
        generate(thread: thread, tone: tone, history: history, force: true)
    }

    /// Number of live (threadID, tone) entries in the draft cache.
    var cacheSize: Int { drafts.count }

    /// Drops all cached draft states and in-flight tasks for a thread.
    /// Called when a thread is deselected so the cache doesn't grow
    /// unboundedly as the user browses.
    func evict(threadID: String) {
        let keys = drafts.keys.filter { $0.threadID == threadID }
        for key in keys {
            tasks[key]?.cancel()
            tasks[key] = nil
            primingTasks["\(key.threadID):\(key.tone.rawValue)"] = nil
            drafts[key] = nil
        }
    }

    /// Resets all (threadID, tone) draft states back to idle without removing
    /// the cache keys. In-flight streams are cancelled so stale content stops
    /// accumulating. A follow-up prime() can restart generation; the existing
    /// key slots mean no extra allocation on first access after invalidation.
    /// Called by InboxViewModel when the watcher delivers new messages to the
    /// currently selected thread — the draft was built without those messages
    /// and is now out of context.
    func invalidate(threadID: String) {
        let keys = drafts.keys.filter { $0.threadID == threadID }
        for key in keys {
            tasks[key]?.cancel()
            tasks[key] = nil
            primingTasks["\(key.threadID):\(key.tone.rawValue)"] = nil
            drafts[key] = DraftState()
        }
    }

    /// Clears the in-flight task + state for a specific key (⌘.).
    /// Also removes any persisted DraftStore entry so the stale draft does
    /// not reappear on the next launch.
    func dismiss(threadID: String, tone: Tone) {
        let key = Key(threadID: threadID, tone: tone)
        tasks[key]?.cancel()
        tasks[key] = nil
        primingTasks["\(threadID):\(tone.rawValue)"] = nil
        drafts[key] = nil
        store?.delete(threadID: threadID)
    }

    private func generate(thread: MessageThread, tone: Tone, history: [Message], force: Bool = false) {
        let key = Key(threadID: thread.id, tone: tone)
        if !force, let existing = drafts[key], !existing.text.isEmpty { return }

        tasks[key]?.cancel()
        drafts[key] = DraftState(text: "", confidence: 1.0, isStreaming: true, isDone: false, error: nil)
        stats?.recordDraftGenerated(tone: tone)

        let stream = service.draft(thread: thread, tone: tone, history: history)
        tasks[key] = Task { [weak self] in
            do {
                for try await chunk in stream {
                    guard let self else { return }
                    if Task.isCancelled { return }
                    self.apply(chunk: chunk, to: key)
                }
                // Stream finished normally. If no .done chunk was emitted (empty
                // stream), isStreaming is still true — transition to idle so the
                // caller isn't stuck waiting for a draft that will never arrive.
                guard let self, !Task.isCancelled else { return }
                if let s = self.drafts[key], s.isStreaming {
                    var cleared = s
                    cleared.isStreaming = false
                    self.drafts[key] = cleared
                }
            } catch {
                guard let self else { return }
                // Suppress errors thrown because *this* task was cancelled —
                // another prime() has already reset state for this key.
                if Task.isCancelled { return }
                self.fail(key: key, message: error.localizedDescription)
            }
        }
    }

    private func apply(chunk: DraftChunk, to key: Key) {
        var s = drafts[key] ?? .init()
        switch chunk.kind {
        case .text(let t):
            s.text.append(t)
            modelLoadStatus = nil   // first token means load is done
        case .confidence(let c):
            s.confidence = c
        case .loadProgress(let fraction, let message):
            modelLoadStatus = ModelLoadStatus(fraction: fraction, message: message)
        case .done:
            s.text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
            s.isStreaming = false
            s.isDone = true
            modelLoadStatus = nil
            store?.write(threadID: key.threadID, text: s.text)
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
