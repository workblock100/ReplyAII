import Foundation
import Security

/// Thin Keychain wrapper for per-channel OAuth tokens.
/// Keys are stored under the `ReplyAI-` prefix so factory-reset can
/// sweep them by prefix without touching unrelated system entries.
struct KeychainHelper: Sendable {
    let service: String

    init(service: String = "co.replyai.app") {
        self.service = service
    }

    /// Write (or overwrite) a string value for the given key.
    func set(value: String, for key: String) throws {
        let data = Data(value.utf8)
        let prefixedKey = "ReplyAI-\(key)"

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
            kSecAttrAccount:      "ReplyAI-\(key)",
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
            kSecAttrAccount: "ReplyAI-\(key)"
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes all items in this service whose account key starts with `prefix`.
    /// Factory reset calls this with `"ReplyAI-"` to wipe every channel token.
    func deleteAll(prefix: String) {
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

enum KeychainError: LocalizedError, Sendable {
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledError(let status): "Keychain error \(status)"
        }
    }
}
