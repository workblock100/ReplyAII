import Foundation
import Network

/// Reusable loopback HTTP listener for OAuth 2 authorization-code callbacks.
/// Binds to the configured port, waits for the first incoming GET request,
/// extracts the `code` query parameter, then shuts down.
/// No Slack-specific logic lives here — this is generic OAuth plumbing.
final class LocalhostOAuthListener: @unchecked Sendable {
    /// HTTP response sent to the browser tab after a successful code capture.
    /// Exposed `internal static` so tests can pin the exact bytes without a
    /// loopback roundtrip — that pattern is timing-flaky on the in-process
    /// listener (see AGENTS.md "Loopback HTTP roundtrip tests" gotcha).
    /// Content-Length must match the body byte count: "OK" = 2.
    static let okResponseTemplate = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"

    /// Production default loopback port. The Slack OAuth flow embeds
    /// `redirect_uri=http://localhost:4242/callback` in both the authorize
    /// URL and the token-exchange POST body — those URIs MUST match exactly
    /// or Slack rejects the exchange. Hoisted to a constant so the port
    /// here, the redirect URI in `SlackOAuthFlow`, and the test harness all
    /// stay coupled to the same number.
    static let defaultPort: UInt16 = 4242

    /// Production default timeout in seconds. 120s is enough for a user to
    /// notice the browser tab, click the workspace, sign in if needed, and
    /// approve. Drop too low and slow-network or 2FA-prompted users hit
    /// `.timeout` mid-flow; raise too high and a stale listener squats the
    /// port across retries.
    static let defaultTimeout: TimeInterval = 120

    /// Maximum bytes we read from a single OAuth callback request before
    /// parsing. The OAuth callback URL is only the redirect URI + a query
    /// string; even with a long state token it's well under 4 KB. 8 KB
    /// gives us headroom without letting a malformed request balloon RAM
    /// usage on the listener queue. Drift below ~2 KB risks truncating the
    /// `code=` value when Slack's authorization codes change shape; drift
    /// above ~64 KB lets a buggy or hostile client pin memory until the
    /// listener cancels.
    static let maxRequestBytes: Int = 8192

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

    init(port: UInt16 = LocalhostOAuthListener.defaultPort,
         timeout: TimeInterval = LocalhostOAuthListener.defaultTimeout) {
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestBytes) { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let data,
                  let request = String(data: data, encoding: .utf8) else { return }

            // First line of HTTP request: "GET /?code=abc123 HTTP/1.1"
            guard let requestLine = request.components(separatedBy: "\r\n").first else { return }
            let parts = requestLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { return }
            let rawPath = String(parts[1])

            // Require a non-empty code value. `?code=` (empty) is symmetric to
            // a missing `code` param: it can't satisfy the token-exchange POST,
            // so silently drop and let the timeout govern instead of completing
            // with an empty string a downstream caller would have to re-validate.
            guard let url = URL(string: "http://localhost\(rawPath)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty
            else { return }

            // Acknowledge to the browser before finishing.
            connection.send(content: Data(Self.okResponseTemplate.utf8), completion: .idempotent)

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

/// Errors surfaced from the OAuth2 callback dance. Used by both the
/// localhost listener (timeout / listener bind failure) and the token
/// exchange POST (`tokenExchangeFailed`). Equatable because tests pattern-
/// match against specific cases and `Settings → Channels` compares the
/// last error with `==` to suppress duplicate banner re-renders.
enum OAuthError: LocalizedError, Sendable, Equatable {
    case timeout
    case listenerFailed(String)
    /// Token exchange POST returned `{"ok":false}` or a network error.
    case tokenExchangeFailed(String)

    /// Without LocalizedError conformance, Settings → Channels would show
    /// the generic "The operation couldn't be completed" CFString fallback
    /// when Slack connect fails — useless for users trying to triage.
    var errorDescription: String? {
        switch self {
        case .timeout:
            "Slack didn't respond. Open the Slack app and try again, or check your internet connection."
        case .listenerFailed(let msg):
            "Couldn't open the local callback server: \(msg)"
        case .tokenExchangeFailed(let msg):
            "Slack rejected the connection: \(msg)"
        }
    }
}
