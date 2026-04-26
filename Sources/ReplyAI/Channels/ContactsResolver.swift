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
/// wrap the mutable state in a `Locked<ResolverState>`.
final class ContactsResolver: @unchecked Sendable {
    enum Access: Sendable {
        case unknown
        case granted
        case denied
    }

    private struct CacheEntry {
        let name: String
        let cachedAt: Date
    }

    private struct ResolverState {
        var cache: [String: CacheEntry] = [:]
        var access: Access = .unknown
    }

    private let store: ContactsStoring
    /// How long a cached name remains fresh before the store is re-queried.
    /// Default 1800 s (30 min). Zero means always re-query (useful in tests).
    let ttl: TimeInterval
    private let locked = Locked<ResolverState>(ResolverState())
    private let notificationCenter: NotificationCenter
    private var notificationObserver: NSObjectProtocol?

    init(store: ContactsStoring? = nil, ttl: TimeInterval = 1800,
         notificationCenter: NotificationCenter = .default) {
        self.store = store ?? CNContactStoreBackedStoring()
        self.ttl = ttl
        self.notificationCenter = notificationCenter
        // Flush the name cache whenever the user's address book changes so
        // newly added contacts appear without waiting for TTL expiry.
        notificationObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.CNContactStoreDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.locked.withLock { $0.cache.removeAll() }
        }
    }

    deinit {
        if let obs = notificationObserver {
            notificationCenter.removeObserver(obs)
        }
    }

    var access: Access {
        locked.withLock { $0.access }
    }

    private func isFresh(_ entry: CacheEntry, now: Date) -> Bool {
        ttl > 0 && now.timeIntervalSince(entry.cachedAt) < ttl
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

    /// Resolves a batch of handles in exactly two lock acquisitions regardless
    /// of inbox size. Cache hits (that are still within TTL) are resolved inside
    /// the first lock; store queries for misses/stale entries happen outside any
    /// lock; the second acquisition writes the results back.
    func resolveAll(handles: [String]) -> [String: String] {
        let now = Date()
        let keys = handles.map { (original: $0, normalized: normalizedHandle($0)) }

        // Pass 1: collect fresh cache hits and identify misses/stale entries.
        var result: [String: String] = [:]
        var missKeys: [(original: String, normalized: String)] = []
        let gate: Access = locked.withLock { state in
            for pair in keys {
                if let entry = state.cache[pair.normalized], isFresh(entry, now: now) {
                    if !entry.name.isEmpty { result[pair.original] = entry.name }
                } else {
                    missKeys.append(pair)
                }
            }
            return state.access
        }

        // Pass 2: query the store for misses (outside the lock).
        // Use the ORIGINAL (un-normalized) handle so CNPhoneNumber sees the
        // country code — see `name(for:)` for the same fix.
        guard gate == .granted else { return result }
        var storeResults: [(normalized: String, name: String)] = []
        for pair in missKeys {
            let resolved = store.lookup(handle: pair.original) ?? ""
            storeResults.append((normalized: pair.normalized, name: resolved))
            if !resolved.isEmpty { result[pair.original] = resolved }
        }

        // Pass 3: write miss results into the cache — second lock acquisition.
        if !storeResults.isEmpty {
            let writeAt = Date()
            locked.withLock { state in
                for item in storeResults {
                    state.cache[item.normalized] = CacheEntry(name: item.name, cachedAt: writeAt)
                }
            }
        }

        return result
    }

    /// Returns the contact's display name for a handle, or nil if we
    /// don't have a match (or don't have permission). Callable from any
    /// thread.
    func name(for handle: String) -> String? {
        let now = Date()
        let key = normalizedHandle(handle)
        let (entry, gate) = locked.withLock { state -> (CacheEntry?, Access) in
            (state.cache[key], state.access)
        }
        if let entry, isFresh(entry, now: now) { return entry.name.isEmpty ? handle : entry.name }
        if gate != .granted { return nil }

        // Pass the ORIGINAL handle (e.g. `+15551234567`) to the store so
        // CNPhoneNumber's matcher sees the country code. Stripping to 10
        // digits before calling the framework breaks matches against
        // contacts that store the full E.164 number.
        let resolved = store.lookup(handle: handle) ?? ""
        let writeAt = Date()
        locked.withLock { $0.cache[key] = CacheEntry(name: resolved, cachedAt: writeAt) }
        return resolved.isEmpty ? handle : resolved
    }

    /// Collapse E.164 variants to a 10-digit canonical form so `+14155551234`,
    /// `14155551234`, and `4155551234` all share the same cache entry.
    /// Non-phone handles (email addresses, group chat IDs) pass through unchanged.
    internal func normalizedHandle(_ handle: String) -> String {
        guard !handle.contains("@"), !handle.hasPrefix("chat") else { return handle }
        let digits = handle.filter(\.isNumber)
        guard digits.count >= 10 else { return handle }
        if digits.count == 11 && digits.hasPrefix("1") { return String(digits.dropFirst()) }
        return digits.count == 10 ? digits : handle
    }

    private func setAccess(_ a: Access) {
        locked.withLock { $0.access = a }
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
final class CNContactStoreBackedStoring: ContactsStoring, @unchecked Sendable {
    private let store = CNContactStore()
    /// Lazily-built digit-keyed index of every contact's phones + emails.
    /// We don't trust `CNContact.predicateForContacts(matching: CNPhoneNumber)` —
    /// it does literal-format comparison and misses common cases like a contact
    /// stored as `(631) 848-6282` when the iMessage handle is `+16318486282`.
    /// Building a normalized digit index once lets every subsequent lookup
    /// hit in O(1) regardless of how the user typed the number.
    private let indexLock = NSLock()
    private var digitIndex: [String: String]?

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
        let index = ensureIndex()
        if handle.contains("@") {
            return index[handle.lowercased()]
        }
        let digits = Self.phoneDigits(handle)
        guard !digits.isEmpty else { return nil }
        return index[digits]
    }

    /// Build (or return cached) a digit-keyed map of every saved contact.
    /// Phones are keyed by their normalized 10-digit form (or the raw digit
    /// string when shorter); emails by lowercased address. Names are stored
    /// in the order CNContactFormatter formats them.
    private func ensureIndex() -> [String: String] {
        if let cached = indexLock.withLock({ digitIndex }) {
            return cached
        }
        var built: [String: String] = [:]
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let name = CNContactFormatter.string(from: contact, style: .fullName),
                      !name.isEmpty else { return }
                for phone in contact.phoneNumbers {
                    let key = Self.phoneDigits(phone.value.stringValue)
                    if !key.isEmpty, built[key] == nil { built[key] = name }
                }
                for email in contact.emailAddresses {
                    let key = (email.value as String).lowercased()
                    if !key.isEmpty, built[key] == nil { built[key] = name }
                }
            }
        } catch {
            // Permission revoked between currentAccess() and enumeration, or
            // the store can't be read — fall through with whatever we built.
        }
        indexLock.withLock { digitIndex = built }
        return built
    }

    /// Strip to digits and drop a leading `1` from 11-digit US numbers so
    /// `+16318486282`, `1-631-848-6282`, `(631) 848-6282`, and `6318486282`
    /// all share the same key `6318486282`.
    static func phoneDigits(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        if digits.count == 11 && digits.hasPrefix("1") { return String(digits.dropFirst()) }
        return digits
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
