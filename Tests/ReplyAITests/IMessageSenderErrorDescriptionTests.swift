import XCTest
@testable import ReplyAI

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
}
