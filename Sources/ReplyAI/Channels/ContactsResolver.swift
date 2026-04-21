import Foundation
import Contacts

/// Narrow surface the resolver needs from whatever contact-lookup
/// backend it's wired against. Lets tests drop in a deterministic
/// fake without pulling in a real `CNContactStore` (which asks the
/// user for Contacts permission and returns nondeterministic data).
protocol ContactsStoring: Sendable {
    /// Current authorization state — synchronous snapshot. Mirrors
    /// `CNContactStore.authorizationStatus(for:)`.
    func currentAccess() -> ContactsResolver.Access

    /// Prompt (if needed) and return the resulting state. Called once
    /// from `ContactsResolver.ensureAccess`.
    func requestAccess() async -> ContactsResolver.Access

    /// Uncached name lookup for a phone/email handle. Returns nil on
    /// miss or on any error — the resolver can't distinguish those
    /// cases and doesn't need to.
    func lookup(handle: String) -> String?
}

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

    private let store: ContactsStoring
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var _access: Access = .unknown

    init(store: ContactsStoring? = nil) {
        self.store = store ?? CNContactStoreBackedStoring()
    }

    var access: Access {
        synced { _access }
    }

    /// Kick off the permission prompt if we haven't asked yet. Safe to
    /// call repeatedly — already-authorized is a no-op.
    func ensureAccess() async {
        let current = store.currentAccess()
        if current != .unknown {
            setAccess(current)
            return
        }
        let resolved = await store.requestAccess()
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

        let resolved = store.lookup(handle: handle) ?? ""
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

    #if DEBUG
    /// Test-only: force the resolver into a given access state without
    /// going through `ensureAccess`. Kept separate from `setAccess`
    /// (which is called from the async ensureAccess path) so it's
    /// obvious at the call site that a test is overriding production
    /// behavior.
    func overrideAccessForTesting(_ a: Access) {
        setAccess(a)
    }
    #endif
}

/// Production `ContactsStoring` — hits the real `CNContactStore`.
/// Keeps all Contacts framework specifics out of the resolver proper
/// so the unit-test path never touches the framework.
struct CNContactStoreBackedStoring: ContactsStoring {
    private let store = CNContactStore()

    func currentAccess() -> ContactsResolver.Access {
        Self.translate(CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestAccess() async -> ContactsResolver.Access {
        do {
            let ok = try await store.requestAccess(for: .contacts)
            return ok ? .granted : .denied
        } catch {
            return .denied
        }
    }

    func lookup(handle: String) -> String? {
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

    private static func translate(_ status: CNAuthorizationStatus) -> ContactsResolver.Access {
        switch status {
        case .authorized, .limited: return .granted
        case .denied, .restricted:  return .denied
        case .notDetermined:        return .unknown
        @unknown default:           return .denied
        }
    }
}
