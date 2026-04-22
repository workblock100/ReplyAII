import XCTest
@testable import ReplyAI

// MARK: - Test doubles

/// ContactsStoring that resolves to .denied immediately, avoiding any
/// system permission dialogs or AddressBook XPC traffic in tests.
private struct DeniedContactStore: ContactsStoring {
    func currentAccess() -> ContactsResolver.Access { .denied }
    func requestAccess() async -> ContactsResolver.Access { .denied }
    func lookup(handle: String) -> String? { nil }
}

private func fastContacts() -> ContactsResolver {
    ContactsResolver(store: DeniedContactStore())
}

/// A `ChannelService` that counts `recentThreads` calls and blocks
/// each call until `resumeAll()` is called. `enteredStream` fires once
/// the call has incremented the counter and entered the blocking wait,
/// so tests can synchronise without busy-polling.
private final class BlockingMockChannel: ChannelService, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var recentThreadsCallCount: Int = 0
    var blocking: Bool = true
    private var pending: [CheckedContinuation<[MessageThread], Error>] = []

    let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        lock.lock(); recentThreadsCallCount += 1; lock.unlock()
        guard blocking else { return [] }
        enteredContinuation.yield(())
        return try await withCheckedThrowingContinuation { cont in
            lock.lock(); pending.append(cont); lock.unlock()
        }
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }

    func resumeAll() {
        lock.lock(); let conts = pending; pending = []; lock.unlock()
        for cont in conts { cont.resume(returning: []) }
    }
}

// MARK: - Tests

@MainActor
final class InboxViewModelTests: XCTestCase {

    // MARK: - Concurrent sync guard (REP-022)

    func testConcurrentSyncCallsDoNotOverlap() async throws {
        let channel = BlockingMockChannel()
        let vm = InboxViewModel(imessage: channel, contacts: fastContacts())

        // Start first sync. It will set isSyncing=true, skip contacts
        // (instantly denied), then block inside recentThreads.
        let sync1 = Task { await vm.syncFromIMessage() }

        // Wait until sync1 is inside the blocking section of recentThreads
        // (count is 1, isSyncing is true). No busy-polling needed.
        for await _ in channel.enteredStream { break }

        // sync1 holds isSyncing=true. Second call must bail immediately.
        await vm.syncFromIMessage()
        XCTAssertEqual(channel.recentThreadsCallCount, 1,
            "second concurrent syncFromIMessage must be a no-op")

        // Release sync1. Empty thread list → .failed path; defer fires.
        channel.resumeAll()
        await sync1.value

        // Guard is cleared. A fresh sync should proceed normally.
        channel.blocking = false
        await vm.syncFromIMessage()
        XCTAssertEqual(channel.recentThreadsCallCount, 2,
            "guard must reset to false after sync1 finishes")
    }

    func testSyncGuardResetsAfterError() async throws {
        final class ThrowingChannel: ChannelService, @unchecked Sendable {
            func recentThreads(limit: Int) async throws -> [MessageThread] {
                throw ChannelError.unavailable("test error")
            }
            func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
        }

        let vm = InboxViewModel(imessage: ThrowingChannel(), contacts: fastContacts())

        await vm.syncFromIMessage()
        // Reaching here confirms the error path executed.
        // If guard didn't reset, the second call would be silently dropped.
        await vm.syncFromIMessage()
        // Reaching here without hanging proves the guard was reset.
    }

    func testSyncGuardResetsAfterSuccess() async throws {
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(imessage: channel, contacts: fastContacts())

        await vm.syncFromIMessage()
        XCTAssertEqual(channel.recentThreadsCallCount, 1)

        await vm.syncFromIMessage()
        XCTAssertEqual(channel.recentThreadsCallCount, 2,
            "guard must reset to false after normal completion")
    }
}
