import Foundation
import Contacts

/// Resolves raw handles (`+15551234567`, `user@example.com`) to contact
/// names via the user's address book. Gated on Contacts access (a
/// separate TCC permission from Full Disk Access).
@MainActor
final class ContactsResolver {
    enum Access {
        case unknown
        case granted
        case denied
    }

    private let store = CNContactStore()
    private var cache: [String: String] = [:]
    private(set) var access: Access = .unknown

    /// Kick off the permission prompt if we haven't asked yet. Safe to
    /// call repeatedly — already-authorized is a no-op.
    func ensureAccess() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            access = .granted
        case .denied, .restricted:
            access = .denied
        case .notDetermined:
            do {
                let ok = try await store.requestAccess(for: .contacts)
                access = ok ? .granted : .denied
            } catch {
                access = .denied
            }
        case .limited:
            access = .granted  // partial access is usable
        @unknown default:
            access = .denied
        }
    }

    /// Returns the contact's display name for a handle, or nil if we
    /// don't have a match (or don't have permission).
    func name(for handle: String) -> String? {
        if access != .granted { return nil }
        if let hit = cache[handle] { return hit.isEmpty ? nil : hit }

        let normalized = normalize(handle)
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]

        // Try phone first, then email. The predicates below match on any
        // contact whose phone OR email contains the handle.
        do {
            let predicate: NSPredicate
            if handle.contains("@") {
                predicate = CNContact.predicateForContacts(matchingEmailAddress: handle)
            } else {
                predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalized))
            }
            let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            if let first = matches.first,
               let formatted = CNContactFormatter.string(from: first, style: .fullName),
               !formatted.isEmpty {
                cache[handle] = formatted
                return formatted
            }
        } catch {
            // Fall through to negative cache.
        }

        cache[handle] = ""   // negative-cache so we don't re-hit for the same handle
        return nil
    }

    /// Collapse "+1 (415) 555-0134" and "4155550134" to the same form.
    private func normalize(_ handle: String) -> String {
        handle.filter { "+0123456789".contains($0) }
    }
}
