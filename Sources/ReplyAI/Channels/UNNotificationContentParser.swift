import Foundation
import UserNotifications

/// Structured output from parsing a UNNotificationContent for an iMessage notification.
struct ParsedMessageNotification: Sendable {
    let senderHandle: String
    let preview: String
    let chatGUID: String?
}

/// Extracts message metadata from a UNNotificationContent without accessing chat.db.
/// Used by NotificationCoordinator when Full Disk Access is unavailable.
enum UNNotificationContentParser {

    /// Parse notification content into a structured value.
    ///
    /// Sender resolution order: `userInfo["CKSenderID"]` → `userInfo["sender"]` → `content.title`.
    /// Returns nil when none of those produce a non-empty string.
    /// `chatGUID` is populated from `userInfo["CKChatIdentifier"]` or `userInfo["CKChatGUID"]`.
    ///
    /// **Divergence with `NotificationCoordinator.willPresent`**: this parser
    /// keeps an empty-string `CKChatIdentifier` verbatim (no fallback to
    /// `CKChatGUID`), pinned by `testEmptyCKChatIdentifierIsNotFalledBack`.
    /// The inline logic in `NotificationCoordinator.userNotificationCenter(_:willPresent:)`
    /// instead filters present-but-empty values to nil and falls through.
    /// If this parser ever replaces the inline path, harmonize the empty
    /// handling first — the pinned test will fail and force a deliberate
    /// decision rather than a silent behavior change.
    static func parse(_ content: UNNotificationContent) -> ParsedMessageNotification? {
        let senderHandle: String
        if let ckSender = content.userInfo["CKSenderID"] as? String, !ckSender.isEmpty {
            senderHandle = ckSender
        } else if let sender = content.userInfo["sender"] as? String, !sender.isEmpty {
            senderHandle = sender
        } else if !content.title.isEmpty {
            senderHandle = content.title
        } else {
            return nil
        }

        let chatGUID = content.userInfo["CKChatIdentifier"] as? String
            ?? content.userInfo["CKChatGUID"] as? String

        return ParsedMessageNotification(
            senderHandle: senderHandle,
            preview: content.body,
            chatGUID: chatGUID
        )
    }
}
