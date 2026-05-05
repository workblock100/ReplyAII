import XCTest
@testable import ReplyAI

final class LockedTests: XCTestCase {

    // MARK: - Initial value

    func testInitialValue() {
        let locked = Locked<Int>(42)
        let value = locked.withLock { $0 }
        XCTAssertEqual(value, 42)
    }

    // MARK: - Mutation

    func testWithLockMutatesValue() {
        let locked = Locked<Int>(0)
        locked.withLock { $0 += 1 }
        locked.withLock { $0 += 1 }
        let result = locked.withLock { $0 }
        XCTAssertEqual(result, 2)
    }

    func testWithLockReturnsResult() {
        let locked = Locked<String>("hello")
        let count = locked.withLock { $0.count }
        XCTAssertEqual(count, 5)
    }

    // MARK: - Rethrowing

    struct TestError: Error {}

    func testWithLockRethrows() {
        let locked = Locked<Int>(0)
        XCTAssertThrowsError(
            try locked.withLock { _ in throw TestError() }
        ) { error in
            XCTAssertTrue(error is TestError)
        }
    }

    func testWithLockDoesNotRethrowOnSuccess() throws {
        let locked = Locked<Int>(7)
        let result = try locked.withLock { v -> Int in
            if v < 0 { throw TestError() }
            return v * 2
        }
        XCTAssertEqual(result, 14)
    }

    // MARK: - Concurrency stress test

    func testConcurrentReadWriteIsThreadSafe() {
        let locked = Locked<Int>(0)
        let iterations = 1000

        // All increments happen under the lock — final value must be exact.
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            locked.withLock { $0 += 1 }
        }

        let final = locked.withLock { $0 }
        XCTAssertEqual(final, iterations, "Expected \(iterations) but got \(final) — data race detected")
    }

    func testConcurrentReadsAndWritesDoNotCorruptDictionary() {
        let locked = Locked<[String: Int]>([:])
        let keys = (0..<20).map { "key\($0)" }

        DispatchQueue.concurrentPerform(iterations: 200) { i in
            let key = keys[i % keys.count]
            locked.withLock { $0[key, default: 0] += 1 }
        }

        let snapshot = locked.withLock { $0 }
        let total = snapshot.values.reduce(0, +)
        XCTAssertEqual(total, 200, "Counter sum should be 200 regardless of key distribution")
    }

    // MARK: - Value semantics wrapper

    func testLockedCanBeStoredAsLet() {
        // The struct wraps a class internally, so let storage still permits withLock mutations.
        let locked = Locked<[Int]>([])
        locked.withLock { $0.append(1) }
        locked.withLock { $0.append(2) }
        let result = locked.withLock { $0 }
        XCTAssertEqual(result, [1, 2])
    }

    // MARK: - Defensive paths

    /// Compound read-modify-write under one lock acquisition must be
    /// atomic — split into two acquisitions a concurrent writer could
    /// interleave between the read and the write. This is the core
    /// reason call sites use `withLock { state in ... }` instead of
    /// pairing `withLock { _ in v }` + `withLock { $0 = v + 1 }`.
    func testCompoundReadModifyWriteIsAtomicUnderConcurrency() {
        let locked = Locked<Int>(0)
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            locked.withLock { state in
                let current = state
                // Simulated work between read and write — under a non-atomic
                // strategy the next concurrent call could observe `current`
                // and overwrite our result.
                state = current + 1
            }
        }
        XCTAssertEqual(locked.withLock { $0 }, 1_000,
            "single-acquisition compound mutation must remain atomic")
    }

    /// Two independent Locked instances must not share state. The class
    /// box backing the struct is per-init, so each Locked has its own
    /// NSLock and value. A regression that accidentally interns the box
    /// would silently coalesce unrelated lock domains.
    func testTwoLockedInstancesAreIndependent() {
        let a = Locked<Int>(1)
        let b = Locked<Int>(100)
        a.withLock { $0 = 2 }
        XCTAssertEqual(a.withLock { $0 }, 2)
        XCTAssertEqual(b.withLock { $0 }, 100,
            "instance B must keep its initial value while A mutates")
    }

    /// Reference-type payloads are mutated in place (the struct holds an
    /// inout reference to the class instance, which has reference
    /// semantics). Asserts the caller can mutate methods on the wrapped
    /// reference and observe the change without reassignment.
    func testReferenceTypePayloadCanBeMutatedThroughInout() {
        final class Counter { var value: Int = 0 }
        let locked = Locked<Counter>(Counter())
        locked.withLock { $0.value += 5 }
        locked.withLock { $0.value += 3 }
        XCTAssertEqual(locked.withLock { $0.value }, 8,
            "reference-type payload must accumulate mutations across acquisitions")
    }

    /// After an acquisition closure throws, the lock must release cleanly
    /// so a follow-up withLock can acquire it. The `defer { unlock }` in
    /// the implementation is the only path between throw and a subsequent
    /// caller — a regression to unlock-then-throw would deadlock the
    /// next acquisition.
    func testRethrowReleasesLockForSubsequentAcquisition() {
        let locked = Locked<Int>(10)
        do {
            try locked.withLock { _ in throw TestError() }
            XCTFail("expected throw")
        } catch is TestError {
            // expected
        } catch {
            XCTFail("expected TestError, got \(error)")
        }
        // The lock must be free now — this acquisition would deadlock
        // (and time-out the test) if the throw path didn't release it.
        let value = locked.withLock { $0 }
        XCTAssertEqual(value, 10,
            "lock must be released after a thrown closure so subsequent acquisitions succeed")
    }
}
