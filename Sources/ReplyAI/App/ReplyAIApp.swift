import SwiftUI

@main
struct ReplyAIApp: App {
    var body: some Scene {
        // Main window: the 28-screen prototype gallery. This mirrors how
        // prototype.html was used — sidebar of screens, use ← / → to step.
        // Swap to `InboxScreen()` to ship only the real app surface.
        WindowGroup("ReplyAI Prototype") {
            AppPrototypeView()
        }
        .defaultSize(width: 1360, height: 820)
        .windowStyle(.hiddenTitleBar)

        // Secondary window: the real inbox, standalone. Useful for testing
        // just the production surface.
        WindowGroup("Inbox", id: "inbox") {
            InboxScreen()
        }
        .defaultSize(width: 1180, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}
