import Foundation

/// Persistent storage for the Groq API key used by `GroqLLMService`.
///
/// Backed by the macOS Keychain via `KeychainHelper`. The key is set
/// out-of-band (CLI `security add-generic-password` or the future
/// `SetModelView` Groq-key field) and read at app launch in
/// `ReplyAIApp.init` to decide which `LLMService` to install.
///
/// **Token shape**: a Groq key looks like `gsk_<52 chars>`. We deliberately
/// don't validate the shape on load — a malformed token will fail at the
/// HTTPS request site with a 401 from Groq, which surfaces to the user
/// as a clean composer-side error.
public enum GroqTokenStore {
    /// Keychain service name. Same reverse-DNS convention as Telegram
    /// (`co.replyai.telegram`); the Slack family uses `ReplyAI-Slack`
    /// instead. Drift here orphans every shipped user's stored key —
    /// pinned by `GroqTokenStoreTests.testServiceNameIsFrozen`.
    public static let service = "co.replyai.groq"

    /// Keychain account key (excluding the `ReplyAI-` prefix that
    /// `KeychainHelper` auto-applies). Single key per install today —
    /// future multi-account work would extend this with account IDs.
    public static let apiKeyAccount = "apiKey"

    /// Returns the stored Groq API key, or nil when none is installed.
    /// nil means `LLMServiceProvider` falls through to MLX or Stub.
    public static func load() -> String? {
        let helper = KeychainHelper(service: service)
        let value = helper.get(key: apiKeyAccount)
        // Treat empty-string as nil — see the "present-but-empty strings
        // are a recurring bug class" gotcha in AGENTS.md.
        guard let v = value, !v.isEmpty else { return nil }
        return v
    }

    /// Writes a new Groq API key. Overwrites any existing key.
    public static func save(_ apiKey: String) throws {
        let helper = KeychainHelper(service: service)
        try helper.set(value: apiKey, for: apiKeyAccount)
    }

    /// Removes the stored key. After this, `load()` returns nil and the
    /// app falls through to MLX/Stub for drafts.
    public static func delete() {
        let helper = KeychainHelper(service: service)
        helper.delete(key: apiKeyAccount)
    }
}
