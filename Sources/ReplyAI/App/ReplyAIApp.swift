import SwiftUI

@main
struct ReplyAIApp: App {
    init() {
        UserDefaults.registerReplyAIDefaults()
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
