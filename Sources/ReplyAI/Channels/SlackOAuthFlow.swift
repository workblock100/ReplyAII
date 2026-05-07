import Foundation
import AppKit

/// Injectable URL-opening abstraction — default implementation uses NSWorkspace.
protocol URLOpener: Sendable {
    func open(_ url: URL)
}

/// Injectable callback-listener abstraction over LocalhostOAuthListener.
/// Allows tests to inject a mock that delivers codes without binding a real port.
protocol OAuthCallbackListener: AnyObject {
    var actualPort: UInt16? { get }
    func start(completion: @escaping (Result<String, OAuthError>) -> Void, onReady: (() -> Void)?)
    func stop()
}

/// Factory closure type: produces an OAuthCallbackListener for a given port + timeout.
typealias OAuthCallbackListenerFactory = (UInt16, TimeInterval) -> any OAuthCallbackListener

// MARK: - Default implementations

/// Production `URLOpener` that hands the URL to AppKit's NSWorkspace, which
/// dispatches it to the user's default browser. Tests substitute a mock
/// implementation that captures the requested URL without launching a
/// real Safari window — the OAuth flow's "did it try to open the right
/// URL?" assertion lives there.
struct WorkspaceURLOpener: URLOpener, Sendable {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// LocalhostOAuthListener satisfies OAuthCallbackListener out of the box.
extension LocalhostOAuthListener: OAuthCallbackListener {}

// MARK: - SlackOAuthFlow

/// Test seam that lets `SlackChannel.authorize` delegate into a fake flow
/// without binding a real localhost listener.
protocol SlackAuthorizing: AnyObject, Sendable {
    func authorize(
        clientID: String,
        clientSecret: String,
        completion: @escaping (Result<Void, OAuthError>) -> Void
    )
}

/// Orchestrates Slack's OAuth2 authorization-code exchange.
/// Wires together: LocalhostOAuthListener (callback server) → NSWorkspace URL open
/// → URLSession token exchange POST → KeychainHelper token storage.
final class SlackOAuthFlow: SlackAuthorizing, @unchecked Sendable {
    /// Production redirect URI. Slack's app config registers exactly this
    /// URL — drift on either of the two sites that previously duplicated it
    /// (auth-URL query item + token-exchange POST body) would produce a
    /// silent "redirect_uri_mismatch" error from Slack with no UI feedback.
    /// Single source of truth so the auth-URL leg and the token-exchange
    /// leg can never desync.
    static let redirectURI = "http://localhost:4242/callback"

    /// Exact, ordered OAuth scope ReplyAI requests on the auth URL. Slack
    /// re-issues a consent prompt to every existing user when the scope
    /// string changes (even reordering items), and any token granted under
    /// the previous scope no longer covers the new bits. Drift here is a
    /// silent re-consent for the entire user base. `channels:read` lets
    /// the app list public channels via `conversations.list`; `chat:write`
    /// is the bot post-message capability used when the user sends a draft.
    /// Pinned by `SlackOAuthFlowTests`'s `testAuthURLContainsExpectedScope`
    /// cluster.
    static let scope = "channels:read,chat:write"

    /// Slack's OAuth2 authorization URL. Hoisted from the inline literal
    /// so the auth-URL leg has a single source of truth. Drift to e.g.
    /// `https://api.slack.com/oauth/v2/authorize` (a Slack-shaped but
    /// wrong host) silently breaks the flow — Slack answers different
    /// things at different hosts. Pinned by
    /// `SlackOAuthFlowTests.testAuthorizationURLLiteralIsSlackOAuthV2Authorize`.
    static let authorizationURL = "https://slack.com/oauth/v2/authorize"

    /// Slack's `oauth.v2.access` token-exchange endpoint. Hoisted from
    /// the inline literal so the token-exchange POST routes through a
    /// named constant. Drift here lands the form-body POST at a wrong
    /// host (Slack's API surface answers different things at different
    /// hosts), which surfaces as a generic `tokenExchangeFailed` with
    /// no UI feedback identifying the host as the cause.
    /// Pinned by `SlackOAuthFlowTests.testTokenExchangeURLIsExactSlackAPIEndpoint`.
    static let tokenExchangeURL = "https://slack.com/api/oauth.v2.access"

    private let tokenStore: SlackTokenStore
    private let urlOpener: any URLOpener
    private let session: URLSession
    private let listenerFactory: OAuthCallbackListenerFactory

    init(
        tokenStore: SlackTokenStore = SlackTokenStore(),
        urlOpener: any URLOpener = WorkspaceURLOpener(),
        session: URLSession = .shared,
        listenerFactory: @escaping OAuthCallbackListenerFactory = { port, timeout in
            LocalhostOAuthListener(port: port, timeout: timeout)
        }
    ) {
        self.tokenStore = tokenStore
        self.urlOpener = urlOpener
        self.session = session
        self.listenerFactory = listenerFactory
    }

    /// Convenience init for tests that wire the OAuth flow against a specific
    /// `KeychainHelper` (e.g. a unique service per test for isolation).
    /// Wraps the helper in a `SlackTokenStore` so storage stays unified with
    /// `SlackChannel` (both read/write the same JSON entry).
    convenience init(
        keychain: KeychainHelper,
        urlOpener: any URLOpener = WorkspaceURLOpener(),
        session: URLSession = .shared,
        listenerFactory: @escaping OAuthCallbackListenerFactory = { port, timeout in
            LocalhostOAuthListener(port: port, timeout: timeout)
        }
    ) {
        self.init(
            tokenStore: SlackTokenStore(keychain: keychain),
            urlOpener: urlOpener,
            session: session,
            listenerFactory: listenerFactory
        )
    }

    /// Start the OAuth2 flow. Opens the Slack auth page in the default browser,
    /// waits for the callback code, exchanges it for an access token, and stores
    /// the token in Keychain under "slack-access-token".
    func authorize(
        clientID: String,
        clientSecret: String,
        completion: @escaping (Result<Void, OAuthError>) -> Void
    ) {
        let listener = listenerFactory(LocalhostOAuthListener.defaultPort, LocalhostOAuthListener.defaultTimeout)

        listener.start(
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let code):
                    self.exchangeCode(code, clientID: clientID, clientSecret: clientSecret, completion: completion)
                }
            },
            onReady: { [weak self] in
                guard let self else { return }
                var components = URLComponents(string: SlackOAuthFlow.authorizationURL)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "scope", value: SlackOAuthFlow.scope),
                    URLQueryItem(name: "redirect_uri", value: SlackOAuthFlow.redirectURI)
                ]
                guard let url = components.url else { return }
                self.urlOpener.open(url)
            }
        )
    }

    // MARK: - Private

    private func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        completion: @escaping (Result<Void, OAuthError>) -> Void
    ) {
        guard let endpointURL = URL(string: SlackOAuthFlow.tokenExchangeURL) else {
            completion(.failure(.tokenExchangeFailed("invalid endpoint URL")))
            return
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Percent-encode each value individually. Slack's actual codes / IDs are
        // alphanumeric so the encoding is usually a no-op, but a code or secret
        // with `&`, `=`, `+`, or `%` would otherwise corrupt the form body
        // (split across separators or change byte semantics on Slack's side).
        // The allowed set is alphanumerics plus the unreserved punctuation per
        // RFC 3986 §2.3 — every other byte is percent-escaped, which is what
        // `application/x-www-form-urlencoded` expects.
        let formAllowed: CharacterSet = {
            var set = CharacterSet.alphanumerics
            set.insert(charactersIn: "-._~")
            return set
        }()
        let escape: (String) -> String = { value in
            value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
        }
        let bodyParts = [
            "code=\(escape(code))",
            "client_id=\(escape(clientID))",
            "client_secret=\(escape(clientSecret))",
            "redirect_uri=\(SlackOAuthFlow.redirectURI)"
        ]
        request.httpBody = Data(bodyParts.joined(separator: "&").utf8)

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                completion(.failure(.tokenExchangeFailed(error.localizedDescription)))
                return
            }
            guard let data else {
                completion(.failure(.tokenExchangeFailed("empty response")))
                return
            }
            // Reject present-but-empty access_token symmetrically with the
            // missing-key path: storing "" produces 401 on every later call
            // and surfaces as a "stale token" UX rather than a clear auth
            // failure at the moment the OAuth handshake actually broke.
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = json["ok"] as? Bool, ok,
                let token = json["access_token"] as? String,
                !token.isEmpty
            else {
                completion(.failure(.tokenExchangeFailed("response missing ok=true or access_token")))
                return
            }
            // Slack's oauth.v2.access response embeds `team: { id, name }`.
            // Pull the workspace name out so the inbox can show "Connected: ACME".
            let workspaceName: String = (json["team"] as? [String: Any])?["name"] as? String ?? ""
            do {
                try self.tokenStore.set(token: token, workspaceName: workspaceName)
                completion(.success(()))
            } catch {
                completion(.failure(.tokenExchangeFailed(error.localizedDescription)))
            }
        }.resume()
    }
}
