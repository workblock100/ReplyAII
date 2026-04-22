import XCTest
@testable import ReplyAI

final class ContactsResolverTests: XCTestCase {

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
        // no name mapping → lookup returns nil

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        XCTAssertNil(resolver.name(for: "+15559999999"))
        XCTAssertNil(resolver.name(for: "+15559999999"))
        XCTAssertEqual(fake.lookupCallCount, 1,
                       "repeat lookup of an unknown handle should not keep hitting the store")
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
        return names[handle]
    }
}

