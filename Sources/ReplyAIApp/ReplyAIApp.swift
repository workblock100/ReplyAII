import SwiftUI
import ReplyAICore       // everything except MLXDraftService
import ReplyAIMLX        // MLXDraftService only — needed because the executable
                         // instantiates it when pref.model.useMLX = true.

/// Branches between WelcomeGate (first-run) and AppPrototypeView (returning
/// user). Reads `PreferenceKey.onboardingCompleted` via @AppStorage so the
/// view re-renders the moment the gate's "Get started" button writes true.
///
/// Also runs the global notification setup once at launch — registers the
/// inline-reply category and installs the UNUserNotificationCenter delegate
/// so any future system-posted notification routes through
/// `NotificationCoordinator.handleReply` even if the user never opens the
/// inbox window. Previously this only ran inside InboxScreen.task, leaving
/// the delegate unset on app launches that landed on the prototype gallery
/// or welcome gate.
struct RootView: View {
    @AppStorage(PreferenceKey.onboardingCompleted) private var completed = false
    @Environment(NotificationCoordinator.self) private var coordinator: NotificationCoordinator?

    var body: some View {
        Group {
            if completed {
                AppPrototypeView()
            } else {
                WelcomeGate()
            }
        }
        .task(id: "rootview-launch-setup") {
            await coordinator?.setUp()
        }
    }
}

/// `@main` entry point. Wires together the two SwiftUI WindowGroups
/// (prototype gallery + inbox), the MenuBarExtra `R` icon, and the
/// retained services that need to outlive any single window:
/// `NotificationCoordinator` (for incoming-message capture and
/// reply-from-notification) and `GlobalHotkey` (the Carbon-backed `⌘⇧R`
/// summon). Both are stored on the App value because the App's lifetime
/// equals the process's — releasing them would silently disable their
/// system-level integrations.
@main
struct ReplyAIApp: App {
    @State private var coordinator = NotificationCoordinator()
    /// REP-044: shared observable backing the menu-bar icon's badge.
    /// The MenuBarExtra label below subscribes via SwiftUI's @State
    /// mechanism; the InboxScreen pushes new counts into this from its
    /// `.onChange(of: model.threads)` modifier.
    @State private var menuBarBadge = MenuBarBadgeState.shared
    /// Held for the lifetime of the app; releasing it would deregister the
    /// system-wide ⌘⇧R hotkey. SwiftUI keeps `@StateObject`-style retains for
    /// any value-type state but a plain `let` is fine here — `App`'s lifetime
    /// equals the process's.
    private let globalHotkey = GlobalHotkey()

    init() {
        // REP-500: install the MLX-aware LLMService factory FIRST, before any
        // window scene constructs an InboxScreen. Without this, InboxScreen
        // would call the default LLMServiceProvider.make (which returns
        // StubLLMService) and the user's `useMLX=true` preference would be
        // silently ignored.
        //
        // Important: we still consult `pref.model.useMLX` at construction
        // time inside the closure (not here). That defers the actual
        // MLXDraftService() call — and the eager dylib loading it triggers —
        // until the first InboxScreen actually mounts. If MLX dylib loading
        // races with NSApp startup again (REP-ALERT-260504-1650), the structural
        // protection is that no MLXDraftService construction happens until
        // the first window scene needs one.
        LLMServiceProvider.make = { useMLX in
            // Explicit if/return form (instead of ternary) so each branch
            // coerces through the closure's `any LLMService` contextual type
            // independently — the ternary form makes the compiler search for
            // a common concrete type of MLXDraftService and StubLLMService,
            // which doesn't exist (they share only protocol conformance).
            if useMLX { return MLXDraftService() }
            return StubLLMService()
        }
        UserDefaults.registerReplyAIDefaults()
        let count = UserDefaults.standard.integer(forKey: PreferenceKey.launchCount)
        UserDefaults.standard.set(count + 1, forKey: PreferenceKey.launchCount)
        if UserDefaults.standard.object(forKey: PreferenceKey.firstLaunchDate) == nil {
            UserDefaults.standard.set(Date(), forKey: PreferenceKey.firstLaunchDate)
        }
        // Flush any pending debounced Stats writes before the process exits so
        // the last session's increments survive a fast quit or Force Quit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in Stats.shared.flushNow() }

        // Register the global hotkey if Accessibility permission is granted.
        // When the user grants it later (via ObPermissionsView), they need to
        // restart the app — Carbon's RegisterEventHotKey doesn't pick up newly
        // granted Accessibility on a running process. We surface this as a
        // hint in onboarding when the toggle goes from needs → granted.
        globalHotkey.register {
            ReplyAIWindowSummoner.summon()
        }
    }

    var body: some Scene {
        // Main window: gated by onboarding completion. New users see the
        // WelcomeGate (intro + permissions) until they click Get started;
        // returning users land in the prototype gallery, which surfaces
        // the inbox by default. Swap AppPrototypeView for `InboxScreen()`
        // to ship only the real app surface (no prototype gallery).
        WindowGroup("ReplyAI") {
            RootView()
                .environment(coordinator)
        }
        .defaultSize(width: 1360, height: 820)
        .windowStyle(.hiddenTitleBar)

        // Secondary window: the real inbox, standalone. Opened by the
        // menu-bar "Open inbox" button and from palette shortcuts.
        WindowGroup(ReplyAIWindowSummoner.inboxWindowTitle, id: ReplyAIWindowSummoner.inboxWindowID) {
            InboxScreen()
                .environment(coordinator)
        }
        .defaultSize(width: 1180, height: 720)
        .windowStyle(.hiddenTitleBar)

        // Real NSStatusItem presence — R icon lives in the system menu bar
        // whenever the app is running. Clicking opens the waiting-threads
        // popover.
        // REP-044: label is now a ViewBuilder so we can overlay the
        // unread-thread count on the R glyph reactively. Falls back to
        // the bare R when count is zero so unread-free inboxes don't
        // show visual noise.
        MenuBarExtra {
            MenuBarContent()
        } label: {
            if menuBarBadge.unreadCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "r.square.fill")
                    Text("\(menuBarBadge.unreadCount)")
                }
            } else {
                Image(systemName: "r.square.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
