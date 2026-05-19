import Foundation
import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon's `RegisterEventHotKey`. Used for
/// the `⌘⇧R` "open ReplyAI from anywhere" affordance. NSEvent's global monitor
/// is observe-only — it can't intercept and doesn't replace the focused app's
/// handling — so the proper API for an actual hotkey on macOS remains Carbon
/// even in 2026. The library is part of HIToolbox and stable.
///
/// Lifecycle: register once at app launch, hold the returned `GlobalHotkey`
/// for the lifetime of the app, call `unregister()` (or just release the
/// instance) when shutting down. Calling `register` twice on the same instance
/// is a no-op.
public final class GlobalHotkey: @unchecked Sendable {
    public init() {}

    /// 4-byte signature used by Carbon's hotkey ID. Must be a unique-per-app
    /// FourCharCode; we pick `RPLY` so a debugger trace makes the source clear.
    private static let signature: OSType = 0x52504C59 // 'RPLY'
    private static let hotkeyID: UInt32 = 1

    /// Common prefix for every GlobalHotkey NSLog line. Visible in
    /// Console.app — `log show --predicate 'process == "ReplyAI"'`
    /// filters by process, and the bracketed prefix lets a triage
    /// engineer further filter by component. Used at THREE call sites
    /// (RegisterEventHotKey-failed, InstallEventHandler-failed,
    /// successful-register confirmation). Drift between any two would
    /// have one site filterable by `[ReplyAI] GlobalHotkey:` while
    /// another is invisible to that grep. Pinned by
    /// `GlobalHotkeyContractTests.testLogPrefixIsFrozen`.
    static let logPrefix = "[ReplyAI] GlobalHotkey: "

    /// Format the diagnostic NSLog line emitted when Carbon's
    /// `RegisterEventHotKey` returns non-`noErr`. Hoisted from the
    /// inline interpolation so the body wording (`RegisterEventHotKey
    /// failed (status=...)`) lives next to the prefix it composes with
    /// — drift to a different verb or a `code=` keyword breaks the
    /// triage grep that looks for "RegisterEventHotKey failed" in
    /// `log show` output. Pinned by `GlobalHotkeyContractTests`'
    /// `testRegisterFailedLogFormat*`.
    static func registerFailedLog(status: OSStatus) -> String {
        "\(Self.logPrefix)RegisterEventHotKey failed (status=\(status))"
    }

    /// Format the diagnostic NSLog line emitted when Carbon's
    /// `InstallEventHandler` returns non-`noErr` — the second-leg
    /// failure mode after `RegisterEventHotKey` succeeded. Hoisted
    /// alongside `registerFailedLog` so both failure-leg messages share
    /// the same shape — drift here would force two distinct triage
    /// greps. Pinned by `GlobalHotkeyContractTests`'
    /// `testInstallFailedLogFormat*`.
    static func installFailedLog(status: OSStatus) -> String {
        "\(Self.logPrefix)InstallEventHandler failed (status=\(status))"
    }

    /// Diagnostic NSLog line emitted on the successful-register tail.
    /// Triage greps on this exact string to confirm `⌘⇧R` registered
    /// at app launch — drift to e.g. "registered ⌘⇧R" would silently
    /// break the runbook check. Pinned by `GlobalHotkeyContractTests`'
    /// `testRegisteredLogIsExact`.
    static let registeredLog = "[ReplyAI] GlobalHotkey: ⌘⇧R registered"

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var callback: (() -> Void)?

    /// Default ⌘⇧R combo. Other combinations are easy to add later — pass a
    /// `keyCode` from `kVK_*` and the modifier bitmask in the same form
    /// Carbon expects (`cmdKey | shiftKey | optionKey | controlKey`).
    public func register(
        keyCode: UInt32 = UInt32(kVK_ANSI_R),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        onPressed: @escaping () -> Void
    ) {
        // Idempotent — repeated calls just refresh the callback target.
        guard ref == nil else {
            self.callback = onPressed
            return
        }
        self.callback = onPressed

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotkeyID)
        var hotkeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard registerStatus == noErr, let hotkeyRef else {
            NSLog(Self.registerFailedLog(status: registerStatus))
            return
        }
        self.ref = hotkeyRef

        // Carbon dispatches hotkey events through the standard Carbon event
        // pipeline. Hand the C callback a pointer to `self` so it can invoke
        // the Swift closure on the main queue.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { me.callback?() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard installStatus == noErr, let handlerRef else {
            NSLog(Self.installFailedLog(status: installStatus))
            UnregisterEventHotKey(hotkeyRef)
            self.ref = nil
            return
        }
        self.handler = handlerRef
        NSLog(Self.registeredLog)
    }

    /// Tear down the registration. Safe to call when nothing is registered.
    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        callback = nil
    }

    deinit { unregister() }
}

/// Helper invoked by the registered hotkey to bring ReplyAI to the front and
/// focus the inbox window, simulating "open the composer from anywhere."
@MainActor
public enum ReplyAIWindowSummoner {
    /// Title used by `WindowGroup("Inbox", id: "inbox")` in `ReplyAIApp`.
    /// SwiftUI titles each scene window after the localized name passed to
    /// `WindowGroup`, so the AppKit fast-path match below uses this exact
    /// string. The summoner and the scene declaration must stay in sync —
    /// drift on either side silently degrades `⌘⇧R` to the slower
    /// notification-fallback path on every summon. Pinned by
    /// `GlobalHotkeyContractTests.testInboxWindowTitleConstantIsInbox`.
    public static let inboxWindowTitle = "Inbox"

    /// Scene id used by `WindowGroup(_, id:)` in `ReplyAIApp` and every
    /// `openWindow(id:)` call site (MenuBarContent, AppPrototypeView,
    /// ObDoneView). Drift on the WindowGroup side leaves `openWindow`
    /// callers spinning up a no-such-id scene (silent no-op); drift on
    /// any caller routes that one button to a stale id (button no-ops
    /// while the others continue to work). Pinned by
    /// `GlobalHotkeyContractTests.testInboxWindowIDConstantIsInbox`.
    public static let inboxWindowID = "inbox"

    public static func summon() {
        NSApp.activate(ignoringOtherApps: true)
        // Fast path: an existing inbox window? Surface it directly via AppKit
        // so we don't need a SwiftUI View in scope. SwiftUI's WindowGroup
        // titles its windows after the localized name we passed
        // (`WindowGroup("Inbox", id: "inbox")`), so a title match is reliable.
        if let inbox = NSApp.windows.first(where: { $0.title == ReplyAIWindowSummoner.inboxWindowTitle }) {
            inbox.makeKeyAndOrderFront(nil)
            return
        }
        // Fallback: post a notification that AppPrototypeView observes — its
        // .onReceive can call `openWindow(id: "inbox")` to spin up a fresh
        // inbox window. Only relevant when zero inbox windows are currently
        // alive in the process.
        NotificationCenter.default.post(name: .replyAIRequestSummonInbox, object: nil)
    }
}

extension Notification.Name {
    /// Posted when the global hotkey fires. The app's @main scene observes
    /// this and calls SwiftUI's `openWindow(id: "inbox")` so the actual
    /// window-management API stays in the SwiftUI environment.
    static let replyAIRequestSummonInbox = Notification.Name("co.replyai.summon.inbox")
}
