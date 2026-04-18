import SwiftUI

struct InboxScreen: View {
    @State private var model = InboxViewModel()
    @State private var engine = DraftEngine()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            ThreadListView(model: model)
            ThreadDetailView(model: model)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 1180, minHeight: 720)
        .background(Theme.Color.bg1)
        .preferredColorScheme(.dark)
        .environment(engine)
        // Global command shortcuts — wired through .background so they stay
        // active whenever the inbox is on screen.
        .background(keyboardCommands)
    }

    @ViewBuilder
    private var keyboardCommands: some View {
        Color.clear
            .background(
                Button("Regenerate") {
                    let thread = model.selectedThread
                    engine.regenerate(
                        thread: thread,
                        tone: model.activeTone,
                        history: model.messages(for: thread)
                    )
                }
                .keyboardShortcut("j", modifiers: .command)
                .opacity(0)
            )
            .background(
                Button("Cycle tone") {
                    withAnimation(Theme.Motion.tone) { model.cycleTone() }
                }
                .keyboardShortcut("/", modifiers: .command)
                .opacity(0)
            )
            .background(
                Button("Dismiss draft") {
                    engine.dismiss(threadID: model.selectedThreadID, tone: model.activeTone)
                }
                .keyboardShortcut(".", modifiers: .command)
                .opacity(0)
            )
            .background(
                // Send — channel send is stubbed until channel integrations land.
                // Advances to next thread so the hotkey feels live.
                Button("Send") {
                    advanceToNextThread()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
            )
    }

    private func advanceToNextThread() {
        let ids = model.threads.map(\.id)
        guard let i = ids.firstIndex(of: model.selectedThreadID) else { return }
        let next = ids[(i + 1) % ids.count]
        withAnimation(Theme.Motion.std) { model.selectThread(next) }
    }
}
