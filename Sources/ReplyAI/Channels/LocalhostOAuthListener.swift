import Foundation
import Network

/// Reusable loopback HTTP listener for OAuth 2 authorization-code callbacks.
/// Binds to the configured port, waits for the first incoming GET request,
/// extracts the `code` query parameter, then shuts down.
/// No Slack-specific logic lives here — this is generic OAuth plumbing.
final class LocalhostOAuthListener: @unchecked Sendable {
    private let preferredPort: UInt16
    private let timeout: TimeInterval

    /// Actual port bound after the listener reaches `.ready` state.
    /// Populated before `onReady` fires; may differ from `preferredPort`
    /// when `preferredPort == 0` and the OS picks the port.
    private(set) var actualPort: UInt16?

    private let lock = NSLock()
    private var isRunning = false
    private var listener: NWListener?
    private var timeoutTask: Task<Void, Never>?
    private var completionHandler: ((Result<String, OAuthError>) -> Void)?
    private var readyHandler: (() -> Void)?

    init(port: UInt16 = 4242, timeout: TimeInterval = 120) {
        self.preferredPort = port
        self.timeout = timeout
    }

    /// Start listening. The completion fires exactly once with either the
    /// extracted code or an `OAuthError`. Calling `start` while already
    /// running is a no-op (neither completion nor onReady is called again).
    ///
    /// - Parameters:
    ///   - completion: Called with `.success(code)` on a valid callback URL,
    ///                 or `.failure` on timeout or listener error.
    ///   - onReady: Optional callback fired when the listener is bound and
    ///              `actualPort` is set. Useful in tests to synchronize
    ///              before connecting.
    func start(
        completion: @escaping (Result<String, OAuthError>) -> Void,
        onReady: (() -> Void)? = nil
    ) {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        completionHandler = completion
        readyHandler = onReady
        lock.unlock()

        let nwPort: NWEndpoint.Port = preferredPort == 0
            ? .any
            : (NWEndpoint.Port(rawValue: preferredPort) ?? .any)

        let newListener: NWListener
        do {
            newListener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            finish(with: .failure(.listenerFailed("Could not create NWListener on port \(preferredPort): \(error)")))
            return
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            switch state {
            case .ready:
                let boundPort = newListener?.port?.rawValue
                self?.lock.lock()
                self?.actualPort = boundPort
                let ready = self?.readyHandler
                self?.readyHandler = nil
                self?.lock.unlock()
                ready?()
            case .failed(let error):
                self?.finish(with: .failure(.listenerFailed(error.localizedDescription)))
            default:
                break
            }
        }

        lock.lock()
        listener = newListener
        lock.unlock()

        newListener.start(queue: .global(qos: .utility))

        let t = timeout
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(with: .failure(.timeout))
        }
        lock.lock()
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    /// Cancel the listener and drop any pending completion without calling it.
    func stop() {
        lock.lock()
        let l = listener
        let t = timeoutTask
        isRunning = false
        listener = nil
        completionHandler = nil
        readyHandler = nil
        timeoutTask = nil
        lock.unlock()
        l?.cancel()
        t?.cancel()
    }

    // MARK: - Private

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let data,
                  let request = String(data: data, encoding: .utf8) else { return }

            // First line of HTTP request: "GET /?code=abc123 HTTP/1.1"
            guard let requestLine = request.components(separatedBy: "\r\n").first else { return }
            let parts = requestLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { return }
            let rawPath = String(parts[1])

            guard let url = URL(string: "http://localhost\(rawPath)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else { return }

            // Acknowledge to the browser before finishing.
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
            connection.send(content: Data(response.utf8), completion: .idempotent)

            self?.finish(with: .success(code))
        }
    }

    private func finish(with result: Result<String, OAuthError>) {
        lock.lock()
        guard let completion = completionHandler else {
            lock.unlock()
            return
        }
        completionHandler = nil
        readyHandler = nil
        isRunning = false
        let l = listener
        let t = timeoutTask
        listener = nil
        timeoutTask = nil
        lock.unlock()
        l?.cancel()
        t?.cancel()
        completion(result)
    }
}

enum OAuthError: Error, Sendable, Equatable {
    case timeout
    case listenerFailed(String)
}
