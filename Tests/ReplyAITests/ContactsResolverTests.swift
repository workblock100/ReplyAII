import XCTest
@testable import ReplyAI

final class ContactsResolverTests: XCTestCase {

    // MARK: - Cache

    func testCacheMissQueriesStore() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        fake.names["+15551111111"] = "Maya Lee"

        let resolver = ContactsResolver(store: fake)
        resolver.overrideAccessForTesting(.granted)

        XCTAssertEqual(resolver.name(for: "+15551111111"), "Maya Lee")
        XCTAssertEqual(fake.lookupCallCount, 1)
    }

    func testCacheHitSkipsStoreCall() {
        let fake = FakeContactStore()
        fake.prepopulate(initialAccess: .granted)
        fake.names["+15552222222"] = "Ravi Patel"

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
        fake.names["+15553333333"] = "Theo"

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

