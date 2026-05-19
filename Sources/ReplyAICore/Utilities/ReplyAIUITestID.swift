import Foundation

/// Stable accessibility identifiers used by UI automation.
///
/// Keep these separate from visible copy: XCUITest should target durable
/// control identity, while copy can still evolve through product review.
public enum ReplyAIUITestID {
    public enum App {
        public static let openInboxButton = "replyai.app.prototype.open-inbox"
    }

    public enum Onboarding {
        public static let getStartedButton = "replyai.onboarding.get-started"
        public static let continueButton = "replyai.onboarding.permissions.continue"
        public static let skipButton = "replyai.onboarding.permissions.skip"

        public static func permissionButton(_ key: String) -> String {
            "replyai.onboarding.permissions.button.\(key)"
        }
    }

    public enum Inbox {
        public static let composerEditor = "replyai.inbox.composer.editor"

        public static func threadRow(id: String) -> String {
            "replyai.inbox.thread-row.\(id)"
        }

        public static func tonePill(_ tone: Tone) -> String {
            "replyai.inbox.tone-pill.\(tone.rawValue.lowercased())"
        }
    }
}
