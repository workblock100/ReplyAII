import XCTest
@testable import ReplyAI

// MARK: - Mock infrastructure

/// Controllable WebSocket task. Deliver messages or close the connection
/// from the test body to drive the receive loop deterministically.
final class MockWebSocketTask: WebSocketTaskProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var messageQueue: [URLSessionWebSocketTask.Message] = []
    private var pendingContinuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var closeError: Error?

    private(set) var resumeCallCount = 0
    private(set) var cancelCallCount = 0

    func resume() {
        lock.lock()
        resumeCallCount += 1
        lock.unlock()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock()
        cancelCallCount += 1
        let cont = pendingContinuation
        pendingContinuation = nil
        lock.unlock()
        cont?.resume(throwing: URLError(.networkConnectionLost))
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let err = closeError {
                lock.unlock()
                continuation.resume(throwing: err)
                return
            }
            if !messageQueue.isEmpty {
                let msg = messageQueue.removeFirst()
                lock.unlock()
                continuation.resume(returning: msg)
                return
            }
            pendingContinuation = continuation
            lock.unlock()
        }
    }

    // MARK: - Test controls

    func deliver(message: URLSessionWebSocketTask.Message) {
        lock.lock()
        if let cont = pendingContinuation {
            pendingContinuation = nil
            lock.unlock()
            cont.resume(returning: message)
        } else {
            messageQueue.append(message)
            lock.unlock()
        }
    }

    func close(with error: Error = URLError(.networkConnectionLost)) {
        lock.lock()
        closeError = error
        let cont = pendingContinuation
        pendingContinuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

/// Records every task created so tests can interact with each connection.
final class MockWebSocketTaskFactory: WebSocketTaskFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [MockWebSocketTask] = []

    var createdTaskCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tasks.count
    }

    func task(at index: Int) -> MockWebSocketTask {
        lock.lock()
        defer { lock.unlock() }
        return tasks[index]
    }

    func makeWebSocketTask(with url: URL) -> any WebSocketTaskProtocol {
        let t = MockWebSocketTask()
        lock.lock()
        tasks.append(t)
        lock.unlock()
        return t
    }
}

// MARK: - Helpers

private func makeClient(
    factory: MockWebSocketTaskFactory,
    reconnectDelay: TimeInterval = 0
) -> SlackSocketClient {
    SlackSocketClient(
        connectionURL: URL(string: "wss://test.slack.example/link")!,
        factory: factory,
        reconnectDelay: reconnectDelay
    )
}

/// Polls until `factory.createdTaskCount >= count` or timeout elapses.
private func waitForTasks(
    _ count: Int,
    factory: MockWebSocketTaskFactory,
    timeout: TimeInterval = 2.0
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while factory.createdTaskCount < count, Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms
    }
}

// MARK: - Tests

final class SlackSocketClientTests: XCTestCase {

    // MARK: - testSlackSocketClientDeliversEventCallbackToHandler

    func testSlackSocketClientDeliversEventCallbackToHandler() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        let exp = expectation(description: "events_callback forwarded")
        var received: Data?
        client.onEventReceived = { data in
            received = data
            exp.fulfill()
        }

        client.start()
        await waitForTasks(1, factory: factory)

        let json = #"{"type":"events_callback","payload":{"event":{"type":"message"}}}"#
        factory.task(at: 0).deliver(message: .string(json))

        await fulfillment(of: [exp], timeout: 2)
        XCTAssertNotNil(received)
        let parsed = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(received)) as? [String: Any]
        )
        XCTAssertEqual(parsed["type"] as? String, "events_callback")

        client.stop()
    }

    // MARK: - testSlackSocketClientStopCancelsTask

    func testSlackSocketClientStopCancelsTask() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        client.start()
        await waitForTasks(1, factory: factory)

        // Give the receive loop time to call receive() before we stop.
        try await Task.sleep(nanoseconds: 20_000_000) // 20 ms

        client.stop()

        // Allow the cancel to propagate.
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(factory.task(at: 0).cancelCallCount, 1)
    }

    // MARK: - testSlackSocketClientReconnectsOnAbnormalClose

    func testSlackSocketClientReconnectsOnAbnormalClose() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        client.start()
        await waitForTasks(1, factory: factory)

        // Close the initial connection — client should reconnect.
        factory.task(at: 0).close()

        // Wait for the reconnected task to be created.
        await waitForTasks(2, factory: factory)

        XCTAssertGreaterThanOrEqual(factory.createdTaskCount, 2,
            "client should reconnect after abnormal close")
        XCTAssertEqual(factory.task(at: 1).resumeCallCount, 1,
            "reconnected task must be resumed")

        client.stop()
    }

    // MARK: - testSlackSocketClientDropsHelloAndPingMessages

    func testSlackSocketClientDropsHelloAndPingMessages() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        var callbackCount = 0
        client.onEventReceived = { _ in callbackCount += 1 }

        client.start()
        await waitForTasks(1, factory: factory)

        let task = factory.task(at: 0)

        // Deliver control frames.
        task.deliver(message: .string(#"{"type":"hello"}"#))
        task.deliver(message: .string(#"{"type":"ping","num_connections":1}"#))

        // Deliver a real event to use as a synchronization point.
        let syncExp = expectation(description: "events_callback sync")
        client.onEventReceived = { _ in syncExp.fulfill() }
        task.deliver(message: .string(#"{"type":"events_callback"}"#))

        await fulfillment(of: [syncExp], timeout: 2)

        XCTAssertEqual(callbackCount, 0,
            "hello and ping frames must not reach onEventReceived")

        client.stop()
    }

    // MARK: - testSlackSocketClientStopsReconnectAfterThreeAttempts

    func testSlackSocketClientStopsReconnectAfterThreeAttempts() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        client.start()

        // Close the initial connection + 3 reconnects = 4 tasks total.
        for i in 0..<(SlackSocketClient.maxReconnects + 1) {
            await waitForTasks(i + 1, factory: factory)
            factory.task(at: i).close()
        }

        // Allow time for any spurious 5th reconnect to appear.
        try await Task.sleep(nanoseconds: 100_000_000) // 100 ms

        XCTAssertEqual(
            factory.createdTaskCount,
            SlackSocketClient.maxReconnects + 1,
            "should create exactly initial + maxReconnects tasks, then stop"
        )

        client.stop()
    }

    // MARK: - dispatch edge cases

    /// Unknown `type:` values (Slack adds new event envelope kinds over time)
    /// must be silently dropped, never forwarded to onEventReceived.
    /// Otherwise a future Slack-side change could deliver garbage to consumers.
    func testSlackSocketClientDropsUnknownEnvelopeTypes() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        var callbackCount = 0
        client.onEventReceived = { _ in callbackCount += 1 }

        client.start()
        await waitForTasks(1, factory: factory)

        let task = factory.task(at: 0)
        task.deliver(message: .string(#"{"type":"goodbye"}"#))
        task.deliver(message: .string(#"{"type":"disconnect","reason":"warning"}"#))

        // Sync via a real events_callback to know the dropped frames have processed.
        let sync = expectation(description: "events_callback sync")
        client.onEventReceived = { _ in sync.fulfill() }
        task.deliver(message: .string(#"{"type":"events_callback"}"#))
        await fulfillment(of: [sync], timeout: 2)

        XCTAssertEqual(callbackCount, 0, "unknown envelope types must not be forwarded")

        client.stop()
    }

    /// Malformed JSON / no `type:` field must be dropped without crashing.
    /// Slack's wire format isn't formally guaranteed; we should never throw
    /// past the receive loop into the consumer.
    func testSlackSocketClientDropsMalformedAndMissingTypeFrames() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        var callbackCount = 0
        client.onEventReceived = { _ in callbackCount += 1 }

        client.start()
        await waitForTasks(1, factory: factory)

        let task = factory.task(at: 0)
        // Not JSON
        task.deliver(message: .string("not-json-at-all"))
        // JSON but no type field
        task.deliver(message: .string(#"{"payload":{}}"#))
        // Empty object
        task.deliver(message: .string("{}"))

        let sync = expectation(description: "events_callback sync")
        client.onEventReceived = { _ in sync.fulfill() }
        task.deliver(message: .string(#"{"type":"events_callback"}"#))
        await fulfillment(of: [sync], timeout: 2)

        XCTAssertEqual(callbackCount, 0, "malformed frames must be silently dropped")

        client.stop()
    }

    /// `.data(...)` variant of WebSocket message is supported as well as `.string(...)`.
    /// Slack's Socket Mode normally sends text frames, but the dispatch path
    /// switches on both — this test guards that branch from regression.
    func testSlackSocketClientHandlesDataFrameVariant() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        let exp = expectation(description: "data variant forwarded")
        client.onEventReceived = { _ in exp.fulfill() }

        client.start()
        await waitForTasks(1, factory: factory)

        let payload = Data(#"{"type":"events_callback"}"#.utf8)
        factory.task(at: 0).deliver(message: .data(payload))

        await fulfillment(of: [exp], timeout: 2)

        client.stop()
    }

    // MARK: - lifecycle idempotency

    /// Calling stop() before start() must not crash and must leave the client
    /// in a state where subsequent start() calls are no-ops.
    func testStopBeforeStartIsSafeAndDisablesFutureStart() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        client.stop()  // before start
        client.start() // must be no-op since isStopped

        // Give the receive loop time to spin up if it were going to.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(factory.createdTaskCount, 0,
            "start() after stop() must not create a websocket task")
    }

    /// Calling stop() twice must not crash or double-cancel.
    func testStopIsIdempotent() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)

        client.start()
        await waitForTasks(1, factory: factory)
        try await Task.sleep(nanoseconds: 20_000_000)

        client.stop()
        client.stop()  // second stop must be safe

        try await Task.sleep(nanoseconds: 20_000_000)

        // First stop cancels the task; second stop has nothing to cancel.
        XCTAssertEqual(factory.task(at: 0).cancelCallCount, 1,
            "second stop() must not double-cancel the underlying task")
    }

    /// onEventReceived = nil must not crash when an events_callback frame arrives.
    /// Production code sets the handler before start(), but defensive nil-check
    /// prevents a future refactor from regressing into a NPE.
    func testEventDeliveredWithNilHandlerDoesNotCrash() async throws {
        let factory = MockWebSocketTaskFactory()
        let client = makeClient(factory: factory)
        client.onEventReceived = nil

        client.start()
        await waitForTasks(1, factory: factory)

        factory.task(at: 0).deliver(message: .string(#"{"type":"events_callback"}"#))

        // No crash within 50 ms = pass.
        try await Task.sleep(nanoseconds: 50_000_000)

        client.stop()
    }

    // MARK: - maxReconnects literal contract

    /// `testSlackSocketClientStopsReconnectAfterThreeAttempts` already verifies
    /// the bound via `SlackSocketClient.maxReconnects + 1`, but that loop
    /// references the constant — if the value drifted from 3 to 5 the loop
    /// would still match. Pin the literal so a quiet retry-budget edit fails
    /// here and prompts a deliberate review (more reconnects masks Socket
    /// Mode endpoint instability; fewer drops events users expected to land).
    func testMaxReconnectsLiteralIsThree() {
        XCTAssertEqual(SlackSocketClient.maxReconnects, 3,
                       "Slack Socket Mode reconnect budget is part of the durability contract — changing it shifts user-visible message-loss behavior")
    }
}
