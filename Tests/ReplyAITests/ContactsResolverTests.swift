import XCTest
import Contacts
@testable import ReplyAICore

final class ContactsResolverTests: XCTestCase {

    /// Headless test runners (autopilot fires, CI without `tccutil`) lack
    /// Contacts access. Even though every test below uses FakeContactStore,
    /// loading the test bundle eagerly resolves Contacts.framework symbols
    /// and surfaces 21 spurious `NSXPCStore` / AddressBook-v22.abcddb
    /// failures from the system's Address Book daemon. Skip the whole suite
    /// when access isn't authorized so the failures don't masquerade as
    /// real regressions and so future fires can drop the
    /// `--skip ContactsResolverTests` carve-out.
    override func setUpWithError() throws {
        try XCTSkipIf(
            CNContactStore.authorizationStatus(for: .contacts) != .authorized,
            "Contacts permission not granted to the test runner; suite is environmentally unrunnable here. Grant Full Disk Access + Contacts to xctest, or run via Xcode, to exercise these tests."
        )
    }

    // MARK: - Cache

    func testCacheMissQueriesStore() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        fake.names["5551111111"] = "Maya Lee"  // normalized key (10-digit canonical form)

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        XCTAssertEqual(resolver.name(for: "+15551111111"), "Maya Lee")
        XCTAssertEqual(fake.lookupCallCount, 1)
    }

    func testCacheHitSkipsStoreCall() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        fake.names["5552222222"] = "Ravi Patel"  // normalized key

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        _ = resolver.name(for: "+15552222222")  // populates cache
        _ = resolver.name(for: "+15552222222")  // should hit cache
        _ = resolver.name(for: "+15552222222")

        XCTAssertEqual(fake.lookupCallCount, 1,
                       "cache should serve the second + third call without another store trip")
    }

    func testCacheRemembersMissesAsEmpty() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        // no name mapping → store returns nil, falls back to the raw handle

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        XCTAssertEqual(resolver.name(for: "+15559999999"), "+15559999999")
        XCTAssertEqual(resolver.name(for: "+15559999999"), "+15559999999")
        XCTAssertEqual(fake.lookupCallCount, 1,
                       "repeat lookup of an unknown handle should not keep hitting the store")
    }

    /// Pins the "Some(\"\") collapses to nil" behavior of the resolver's
    /// per-handle cache. `name(for:)` writes `store.lookup(...) ?? ""` into
    /// `cache[key].name`, then on a fresh cache hit returns
    /// `entry.name.isEmpty ? handle : entry.name`. So a store that returns
    /// `Some("")` (a contact whose display name is the empty string —
    /// possible if a CNContact has no givenName/familyName/organizationName
    /// but does match by phone) ends up indistinguishable from a `nil`
    /// store result at the resolver's API surface: both fall back to the
    /// raw handle on every subsequent call within the TTL window, both
    /// cache as a single empty entry, both consume a single store-lookup
    /// call. This is a recurring bug class flagged by the `Present-but-
    /// empty strings` gotcha — pinning the surprising-but-safe behavior
    /// surfaces a future "consistency fix" refactor (e.g. switching the
    /// `?? ""` to `if let resolved = ..., !resolved.isEmpty`) as a
    /// deliberate change rather than silent drift in either direction
    /// (start re-querying every call, or start surfacing empty strings
    /// in the UI). Companion to `testCacheRemembersMissesAsEmpty` which
    /// covers the nil leg.
    func testCacheTreatsEmptyStringResolutionLikeNil() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        // Set the lookup to return Some("") rather than nil — the
        // FakeContactStore's `lookup(handle:)` is `names[handle] ??
        // names[Self.normalize(handle)]`, so seeding either form with ""
        // produces a Some("") return.
        fake.names["+15558887777"] = ""

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        XCTAssertEqual(resolver.name(for: "+15558887777"), "+15558887777",
                       "Some(\"\") store result must fall back to the raw handle, identically to nil")
        XCTAssertEqual(resolver.name(for: "+15558887777"), "+15558887777",
                       "second call must hit cache, not re-query the store")
        XCTAssertEqual(fake.lookupCallCount, 1,
                       "Some(\"\") result must cache as a single empty entry — repeat calls should not retry the store")
    }

    // MARK: - REP-156: fallback contract

    func testNameForHandleFallsBackToHandleWhenNotInStore() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        // No contact entry for this handle.
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let result = resolver.name(for: "+15558880001")
        XCTAssertEqual(result, "+15558880001",
                       "unresolved handle must fall back to the raw handle string, not nil")
    }

    func testNameForHandleReturnsContactNameWhenFound() {
        let fake = FakeContactStore()
        fake.names["alice@example.com"] = "Alice Smith"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let result = resolver.name(for: "alice@example.com")
        XCTAssertEqual(result, "Alice Smith",
                       "resolved handle must return the contact name from the store")
    }

    // MARK: - Access gating

    func testLookupReturnsNilWhenAccessDenied() {
        let fake = FakeContactStore()
        fake.names["+15550000000"] = "should not surface"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.denied)

        XCTAssertNil(resolver.name(for: "+15550000000"))
        XCTAssertEqual(fake.lookupCallCount, 0,
                       "denied access must short-circuit before the store")
    }

    // MARK: - Access state machine

    func testEnsureAccessPromotesFromUnknownToGranted() async {
        let fake = FakeContactStore()
        fake.initialAccess = .unknown
        fake.requestAccessResult = .granted

        let resolver = ContactsResolver(store: fake)
        XCTAssertEqual(resolver.access, .unknown)

        await resolver.ensureAccess()
        XCTAssertEqual(resolver.access, .granted)
        XCTAssertEqual(fake.requestAccessCallCount, 1)
    }

    func testEnsureAccessPromotesFromUnknownToDenied() async {
        let fake = FakeContactStore()
        fake.initialAccess = .unknown
        fake.requestAccessResult = .denied

        let resolver = ContactsResolver(store: fake)
        await resolver.ensureAccess()
        XCTAssertEqual(resolver.access, .denied)
    }

    func testEnsureAccessSkipsRequestIfAlreadyGranted() async {
        let fake = FakeContactStore()
        fake.initialAccess = .granted

        let resolver = ContactsResolver(store: fake)
        await resolver.ensureAccess()
        XCTAssertEqual(resolver.access, .granted)
        XCTAssertEqual(fake.requestAccessCallCount, 0,
                       "already-granted means no prompt — otherwise we'd re-prompt on every launch")
    }

    // MARK: - Thread safety

    func testConcurrentResolutionIsSafe() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        fake.names["5553333333"] = "Theo"  // normalized key

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let queue = DispatchQueue(label: "contacts.test", attributes: .concurrent)
        let group = DispatchGroup()
        let iterations = 200
        let workers = 8

        for _ in 0..<workers {
            group.enter()
            queue.async {
                for _ in 0..<iterations {
                    _ = resolver.name(for: "+15553333333")
                }
                group.leave()
            }
        }
        let done = expectation(description: "concurrent resolutions finish")
        group.notify(queue: .main) { done.fulfill() }
        wait(for: [done], timeout: 15)

        XCTAssertEqual(resolver.name(for: "+15553333333"), "Theo")
        XCTAssertGreaterThanOrEqual(fake.lookupCallCount, 1)
        // Cache should have absorbed the vast majority of the calls; an
        // upper bound of (workers) is enough to catch a regression that
        // loses the cache entirely under concurrency.
        XCTAssertLessThanOrEqual(fake.lookupCallCount, workers,
                                 "cache should have coalesced ~\(workers * iterations) reads into ≤\(workers) store hits")
    }

    // MARK: - REP-037: batch resolution

    func testBatchResultMatchesSerial() {
        let fake = FakeContactStore()
        fake.names["4155550001"] = "Alice"
        fake.names["4155550002"] = "Bob"
        fake.names["4155550003"] = "Carol"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let handles = ["+14155550001", "+14155550002", "+14155550003"]
        let batch = resolver.resolveAll(handles: handles)

        // Batch must agree with individual lookups on every handle.
        for h in handles {
            XCTAssertEqual(batch[h], resolver.name(for: h),
                           "resolveAll result for \(h) must match name(for:)")
        }
    }

    func testBatchCacheHitsSkipStore() {
        let fake = FakeContactStore()
        fake.names["4155550010"] = "Dana"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        // Warm the cache with a serial lookup.
        _ = resolver.name(for: "+14155550010")
        let callsAfterWarm = fake.lookupCallCount

        // Batch of the same handle must not call the store again.
        let result = resolver.resolveAll(handles: ["+14155550010"])
        XCTAssertEqual(result["+14155550010"], "Dana")
        XCTAssertEqual(fake.lookupCallCount, callsAfterWarm,
                       "resolveAll must serve cached handles without a store trip")
    }

    func testBatchMixedHitMiss() {
        let fake = FakeContactStore()
        fake.names["4155550020"] = "Eve"
        fake.names["4155550021"] = "Frank"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        // Pre-cache one of the two handles.
        _ = resolver.name(for: "+14155550020")
        let callsAfterWarm = fake.lookupCallCount  // 1

        let result = resolver.resolveAll(handles: ["+14155550020", "+14155550021"])
        XCTAssertEqual(result["+14155550020"], "Eve", "cached handle must resolve correctly")
        XCTAssertEqual(result["+14155550021"], "Frank", "uncached handle must be fetched from store")
        // Only the miss should have hit the store.
        XCTAssertEqual(fake.lookupCallCount, callsAfterWarm + 1,
                       "exactly one store call for the one cache miss")
    }

    // MARK: - REP-019: E.164 phone normalization

    func testNormalizedHandleStripsPlus() {
        let resolver = ContactsResolver(store: FakeContactStore())
        XCTAssertEqual(resolver.normalizedHandle("+14155551234"), "4155551234")
    }

    func testNormalizedHandleStripsCountryCode() {
        let resolver = ContactsResolver(store: FakeContactStore())
        XCTAssertEqual(resolver.normalizedHandle("14155551234"), "4155551234")
        XCTAssertEqual(resolver.normalizedHandle("+14155551234"), "4155551234")
    }

    func testNormalizedHandlePreservesEmail() {
        let resolver = ContactsResolver(store: FakeContactStore())
        let email = "user@example.com"
        XCTAssertEqual(resolver.normalizedHandle(email), email)
    }

    func testAlternateFormsHitSameCache() {
        let fake = FakeContactStore()
        fake.names["4155551234"] = "Bob"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let r1 = resolver.name(for: "+14155551234")
        let r2 = resolver.name(for: "14155551234")
        let r3 = resolver.name(for: "4155551234")

        XCTAssertEqual(r1, "Bob")
        XCTAssertEqual(r2, "Bob")
        XCTAssertEqual(r3, "Bob")
        XCTAssertEqual(fake.lookupCallCount, 1,
                       "all three variants should collapse to one store lookup")
    }

    // MARK: - REP-074: per-handle cache TTL

    func testFreshCacheHitSkipsStore() {
        // With a long TTL (1 hour), a warm entry should never re-query the store.
        let fake = FakeContactStore()
        fake.names["4155559001"] = "Grace"
        let resolver = ContactsResolver(store: fake, ttl: 3600)
        resolver.overrideAccessForTesting(.granted)

        _ = resolver.name(for: "+14155559001")  // populates cache
        let countAfterWarm = fake.lookupCallCount

        _ = resolver.name(for: "+14155559001")  // should hit fresh cache
        _ = resolver.name(for: "+14155559001")
        XCTAssertEqual(fake.lookupCallCount, countAfterWarm,
                       "fresh cache entry must not trigger a store re-query")
    }

    func testStaleEntryTriggersFetch() {
        // With a zero TTL, every lookup is treated as stale and re-queries the store.
        let fake = FakeContactStore()
        fake.names["4155559002"] = "Hank"
        let resolver = ContactsResolver(store: fake, ttl: 0)
        resolver.overrideAccessForTesting(.granted)

        _ = resolver.name(for: "+14155559002")
        _ = resolver.name(for: "+14155559002")
        XCTAssertEqual(fake.lookupCallCount, 2,
                       "ttl=0 must re-query the store on every call")
    }

    func testZeroTTLAlwaysFetches() {
        // Variant of the above using resolveAll to exercise the batch path.
        let fake = FakeContactStore()
        fake.names["4155559003"] = "Iris"
        let resolver = ContactsResolver(store: fake, ttl: 0)
        resolver.overrideAccessForTesting(.granted)

        _ = resolver.resolveAll(handles: ["+14155559003"])
        _ = resolver.resolveAll(handles: ["+14155559003"])
        XCTAssertEqual(fake.lookupCallCount, 2,
                       "resolveAll with ttl=0 must bypass cache on every call")
    }

    // MARK: - CNContactStoreDidChange flush (REP-108)

    func testContactStoreChangeFlushesCache() {
        let fake = FakeContactStore()
        fake.names["4155559010"] = "Jane"
        // Use an isolated NotificationCenter so the test never touches the
        // global center or triggers real Contacts notifications.
        let center = NotificationCenter()
        let resolver = ContactsResolver(store: fake, ttl: 1800, notificationCenter: center)
        resolver.overrideAccessForTesting(.granted)

        // Warm the cache with one lookup.
        let first = resolver.name(for: "+14155559010")
        XCTAssertEqual(first, "Jane")
        XCTAssertEqual(fake.lookupCallCount, 1, "first call must hit the store")

        // Post the change notification — cache should be flushed.
        center.post(name: NSNotification.Name.CNContactStoreDidChange, object: nil)

        // Second lookup must re-query the store, not return from cache.
        _ = resolver.name(for: "+14155559010")
        XCTAssertEqual(fake.lookupCallCount, 2,
                       "cache flush on CNContactStoreDidChange must force a re-query")
    }

    func testFlushDoesNotCrashOnEmptyCache() {
        let fake = FakeContactStore()
        let center = NotificationCenter()
        let resolver = ContactsResolver(store: fake, ttl: 1800, notificationCenter: center)
        // Post the notification before any lookup has populated the cache.
        XCTAssertNoThrow(
            center.post(name: NSNotification.Name.CNContactStoreDidChange, object: nil),
            "flush on empty cache must not crash"
        )
        _ = resolver  // keep alive through the test
    }

    // MARK: - REP-141: batchResolve result contract

    func testBatchResolveResultKeySetMatchesInputHandles() {
        let fake = FakeContactStore()
        fake.names["4155550100"] = "Alice"
        fake.names["4155550102"] = "Charlie"
        // bob (4155550101) is not resolvable — will be absent from result.
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let handles = ["+14155550100", "+14155550101", "+14155550102"]
        let result = resolver.resolveAll(handles: handles)

        XCTAssertEqual(result["+14155550100"], "Alice",
                       "resolvable alice handle must appear in result")
        XCTAssertEqual(result["+14155550102"], "Charlie",
                       "resolvable charlie handle must appear in result")
        // bob is unresolvable — subscript returns nil for absent key.
        XCTAssertNil(result["+14155550101"],
                     "unresolvable handle must return nil via subscript")
    }

    func testBatchResolveUnresolvableHandleAbsentOrNil() {
        let fake = FakeContactStore()
        fake.names["4155550200"] = "Alice"
        // bob is not in the store.
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        let result = resolver.resolveAll(handles: ["+14155550200", "+14155550201"])

        XCTAssertEqual(result["+14155550200"], "Alice",
                       "resolvable handle must map to the contact name")
        // Unresolvable handle is either absent or nil when accessed via subscript.
        XCTAssertNil(result["+14155550201"],
                     "unresolvable handle must not appear as a non-nil value in result")
    }

    func testBatchResolveCacheHitsDoNotInvokeStore() {
        let fake = FakeContactStore()
        fake.names["4155550300"] = "Dave"
        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        // Warm the cache.
        _ = resolver.name(for: "+14155550300")
        let callsAfterWarm = fake.lookupCallCount

        // Batch of the already-cached handle must not call the store again.
        _ = resolver.resolveAll(handles: ["+14155550300"])
        XCTAssertEqual(fake.lookupCallCount, callsAfterWarm,
                       "cached handles must not trigger additional store lookups")
    }

    // MARK: - REP-185: TTL cache invalidation contract

    func testExpiredTTLForcesRefetch() {
        // ttl=0 expires every entry immediately — two calls must each hit the store.
        let fake = FakeContactStore()
        fake.names["4155550185"] = "Paula"
        let resolver = ContactsResolver(store: fake, ttl: 0)
        resolver.overrideAccessForTesting(.granted)

        _ = resolver.name(for: "+14155550185")
        let afterFirst = fake.lookupCallCount
        _ = resolver.name(for: "+14155550185")

        XCTAssertEqual(fake.lookupCallCount, afterFirst + 1,
                       "ttl=0 must re-query the store on the second call (cache expired)")
    }

    func testActiveTTLUsesCache() {
        // ttl=9999 keeps entry fresh — two calls must hit the store only once.
        let fake = FakeContactStore()
        fake.names["4155550186"] = "Quinn"
        let resolver = ContactsResolver(store: fake, ttl: 9999)
        resolver.overrideAccessForTesting(.granted)

        _ = resolver.name(for: "+14155550186")
        let afterFirst = fake.lookupCallCount
        _ = resolver.name(for: "+14155550186")

        XCTAssertEqual(fake.lookupCallCount, afterFirst,
                       "ttl=9999 must not re-query the store on the second call (cache still valid)")
    }

    func testConcurrentSameHandleResolvesConsistently() {
        let fake = FakeContactStore()
        fake.names["8005559249"] = "Concurrent Alice"
        let resolver = ContactsResolver(store: fake, ttl: 3600)
        resolver.overrideAccessForTesting(.granted)

        let results = Locked([String?]())
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let name = resolver.name(for: "+18005559249")
            results.withLock { $0.append(name) }
        }

        let all = results.withLock { $0 }
        XCTAssertEqual(all.count, 10)
        XCTAssertTrue(all.allSatisfy { $0 == "Concurrent Alice" })
    }

    func testConcurrentSameHandleUsesWarmCache() {
        let fake = FakeContactStore()
        fake.names["8005559249"] = "Concurrent Alice"
        let resolver = ContactsResolver(store: fake, ttl: 3600)
        resolver.overrideAccessForTesting(.granted)

        XCTAssertEqual(resolver.name(for: "+18005559249"), "Concurrent Alice")
        let callsAfterWarmup = fake.lookupCallCount

        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            _ = resolver.name(for: "+18005559249")
        }

        XCTAssertEqual(fake.lookupCallCount, callsAfterWarmup,
                       "warm cache must serve concurrent same-handle reads without extra store hits")
    }

    /// Pin the default TTL to 1800s (30 min). Every existing test passes
    /// `ttl: 1800` explicitly, so a regression that flipped the default
    /// (e.g. to 60s for "fresher" results, or to 0 for "always re-query")
    /// would not be caught by any test — the explicit-init path always
    /// takes the test value. Pin the no-arg default so production behavior
    /// (the value users actually run with) stays under test.
    func testContactsResolverDefaultTTLIs1800Seconds() {
        let resolver = ContactsResolver(store: FakeContactStore())
        XCTAssertEqual(resolver.ttl, 1800,
            "default TTL must remain 1800s (30 min) — drift to 0 produces a thundering herd of CNContactStore queries; drift to a much larger value silently delays new-contact resolution")
    }
}

// MARK: - Test double

/// Deterministic `ContactsStoring` used by the resolver tests.
/// Thread-safe so the concurrency test doesn't race its own counters.
private final class FakeContactStore: ContactsStoring, @unchecked Sendable {
    private let lock = NSLock()
    var names: [String: String] = [:]
    var initialAccess: ContactsResolver.Access = .unknown
    var requestAccessResult: ContactsResolver.Access = .granted

    private var _lookupCallCount = 0
    private var _requestAccessCallCount = 0

    var lookupCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _lookupCallCount
    }
    var requestAccessCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requestAccessCallCount
    }

    func prepopulate(initialAccess: ContactsResolver.Access) {
        self.initialAccess = initialAccess
    }

    func currentAccess() -> ContactsResolver.Access {
        initialAccess
    }

    func requestAccess() async -> ContactsResolver.Access {
        lock.lock(); _requestAccessCallCount += 1; lock.unlock()
        return requestAccessResult
    }

    func lookup(handle: String) -> String? {
        lock.lock(); _lookupCallCount += 1; lock.unlock()
        // Mirror CNContactStoreBackedStoring's digit-keyed index: callers
        // populate `names` with either the original handle (e.g. an email)
        // or the 10-digit canonical form. The resolver passes the original
        // handle here (so CNPhoneNumber matching works in production), so
        // we have to normalise on the lookup side to find that canonical
        // entry.
        if let direct = names[handle] { return direct }
        return names[Self.normalize(handle)]
    }

    private static func normalize(_ handle: String) -> String {
        guard !handle.contains("@"), !handle.hasPrefix("chat") else { return handle }
        let digits = handle.filter(\.isNumber)
        guard digits.count >= 10 else { return handle }
        if digits.count == 11 && digits.hasPrefix("1") { return String(digits.dropFirst()) }
        return digits.count == 10 ? digits : handle
    }
}
