import XCTest
@testable import ReplyAI

/// Pins the user-visible `errorDescription` strings on `IMessageSender.SendError`.
/// These strings surface in the inbox composer's send-failure banner and the
/// debug pane — a silent rewording would land in front of users without any
/// review. The existing `IMessageSenderTests` covers the *behavior* that
/// produces each error; this file is the *copy contract*.
final class IMessageSendErrorCopyTests: XCTestCase {

    func testScriptFailureRoundsTripsAssociatedValue() {
        // .scriptFailure is the catch-all for AppleScript executor errors;
        // the wrapping message comes from NSAppleScript or our own raise. We
        // pass it through verbatim so debug logs match the user-visible text.
        let err = IMessageSender.SendError.scriptFailure("AppleScript error -1708: Event not handled")
        XCTAssertEqual(err.errorDescription,
                       "AppleScript error -1708: Event not handled")
    }

    func testNotAuthorizedCopyIsPinned() {
        // Surfaced after Messages.app refuses an Automation request — the user
        // needs the System Settings deep-link path verbatim, not paraphrased.
        let err = IMessageSender.SendError.notAuthorized
        XCTAssertEqual(err.errorDescription,
                       "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation.")
    }

    func testUnsupportedCopyIsPinned() {
        let err = IMessageSender.SendError.unsupported
        XCTAssertEqual(err.errorDescription,
                       "This thread can't be sent to (unsupported channel).")
    }

    func testTimedOutCopyIsPinned() {
        // The "iCloud sync" hint is load-bearing — it's the most common cause
        // of NSAppleScript timing out, and the copy is the user's only signal
        // to wait rather than retry.
        let err = IMessageSender.SendError.timedOut
        XCTAssertEqual(err.errorDescription,
                       "Messages.app did not respond within the timeout. It may be busy with iCloud sync.")
    }

    func testMessageTooLongCopyInterpolatesActualLengthAndMaximum() {
        // Both the supplied length AND the runtime maxMessageLength constant
        // appear in the user-visible string. Pin both so a refactor that
        // moves the cap (or drops the supplied length) trips here.
        let err = IMessageSender.SendError.messageTooLong(5000)
        XCTAssertEqual(err.errorDescription,
                       "Message too long (5000 chars, max \(IMessageSender.maxMessageLength)).")
    }

    func testInvalidChatGUIDCopyIsPinnedAndRoundsTripsGUID() {
        // The hint format `iMessage;[+-];<identifier>` is the GUID grammar
        // — drift here means the user is told to fix something that doesn't
        // match what the parser actually expects.
        let bad = "garbage;0;xxx"
        let err = IMessageSender.SendError.invalidChatGUID(bad)
        XCTAssertEqual(err.errorDescription,
                       "Invalid chat GUID '\(bad)': must match iMessage;[+-];<identifier>.")
    }

    // MARK: - LocalizedError wiring

    func testEveryCaseHasNonNilNonEmptyDescription() {
        // LocalizedError surfaces via NSError.localizedDescription too —
        // a nil errorDescription would fall back to a useless system string.
        let cases: [IMessageSender.SendError] = [
            .scriptFailure("x"),
            .notAuthorized,
            .unsupported,
            .timedOut,
            .messageTooLong(1),
            .invalidChatGUID("y"),
        ]
        for c in cases {
            XCTAssertNotNil(c.errorDescription, "\(c) must surface a non-nil description")
            XCTAssertFalse(c.errorDescription!.isEmpty,
                           "\(c) must surface a non-empty description")
        }
    }
}
