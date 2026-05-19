import XCTest
import Network
@testable import ReplyAICore

final class LocalhostOAuthListenerTests: XCTestCase {
    private func sendRequest(
        _ request: String,
        to port: UInt16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> NWConnection {
        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let readyExp = expectation(description: "client connection ready")
        let sentExp = expectation(description: "client request sent")
        readyExp.assertForOverFulfill = false
        sentExp.assertForOverFulfill = false

        conn.stateUpdateHandler = { state in
            if case .ready = state {
                readyExp.fulfill()
            }
            if case .failed(let error) = state {
                XCTFail("NWConnection failed before request send: \(error)", file: file, line: line)
                readyExp.fulfill()
            }
        }
        conn.start(queue: .global())
        await fulfillment(of: [readyExp], timeout: 3)

        conn.send(content: Data(request.utf8), completion: .contentProcessed { error in
            if let error {
                XCTFail("NWConnection failed to send request: \(error)", file: file, line: line)
            }
            sentExp.fulfill()
        })
        await fulfillment(of: [sentExp], timeout: 3)
        return conn
    }

    // MARK: - testValidCallbackURLExtractsCode

    func testValidCallbackURLExtractsCode() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 5)

        let exp = expectation(description: "code extracted")
        let readyExp = expectation(description: "listener ready")
        var receivedCode: String?

        listener.start(
            completion: { result in
                if case .success(let code) = result { receivedCode = code }
                exp.fulfill()
            },
            onReady: { readyExp.fulfill() }
        )

        await fulfillment(of: [readyExp], timeout: 3)
        guard let port = listener.actualPort else {
            XCTFail("actualPort not set after ready")
            return
        }

        let request = "GET /?code=abc123 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let conn = await sendRequest(request, to: port)

        await fulfillment(of: [exp], timeout: 5)
        conn.cancel()

        XCTAssertEqual(receivedCode, "abc123")
    }

    // MARK: - testTimeoutFiresWithOAuthError

    func testTimeoutFiresWithOAuthError() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 0.25)

        let exp = expectation(description: "timeout fired")
        var receivedError: OAuthError?

        listener.start { result in
            if case .failure(let e) = result { receivedError = e }
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 5)

        XCTAssertEqual(receivedError, OAuthError.timeout)
    }

    // MARK: - testDoubleStartIsNoop

    func testDoubleStartIsNoop() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 5)

        var completionCount = 0
        let firstExp = expectation(description: "first completion")
        let readyExp = expectation(description: "listener ready")

        listener.start(
            completion: { _ in
                completionCount += 1
                firstExp.fulfill()
            },
            onReady: { readyExp.fulfill() }
        )

        // Second call while already running — must be a no-op.
        listener.start { _ in
            completionCount += 1
        }

        await fulfillment(of: [readyExp], timeout: 3)
        guard let port = listener.actualPort else {
            XCTFail("actualPort not set after ready")
            return
        }

        let request = "GET /?code=trigger HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let conn = await sendRequest(request, to: port)

        await fulfillment(of: [firstExp], timeout: 5)
        conn.cancel()

        // Extra settle time to catch any spurious second fire.
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(completionCount, 1, "second start() must not fire an extra completion")
    }

    // MARK: - testCallbackURLWithoutCodeIsIgnored

    /// Browser GET with no `code` query param must not fire the completion.
    /// Slack's redirect can be probed by random clients (curl, monitors); we
    /// must wait for the genuine OAuth callback and let the timeout handle a
    /// no-show rather than completing with garbage.
    func testCallbackURLWithoutCodeIsIgnored() async throws {
        // Short timeout so the test fails fast if the listener wrongly completes
        // on the no-code GET — the genuine no-code path should hit timeout.
        let listener = LocalhostOAuthListener(port: 0, timeout: 0.4)

        let exp = expectation(description: "completion fired (expected: timeout)")
        let readyExp = expectation(description: "listener ready")
        var receivedResult: Result<String, OAuthError>?

        listener.start(
            completion: { result in
                receivedResult = result
                exp.fulfill()
            },
            onReady: { readyExp.fulfill() }
        )

        await fulfillment(of: [readyExp], timeout: 3)
        guard let port = listener.actualPort else {
            XCTFail("actualPort not set after ready")
            return
        }

        // Send a GET with no `code` query parameter — should be silently dropped.
        let request = "GET /?state=xyz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let conn = await sendRequest(request, to: port)

        await fulfillment(of: [exp], timeout: 5)
        conn.cancel()

        // Result must be the timeout, not a spurious .success
        guard case .failure(let err) = receivedResult else {
            XCTFail("Expected timeout failure, got \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(err, .timeout, "no-code GET must not satisfy the listener — must time out")
    }

    // MARK: - testCallbackURLWithEmptyCodeIsIgnored

    /// Browser GET with `?code=` (empty value) is symmetric to `?state=xyz`:
    /// the listener must NOT fire `.success("")` because an empty code can't
    /// satisfy the subsequent token-exchange POST and we'd just round-trip the
    /// failure through Slack's API for nothing. Pin the silent-drop behavior
    /// so a refactor that swaps the parser onto a path which preserves empty
    /// values doesn't ship a broken success callback.
    func testCallbackURLWithEmptyCodeIsIgnored() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 0.4)

        let exp = expectation(description: "completion fired (expected: timeout)")
        let readyExp = expectation(description: "listener ready")
        var receivedResult: Result<String, OAuthError>?

        listener.start(
            completion: { result in
                receivedResult = result
                exp.fulfill()
            },
            onReady: { readyExp.fulfill() }
        )

        await fulfillment(of: [readyExp], timeout: 3)
        guard let port = listener.actualPort else {
            XCTFail("actualPort not set after ready")
            return
        }

        // GET /?code= (the parameter is present but the value is empty).
        let request = "GET /?code= HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let conn = await sendRequest(request, to: port)

        await fulfillment(of: [exp], timeout: 5)
        conn.cancel()

        guard case .failure(let err) = receivedResult else {
            XCTFail("empty-code GET must not produce .success — got \(String(describing: receivedResult))")
            return
        }
        XCTAssertEqual(err, .timeout,
            "empty-code GET must be silently dropped and the listener must hit its timeout, same as no-code")
    }

    // MARK: - testStopBeforeStartIsSafeNoop

    /// stop() called when nothing is running must be safe and not crash.
    func testStopBeforeStartIsSafeNoop() {
        let listener = LocalhostOAuthListener(port: 0, timeout: 5)
        listener.stop()
        listener.stop()
        // No assertion needed — passing means no crash on idle stop.
    }

    // MARK: - testStopDuringRunDoesNotCallCompletion

    /// Stopping a running listener must drop the pending completion silently —
    /// the caller has explicitly opted out and shouldn't get a spurious result.
    func testStopDuringRunDoesNotCallCompletion() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 5)

        let readyExp = expectation(description: "listener ready")
        var completionFired = false
        listener.start(
            completion: { _ in completionFired = true },
            onReady: { readyExp.fulfill() }
        )

        await fulfillment(of: [readyExp], timeout: 3)
        listener.stop()

        // Wait long enough that any spurious completion (timeout, etc.) would have fired.
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(completionFired,
            "stop() must drop the pending completion — caller opted out")
    }

    // MARK: - OAuthError equatable

    /// `OAuthError` is Equatable; same case + same payload compare equal.
    /// Production code uses `XCTAssertEqual(error, .timeout)` and pattern
    /// matches in switch statements — both rely on the synthesized conformance.
    func testOAuthErrorEquatable() {
        XCTAssertEqual(OAuthError.timeout, OAuthError.timeout)
        XCTAssertEqual(OAuthError.listenerFailed("x"), OAuthError.listenerFailed("x"))
        XCTAssertNotEqual(OAuthError.listenerFailed("x"), OAuthError.listenerFailed("y"))
        XCTAssertNotEqual(OAuthError.timeout, OAuthError.tokenExchangeFailed("oops"))
        XCTAssertEqual(OAuthError.tokenExchangeFailed("a"), OAuthError.tokenExchangeFailed("a"))
        XCTAssertNotEqual(OAuthError.tokenExchangeFailed("a"), OAuthError.tokenExchangeFailed("b"))
    }

    // MARK: - LocalizedError conformance (rendered in Settings → Channels)

    func testTimeoutHasUserActionableCopy() {
        let copy = OAuthError.timeout.errorDescription ?? ""
        XCTAssertFalse(copy.isEmpty)
        XCTAssertTrue(copy.contains("Slack"),
            "timeout copy should reference Slack so the user knows which connection failed — got: \(copy)")
    }

    func testListenerFailedInterpolatesUnderlyingMessage() {
        let raw = "Address already in use (port 4242)"
        let copy = OAuthError.listenerFailed(raw).errorDescription ?? ""
        XCTAssertTrue(copy.contains(raw),
            "listenerFailed must include the underlying cause — got: \(copy)")
    }

    func testTokenExchangeFailedInterpolatesUnderlyingMessage() {
        let raw = "invalid_client_id"
        let copy = OAuthError.tokenExchangeFailed(raw).errorDescription ?? ""
        XCTAssertTrue(copy.contains(raw),
            "tokenExchangeFailed must include Slack's reason — got: \(copy)")
    }

    func testLocalizedErrorBridgeSurfacesOurCopy() {
        // Settings → Channels uses `err.localizedDescription` to populate
        // the connect-error label. Without LocalizedError, that returns
        // "The operation couldn't be completed (...OAuthError error 0)" —
        // unparseable to users. Confirm the bridge surfaces our copy.
        let err: Error = OAuthError.timeout
        XCTAssertTrue(err.localizedDescription.contains("Slack"),
            "Settings would show the unhelpful CFString fallback — got: \(err.localizedDescription)")
    }

    // MARK: - Exact-copy pins
    //
    // The keyword-contains tests above keep tests resilient to small
    // wording tweaks. The literals here ship verbatim to Settings →
    // Channels and the inline OAuth error label, so a designer-led
    // rephrasing should land as a code-review diff. Pin the full copy
    // and update both source + test in the same commit when the words
    // intentionally change.

    func testTimeoutCopyExactLiteral() {
        XCTAssertEqual(
            OAuthError.timeout.errorDescription,
            "Slack didn't respond. Open the Slack app and try again, or check your internet connection."
        )
    }

    func testListenerFailedCopyExactPrefix() {
        let raw = "Address already in use (port 4242)"
        XCTAssertEqual(
            OAuthError.listenerFailed(raw).errorDescription,
            "Couldn't open the local callback server: \(raw)"
        )
    }

    func testTokenExchangeFailedCopyExactPrefix() {
        let raw = "invalid_client_id"
        XCTAssertEqual(
            OAuthError.tokenExchangeFailed(raw).errorDescription,
            "Slack rejected the connection: \(raw)"
        )
    }

    // MARK: - parser edge cases (request-side)

    /// The handler reads up to 8192 bytes of the request and parses the
    /// FIRST line by splitting on `\r\n`. A request whose first line is
    /// only `GET` (no path, no version) splits into a single token; the
    /// `parts.count >= 2` guard drops it. Pin the silent-drop behavior so
    /// a future relaxation that calls `URL(string: "http://localhost")`
    /// with a missing path doesn't ship — that path produces a URL with
    /// no `queryItems`, so the silent-drop is the only sane outcome.
    func testRequestLineWithOnlyMethodIsIgnored() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 0.4)

        let exp = expectation(description: "completion fired (expected: timeout)")
        let readyExp = expectation(description: "listener ready")
        var receivedResult: Result<String, OAuthError>?

        listener.start(
            completion: { result in
                receivedResult = result
                exp.fulfill()
            },
            onReady: { readyExp.fulfill() }
        )

        await fulfillment(of: [readyExp], timeout: 3)
        guard let port = listener.actualPort else {
            XCTFail("actualPort not set after ready"); return
        }

        // First line is "GET\r\n…" — only one whitespace-delimited token.
        let request = "GET\r\nHost: localhost\r\n\r\n"
        let conn = await sendRequest(request, to: port)

        await fulfillment(of: [exp], timeout: 5)
        conn.cancel()

        guard case .failure(let err) = receivedResult else {
            XCTFail("Expected timeout, got \(String(describing: receivedResult))"); return
        }
        XCTAssertEqual(err, .timeout,
            "a request line with only a method must be silently dropped — only the timeout should fire")
    }

    /// A request whose `code` parameter appears multiple times (`?code=a&code=b`)
    /// must use the FIRST occurrence — the parser uses `queryItems?.first(where:)`.
    /// Pin this so a future swap to `last(where:)` (which would silently change
    /// which code we exchange) shows up here rather than as a silent OAuth
    /// regression that only fires when an attacker queries with a doctored URL.
    func testFirstCodeQueryItemWinsWhenDuplicated() async throws {
        let listener = LocalhostOAuthListener(port: 0, timeout: 5)

        let exp = expectation(description: "code extracted")
        let readyExp = expectation(description: "listener ready")
        var receivedCode: String?

        listener.start(
            completion: { result in
                if case .success(let code) = result { receivedCode = code }
                exp.fulfill()
            },
            onReady: { readyExp.fulfill() }
        )

        await fulfillment(of: [readyExp], timeout: 3)
        guard let port = listener.actualPort else {
            XCTFail("actualPort not set after ready"); return
        }

        let request = "GET /?code=first&code=second HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let conn = await sendRequest(request, to: port)

        await fulfillment(of: [exp], timeout: 5)
        conn.cancel()

        XCTAssertEqual(receivedCode, "first",
            "duplicate `code` params must resolve to the first occurrence; a switch to `last` would silently change which auth code we exchange")
    }

    // MARK: - Production default port + timeout pins

    /// Production port is `4242`. The Slack OAuth flow embeds
    /// `redirect_uri=http://localhost:4242/callback` in both the
    /// authorize URL and the token-exchange POST body; Slack rejects
    /// the exchange if those don't match the registered app's redirect.
    /// A drift here while the registered app stays on `:4242` would
    /// break Slack auth flow for every existing install.
    func testDefaultPortIs4242() {
        XCTAssertEqual(LocalhostOAuthListener.defaultPort, 4242,
                       "loopback port is part of the OAuth redirect_uri contract — see test rationale")
    }

    /// Production timeout is `120` seconds. Drop too low and slow-network
    /// or 2FA-prompted users hit `.timeout` mid-flow; raise too high and
    /// a stale listener squats the port across retries.
    func testDefaultTimeoutIs120Seconds() {
        XCTAssertEqual(LocalhostOAuthListener.defaultTimeout, 120,
                       "OAuth wait budget — see test rationale")
    }

    // MARK: - testOkResponseTemplateIsExactLiteral

    /// Pins the exact HTTP/1.1 ack we send back to the browser tab after
    /// extracting the OAuth code. Three properties matter:
    ///   1. Status line `HTTP/1.1 200 OK\r\n` — anything else and the
    ///      browser may render Slack's "page unreachable" instead of
    ///      "you can close this tab," which is exactly the moment the
    ///      user is most anxious about whether the auth worked.
    ///   2. `Content-Length: 2\r\n` matching the literal "OK" body byte
    ///      count — drift here causes some browsers to hang waiting for
    ///      more bytes before closing the connection (Chrome 1xx behavior
    ///      observed during dev), which delays the "all done" signal.
    ///   3. `Connection: close\r\n` — we want the browser to close the
    ///      socket immediately so subsequent listener restarts can
    ///      reuse the port. Without it, keep-alive can wedge a TIME_WAIT
    ///      that bites a back-to-back retry.
    /// Asserting against the package-level `okResponseTemplate` is the
    /// safe alternative to a loopback roundtrip — see AGENTS.md gotcha.
    func testOkResponseTemplateIsExactLiteral() {
        XCTAssertEqual(
            LocalhostOAuthListener.okResponseTemplate,
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK",
            "OAuth ack template is part of the user-visible contract — see test rationale"
        )

        // Sanity: the Content-Length value must match the literal body byte
        // count. Catches a refactor that changes "OK" to "Done." but
        // forgets to bump the header.
        let template = LocalhostOAuthListener.okResponseTemplate
        let parts = template.components(separatedBy: "\r\n\r\n")
        XCTAssertEqual(parts.count, 2,
                       "must split into exactly headers + body around \\r\\n\\r\\n")
        let body = parts[1]
        let bodyBytes = body.utf8.count
        XCTAssertTrue(template.contains("Content-Length: \(bodyBytes)\r\n"),
                       "Content-Length header must match body byte count (\(bodyBytes))")
    }

    /// Pin the request-receive byte cap. The handler limits the
    /// initial `connection.receive` to `maxRequestBytes`. Drift below
    /// ~2 KB risks truncating the `code=` value once Slack's
    /// authorization codes grow (they've drifted upward historically);
    /// drift above ~64 KB lets a buggy or hostile client pin memory on
    /// the listener queue until cancel. Existing parser-edge-case
    /// tests note `8192` in a comment but no XCTAssertEqual ties the
    /// constant down — pin it.
    func testMaxRequestBytesIsHoistedAndProductionDefaultIs8192() {
        XCTAssertEqual(LocalhostOAuthListener.maxRequestBytes, 8192,
            "maxRequestBytes drift either truncates legitimate Slack codes (too low) or invites memory-pinning by a hostile client (too high)")
    }

    /// OAuth 2 §4.1.2 mandates the authorization code lives under the
    /// `code` query parameter — providers (Slack, Google, GitHub) all
    /// emit it under that exact key. The handler used to compare
    /// against an inline `"code"` literal; a typo there silently
    /// dropped every successful callback into the missing-code path
    /// and let the 120 s listener timeout govern, so the flow looked
    /// broken to the user with no actionable error. Hoisted to
    /// `LocalhostOAuthListener.codeQueryParameterName`; pin freezes
    /// the literal.
    func testCodeQueryParameterNameIsFrozen() {
        XCTAssertEqual(LocalhostOAuthListener.codeQueryParameterName, "code",
            "OAuth 2 §4.1.2 specifies the authorization code is delivered under the `code` query parameter — drift here silently drops every callback")
    }

    // MARK: - OAuthError toast vocabulary pins (REP-hoist 2026-05-07)

    /// The three OAuthError toasts surface in Settings → Channels
    /// when Slack connect fails. Hoisting the literals lets copy
    /// review land in named constants rather than inside a switch
    /// arm, and pinning each independently catches a future drift
    /// between switch and constant.

    func testOAuthErrorTimeoutToastCopyIsFrozen() {
        XCTAssertEqual(OAuthError.timeoutToast,
                       "Slack didn't respond. Open the Slack app and try again, or check your internet connection.",
            "timeoutToast literal must not drift — `Open the Slack app and try again` is the actionable verb the user needs")
    }

    func testOAuthErrorListenerFailedPrefixIsFrozen() {
        XCTAssertEqual(OAuthError.listenerFailedPrefix, "Couldn't open the local callback server: ",
            "listenerFailedPrefix literal must not drift — the trailing colon-space is what visually separates the prefix from the dynamic message")
    }

    func testOAuthErrorTokenExchangeFailedPrefixIsFrozen() {
        XCTAssertEqual(OAuthError.tokenExchangeFailedPrefix, "Slack rejected the connection: ",
            "tokenExchangeFailedPrefix literal must not drift — `Slack rejected the connection` is the user-visible cause")
    }

    /// Routing pins: each case's `errorDescription` must wire through
    /// the hoisted constant.
    func testOAuthErrorTimeoutRoutesThroughHoistedConstant() {
        XCTAssertEqual(OAuthError.timeout.errorDescription,
                       OAuthError.timeoutToast,
            ".timeout errorDescription must equal timeoutToast byte-for-byte — drift between switch and constant is silent")
    }

    func testOAuthErrorListenerFailedRoutesThroughHoistedPrefix() {
        XCTAssertEqual(OAuthError.listenerFailed("xyz").errorDescription,
                       OAuthError.listenerFailedPrefix + "xyz",
            ".listenerFailed errorDescription must compose `listenerFailedPrefix + msg` byte-for-byte — drift in the prefix or the colon-space is silent")
    }

    func testOAuthErrorTokenExchangeFailedRoutesThroughHoistedPrefix() {
        XCTAssertEqual(OAuthError.tokenExchangeFailed("rejected").errorDescription,
                       OAuthError.tokenExchangeFailedPrefix + "rejected",
            ".tokenExchangeFailed errorDescription must compose `tokenExchangeFailedPrefix + msg` byte-for-byte")
    }

    // MARK: - Synthetic parse-URL host + listener-creation reason format

    /// Pin the loopback host string used to feed captured request paths
    /// through `URL(string:)` for query-item extraction. Drift to a
    /// host that `URL(string:)` rejects (e.g. dropping the `http://`
    /// scheme) silently makes every callback get dropped.
    func testSyntheticParseURLHostIsFrozen() {
        XCTAssertEqual(LocalhostOAuthListener.syntheticParseURLHost,
                       "http://localhost")
        // Synthesizing with a typical request path must produce a URL
        // that URL(string:) accepts.
        let url = URL(string: "\(LocalhostOAuthListener.syntheticParseURLHost)/?code=abc")
        XCTAssertNotNil(url,
            "synthetic host + path must produce a URL the parser can extract query items from")
    }

    /// Pin the parameterized listener-creation failure-reason format.
    /// Embeds the requested port (only triage signal — was 4242 in
    /// use?) and the underlying error description. Drift drops either
    /// signal.
    func testListenerCreationFailureFormatRoundTrips() {
        struct Boom: Error, CustomStringConvertible {
            var description: String { "address already in use" }
        }
        let reason = LocalhostOAuthListener.listenerCreationFailureReason(
            port: 4242, error: Boom())
        XCTAssertEqual(reason,
                       "Could not create NWListener on port 4242: address already in use")
        XCTAssertTrue(reason.contains("4242"),
            "reason must surface the requested port so triage can confirm whether the port was occupied")
    }

    /// Pin the integer port appears in the reason regardless of value.
    /// Catches a future refactor that surfaces the port as a hex form
    /// or drops it.
    func testListenerCreationFailureFormatEmbedsRawPort() {
        struct Boom: Error {}
        let reason1 = LocalhostOAuthListener.listenerCreationFailureReason(port: 0,    error: Boom())
        let reason2 = LocalhostOAuthListener.listenerCreationFailureReason(port: 8080, error: Boom())
        XCTAssertTrue(reason1.contains("port 0"),
            "raw integer port (0) must appear in the reason — drift to hex or symbolic form loses triage signal")
        XCTAssertTrue(reason2.contains("port 8080"),
            "raw integer port (8080) must appear in the reason")
    }
}
