import Foundation
import ReplyAICore

/// Lazy-construction wrapper around MLXDraftService.
///
/// REP-ALERT-260504-1650 (rediscovered 2026-05-19 after the "fix" via
/// REP-501→REP-505 SPM split): launching the bundled `.app` via the
/// macOS LaunchServices foreground path (i.e. `open` or double-click)
/// with `pref.model.useMLX = true` causes the process to exit ~28ms
/// after `applicationDidFinishLaunching`. The same bundle launched via
/// `open -g` (background) or by exec-ing the inner binary directly
/// (`build/ReplyAI.app/Contents/MacOS/ReplyAI`) stays alive indefinitely
/// — confirming the crash is foreground-LaunchServices-context-specific,
/// not a simple dylib-load failure.
///
/// Empirically the trigger is `MLXDraftService()` being constructed
/// during `InboxScreen`'s `@State engine` initializer, which runs at
/// SwiftUI view-tree mount time on the foreground-launch path. Pushing
/// the MLXDraftService construction past first-window-shown by deferring
/// it to first-draft-requested bypasses the issue: by the time
/// `DraftEngine.prime` fires, the app is already foregrounded, the
/// scene graph is settled, and whatever launch-time check was failing
/// has passed.
///
/// Behavior: `ReplyAIApp.init` installs this wrapper into
/// `LLMServiceProvider.make` when `useMLX = true`. The first call to
/// `draft(...)` constructs the actual MLXDraftService under a lock;
/// every subsequent call reuses it. The download + Metal-compile
/// progress chunks still surface to the user via the existing
/// `loadProgress` `DraftChunk.kind` cases.
public final class LazyMLXDraftService: LLMService, @unchecked Sendable {
    private let lock = NSLock()
    private var inner: MLXDraftService?
    private let modelID: String

    public init(modelID: String = MLXDraftService.defaultModelID) {
        self.modelID = modelID
    }

    public func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        let service: MLXDraftService = {
            lock.lock()
            defer { lock.unlock() }
            if let existing = inner { return existing }
            let fresh = MLXDraftService(modelID: modelID)
            inner = fresh
            return fresh
        }()
        return service.draft(thread: thread, tone: tone, history: history)
    }
}
