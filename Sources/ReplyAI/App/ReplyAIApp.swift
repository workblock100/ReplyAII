import SwiftUI

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
        // Main window: the 28-screen prototype gallery. This mirrors how
        // prototype.html was used — sidebar of screens, use ← / → to step.
        // Swap to `InboxScreen()` to ship only the real app surface.
        WindowGroup("ReplyAI Prototype") {
            AppPrototypeView()
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
