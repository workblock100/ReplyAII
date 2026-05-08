import Foundation
import Security

/// Thin Keychain wrapper for per-channel OAuth + relay tokens.
///
/// Each item lives at (`kSecAttrService = service`,
/// `kSecAttrAccount = "ReplyAI-" + key`). The `ReplyAI-` prefix on the
/// account side lets a factory-reset sweep all our entries via an
/// account-prefix query without iterating every service. The `service`
/// is per-channel and may use either the `ReplyAI-<Channel>` form or a
/// reverse-DNS form like `co.replyai.telegram` — see each channel's
/// `keychainService` constant for the exact value (pinned by
/// `ChannelStubKeychainContractTests`).
struct KeychainHelper: Sendable {
    /// Account-prefix every Keychain entry written by ReplyAI carries.
    /// Lets factory-reset sweep all our entries via a prefix query
    /// without iterating every service. Drift on this prefix orphans
    /// every existing user's stored channel tokens — they appear as a
    /// fresh "not connected" state with no migration path. Pinned by
    /// `KeychainHelperTests` (literal `"ReplyAI-"` references).
    static let accountPrefix = "ReplyAI-"

    /// Default Keychain service identifier for the production app's tokens
    /// — Slack OAuth via `SlackTokenStore` reads/writes against this
    /// service. Renaming orphans every shipped user's stored token
    /// (Keychain identity is the service+account literal). Hoisted so the
    /// `KeychainHelper` default and the `SlackTokenStore` default route
    /// through the same constant; previously each was an inline literal,
    /// so a rename touching one wouldn't fail the other's test. Pinned by
    /// `KeychainHelperTests.testDefaultServiceLiteralIsCoReplyAIApp`.
    static let defaultService = "co.replyai.app"

    let service: String

    init(service: String = KeychainHelper.defaultService) {
        self.service = service
    }

    /// Write (or overwrite) a string value for the given key.
    func set(value: String, for key: String) throws {
        let data = Data(value.utf8)
        let prefixedKey = "\(KeychainHelper.accountPrefix)\(key)"

        // Attempt update of an existing item; add if absent.
        let baseQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: prefixedKey
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }

    /// Returns the stored value, or nil if the key is absent.
    func get(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      "\(KeychainHelper.accountPrefix)\(key)",
            kSecMatchLimit:       kSecMatchLimitOne,
            kSecReturnData:       kCFBooleanTrue as Any
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the key from Keychain. No-op if absent.
    func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "\(KeychainHelper.accountPrefix)\(key)"
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes all items in this service whose account key starts with `prefix`.
    /// Factory reset calls this with `"ReplyAI-"` to wipe every channel token.
    func deleteAll(prefix: String) {
        // Refuse to operate with an empty prefix — `String.hasPrefix("")` returns
        // true for every account, so a caller that accidentally computed an empty
        // prefix from missing configuration would catastrophically wipe every
        // item in this service. Caller error; no-op rather than nuke the keychain.
        guard !prefix.isEmpty else { return }
        let listQuery: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecMatchLimit:       kSecMatchLimitAll,
            kSecReturnAttributes: kCFBooleanTrue as Any
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(listQuery as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[CFString: Any]] else { return }

        for item in items {
            guard let account = item[kSecAttrAccount] as? String,
                  account.hasPrefix(prefix) else { continue }
            let deleteQuery: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }
}

/// Wraps the raw `OSStatus` from `SecItem*` calls so callers and logs see
/// something more actionable than a bare integer. The status is the only
/// payload the Security framework gives us — keep it on the value so a
/// support engineer can grep Apple's status tables for the code.
enum KeychainError: LocalizedError, Sendable {
    case unhandledError(status: OSStatus)

    /// User-visible toast copy for each translated `OSStatus`. Hoisted
    /// from the inline literals inside `errorDescription` so a copy
    /// edit lands on a clearly-named constant rather than buried
    /// inside a nested switch in a non-UI file. Existing tests in
    /// `KeychainErrorTests` use substring matching (e.g.
    /// `.contains("sign in")`) which doesn't catch a re-wording that
    /// drops the actionable hint — these constants plus the
    /// `*ToastCopyIsFrozen` pin tests are the byte-for-byte contract.
    /// Pinned by `KeychainHelperTests`'
    /// `*ToastCopyIsFrozen` cluster.
    static let authFailedToast              = "Keychain refused access. Sign in to your Mac and try again."
    static let userCanceledToast            = "Keychain access canceled. Try connecting again to retry."
    static let interactionNotAllowedToast   = "Keychain is locked. Unlock your login keychain in Keychain Access and try again."
    static let duplicateItemToast           = "Keychain already has a saved entry for this account. Disconnect the account in Settings → Channels and reconnect."
    static let itemNotFoundToast            = "Keychain entry missing. Reconnect the account in Settings → Channels."

    /// Format the unhandled-error fallback toast for an arbitrary
    /// OSStatus. Surfaces when the raw status doesn't match any of the
    /// five translated toasts — e.g. a future macOS release introduces
    /// a new SecBase.h status code we haven't translated. The format
    /// surfaces the raw integer status so a support engineer can grep
    /// Apple's table; drift here either drops the integer (eliminating
    /// the only signal a triage-engineer has) or rewords the recovery
    /// hint ("Open Keychain Access…") which is the user's only
    /// actionable next step. Pinned by
    /// `KeychainErrorTests.testUnhandledErrorFallbackToastFormatRoundTrips`.
    static func unhandledErrorFallbackToast(status: OSStatus) -> String {
        "Keychain error \(status). Open Keychain Access to inspect, or reconnect the account in Settings → Channels."
    }

    /// Surfaces in Settings → Channels when an OAuth token write fails.
    /// The bare-integer fallback used to read "Keychain error -25308" which
    /// is unactionable — translating the handful of statuses ReplyAI can
    /// realistically hit gives the user a clear next step (re-grant access,
    /// unlock the keychain, reconnect the account) instead of a number to
    /// google. Unknown codes still include the raw OSStatus so a support
    /// engineer can look it up against Apple's `SecBase.h` table.
    var errorDescription: String? {
        switch self {
        case .unhandledError(let status):
            switch status {
            case errSecAuthFailed:
                return Self.authFailedToast
            case errSecUserCanceled:
                return Self.userCanceledToast
            case errSecInteractionNotAllowed:
                return Self.interactionNotAllowedToast
            case errSecDuplicateItem:
                return Self.duplicateItemToast
            case errSecItemNotFound:
                return Self.itemNotFoundToast
            default:
                return Self.unhandledErrorFallbackToast(status: status)
            }
        }
    }
}

/// Structured storage for the Slack OAuth access token and workspace name.
/// The Slack v2.access response includes both; storing them together avoids
/// a second API round-trip in Settings when displaying "Connected: <workspace>".
struct SlackTokenStore: Sendable {
    private let keychain: KeychainHelper

    /// Keychain key the Slack access-token JSON entry lives under (the
    /// account-side prefix is added by `KeychainHelper`). Promoted from
    /// `private` so existing tests can reference it directly instead of
    /// re-typing the literal at five call sites — drift between any test's
    /// inline literal and this constant would make the test pass against
    /// a different (and almost-always empty) Keychain row, hiding real
    /// production regressions in the storage path. Pinned by
    /// `KeychainHelperTests` (existing literal references re-routed).
    static let storageKey = "slack-access-token"

    private struct Entry: Codable {
        let token: String
        let workspaceName: String
    }

    init(keychain: KeychainHelper = KeychainHelper(service: KeychainHelper.defaultService)) {
        self.keychain = keychain
    }

    /// Encode token + workspaceName as JSON and persist to Keychain.
    func set(token: String, workspaceName: String) throws {
        let data = try JSONEncoder().encode(Entry(token: token, workspaceName: workspaceName))
        guard let json = String(data: data, encoding: .utf8) else {
            throw KeychainError.unhandledError(status: OSStatus(-1))
        }
        try keychain.set(value: json, for: Self.storageKey)
    }

    /// Returns stored (token, workspaceName), or nil if absent or unreadable.
    func get() -> (token: String, workspaceName: String)? {
        guard let json = keychain.get(key: Self.storageKey),
              let data = json.data(using: .utf8),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return (entry.token, entry.workspaceName)
    }

    /// Remove the stored entry. No-op if absent.
    func delete() {
        keychain.delete(key: Self.storageKey)
    }
}
