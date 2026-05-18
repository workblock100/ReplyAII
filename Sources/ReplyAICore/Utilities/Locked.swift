import Foundation

/// Thread-safe value box. Replaces the repeated `NSLock + synced { }` pattern
/// used across `ContactsResolver`, `Stats`, and similar non-actor types that
/// must be callable from any thread without actor bridging overhead.
///
/// Using a class-backed struct lets callers store `let locked: Locked<T>`
/// while still supporting in-place mutation through `withLock`.
struct Locked<T>: @unchecked Sendable {
    private final class _Box: @unchecked Sendable {
        let lock = NSLock()
        var value: T
        init(_ value: T) { self.value = value }
    }

    private let box: _Box

    init(_ value: T) {
        box = _Box(value)
    }

    /// Read or mutate the wrapped value under the lock. The closure receives
    /// an `inout` reference so callers can perform compound mutations atomically.
    /// Never call `withLock` again from inside the closure — NSLock is not
    /// re-entrant and will deadlock.
    @discardableResult
    func withLock<U>(_ body: (inout T) throws -> U) rethrows -> U {
        box.lock.lock()
        defer { box.lock.unlock() }
        return try body(&box.value)
    }
}
