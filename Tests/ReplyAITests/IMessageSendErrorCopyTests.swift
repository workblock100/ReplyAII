import XCTest
@testable import ReplyAICore

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

    // MARK: - Hoisted-constant pins (REP-hoist 2026-05-07)
    //
    // The three parameterless toast strings (`notAuthorizedToast`,
    // `unsupportedToast`, `timedOutToast`) live as `static let` on
    // `IMessageSender.SendError` so a copy review can edit them in
    // isolation without grepping through a switch arm in a non-UI
    // file. Each pin asserts BOTH the constant equals the literal AND
    // the case routes through the constant — catching a future drift
    // between switch and constant.

    func testNotAuthorizedToastCopyIsFrozen() {
        XCTAssertEqual(IMessageSender.SendError.notAuthorizedToast,
                       "Messages.app denied ReplyAI. Re-grant in System Settings → Privacy & Security → Automation.",
            "notAuthorizedToast literal must not drift — the System Settings deep-link path is the user's only recovery action")
    }

    func testUnsupportedToastCopyIsFrozen() {
        XCTAssertEqual(IMessageSender.SendError.unsupportedToast,
                       "This thread can't be sent to (unsupported channel).",
            "unsupportedToast literal must not drift — surfaces every time the user tries to send into a non-iMessage / non-SMS-relay channel")
    }

    func testTimedOutToastCopyIsFrozen() {
        XCTAssertEqual(IMessageSender.SendError.timedOutToast,
                       "Messages.app did not respond within the timeout. It may be busy with iCloud sync.",
            "timedOutToast literal must not drift — the `iCloud sync` hint is the user's only signal to wait rather than retry")
    }

    /// Routing pins: the case must produce the constant byte-for-byte.
    /// Catches a refactor that defines the constant but rebuilds the
    /// switch arm with a slightly-different inline literal — every
    /// constant-only test would still pass while every user toast
    /// silently desyncs from the documented copy.
    func testNotAuthorizedCaseRoutesThroughHoistedConstant() {
        XCTAssertEqual(IMessageSender.SendError.notAuthorized.errorDescription,
                       IMessageSender.SendError.notAuthorizedToast,
            ".notAuthorized errorDescription must equal the hoisted constant — drift is silent in user UX")
    }

    func testUnsupportedCaseRoutesThroughHoistedConstant() {
        XCTAssertEqual(IMessageSender.SendError.unsupported.errorDescription,
                       IMessageSender.SendError.unsupportedToast,
            ".unsupported errorDescription must equal the hoisted constant — drift is silent in user UX")
    }

    func testTimedOutCaseRoutesThroughHoistedConstant() {
        XCTAssertEqual(IMessageSender.SendError.timedOut.errorDescription,
                       IMessageSender.SendError.timedOutToast,
            ".timedOut errorDescription must equal the hoisted constant — drift is silent in user UX")
    }

    // MARK: - Parameterized toast format pins

    /// Pin the .messageTooLong toast format. The format embeds the
    /// caller's char count AND `IMessageSender.maxMessageLength` —
    /// drift in the surfaced max number desyncs the toast from the
    /// validator's actual cutoff and lies to the user.
    func testMessageTooLongToastFormatRoundTrips() {
        let toast = IMessageSender.SendError.messageTooLongToast(chars: 5000)
        XCTAssertEqual(toast,
                       "Message too long (5000 chars, max \(IMessageSender.maxMessageLength)).")
        // Routing: the case's errorDescription must equal the format
        // helper applied to its associated value.
        XCTAssertEqual(IMessageSender.SendError.messageTooLong(5000).errorDescription, toast,
            ".messageTooLong case must route through messageTooLongToast(chars:) — drift desyncs case from helper")
    }

    /// Pin the .messageTooLong format embeds the production
    /// `maxMessageLength` constant, not a hard-coded number. A future
    /// max-length bump (e.g. 4096 → 8192) must update the toast
    /// automatically.
    func testMessageTooLongToastEmbedsProductionMax() {
        let toast = IMessageSender.SendError.messageTooLongToast(chars: 1)
        XCTAssertTrue(toast.contains("max \(IMessageSender.maxMessageLength)"),
            "messageTooLongToast must embed the production maxMessageLength — drift would surface a stale max in the user toast")
    }

    /// Pin the .invalidChatGUID toast format. The shape description
    /// `iMessage;[+-];<identifier>` must stay in sync with what the
    /// validator actually accepts — drift either rewords the user-
    /// visible expected shape away from the validator or vice versa.
    func testInvalidChatGUIDToastFormatRoundTrips() {
        let toast = IMessageSender.SendError.invalidChatGUIDToast(guid: "bogus;guid")
        XCTAssertEqual(toast,
                       "Invalid chat GUID 'bogus;guid': must match iMessage;[+-];<identifier>.")
        XCTAssertEqual(IMessageSender.SendError.invalidChatGUID("bogus;guid").errorDescription, toast,
            ".invalidChatGUID case must route through invalidChatGUIDToast(guid:) — drift desyncs case from helper")
    }

    /// Pin the GUID-shape phrase the validator promises. The toast is
    /// the user's only signal of what shape ReplyAI expects — drift
    /// here makes a legitimate-shaped GUID look wrong to the user or
    /// claims a different shape than the validator enforces.
    func testInvalidChatGUIDToastEmbedsExpectedShape() {
        let toast = IMessageSender.SendError.invalidChatGUIDToast(guid: "X")
        XCTAssertTrue(toast.contains("iMessage;[+-];<identifier>"),
            "invalidChatGUIDToast must surface the same shape the validator accepts — drift between toast and validator is silent")
    }
}
