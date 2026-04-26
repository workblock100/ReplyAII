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
final class GlobalHotkey: @unchecked Sendable {
    /// 4-byte signature used by Carbon's hotkey ID. Must be a unique-per-app
    /// FourCharCode; we pick `RPLY` so a debugger trace makes the source clear.
    private static let signature: OSType = 0x52504C59 // 'RPLY'
    private static let hotkeyID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var callback: (() -> Void)?

    /// Default ⌘⇧R combo. Other combinations are easy to add later — pass a
    /// `keyCode` from `kVK_*` and the modifier bitmask in the same form
    /// Carbon expects (`cmdKey | shiftKey | optionKey | controlKey`).
    func register(
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
            NSLog("[ReplyAI] GlobalHotkey: RegisterEventHotKey failed (status=\(registerStatus))")
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
            NSLog("[ReplyAI] GlobalHotkey: InstallEventHandler failed (status=\(installStatus))")
            UnregisterEventHotKey(hotkeyRef)
            self.ref = nil
            return
        }
        self.handler = handlerRef
        NSLog("[ReplyAI] GlobalHotkey: ⌘⇧R registered")
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
enum ReplyAIWindowSummoner {
    static func summon() {
        NSApp.activate(ignoringOtherApps: true)
        // Fast path: an existing inbox window? Surface it directly via AppKit
        // so we don't need a SwiftUI View in scope. SwiftUI's WindowGroup
        // titles its windows after the localized name we passed
        // (`WindowGroup("Inbox", id: "inbox")`), so a title match is reliable.
        if let inbox = NSApp.windows.first(where: { $0.title == "Inbox" }) {
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
