import Foundation
import Contacts

/// Resolves raw handles (`+15551234567`, `user@example.com`) to contact
/// names via the user's address book. Gated on Contacts access (a
/// separate TCC permission from Full Disk Access).
///
/// Thread-safety: `name(for:)` is called from the SQLite worker thread
/// inside IMessageChannel.recentThreads, so the resolver must not be
/// actor-isolated. CNContactStore reads are safe from any thread; we
/// wrap the cache in an NSLock.
final class ContactsResolver: @unchecked Sendable {
    enum Access: Sendable {
        case unknown
        case granted
        case denied
    }

    private let store = CNContactStore()
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var _access: Access = .unknown

    var access: Access {
        synced { _access }
    }

    /// Kick off the permission prompt if we haven't asked yet. Safe to
    /// call repeatedly — already-authorized is a no-op.
    func ensureAccess() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let resolved: Access
        switch status {
        case .authorized:
            resolved = .granted
        case .denied, .restricted:
            resolved = .denied
        case .notDetermined:
            do {
                let ok = try await store.requestAccess(for: .contacts)
                resolved = ok ? .granted : .denied
            } catch {
                resolved = .denied
            }
        case .limited:
            resolved = .granted  // partial access is usable
        @unknown default:
            resolved = .denied
        }
        setAccess(resolved)
    }

    /// Returns the contact's display name for a handle, or nil if we
    /// don't have a match (or don't have permission). Callable from any
    /// thread.
    func name(for handle: String) -> String? {
        let (hit, gate) = synced { () -> (String?, Access) in
            (cache[handle], _access)
        }
        if let hit { return hit.isEmpty ? nil : hit }
        if gate != .granted { return nil }

        let resolved = lookup(handle: handle) ?? ""
        synced { cache[handle] = resolved }
        return resolved.isEmpty ? nil : resolved
    }

    // MARK: - Synchronous lock helpers

    /// Wraps NSLock usage in a sync method so callers from `async`
    /// contexts don't trip Swift 6's "NSLock unavailable in async
    /// contexts" diagnostic — the lock is never held across an await.
    private func synced<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private func setAccess(_ a: Access) {
        synced { _access = a }
    }

    /// Uncached lookup. CNContactStore + CNContactFormatter are both
    /// documented thread-safe for read access.
    private func lookup(handle: String) -> String? {
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        do {
            let predicate: NSPredicate
            if handle.contains("@") {
                predicate = CNContact.predicateForContacts(matchingEmailAddress: handle)
            } else {
                predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalize(handle)))
            }
            let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            if let first = matches.first,
               let formatted = CNContactFormatter.string(from: first, style: .fullName),
               !formatted.isEmpty {
                return formatted
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Collapse "+1 (415) 555-0134" and "4155550134" to the same form.
    private func normalize(_ handle: String) -> String {
        handle.filter { "+0123456789".contains($0) }
    }
}
