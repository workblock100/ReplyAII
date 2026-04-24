import Foundation

// MARK: - Injectable seams

/// Minimum surface of URLSessionWebSocketTask needed by SlackSocketClient.
/// Allows tests to inject a mock without touching real network connections.
protocol WebSocketTaskProtocol: AnyObject {
    func resume()
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: WebSocketTaskProtocol {}

/// Creates WebSocket tasks from a URL. Default implementation delegates to URLSession.
protocol WebSocketTaskFactory: Sendable {
    func makeWebSocketTask(with url: URL) -> any WebSocketTaskProtocol
}

struct URLSessionWebSocketFactory: WebSocketTaskFactory, @unchecked Sendable {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func makeWebSocketTask(with url: URL) -> any WebSocketTaskProtocol {
        session.webSocketTask(with: url)
    }
}

// MARK: - SlackSocketClient

/// WebSocket client for Slack Socket Mode real-time event streaming.
///
/// Takes a pre-formed connection URL from `apps.connections.open`, drives the
/// receive loop, filters out `ping` and `hello` control frames, and forwards
/// only `events_callback` envelopes to `onEventReceived`. Auto-reconnects up
/// to `maxReconnects` times after an abnormal close.
final class SlackSocketClient: @unchecked Sendable {

    /// Called on the calling context for each `events_callback` frame received.
    var onEventReceived: ((Data) -> Void)?

    static let maxReconnects = 3

    private let connectionURL: URL
    private let factory: any WebSocketTaskFactory
    // Internal so tests can inject 0 to skip sleep.
    let reconnectDelay: TimeInterval

    private let lock = NSLock()
    private var currentTask: (any WebSocketTaskProtocol)?
    private var isStopped = false

    // MARK: - Init

    init(
        connectionURL: URL,
        factory: any WebSocketTaskFactory,
        reconnectDelay: TimeInterval = 5.0
    ) {
        self.connectionURL = connectionURL
        self.factory = factory
        self.reconnectDelay = reconnectDelay
    }

    /// Convenience init for production use.
    convenience init(
        connectionURL: URL,
        urlSession: URLSession = .shared,
        reconnectDelay: TimeInterval = 5.0
    ) {
        self.init(
            connectionURL: connectionURL,
            factory: URLSessionWebSocketFactory(session: urlSession),
            reconnectDelay: reconnectDelay
        )
    }

    // MARK: - Public API

    /// Connect and begin receiving. Idempotent after the first call.
    func start() {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        lock.unlock()
        spawnReceiveLoop(attempt: 0)
    }

    /// Disconnect immediately. No further reconnects will occur.
    func stop() {
        lock.lock()
        isStopped = true
        let t = currentTask
        currentTask = nil
        lock.unlock()
        t?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Private

    private func spawnReceiveLoop(attempt: Int) {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        let wsTask = factory.makeWebSocketTask(with: connectionURL)
        currentTask = wsTask
        lock.unlock()
        wsTask.resume()

        Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(wsTask: wsTask, attempt: attempt)
        }
    }

    private func receiveLoop(wsTask: any WebSocketTaskProtocol, attempt: Int) async {
        while true {
            lock.lock()
            let stopped = isStopped
            lock.unlock()
            if stopped { return }

            do {
                let message = try await wsTask.receive()
                dispatch(message: message)
            } catch {
                lock.lock()
                let stopped = isStopped
                lock.unlock()
                if stopped { return }

                guard attempt < Self.maxReconnects else { return }

                if reconnectDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
                }

                lock.lock()
                let stillStopped = isStopped
                lock.unlock()
                if !stillStopped {
                    spawnReceiveLoop(attempt: attempt + 1)
                }
                return
            }
        }
    }

    private func dispatch(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):   data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default:    return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = json["type"] as? String else {
            return
        }

        switch type_ {
        case "ping", "hello":
            return
        case "events_callback":
            onEventReceived?(data)
        default:
            break
        }
    }
}
