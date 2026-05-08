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

    /// `userInfo` keys iMessage and CallKit attach to incoming-message
    /// notifications. They live here as named constants so this parser
    /// AND the inline divergent path in `NotificationCoordinator.willPresent`
    /// (see the divergence note below) reference one source of truth.
    /// Drift on any key silently breaks that key's resolution leg
    /// without throwing — sender attribution falls through to `title`,
    /// chatGUID resolution returns nil and creates a duplicate thread.
    /// Pinned by `UNNotificationContentParserTests.testUserInfoKeysAreFrozen`.
    enum UserInfoKey {
        /// Primary sender handle key — Continuity / CallKit convention.
        static let ckSenderID       = "CKSenderID"
        /// Fallback sender key for older notification payloads.
        static let sender           = "sender"
        /// Primary chat identifier key.
        static let ckChatIdentifier = "CKChatIdentifier"
        /// Fallback chat identifier key for older notification payloads.
        static let ckChatGUID       = "CKChatGUID"
    }

    /// Parse notification content into a structured value.
    ///
    /// Sender resolution order: `userInfo[CKSenderID]` → `userInfo[sender]` → `content.title`.
    /// Returns nil when none of those produce a non-empty string.
    /// `chatGUID` is populated from `userInfo[CKChatIdentifier]` or `userInfo[CKChatGUID]`.
    ///
    /// **Divergence with `NotificationCoordinator.willPresent`**: two
    /// paths exist for resolving the same notification fields, and they
    /// disagree on two contracts:
    ///
    /// 1. **Sender key**: this parser checks `ckSenderID` → `sender` →
    ///    `title` (three steps); willPresent skips `ckSenderID` and only
    ///    checks `sender` → `title`. Modern iMessage / Continuity
    ///    payloads populate `CKSenderID` but not always `sender`, so
    ///    willPresent on those falls through to the title (contact
    ///    display name) while this parser returns the raw handle.
    ///
    /// 2. **Empty `CKChatIdentifier`**: this parser keeps a present-
    ///    but-empty `CKChatIdentifier` verbatim (no fallback to
    ///    `CKChatGUID`), pinned by `testEmptyCKChatIdentifierIsNotFalledBack`.
    ///    The inline willPresent path filters present-but-empty values
    ///    to nil and falls through to `CKChatGUID`.
    ///
    /// If this parser ever replaces the inline path, harmonize both
    /// contracts deliberately — the pinned tests on each side will
    /// fail and force a real decision rather than a silent behavior
    /// flip in production notification handling.
    static func parse(_ content: UNNotificationContent) -> ParsedMessageNotification? {
        let senderHandle: String
        if let ckSender = content.userInfo[UserInfoKey.ckSenderID] as? String, !ckSender.isEmpty {
            senderHandle = ckSender
        } else if let sender = content.userInfo[UserInfoKey.sender] as? String, !sender.isEmpty {
            senderHandle = sender
        } else if !content.title.isEmpty {
            senderHandle = content.title
        } else {
            return nil
        }

        let chatGUID = content.userInfo[UserInfoKey.ckChatIdentifier] as? String
            ?? content.userInfo[UserInfoKey.ckChatGUID] as? String

        return ParsedMessageNotification(
            senderHandle: senderHandle,
            preview: content.body,
            chatGUID: chatGUID
        )
    }
}
