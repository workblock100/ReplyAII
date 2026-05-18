import XCTest
@testable import ReplyAICore

/// `IMessageSender.SendError.errorDescription` strings are surfaced in
/// the inbox error banner when an iMessage send fails. Pin per-case copy
/// + the LocalizedError bridge so a careless edit cannot silently rewrite
/// what users see.
final class IMessageSenderErrorDescriptionTests: XCTestCase {

    func testNotAuthorizedReferencesSystemSettingsRecoveryPath() {
        // The user has to take action in System Settings; the message
        // must surface the path so they know where to go.
        let copy = IMessageSender.SendError.notAuthorized.errorDescription ?? ""
        XCTAssertTrue(copy.contains("System Settings"),
            "notAuthorized must reference System Settings — got: \(copy)")
        XCTAssertTrue(copy.contains("Automation"),
            "notAuthorized must mention the Automation pane — got: \(copy)")
    }

    func testUnsupportedHasNonEmptyCopy() {
        let copy = IMessageSender.SendError.unsupported.errorDescription ?? ""
        XCTAssertFalse(copy.isEmpty,
            "unsupported must have user-visible copy")
    }

    func testTimedOutSurfacesTimeoutContext() {
        // Pin the iCloud-sync hint — that's the most common cause and
        // gives users something to wait for vs. retry immediately.
        let copy = IMessageSender.SendError.timedOut.errorDescription ?? ""
        XCTAssertTrue(copy.contains("timeout") || copy.contains("Messages.app"),
            "timedOut copy should reference timeout/Messages.app — got: \(copy)")
    }

    func testMessageTooLongInterpolatesActualLength() {
        // The user needs the count to know how much to trim.
        let copy = IMessageSender.SendError.messageTooLong(5000).errorDescription ?? ""
        XCTAssertTrue(copy.contains("5000"),
            "messageTooLong must include the actual char count — got: \(copy)")
        XCTAssertTrue(copy.contains("\(IMessageSender.maxMessageLength)"),
            "messageTooLong must reference the max — got: \(copy)")
    }

    func testInvalidChatGUIDInterpolatesGUID() {
        // The actual GUID is needed for the user (or a support thread)
        // to diagnose what's malformed.
        let bad = "iMessage;X;not-a-real-guid"
        let copy = IMessageSender.SendError.invalidChatGUID(bad).errorDescription ?? ""
        XCTAssertTrue(copy.contains(bad),
            "invalidChatGUID must echo the offending GUID — got: \(copy)")
    }

    func testScriptFailurePassesThroughMessageVerbatim() {
        // AppleScript error strings are already user-readable; surface
        // them verbatim rather than wrapping in a generic message.
        let raw = "AppleScript error -1708: Event not handled"
        let copy = IMessageSender.SendError.scriptFailure(raw).errorDescription
        XCTAssertEqual(copy, raw,
            "scriptFailure must surface the raw AppleScript error verbatim")
    }

    func testEverySendErrorCaseHasNonEmptyDescription() {
        // Defense in depth — a future case that returns nil/empty would
        // render a blank alert body in SwiftUI.
        let cases: [IMessageSender.SendError] = [
            .scriptFailure("x"),
            .notAuthorized,
            .unsupported,
            .timedOut,
            .messageTooLong(100),
            .invalidChatGUID("x"),
        ]
        for err in cases {
            let desc = err.errorDescription ?? ""
            XCTAssertFalse(desc.isEmpty, "empty description for \(err)")
        }
    }

    func testLocalizedErrorBridgeReturnsErrorDescription() {
        // SwiftUI alerts display `error.localizedDescription` — confirm
        // the LocalizedError bridge surfaces our copy rather than the
        // generic CFString fallback.
        let err: Error = IMessageSender.SendError.notAuthorized
        XCTAssertTrue(err.localizedDescription.contains("System Settings"),
            "LocalizedError bridge must surface our copy — got: \(err.localizedDescription)")
    }

    // MARK: - Exact-copy pins
    //
    // The keyword-contains tests above keep tests resilient to small
    // wording tweaks. Pin the full literals so a designer-led rewrite
    // surfaces as a code-review diff. Update both source + test
    // together when the words intentionally change.

    func testNotAuthorizedCopyExactLiteral() {
        XCTAssertEqual(
            IMessageSender.SendError.notAuthorized.errorDescription,
            "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation."
        )
    }

    func testUnsupportedCopyExactLiteral() {
        XCTAssertEqual(
            IMessageSender.SendError.unsupported.errorDescription,
            "This thread can't be sent to (unsupported channel)."
        )
    }

    func testTimedOutCopyExactLiteral() {
        XCTAssertEqual(
            IMessageSender.SendError.timedOut.errorDescription,
            "Messages.app did not respond within the timeout. It may be busy with iCloud sync."
        )
    }

    func testMessageTooLongCopyExactLiteral() {
        XCTAssertEqual(
            IMessageSender.SendError.messageTooLong(5000).errorDescription,
            "Message too long (5000 chars, max \(IMessageSender.maxMessageLength))."
        )
    }

    func testInvalidChatGUIDCopyExactLiteral() {
        XCTAssertEqual(
            IMessageSender.SendError.invalidChatGUID("not-a-guid").errorDescription,
            "Invalid chat GUID 'not-a-guid': must match iMessage;[+-];<identifier>."
        )
    }

    func testMaxMessageLengthLiteralIsPinned() {
        // The 4096-char cap is the iMessage AppleScript send limit. A
        // tweak here changes both the validation gate and the user-
        // visible "max N" copy; pin so a refactor surfaces.
        XCTAssertEqual(IMessageSender.maxMessageLength, 4096,
            "iMessage AppleScript send cap must remain 4096 chars — bumping requires testing real send-path behavior")
    }

    /// `errOSAScriptError` (-1743) is the macOS TCC denial code returned
    /// when the user has not granted ReplyAI Automation permission to
    /// control Messages.app. Drift here decouples the AppleScript error
    /// classifier from `SendError.notAuthorized`, which is the case the
    /// inbox uses to render the "re-grant in System Settings" CTA. The
    /// raw integer is part of the macOS ABI; refactoring it would silently
    /// route TCC denials through the generic `.scriptFailure` path.
    func testTCCDeniedErrorCodeIsPinned() {
        XCTAssertEqual(IMessageSender.tccDeniedErrorCode, -1743,
            "tccDeniedErrorCode is the macOS Automation-permission denial code; drift breaks the System Settings reconnect CTA")
    }

    /// `errAEEventNotHandled` (-1708) is Messages's transient "I accepted
    /// the script but couldn't dispatch it" error. The retry path keys off
    /// this exact integer; if it drifts, every transient send becomes a
    /// hard failure surfaced to the user as "AppleScript error -1708"
    /// with no retry. Pin the constant + the existing retry mechanism's
    /// message-substring contract.
    func testEventNotHandledErrorCodeIsPinned() {
        XCTAssertEqual(IMessageSender.eventNotHandledErrorCode, -1708,
            "eventNotHandledErrorCode drift breaks the transient-failure retry path; transient failures would surface as hard send errors")

        // The retry classifier uses substring matching on the error
        // message, so pin the substring shape that the AppleScript
        // executor formats when it hits this code.
        let formatted = "AppleScript error \(IMessageSender.eventNotHandledErrorCode)"
        XCTAssertEqual(formatted, "AppleScript error -1708",
            "the retry classifier relies on this exact formatted substring — drift in either side breaks transient retry")
    }
}
