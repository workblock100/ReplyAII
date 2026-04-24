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
}
