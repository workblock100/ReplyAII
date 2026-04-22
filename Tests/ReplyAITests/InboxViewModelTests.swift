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

// MARK: - Rule re-evaluation when RulesStore changes (REP-023)

@MainActor
final class InboxViewModelRuleObservationTests: XCTestCase {

    private func tempRulesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMTests-\(UUID())/rules.json")
    }

    /// Adding a pin rule while threads are loaded must immediately pin the
    /// matching thread — no re-select or watcher refire required.
    func testRuleAdditionTriggersReEvaluation() async throws {
        let rulesURL = tempRulesURL()
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rules = RulesStore(fileURL: rulesURL)
        // Start with no rules so the initial observation baseline is clean.
        rules.resetToSeeds()
        rules.rules.forEach { rules.remove($0.id) }

        let thread = MessageThread(
            id: "t1", channel: .imessage, name: "Alice Smith",
            avatar: "A", preview: "hey", time: "12:00", unread: 1, pinned: false)
        let noopChannel = BlockingMockChannel()
        noopChannel.blocking = false
        let vm = InboxViewModel(
            threads: [thread], imessage: noopChannel,
            contacts: fastContacts(), rules: rules)
        vm.selectedThreadID = "t1"

        XCTAssertFalse(vm.threads.first!.pinned, "pre-condition: thread starts unpinned")

        let pinRule = SmartRule(name: "pin alice", when: .senderIs("Alice Smith"), then: .pin)
        rules.add(pinRule)

        // onChange fires on the next run-loop iteration; two yields are
        // sufficient for the Task to dispatch and complete on @MainActor.
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(vm.threads.first?.pinned ?? false,
            "adding a matching pin rule must pin the thread without re-select")
    }

    /// Updating an existing rule (e.g. activating a previously disabled pin
    /// rule) must also trigger re-evaluation and pin the matching thread.
    func testRuleChangeUpdatesPinnedThreads() async throws {
        let rulesURL = tempRulesURL()
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rules = RulesStore(fileURL: rulesURL)
        rules.resetToSeeds()
        rules.rules.forEach { rules.remove($0.id) }

        let thread = MessageThread(
            id: "t2", channel: .imessage, name: "Bob Jones",
            avatar: "B", preview: "hello", time: "12:01", unread: 0, pinned: false)
        let noopChannel = BlockingMockChannel()
        noopChannel.blocking = false
        let vm = InboxViewModel(
            threads: [thread], imessage: noopChannel,
            contacts: fastContacts(), rules: rules)
        vm.selectedThreadID = "t2"

        // Add the rule in a disabled state — should NOT pin yet.
        let disabledRule = SmartRule(
            name: "pin bob", when: .senderIs("Bob Jones"), then: .pin, active: false)
        rules.add(disabledRule)
        await Task.yield()
        await Task.yield()
        XCTAssertFalse(vm.threads.first!.pinned, "disabled rule must not pin")

        // Enable the rule — re-evaluation fires, thread should be pinned.
        rules.toggle(disabledRule.id)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(vm.threads.first?.pinned ?? false,
            "enabling a pin rule must immediately pin the matching thread")
    }
}
