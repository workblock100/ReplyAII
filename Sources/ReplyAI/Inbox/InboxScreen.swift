import SwiftUI

struct InboxScreen: View {
    @AppStorage(PreferenceKey.useMLX) private var useMLX = PreferenceDefaults.useMLX
    @Environment(NotificationCoordinator.self) private var coordinator: NotificationCoordinator?
    @State private var model = InboxViewModel()
    @State private var engine: DraftEngine = {
        let useMLXNow = UserDefaults.standard.bool(forKey: PreferenceKey.useMLX)
        let service: LLMService = useMLXNow ? MLXDraftService() : StubLLMService()
        return DraftEngine(service: service)
    }()
    @State private var paletteOpen = false

    /// Current visible draft text — user's edit if present, else the
    /// streamed text from DraftEngine. `⌘↵` snapshots this into
    /// model.sendConfirmation.
    private var currentDraftText: String {
        let state = engine.state(threadID: model.selectedThreadID, tone: model.activeTone)
        return model.effectiveDraft(
            threadID: model.selectedThreadID,
            tone: model.activeTone,
            fallback: state.text
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .denied(let hint) = model.syncStatus {
                FDABanner(hint: hint) {
                    Task { await model.syncFromIMessage() }
                }
            }
            if let loadStatus = engine.modelLoadStatus {
                ModelLoadBanner(status: loadStatus)
            }
            HStack(spacing: 0) {
                SidebarView(model: model)
                ThreadListView(model: model)
                ThreadDetailView(model: model)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 1180, minHeight: 720)
        .background(Theme.Color.bg1)
        .preferredColorScheme(.dark)
        .environment(engine)
        .overlay {
            if paletteOpen {
                paletteOverlay
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.sendToast {
                Text(toast)
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(Theme.Color.accent))
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.std, value: model.sendToast)
        .sheet(isPresented: sendConfirmPresented()) {
            SendConfirmSheet(model: model)
        }
        .task(id: "initial-sync") {
            coordinator?.inbox = model
            await coordinator?.setUp()
            await model.syncFromIMessage()
        }
        .task(id: model.selectedThreadID) {
            await model.loadMessages(for: model.selectedThreadID)
        }
        // Global command shortcuts — wired through .background so they stay
        // active whenever the inbox is on screen.
        .background(keyboardCommands)
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(Theme.Motion.fast) { paletteOpen = false } }
            PalettePopover(
                searchIndex: model.searchIndex,
                onJump: { hit in
                    withAnimation(Theme.Motion.std) { model.selectThread(hit.threadID) }
                    paletteOpen = false
                }
            )
            .padding(.top, 120)
        }
        .background(
            Button("Close palette") {
                withAnimation(Theme.Motion.fast) { paletteOpen = false }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
        )
    }

    @ViewBuilder
    private var keyboardCommands: some View {
        Color.clear
            .background(
                Button("Regenerate") {
                    let thread = model.selectedThread
                    model.clearEdit(threadID: thread.id, tone: model.activeTone)
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
                // Send — stage the current draft for confirmation. The
                // confirm sheet dispatches via AppleScript only after the
                // user explicitly approves, so a hallucinated stub draft
                // can't go out by accident.
                Button("Send") {
                    let text = currentDraftText
                    guard !text.isEmpty else { return }
                    model.requestSend(text: text)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
            )
            .background(
                Button("Command palette") {
                    withAnimation(Theme.Motion.std) { paletteOpen.toggle() }
                }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
            )
            .background(
                Button("Refresh iMessage") {
                    Task { await model.syncFromIMessage() }
                }
                .keyboardShortcut("r", modifiers: .command)
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

extension InboxScreen {
    fileprivate func sendConfirmPresented() -> Binding<Bool> {
        Binding(
            get: { model.sendConfirmation != nil },
            set: { present in if !present { model.cancelSend() } }
        )
    }
}
