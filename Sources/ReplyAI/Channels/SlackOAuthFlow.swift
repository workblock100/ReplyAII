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

struct WorkspaceURLOpener: URLOpener, Sendable {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// LocalhostOAuthListener satisfies OAuthCallbackListener out of the box.
extension LocalhostOAuthListener: OAuthCallbackListener {}

// MARK: - SlackOAuthFlow

/// Orchestrates Slack's OAuth2 authorization-code exchange.
/// Wires together: LocalhostOAuthListener (callback server) → NSWorkspace URL open
/// → URLSession token exchange POST → KeychainHelper token storage.
final class SlackOAuthFlow: @unchecked Sendable {
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
        let listener = listenerFactory(4242, 120)

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
                var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "scope", value: "channels:read,chat:write"),
                    URLQueryItem(name: "redirect_uri", value: "http://localhost:4242/callback")
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
        guard let endpointURL = URL(string: "https://slack.com/api/oauth.v2.access") else {
            completion(.failure(.tokenExchangeFailed("invalid endpoint URL")))
            return
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyParts = [
            "code=\(code)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "redirect_uri=http://localhost:4242/callback"
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
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = json["ok"] as? Bool, ok,
                let token = json["access_token"] as? String
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
