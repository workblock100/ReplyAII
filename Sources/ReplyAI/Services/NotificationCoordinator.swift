import Foundation
import UserNotifications
import Observation

// MARK: - Injectable protocol

/// Subset of UNUserNotificationCenter used by NotificationCoordinator.
/// Extracted so tests can supply a mock without launching a real notification center.
protocol NotificationCenterProtocol: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    /// Returns the current authorization status. Bridges the callback-style
    /// getNotificationSettings to an async-friendly form for protocol conformance.
    func authorizationStatus() async -> UNAuthorizationStatus
}

extension UNUserNotificationCenter: NotificationCenterProtocol {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            getNotificationSettings { cont.resume(returning: $0.authorizationStatus) }
        }
    }
}

// MARK: - Coordinator

/// Owns the UserNotifications setup for ReplyAI: registers the inline-reply
/// category on launch, requests authorization (once), and routes tapped replies
/// from the notification shade into InboxViewModel.
///
/// Instantiate once in ReplyAIApp and pass via .environment so InboxScreen can
/// wire coordinator.inbox = viewModel.
@Observable
@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {

    static let categoryID    = "REPLYAI_THREAD"
    static let replyActionID = "REPLY"

    /// Weak reference set by InboxScreen after InboxViewModel is alive.
    weak var inbox: InboxViewModel?

    /// Fires when an incoming message notification arrives and the category is
    /// not the inline-reply category. Wired by InboxScreen to
    /// InboxViewModel.applyIncomingNotification so the VM can create/refresh a
    /// lightweight thread entry when chat.db is unavailable.
    var onIncomingMessage: ((String, String) -> Void)?

    private let center: NotificationCenterProtocol

    init(center: NotificationCenterProtocol = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Call once at app launch. Registers the inline-reply category and requests
    /// notification authorization if not yet determined. Idempotent.
    func setUp() async {
        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyActionID,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Your reply…"
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        // Register this coordinator as the delegate for the real center.
        if let real = center as? UNUserNotificationCenter {
            real.delegate = self
        }

        // Request authorization only when the status is not yet determined —
        // re-requesting when already granted prompts a redundant system dialog.
        let status = await center.authorizationStatus()
        guard status == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    // MARK: - Reply handling (extracted for direct testability)

    /// Processes a notification action. Exposed internally so tests can drive
    /// it without constructing a real UNNotificationResponse.
    func handleReply(actionIdentifier: String, userText: String?, notificationID: String) {
        guard actionIdentifier == Self.replyActionID,
              let text = userText, !text.isEmpty else { return }
        inbox?.pendingNotificationReply = (threadID: notificationID, text: text)
    }

    // MARK: - Incoming message capture (extracted for direct testability)

    /// Processes a foreground notification arrival. Skips inline-reply category
    /// notifications (those are handled by handleReply). Fires onIncomingMessage
    /// and forwards to inbox so it can refresh-or-create a thread entry.
    ///
    /// Exposed internally so tests can drive it without constructing a real
    /// UNNotification (which has no public initializer).
    func handleIncomingNotification(categoryID: String, senderHandle: String, preview: String) {
        guard categoryID != Self.categoryID else { return }
        onIncomingMessage?(senderHandle, preview)
        inbox?.applyIncomingNotification(senderHandle: senderHandle, preview: preview)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let notifID  = response.notification.request.identifier
        let userText = (response as? UNTextInputNotificationResponse)?.userText
        Task { @MainActor in
            self.handleReply(actionIdentifier: actionID, userText: userText, notificationID: notifID)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let categoryID = content.categoryIdentifier
        // Prefer the explicit sender key iMessage/CKSenderID sets; fall back to title.
        let senderHandle = content.userInfo["sender"] as? String ?? content.title
        let preview = content.body
        Task { @MainActor in
            self.handleIncomingNotification(categoryID: categoryID, senderHandle: senderHandle, preview: preview)
        }
        completionHandler([.banner, .sound])
    }
}
