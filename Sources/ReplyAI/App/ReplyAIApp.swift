import SwiftUI

/// Branches between WelcomeGate (first-run) and AppPrototypeView (returning
/// user). Reads `PreferenceKey.onboardingCompleted` via @AppStorage so the
/// view re-renders the moment the gate's "Get started" button writes true.
struct RootView: View {
    @AppStorage(PreferenceKey.onboardingCompleted) private var completed = false

    var body: some View {
        if completed {
            AppPrototypeView()
        } else {
            WelcomeGate()
        }
    }
}

@main
struct ReplyAIApp: App {
    @State private var coordinator = NotificationCoordinator()
    /// Held for the lifetime of the app; releasing it would deregister the
    /// system-wide ⌘⇧R hotkey. SwiftUI keeps `@StateObject`-style retains for
    /// any value-type state but a plain `let` is fine here — `App`'s lifetime
    /// equals the process's.
    private let globalHotkey = GlobalHotkey()

    init() {
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
        }
        .defaultSize(width: 1360, height: 820)
        .windowStyle(.hiddenTitleBar)

        // Secondary window: the real inbox, standalone. Opened by the
        // menu-bar "Open inbox" button and from palette shortcuts.
        WindowGroup("Inbox", id: "inbox") {
            InboxScreen()
                .environment(coordinator)
        }
        .defaultSize(width: 1180, height: 720)
        .windowStyle(.hiddenTitleBar)

        // Real NSStatusItem presence — R icon lives in the system menu bar
        // whenever the app is running. Clicking opens the waiting-threads
        // popover.
        MenuBarExtra("ReplyAI", systemImage: "r.square.fill") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.window)
    }
}
