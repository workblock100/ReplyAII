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

    /// User-visible strings used to construct the inline-reply notification
    /// action. macOS shows these in the system notification chrome — they
    /// are the only ReplyAI copy a user sees from the notification surface
    /// when ReplyAI itself isn't focused. Hoisted from the inline literals
    /// in `setUp()` so the copy review surface lives in one place and a
    /// future copy edit doesn't have to grep for the strings inside a
    /// UNTextInputNotificationAction constructor. Pinned by
    /// `NotificationCoordinatorTests.testInlineReplyActionStringsAreFrozen`.
    enum InlineReplyAction {
        static let title       = "Reply"
        static let buttonTitle = "Send"
        static let placeholder = "Your reply…"
    }

    /// Presentation options returned to UN when a message notification arrives
    /// while the app is foregrounded. `.banner` ensures the user still sees the
    /// notification (without it, foregrounded notifications are silently
    /// suppressed by macOS — confusing for users who expect ReplyAI to surface
    /// every message). `.sound` plays the chime so focus-mode users still get
    /// the audio cue. Hoisted to a constant so the bitmask is pinnable
    /// independently of the inline arithmetic inside the nonisolated
    /// `willPresent` callback (which has no public path for tests).
    static let foregroundPresentationOptions: UNNotificationPresentationOptions = [.banner, .sound]

    /// Options bitmask both `setUp()` and `requestPermissionIfNeeded()` pass
    /// to `requestAuthorization`. Hoisted so the two paths share a single
    /// source of truth — they previously used set-literal `[.alert, .badge, .sound]`
    /// vs `[.alert, .sound, .badge]` which is order-equivalent today but
    /// would silently diverge if either side dropped or added a flag in a
    /// refactor. A drifted bitmask between the two paths produces a TCC
    /// dialog whose granted permissions depend on which call site ran
    /// first. Pinned by `NotificationCoordinatorTests`'
    /// `*RequestsAlertBadgeAndSoundOptions` cluster.
    static let authorizationRequestOptions: UNAuthorizationOptions = [.alert, .badge, .sound]

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
            title: InlineReplyAction.title,
            options: [],
            textInputButtonTitle: InlineReplyAction.buttonTitle,
            textInputPlaceholder: InlineReplyAction.placeholder
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
        _ = try? await center.requestAuthorization(options: Self.authorizationRequestOptions)
    }

    /// Requests notification authorization if the status is still undetermined.
    /// Safe to call multiple times — no-ops when already authorized or denied.
    /// Called from InboxViewModel.init so the macOS permission dialog appears
    /// at app launch rather than waiting for the full setUp() flow.
    func requestPermissionIfNeeded() async {
        let status = await center.authorizationStatus()
        guard status == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: Self.authorizationRequestOptions)
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
    /// `chatGUID` — extracted from `userInfo["CKChatIdentifier"]` (primary) or
    /// `userInfo["CKChatGUID"]` (fallback) — lets InboxViewModel match the
    /// notification to an existing thread instead of always creating a new one.
    ///
    /// Exposed internally so tests can drive it without constructing a real
    /// UNNotification (which has no public initializer).
    func handleIncomingNotification(
        categoryID: String,
        senderHandle: String,
        preview: String,
        chatGUID: String? = nil
    ) {
        guard categoryID != Self.categoryID else { return }
        // Normalize a present-but-empty chatGUID to nil. A malformed
        // notification with `userInfo["CKChatIdentifier"] = ""` would
        // otherwise bypass the senderHandle/name fallback in
        // applyIncomingNotification — the chatGUID branch does an exact
        // equality check that almost never matches `""`, which silently
        // creates a duplicate thread per notification instead of refreshing
        // the existing one. Same shape as the senderHandle empty-string fix.
        let normalizedGUID = (chatGUID?.isEmpty == false) ? chatGUID : nil
        onIncomingMessage?(senderHandle, preview)
        inbox?.applyIncomingNotification(senderHandle: senderHandle, preview: preview, chatGUID: normalizedGUID)
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
        // The empty-string check prevents an empty `sender` value from
        // bypassing the title fallback — without it, a malformed
        // notification with `userInfo["sender"] = ""` would propagate an
        // empty handle into applyIncomingNotification and (because
        // `chatGUID.hasSuffix("")` is true for every string) match the
        // first thread by accident.
        let rawSender = content.userInfo[UNNotificationContentParser.UserInfoKey.sender] as? String
        let senderHandle = (rawSender?.isEmpty == false ? rawSender : nil) ?? content.title
        let preview = content.body
        // CKChatIdentifier is the primary key iMessage userInfo uses for the conversation;
        // CKChatGUID is the older fallback. Either uniquely identifies the chat.db thread.
        // Empty strings on either key are filtered to nil so the present-but-empty
        // case can't bypass the senderHandle/name fallback (see handleIncomingNotification).
        let rawIdentifier = content.userInfo[UNNotificationContentParser.UserInfoKey.ckChatIdentifier] as? String
        let rawGUID = content.userInfo[UNNotificationContentParser.UserInfoKey.ckChatGUID] as? String
        let chatGUID = (rawIdentifier?.isEmpty == false ? rawIdentifier : nil)
            ?? (rawGUID?.isEmpty == false ? rawGUID : nil)
        Task { @MainActor in
            self.handleIncomingNotification(categoryID: categoryID, senderHandle: senderHandle, preview: preview, chatGUID: chatGUID)
        }
        completionHandler(Self.foregroundPresentationOptions)
    }
}
