import XCTest
import Network
@testable import ReplyAI

final class LocalhostOAuthListenerTests: XCTestCase {

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

        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global())

        let request = "GET /?code=abc123 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(request.utf8), completion: .idempotent)

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

        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global())
        let request = "GET /?code=trigger HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(request.utf8), completion: .idempotent)

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
        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global())
        let request = "GET /?state=xyz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(request.utf8), completion: .idempotent)

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
        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global())
        let request = "GET /?code= HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(request.utf8), completion: .idempotent)

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

        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global())
        // First line is "GET\r\n…" — only one whitespace-delimited token.
        let request = "GET\r\nHost: localhost\r\n\r\n"
        conn.send(content: Data(request.utf8), completion: .idempotent)

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

        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global())
        let request = "GET /?code=first&code=second HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(request.utf8), completion: .idempotent)

        await fulfillment(of: [exp], timeout: 5)
        conn.cancel()

        XCTAssertEqual(receivedCode, "first",
            "duplicate `code` params must resolve to the first occurrence; a switch to `last` would silently change which auth code we exchange")
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
}
