import SwiftUI
import AppKit

/// Main inbox surface — wires `InboxViewModel` and `DraftEngine` together,
/// mounts the sidebar / thread-list / detail layout, and overlays the
/// command palette and model-load banner. The DraftEngine's underlying
/// LLM service (MLX vs stub) is selected at construction time off
/// `pref.useMLX`; toggling that pref takes effect on the next launch.
public struct InboxScreen: View {
    @AppStorage(PreferenceKey.useMLX) private var useMLX = PreferenceDefaults.useMLX
    /// Drives the LimitedModeBanner — true until any channel sync returns
    /// ≥1 real thread (REP-228 flips this on `Preferences.demoModeActive`).
    @AppStorage(PreferenceKey.demoModeActive) private var demoModeActive = PreferenceDefaults.demoModeActive
    /// Session-only dismissal for the Limited Mode banner. Re-shows on
    /// next launch until `demoModeActive` itself flips to false.
    @State private var limitedModeBannerDismissed = false
    @Environment(NotificationCoordinator.self) private var coordinator: NotificationCoordinator?
    /// Honor System Settings → Accessibility → Display → Reduce Motion.
    /// Every `withAnimation(...)` call in this file gates on this flag —
    /// a Reduce Motion user gets instant cuts on palette open/close,
    /// thread switch, tone cycle, and palette-jump-to-thread (matches the
    /// REP-083 contract for the inbox surface).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = InboxViewModel()
    @State private var engine: DraftEngine = {
        let useMLXNow = UserDefaults.standard.bool(forKey: PreferenceKey.useMLX)
        // REP-500: indirection via LLMServiceProvider so ReplyAICore doesn't
        // import ReplyAIMLX. ReplyAIApp.init installs the MLX-aware factory
        // before any window scene constructs an InboxScreen; absent that
        // override (e.g. unit-test construction), the user gets stub drafts.
        let service = LLMServiceProvider.make(useMLXNow)
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

    public init() {}

    /// REP-259: deep-link to the top-level Privacy & Security pane in
    /// System Settings, which is where the user grants Full Disk Access,
    /// Contacts, Notifications, and Accessibility. The same destination
    /// is reachable from the per-permission cards in `ObPermissionsView`;
    /// when those cards each open a more specific pane, the Limited Mode
    /// banner intentionally surfaces the top-level Privacy pane because
    /// the user typically needs to grant multiple permissions in sequence.
    private func openSystemPrivacyPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // FDA banner suppressed per 2026-04-23 pivot. The chat.db / FDA
            // path is no longer the primary route; alternative architectures
            // (AppleScript, UNNotification capture, demo mode) are taking over.
            // The `.denied` case in SyncStatus is preserved but no longer
            // emitted by InboxViewModel.syncFromIMessage — see that method's
            // catch block. Re-enable here only if you intentionally bring FDA
            // back as a primary path.
            if case .denied(let hint) = model.syncStatus, false {
                FDABanner(hint: hint) {
                    Task { await model.syncFromIMessage() }
                }
            }
            if let loadStatus = engine.modelLoadStatus {
                ModelLoadBanner(status: loadStatus)
            }
            // REP-259: Limited Mode affordance. Pivot-aligned — the app must
            // be valuable to a user with zero permissions granted. When demo
            // mode is active (no channel returned real threads yet), surface
            // a banner that explains the state and points to Settings.
            if demoModeActive && !limitedModeBannerDismissed {
                LimitedModeBanner(
                    onOpenSettings: openSystemPrivacyPane,
                    onDismiss: {
                        withAnimation(reduceMotion ? nil : Theme.Motion.std) {
                            limitedModeBannerDismissed = true
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
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
        .onChange(of: model.selectedThreadID) { old, _ in engine.evict(threadID: old) }
        // Global command shortcuts — wired through .background so they stay
        // active whenever the inbox is on screen.
        .background(keyboardCommands)
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(reduceMotion ? nil : Theme.Motion.fast) { paletteOpen = false } }
            PalettePopover(
                searchIndex: model.searchIndex,
                onJump: { hit in
                    withAnimation(reduceMotion ? nil : Theme.Motion.std) { model.selectThread(hit.threadID) }
                    paletteOpen = false
                }
            )
            .padding(.top, 120)
        }
        .background(
            Button("Close palette") {
                withAnimation(reduceMotion ? nil : Theme.Motion.fast) { paletteOpen = false }
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
                    withAnimation(reduceMotion ? nil : Theme.Motion.tone) { model.cycleTone() }
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
                    withAnimation(reduceMotion ? nil : Theme.Motion.std) { paletteOpen.toggle() }
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
        withAnimation(reduceMotion ? nil : Theme.Motion.std) { model.selectThread(next) }
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
