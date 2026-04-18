import SwiftUI

@main
struct ReplyAIApp: App {
    var body: some Scene {
        WindowGroup("ReplyAI") {
            InboxScreen()
        }
        .defaultSize(width: 1180, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
