import Foundation
import AppKit

/// Fires `onMessagesActivated` whenever Messages.app (`com.apple.MobileSMS`)
/// becomes the frontmost application. Watches NSWorkspace activation
/// notifications with a debounce so rapid app-switching coalesces to one
/// callback per window.
///
/// Injectable `notificationCenter` and `bundleIDExtractor` enable full
/// test coverage without real NSRunningApplication instances or
/// NSWorkspace machinery.
final class MessagesAppActivationObserver: @unchecked Sendable {
    /// Production debounce window. Drift here changes how many sync triggers
    /// fire when the user thumbs through Messages between conversations —
    /// 600ms coalesces rapid activations to one callback per visit.
    static let defaultDebounce: TimeInterval = 0.6

    /// Fired at most once per `debounce` interval when Messages becomes frontmost.
    var onMessagesActivated: (() -> Void)?

    /// Package-internal so tests can pin the production default without
    /// constructing a second observer with an explicit value (see
    /// `MessagesAppActivationObserverTests.testDefaultDebounceIsSixHundredMilliseconds`).
    let debounce: TimeInterval
    private let notificationCenter: NotificationCenter
    /// Extracts the activated app's bundle ID from the notification userInfo.
    /// Production uses NSWorkspace.applicationUserInfoKey; tests inject a stub.
    private let bundleIDExtractor: (Notification) -> String?
    private let queue = DispatchQueue(label: "co.replyai.messages-activation", qos: .utility)
    private var pending: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        bundleIDExtractor: @escaping (Notification) -> String? = {
            ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        },
        debounce: TimeInterval = MessagesAppActivationObserver.defaultDebounce
    ) {
        self.notificationCenter = notificationCenter
        self.bundleIDExtractor = bundleIDExtractor
        self.debounce = debounce
        startObserving()
    }

    deinit { stop() }

    /// Cancel the workspace observer and any pending debounced callback.
    func stop() {
        if let obs = observer {
            notificationCenter.removeObserver(obs)
            observer = nil
        }
        pending?.cancel()
        pending = nil
    }

    // MARK: - Private

    private func startObserving() {
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  self.bundleIDExtractor(notification) == "com.apple.MobileSMS" else { return }
            self.scheduleCallback()
        }
    }

    /// Coalesces rapid activations into a single callback after `debounce`.
    private func scheduleCallback() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onMessagesActivated?()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
