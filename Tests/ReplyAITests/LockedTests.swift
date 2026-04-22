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
}
