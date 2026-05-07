import XCTest
@testable import ReplyAI

/// `ChannelError.errorDescription` strings are surfaced verbatim in the
/// inbox error banner and Settings → Channels list. Pin the contract so a
/// careless edit to the enum cannot silently rewrite UX copy.
final class ChannelErrorTests: XCTestCase {

    // MARK: - Per-case errorDescription contract

    func testPermissionDeniedReturnsHintVerbatim() {
        let hint = "Grant Full Disk Access in System Settings."
        let err = ChannelError.permissionDenied(hint: hint)
        XCTAssertEqual(err.errorDescription, hint)
    }

    func testAuthorizationDeniedHasUserActionableCopy() {
        let err = ChannelError.authorizationDenied
        XCTAssertEqual(
            err.errorDescription,
            "This channel isn't connected yet. Open Settings to sign in."
        )
    }

    func testUnavailableReturnsAssociatedString() {
        let err = ChannelError.unavailable("Slack workspace deleted by admin")
        XCTAssertEqual(err.errorDescription, "Slack workspace deleted by admin")
    }

    func testQueryReturnsAssociatedString() {
        let err = ChannelError.query("no such table: messages")
        XCTAssertEqual(err.errorDescription, "no such table: messages")
    }

    func testDatabaseErrorSurfacesMessageNotCode() {
        // The numeric code is for programmatic dispatch; the message is the
        // copy the user reads.
        let err = ChannelError.databaseError(code: 5, message: "database is locked")
        XCTAssertEqual(err.errorDescription, "database is locked")
    }

    func testDatabaseCorruptedRecommendsRecoveryPath() {
        let err = ChannelError.databaseCorrupted
        // Recovery hint must reference iCloud — that is the only first-line
        // remediation available without third-party tooling.
        let copy = err.errorDescription ?? ""
        XCTAssertTrue(copy.contains("iCloud"), "expected iCloud hint, got: \(copy)")
    }

    func testNetworkErrorReturnsAssociatedString() {
        let err = ChannelError.networkError("HTTP 503 from slack.com")
        XCTAssertEqual(err.errorDescription, "HTTP 503 from slack.com")
    }

    // MARK: - LocalizedError conformance

    func testLocalizedErrorBridgeReturnsErrorDescription() {
        // `(error as Error).localizedDescription` falls back to a generic
        // string unless the type is bridged via LocalizedError. Verify the
        // bridge so SwiftUI alerts using `error.localizedDescription`
        // surface the right copy.
        let err: Error = ChannelError.authorizationDenied
        XCTAssertEqual(
            err.localizedDescription,
            "This channel isn't connected yet. Open Settings to sign in."
        )
    }

    func testEveryCaseProducesNonEmptyDescription() {
        // Defense-in-depth: a refactor could accidentally return `nil` from
        // a new case and SwiftUI would render an empty alert body.
        let cases: [ChannelError] = [
            .permissionDenied(hint: "x"),
            .authorizationDenied,
            .unavailable("x"),
            .query("x"),
            .databaseError(code: 1, message: "x"),
            .databaseCorrupted,
            .networkError("x"),
        ]
        for err in cases {
            let desc = err.errorDescription ?? ""
            XCTAssertFalse(desc.isEmpty, "empty description for \(err)")
        }
    }

    /// Pin the verbatim-passthrough policy for cases with associated values:
    /// `networkError("")`, `query("")`, `unavailable("")`, `databaseError(_, "")`,
    /// and `permissionDenied(hint: "")` all surface their empty associated
    /// string AS the error description. This is intentional — the cases are
    /// "wrap whatever the lower layer reported," and silently injecting a
    /// fallback like "Unknown error" would mask a malformed upstream call site.
    /// Pinned so a future "make every error description non-empty" hardening
    /// is a deliberate change visible here.
    func testCasesWithEmptyAssociatedValueSurfaceEmptyDescription() {
        let casesWithEmpty: [(ChannelError, String)] = [
            (.networkError(""),                       "networkError"),
            (.query(""),                              "query"),
            (.unavailable(""),                        "unavailable"),
            (.databaseError(code: 5, message: ""),    "databaseError"),
            (.permissionDenied(hint: ""),             "permissionDenied"),
        ]
        for (err, label) in casesWithEmpty {
            XCTAssertEqual(err.errorDescription, "",
                "\(label) with empty associated value passes the empty string through verbatim — no fallback")
        }
    }

    // MARK: - Pattern-match stability for code paths that branch on case

    func testDatabaseErrorPreservesCodeForProgrammaticDispatch() {
        // Callers distinguish SQLITE_BUSY (5) from auth failures via the
        // numeric code — pinning so a future refactor doesn't drop it.
        let err = ChannelError.databaseError(code: 5, message: "locked")
        if case let .databaseError(code, _) = err {
            XCTAssertEqual(code, 5)
        } else {
            XCTFail("expected .databaseError, got \(err)")
        }
    }
}
