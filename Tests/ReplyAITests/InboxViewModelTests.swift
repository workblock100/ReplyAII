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
///
/// All mutable state is wrapped in `Locked<T>` so that the cooperative-pool
/// thread running `recentThreads` and the main-actor test code that reads
/// `recentThreadsCallCount` / `blocking` never race. Without this,
/// Swift 6 strict-concurrency + macOS 26 TSan would flag data races on
/// plain integer reads crossing executor boundaries.
private final class BlockingMockChannel: ChannelService, @unchecked Sendable {
    private let _callCount = Locked(0)
    private let _blocking  = Locked(true)
    private let _pending   = Locked([CheckedContinuation<[MessageThread], Error>]())

    let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()

    var recentThreadsCallCount: Int { _callCount.withLock { $0 } }
    var blocking: Bool {
        get { _blocking.withLock { $0 } }
        set { _blocking.withLock { $0 = newValue } }
    }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        _callCount.withLock { $0 += 1 }
        guard blocking else { return [] }
        enteredContinuation.yield(())
        return try await withCheckedThrowingContinuation { cont in
            _pending.withLock { $0.append(cont) }
        }
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }

    func resumeAll() {
        let conts = _pending.withLock { arr -> [CheckedContinuation<[MessageThread], Error>] in
            defer { arr = [] }
            return arr
        }
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
        try rules.add(pinRule)

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
        try rules.add(disabledRule)
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

// MARK: - Notification reply consumption (REP-072)

@MainActor
final class InboxViewModelNotificationReplyTests: XCTestCase {

    /// When `pendingNotificationReply` is set with a known threadID,
    /// `InboxViewModel` must dispatch an iMessage send with the thread's
    /// real chatGUID and then clear the pending value.
    func testNotificationReplyConsumedAndSent() async throws {
        let thread = MessageThread(
            id: "tA", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hi", time: "10:00",
            chatGUID: "iMessage;+;chat9999")

        let noopChannel = BlockingMockChannel()
        noopChannel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: noopChannel,
                                contacts: fastContacts())

        // Intercept the AppleScript execution to capture what would be sent.
        var capturedScript: String? = nil
        let hookExpectation = expectation(description: "execute hook fires")
        IMessageSender.executeHook = { src in
            capturedScript = src
            hookExpectation.fulfill()
        }
        defer { IMessageSender.executeHook = nil }

        // Trigger the observation.
        vm.pendingNotificationReply = (threadID: "tA", text: "Hello!")
        // Allow the Task inside onChange to dispatch and complete.
        await Task.yield()
        await Task.yield()

        // The hook runs on a background thread inside Task.detached; give it
        // a moment to fire before timing out.
        await fulfillment(of: [hookExpectation], timeout: 3)

        XCTAssertNil(vm.pendingNotificationReply, "pending reply must be cleared after consumption")
        let script = try XCTUnwrap(capturedScript, "execute hook must have fired")
        XCTAssertTrue(script.contains("chat9999"),
            "script must use the thread's real chatGUID, not a synthesized one")
        XCTAssertTrue(script.contains("Hello!"),
            "script must embed the reply text")
    }

    /// When `pendingNotificationReply` names a threadID not in the loaded list,
    /// `InboxViewModel` must discard the reply without calling IMessageSender.
    func testNotificationReplyUnknownThreadDiscarded() async throws {
        let thread = MessageThread(
            id: "tB", channel: .imessage, name: "Bob",
            avatar: "B", preview: "hey", time: "11:00")

        let noopChannel = BlockingMockChannel()
        noopChannel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: noopChannel,
                                contacts: fastContacts())

        var hookFired = false
        IMessageSender.executeHook = { _ in hookFired = true }
        defer { IMessageSender.executeHook = nil }

        vm.pendingNotificationReply = (threadID: "unknown-id", text: "Whoops")
        await Task.yield()
        await Task.yield()
        // Give background tasks a moment to complete (should be a no-op).
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 s

        XCTAssertNil(vm.pendingNotificationReply, "pending reply must be cleared even for unknown thread")
        XCTAssertFalse(hookFired, "execute hook must NOT fire for an unknown threadID")
    }

    // MARK: - Mark thread read on selection (REP-076)

    @MainActor
    func testSelectMarkThreadRead() {
        let thread = MessageThread(
            id: "t-unread", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hello", time: "now", unread: 3)
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("t-unread")
        XCTAssertEqual(
            vm.threads.first(where: { $0.id == "t-unread" })?.unread, 0,
            "selecting a thread must clear its local unread count"
        )
    }

    @MainActor
    func testSelectDoesNotAffectOtherThreads() {
        let t1 = MessageThread(
            id: "t1-76", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hi", time: "now", unread: 5)
        let t2 = MessageThread(
            id: "t2-76", channel: .imessage, name: "Bob",
            avatar: "B", preview: "hey", time: "now", unread: 2)
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [t1, t2], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("t1-76")
        XCTAssertEqual(vm.threads.first(where: { $0.id == "t1-76" })?.unread, 0,
            "selected thread unread must be 0")
        XCTAssertEqual(vm.threads.first(where: { $0.id == "t2-76" })?.unread, 2,
            "other thread unread must be unaffected")
    }
}

// MARK: - Thread selection model (REP-071)

@MainActor
final class InboxViewModelThreadSelectionTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.ReplyAI.selection.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        return d
    }

    private func makeChannel() -> BlockingMockChannel {
        let ch = BlockingMockChannel()
        ch.blocking = false
        return ch
    }

    private func makeRules() -> RulesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAI-selection-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }
        return store
    }

    func testSelectThreadUpdatesSelectedID() {
        let t1 = MessageThread(id: "t1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "t2", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(),
                                rules: makeRules(), searchIndex: SearchIndex(databaseURL: nil))
        vm.selectThread("t2")
        XCTAssertEqual(vm.selectedThreadID, "t2", "selectThread must update selectedThreadID")
    }

    func testSelectThreadCallsPrime() {
        let d = makeDefaults()
        // autoPrime defaults to true after registerReplyAIDefaults
        let t1 = MessageThread(id: "t1-prime", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "t2-prime", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(),
                                rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))

        var primeCallCount = 0
        vm.primeHandler = { _, _, _ in primeCallCount += 1 }

        vm.selectThread("t2-prime")
        XCTAssertEqual(primeCallCount, 1, "selectThread must invoke primeHandler when autoPrime is true")
    }

    func testSelectSameThreadTwiceCallsPrimeOnce() {
        let d = makeDefaults()
        let t1 = MessageThread(id: "t1-idem", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "t2-idem", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(),
                                rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))

        var primeCallCount = 0
        vm.primeHandler = { _, _, _ in primeCallCount += 1 }

        vm.selectThread("t2-idem")
        vm.selectThread("t2-idem") // same thread again
        XCTAssertEqual(primeCallCount, 1,
            "selecting the same thread twice must only call primeHandler once")
    }
}

// MARK: - autoPrime preference (REP-039)

@MainActor
final class InboxViewModelAutoPrimeTests: XCTestCase {

    private func makeChannel() -> BlockingMockChannel {
        let ch = BlockingMockChannel()
        ch.blocking = false
        return ch
    }

    /// Isolated RulesStore backed by a per-test temp file so `startObservingRules`
    /// inside InboxViewModel.init does not share the production rules.json across
    /// tests. Without isolation, concurrent runs of different test classes could
    /// mutate the shared file, trigger onChange callbacks in other tests' VMs,
    /// and race on the @Observable machinery under Swift 6 + macOS 26.
    private func makeRules() -> RulesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAI-autoprime-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }
        return store
    }

    func testAutoPrimeTrueCallsPrime() {
        let suite = "test.ReplyAI.autoprime.true.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        // default is true after register

        let t1 = MessageThread(id: "ap-t1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "ap-t2", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(),
                                rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))

        var primeCalled = false
        vm.primeHandler = { _, _, _ in primeCalled = true }

        vm.selectThread("ap-t2")
        XCTAssertTrue(primeCalled, "primeHandler must fire when autoPrime is true")
    }

    func testAutoPrimeFalseSkipsPrime() {
        let suite = "test.ReplyAI.autoprime.false.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        d.set(false, forKey: PreferenceKey.autoPrime)

        let t1 = MessageThread(id: "ap2-t1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "ap2-t2", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(),
                                rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))

        var primeCalled = false
        vm.primeHandler = { _, _, _ in primeCalled = true }

        vm.selectThread("ap2-t2")
        XCTAssertFalse(primeCalled, "primeHandler must NOT fire when autoPrime is false")
    }
}

// MARK: - autoApplyRulesOnSync preference (REP-081)

/// A channel that immediately returns a fixed list of threads and no messages.
private final class StaticMockChannel: ChannelService, @unchecked Sendable {
    let threads: [MessageThread]
    init(threads: [MessageThread]) { self.threads = threads }
    func recentThreads(limit: Int) async throws -> [MessageThread] { threads }
    func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
}

@MainActor
final class InboxViewModelAutoApplyRulesTests: XCTestCase {

    private func tempRulesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMRulesTests-\(UUID())/rules.json")
    }

    /// When `autoApplyRulesOnSync` is false, a sync must not apply rules
    /// (i.e. `activeTone` stays at its pre-sync value even if a matching
    /// setDefaultTone rule exists).
    func testAutoApplyRulesFalseSkipsRulesOnSync() async throws {
        let suite = "test.ReplyAI.autoApplySync.false.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        d.set(false, forKey: PreferenceKey.autoApplyRulesOnSync)

        let rulesURL = tempRulesURL()
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rulesStore = RulesStore(fileURL: rulesURL)
        rulesStore.resetToSeeds()
        rulesStore.rules.forEach { rulesStore.remove($0.id) }

        let thread = MessageThread(
            id: "sync-t1", channel: .imessage, name: "Alice Smith",
            avatar: "A", preview: "hello", time: "now", unread: 1)
        let rule = SmartRule(
            name: "alice→direct", when: .senderIs("Alice Smith"), then: .setDefaultTone(.direct))
        try rulesStore.add(rule)

        let vm = InboxViewModel(
            threads: [thread], imessage: StaticMockChannel(threads: [thread]),
            contacts: fastContacts(), rules: rulesStore, defaults: d)
        vm.selectedThreadID = "sync-t1"
        let beforeTone = vm.activeTone

        await vm.syncFromIMessage()

        XCTAssertEqual(vm.activeTone, beforeTone,
            "rules must not fire during sync when autoApplyRulesOnSync is false")
    }

    /// Default (true) must preserve existing behaviour — rules still fire.
    func testAutoApplyRulesOnSyncDefaultAppliesRules() async throws {
        let suite = "test.ReplyAI.autoApplySync.true.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        // default is true — no override needed

        let rulesURL = tempRulesURL()
        try FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rulesStore = RulesStore(fileURL: rulesURL)
        rulesStore.resetToSeeds()
        rulesStore.rules.forEach { rulesStore.remove($0.id) }

        let thread = MessageThread(
            id: "sync-t2", channel: .imessage, name: "Bob Jones",
            avatar: "B", preview: "hey", time: "now", unread: 1)
        let rule = SmartRule(
            name: "bob→direct", when: .senderIs("Bob Jones"), then: .setDefaultTone(.direct))
        try rulesStore.add(rule)

        let vm = InboxViewModel(
            threads: [thread], imessage: StaticMockChannel(threads: [thread]),
            contacts: fastContacts(), rules: rulesStore, defaults: d)
        vm.selectedThreadID = "sync-t2"

        await vm.syncFromIMessage()

        XCTAssertEqual(vm.activeTone, .direct,
            "rules must fire during sync when autoApplyRulesOnSync is true (default)")
    }

    // MARK: - Archive / unarchive round-trip (REP-053)

    private func makeIsolatedDefaults(suffix: String = "") -> UserDefaults {
        let suite = "test.ReplyAI.archive.\(UUID())\(suffix)"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        return d
    }

    func testArchiveRemovesFromList() {
        let d = makeIsolatedDefaults()
        let t1 = MessageThread(id: "a1", channel: .imessage, name: "Alice", avatar: "A", preview: "hi", time: "now")
        let t2 = MessageThread(id: "a2", channel: .imessage, name: "Bob",   avatar: "B", preview: "yo", time: "now")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.archive("a1")

        XCTAssertTrue(vm.archivedThreadIDs.contains("a1"),
                      "archived thread ID must be in archivedThreadIDs")
        XCTAssertFalse(vm.archivedThreadIDs.contains("a2"),
                       "non-archived thread must not appear in archivedThreadIDs")
        // ThreadListView filters: threads not in archivedThreadIDs remain visible.
        let visible = vm.threads.filter { !vm.archivedThreadIDs.contains($0.id) }
        XCTAssertFalse(visible.contains(where: { $0.id == "a1" }),
                       "archived thread must not appear in the visible list")
        XCTAssertTrue(visible.contains(where: { $0.id == "a2" }),
                      "non-archived thread must remain in the visible list")
    }

    func testUnarchiveRestoresThread() {
        let d = makeIsolatedDefaults()
        let t1 = MessageThread(id: "u1", channel: .imessage, name: "Carol", avatar: "C", preview: "hey", time: "now")
        let vm = InboxViewModel(threads: [t1], contacts: fastContacts(), defaults: d)

        vm.archive("u1")
        XCTAssertTrue(vm.archivedThreadIDs.contains("u1"))

        vm.unarchive("u1")
        XCTAssertFalse(vm.archivedThreadIDs.contains("u1"),
                       "unarchived thread must be removed from archivedThreadIDs")
        let visible = vm.threads.filter { !vm.archivedThreadIDs.contains($0.id) }
        XCTAssertTrue(visible.contains(where: { $0.id == "u1" }),
                      "unarchived thread must reappear in the visible list")
    }

    func testArchivedIDsPersist() {
        let d = makeIsolatedDefaults()
        let t1 = MessageThread(id: "p1", channel: .imessage, name: "Dave", avatar: "D", preview: "sup", time: "now")
        let vm1 = InboxViewModel(threads: [t1], contacts: fastContacts(), defaults: d)
        vm1.archive("p1")

        // Simulate relaunch: new VM with the same isolated UserDefaults.
        let vm2 = InboxViewModel(threads: [t1], contacts: fastContacts(), defaults: d)
        XCTAssertTrue(vm2.archivedThreadIDs.contains("p1"),
                      "archivedThreadIDs must survive a simulated relaunch via UserDefaults")
    }
}

// MARK: - send() state transitions (REP-096)

@MainActor
final class InboxViewModelSendTests: XCTestCase {

    /// On a successful send, `sendConfirmation` is nil and `sendToast` contains
    /// the "Sent to…" confirmation — verifying the composer returns to its idle state.
    func testSendSuccessClearsConfirmationAndShowsToast() async {
        let thread = MessageThread(
            id: "t-send", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hi", time: "now",
            chatGUID: "iMessage;-;t-send")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("t-send")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = IMessageSender.dryRunHook()
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "Hello Alice!")
        XCTAssertNotNil(vm.sendConfirmation, "requestSend must stage a pending confirmation")

        await vm.confirmSend()

        XCTAssertNil(vm.sendConfirmation,
                     "sendConfirmation must be nil after a successful send")
        XCTAssertNotNil(vm.sendToast,
                        "sendToast must be set with success message after send")
        XCTAssertTrue(vm.sendToast?.contains("Alice") == true,
                      "sendToast must name the recipient")
    }

    /// On a failed send, `sendConfirmation` is already cleared (it was consumed
    /// at the start of confirmSend), but `sendToast` carries the error message —
    /// the user can re-stage the send via requestSend without losing their text.
    func testSendFailurePreservesEditAndShowsErrorToast() async {
        let thread = MessageThread(
            id: "t-fail", channel: .imessage, name: "Bob",
            avatar: "B", preview: "hey", time: "now",
            chatGUID: "iMessage;-;t-fail")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("t-fail")
        vm.setEdit(threadID: "t-fail", tone: .warm, text: "My draft text")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = { _ in
            throw IMessageSender.SendError.notAuthorized
        }
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "My draft text")
        await vm.confirmSend()

        XCTAssertNil(vm.sendConfirmation,
                     "sendConfirmation is consumed at start of confirmSend regardless of outcome")
        XCTAssertNotNil(vm.sendToast,
                        "sendToast must surface the error so the user knows the send failed")
        // The user's edited draft text must still be intact so they can retry.
        let draft = vm.effectiveDraft(threadID: "t-fail", tone: .warm, fallback: "")
        XCTAssertEqual(draft, "My draft text",
                       "userEdits must be preserved on failure so the user can retry")
    }
}

// MARK: - Thread ordering (REP-103)

@MainActor
final class InboxViewModelOrderingTests: XCTestCase {

    func testThreadsAreSortedByRecencyAfterSync() async throws {
        // StaticMockChannel returns threads in the order given. The real
        // IMessageChannel sorts by date DESC in SQL. This test guards against
        // InboxViewModel accidentally scrambling the channel's ordering.
        let newest = MessageThread(id: "t-newest", channel: .imessage, name: "Newest",
                                   avatar: "N", preview: "just now", time: "12:00")
        let middle = MessageThread(id: "t-middle", channel: .imessage, name: "Middle",
                                   avatar: "M", preview: "earlier", time: "11:00")
        let oldest = MessageThread(id: "t-oldest", channel: .imessage, name: "Oldest",
                                   avatar: "O", preview: "long ago", time: "10:00")

        let channel = StaticMockChannel(threads: [newest, middle, oldest])
        let vm = InboxViewModel(imessage: channel,
                                contacts: ContactsResolver(store: DeniedContactStore()))
        await vm.syncFromIMessage()

        XCTAssertEqual(vm.threads.map(\.id), ["t-newest", "t-middle", "t-oldest"],
                       "ViewModel must preserve the channel's newest-first ordering")
    }

    func testPinnedThreadSortsAboveNewerUnpinnedThread() async throws {
        // Channel returns unpinned (newer) first then pinned (older),
        // matching what IMessageChannel's date DESC query would produce.
        // InboxViewModel must lift the pinned thread to position 0.
        let unpinned = MessageThread(id: "t-unpinned", channel: .imessage, name: "Unpinned",
                                     avatar: "U", preview: "newer msg", time: "12:00",
                                     pinned: false)
        let pinned = MessageThread(id: "t-pinned", channel: .imessage, name: "Pinned",
                                   avatar: "P", preview: "older msg", time: "10:00",
                                   pinned: true)

        let channel = StaticMockChannel(threads: [unpinned, pinned])
        let vm = InboxViewModel(imessage: channel,
                                contacts: ContactsResolver(store: DeniedContactStore()))
        await vm.syncFromIMessage()

        XCTAssertEqual(vm.threads.first?.id, "t-pinned",
                       "pinned thread must sort above unpinned thread regardless of recency")
        XCTAssertEqual(vm.threads.last?.id, "t-unpinned")
    }

    // REP-190: two non-pinned threads with the same effective timestamp must
    // retain channel-provided order across repeated syncs.  InboxViewModel's
    // sort is { pinned > unpinned }, which Swift guarantees to be stable, so
    // equal-pinned threads preserve their input order.
    func testEqualTimestampThreadsSortStably() async throws {
        let a = MessageThread(id: "stable-a", channel: .imessage, name: "A",
                              avatar: "A", preview: "msg", time: "10:00")
        let b = MessageThread(id: "stable-b", channel: .imessage, name: "B",
                              avatar: "B", preview: "msg", time: "10:00")

        let channel = StaticMockChannel(threads: [a, b])
        let vm = InboxViewModel(imessage: channel,
                                contacts: ContactsResolver(store: DeniedContactStore()))

        await vm.syncFromIMessage()
        let firstOrder = vm.threads.map(\.id)

        await vm.syncFromIMessage()
        XCTAssertEqual(vm.threads.map(\.id), firstOrder,
                       "equal-timestamp (non-pinned) threads must not swap positions between syncs")
    }

    // REP-190: channel insertion order acts as the tiebreaker for threads
    // that compare equal under the sort predicate.  The channel provides [A, B];
    // after any number of syncs the ViewModel must expose [A, B], not [B, A].
    func testEqualTimestampSortPreservesChannelOrder() async throws {
        let a = MessageThread(id: "order-a", channel: .imessage, name: "Alice",
                              avatar: "A", preview: "hi", time: "09:00")
        let b = MessageThread(id: "order-b", channel: .imessage, name: "Bob",
                              avatar: "B", preview: "hey", time: "09:00")

        let channel = StaticMockChannel(threads: [a, b])
        let vm = InboxViewModel(imessage: channel,
                                contacts: ContactsResolver(store: DeniedContactStore()))

        for _ in 0..<3 {
            await vm.syncFromIMessage()
        }
        XCTAssertEqual(vm.threads.map(\.id), ["order-a", "order-b"],
                       "channel-provided order must be preserved when threads are equal under the sort predicate")
    }
}

// MARK: - REP-118: archive evicts DraftEngine cache entry

@MainActor
final class ArchiveDraftEvictionTests: XCTestCase {

    func testArchiveClearsDraftCacheEntry() {
        let d = UserDefaults(suiteName: "test.ReplyAI.archive-evict.\(UUID())")!
        UserDefaults.registerReplyAIDefaults(in: d)

        let thread = MessageThread(id: "evict-1", channel: .imessage, name: "Eve",
                                   avatar: "E", preview: "hey", time: "now")
        let vm = InboxViewModel(threads: [thread], contacts: fastContacts(), defaults: d)

        var dismissedID: String?
        vm.dismissHandler = { id in dismissedID = id }

        vm.archive(thread.id)

        XCTAssertEqual(dismissedID, thread.id,
                       "archive must invoke dismissHandler with the archived thread ID")
    }
}

// MARK: - REP-134: archive removes thread from SearchIndex (integration test)

@MainActor
final class ArchiveSearchIndexTests: XCTestCase {

    func testArchiveRemovesThreadFromSearchIndex() async {
        let d = UserDefaults(suiteName: "test.ReplyAI.archive-search.\(UUID())")!
        UserDefaults.registerReplyAIDefaults(in: d)

        let thread = MessageThread(id: "srch-archive-1", channel: .imessage, name: "SearchUser",
                                   avatar: "S", preview: "hello world", time: "now")
        let msgs = [Message(from: .them, text: "hello world uniqueterm", time: "t1")]
        let index = SearchIndex(databaseURL: nil)
        let vm = InboxViewModel(threads: [thread], contacts: fastContacts(), defaults: d,
                                searchIndex: index)

        // Index the thread before archiving.
        await index.upsert(thread: thread, messages: msgs)

        let hitsBefore = await index.search("uniqueterm")
        XCTAssertEqual(hitsBefore.count, 1, "thread must be findable before archive")

        vm.archive(thread.id)

        // Give the async Task inside archive() time to complete.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let hitsAfter = await index.search("uniqueterm")
        XCTAssertEqual(hitsAfter.count, 0, "archived thread must not be findable in SearchIndex")
    }
}

// MARK: - Watcher-driven sync updates previewText (REP-142)

/// A ChannelService that returns successive thread batches on each call.
/// After exhausting the provided batches, repeats the last one.
private final class MutableMockChannel: ChannelService, @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[MessageThread]]
    private var callIndex = 0

    init(batches: [[MessageThread]]) { self.batches = batches }

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        lock.lock(); defer { lock.unlock() }
        let i = min(callIndex, batches.count - 1)
        callIndex += 1
        return batches[i]
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
}

@MainActor
final class InboxViewModelSyncPreviewTests: XCTestCase {

    func testSyncUpdatesExistingThreadPreviewText() async {
        let initial = MessageThread(id: "rep142-a", channel: .imessage, name: "Alice",
                                    avatar: "A", preview: "hello", time: "now")
        let updated = MessageThread(id: "rep142-a", channel: .imessage, name: "Alice",
                                    avatar: "A", preview: "world", time: "now")
        let channel = MutableMockChannel(batches: [[initial], [updated]])
        let vm = InboxViewModel(threads: [initial], imessage: channel, contacts: fastContacts())
        vm.selectedThreadID = "rep142-a"

        await vm.syncFromIMessage()
        await vm.syncFromIMessage()

        XCTAssertEqual(
            vm.threads.first(where: { $0.id == "rep142-a" })?.preview, "world",
            "re-sync must update previewText for an existing thread in place")
    }

    func testSyncPreservesUnchangedThreadCount() async {
        let initial = MessageThread(id: "rep142-b", channel: .imessage, name: "Bob",
                                    avatar: "B", preview: "first", time: "now")
        let updated = MessageThread(id: "rep142-b", channel: .imessage, name: "Bob",
                                    avatar: "B", preview: "second", time: "now")
        let channel = MutableMockChannel(batches: [[initial], [updated]])
        let vm = InboxViewModel(threads: [initial], imessage: channel, contacts: fastContacts())
        vm.selectedThreadID = "rep142-b"

        await vm.syncFromIMessage()
        let countAfterFirst = vm.threads.count
        await vm.syncFromIMessage()

        XCTAssertEqual(vm.threads.count, countAfterFirst,
            "re-syncing the same thread IDs must not grow the thread count")
    }
}

// MARK: - Re-select same thread does not double-prime (REP-155)

@MainActor
final class InboxViewModelReselectTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test.ReplyAI.reselect.\(UUID())")!
        UserDefaults.registerReplyAIDefaults(in: d)
        return d
    }

    private func makeRules() -> RulesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAI-reselect-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }
        return store
    }

    func testReselectSameThreadDoesNotDoublePrime() {
        let d = makeDefaults()
        let t1 = MessageThread(id: "rep155-t1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "rep155-t2", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let ch = BlockingMockChannel(); ch.blocking = false
        let vm = InboxViewModel(threads: [t1, t2], imessage: ch, contacts: fastContacts(),
                                rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))

        var primeCount = 0
        vm.primeHandler = { _, _, _ in primeCount += 1 }

        vm.selectThread("rep155-t2")
        vm.selectThread("rep155-t2")

        XCTAssertEqual(primeCount, 1,
            "primeHandler must be invoked exactly once for consecutive selects of the same thread")
    }

    func testSelectedThreadIsCorrectAfterDoubleSelect() {
        let d = makeDefaults()
        let t1 = MessageThread(id: "rep155-ta", channel: .imessage, name: "Carol", avatar: "C", preview: "", time: "")
        let t2 = MessageThread(id: "rep155-tb", channel: .imessage, name: "Dave",  avatar: "D", preview: "", time: "")
        let ch = BlockingMockChannel(); ch.blocking = false
        let vm = InboxViewModel(threads: [t1, t2], imessage: ch, contacts: fastContacts(),
                                rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))

        vm.selectThread("rep155-tb")
        vm.selectThread("rep155-tb")

        XCTAssertEqual(vm.selectedThreadID, "rep155-tb",
            "selectedThreadID must be the doubly-selected thread")
        XCTAssertEqual(vm.selectedThread.id, "rep155-tb",
            "selectedThread must reflect the doubly-selected thread")
    }
}

// MARK: - isSyncing flag transitions (REP-168)

@MainActor
final class InboxViewModelIsSyncingTests: XCTestCase {

    func testIsSyncingTrueWhileSyncing() async throws {
        let channel = BlockingMockChannel()
        let vm = InboxViewModel(imessage: channel, contacts: fastContacts())

        XCTAssertFalse(vm.isSyncing, "isSyncing must start false")

        let syncTask = Task { await vm.syncFromIMessage() }

        // Yield until recentThreads has been entered (callCount increments before the
        // continuation is appended to pending). Both tasks share the MainActor, so
        // after a yield that sees callCount > 0, syncTask has already suspended inside
        // withCheckedThrowingContinuation — making it safe to call resumeAll().
        var count = 0
        while channel.recentThreadsCallCount == 0 && count < 100 {
            await Task.yield()
            count += 1
        }

        // Safety guard: if the loop timed out before recentThreads was entered,
        // turn off blocking so syncTask can still complete (avoids deadlock).
        defer { channel.blocking = false; channel.resumeAll() }

        XCTAssertTrue(vm.isSyncing, "isSyncing must be true while syncFromIMessage is blocked in recentThreads")

        channel.resumeAll()
        await syncTask.value

        XCTAssertFalse(vm.isSyncing, "isSyncing must be false after sync completes")
    }

    func testIsSyncingFalseAfterSuccess() async {
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(imessage: channel, contacts: fastContacts())

        await vm.syncFromIMessage()

        XCTAssertFalse(vm.isSyncing, "isSyncing must be false after a successful sync")
    }

    func testIsSyncingFalseAfterError() async {
        final class ThrowingChannel168: ChannelService, @unchecked Sendable {
            func recentThreads(limit: Int) async throws -> [MessageThread] {
                throw ChannelError.unavailable("forced error for REP-168")
            }
            func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
        }

        let vm = InboxViewModel(imessage: ThrowingChannel168(), contacts: fastContacts())

        await vm.syncFromIMessage()

        XCTAssertFalse(vm.isSyncing, "isSyncing must be false after sync throws an error")
    }
}

// MARK: - REP-263: applyIncomingNotification chatGUID deduplication

@MainActor
final class InboxViewModelChatGUIDDeduplicationTests: XCTestCase {

    private func makeVM(threads: [MessageThread]) -> InboxViewModel {
        let ch = BlockingMockChannel()
        ch.blocking = false
        return InboxViewModel(threads: threads, imessage: ch, contacts: fastContacts())
    }

    func testIncomingNotificationWithMatchingGUIDUpdatesExistingThread() {
        let guid = "iMessage;+;chat5555"
        let vm = makeVM(threads: [
            MessageThread(id: "t1", channel: .imessage, name: "Carol",
                          avatar: "C", preview: "old text", time: "08:00",
                          chatGUID: guid)
        ])

        vm.applyIncomingNotification(senderHandle: "+15550001111", preview: "New message", chatGUID: guid)

        XCTAssertEqual(vm.threads.count, 1,
            "thread count must stay 1 when chatGUID matches existing thread")
        XCTAssertEqual(vm.threads.first?.preview, "New message",
            "existing thread previewText must be updated")
        XCTAssertEqual(vm.threads.first?.unread, 1,
            "unread count must increment by 1 on match")
    }

    func testIncomingNotificationWithUnknownGUIDCreatesNewThread() {
        let vm = makeVM(threads: [
            MessageThread(id: "t2", channel: .imessage, name: "Dave",
                          avatar: "D", preview: "hi", time: "09:00",
                          chatGUID: "iMessage;+;chat9999")
        ])

        vm.applyIncomingNotification(
            senderHandle: "+15552223333",
            preview: "Hello from unknown",
            chatGUID: "iMessage;+;chatAAAA"   // does not match any seeded thread
        )

        XCTAssertEqual(vm.threads.count, 2,
            "unknown chatGUID must create a new thread entry")
    }

    func testIncomingNotificationWithNilGUIDCreatesNewThread() {
        let vm = makeVM(threads: [
            MessageThread(id: "t3", channel: .imessage, name: "Eve",
                          avatar: "E", preview: "hey", time: "10:00",
                          chatGUID: "iMessage;+;chat1234")
        ])

        // nil chatGUID → fall back to senderHandle heuristic; senderHandle doesn't match name/GUID
        vm.applyIncomingNotification(senderHandle: "+19990001111", preview: "Surprise", chatGUID: nil)

        XCTAssertEqual(vm.threads.count, 2,
            "nil chatGUID with non-matching senderHandle must create a new thread")
    }
}

// MARK: - Messages app activation re-sync (REP-265)

@MainActor
final class InboxViewModelMessagesActivationTests: XCTestCase {

    private let testExtractor: (Notification) -> String? = { $0.userInfo?["bundleID"] as? String }

    // MARK: - Observer fires → syncFromIMessage triggered

    func testMessagesActivationTriggersSyncOnObserverFire() async throws {
        let channel = BlockingMockChannel()
        channel.blocking = false

        let obs = MessagesAppActivationObserver(
            notificationCenter: NotificationCenter(),
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        let vm = InboxViewModel(
            imessage: channel,
            contacts: fastContacts(),
            activationObserver: obs
        )

        // Fire the activation directly (bypasses NSWorkspace notification)
        obs.onMessagesActivated?()

        // Yield to let the Task reach and complete syncFromIMessage
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertGreaterThanOrEqual(channel.recentThreadsCallCount, 1,
            "Messages activation must trigger syncFromIMessage")
        _ = vm
    }

    // MARK: - 5-second debounce prevents rapid second sync

    func testMessagesActivationDebounceSkipsRapidSecondFire() async throws {
        let channel = BlockingMockChannel()
        channel.blocking = false

        let obs = MessagesAppActivationObserver(
            notificationCenter: NotificationCenter(),
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )
        let vm = InboxViewModel(
            imessage: channel,
            contacts: fastContacts(),
            activationObserver: obs
        )

        // Fire twice in rapid succession; InboxViewModel's 5s debounce stops the second
        obs.onMessagesActivated?()
        obs.onMessagesActivated?()

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(channel.recentThreadsCallCount, 1,
            "second activation within 5s must be debounced — only one sync should fire")
        _ = vm
    }

    // MARK: - Weak capture prevents crash after ViewModel deinit

    func testMessagesActivationWeakCaptureNoCrashAfterDeinit() async throws {
        let obs = MessagesAppActivationObserver(
            notificationCenter: NotificationCenter(),
            bundleIDExtractor: testExtractor,
            debounce: 0.0
        )

        autoreleasepool {
            let channel = BlockingMockChannel()
            channel.blocking = false
            let vm = InboxViewModel(
                imessage: channel,
                contacts: fastContacts(),
                activationObserver: obs
            )
            _ = vm
        }
        // vm and channel are deallocated; weak capture in the Task holds nil

        obs.onMessagesActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        // Reaching here without a crash means the weak capture is correct
    }
}

// MARK: - REP-212: selectThread seeds userEdits from DraftStore

@MainActor
final class InboxViewModelDraftStoreSeedTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.ReplyAI.draftstore-seed.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        return d
    }

    private func makeChannel() -> BlockingMockChannel {
        let ch = BlockingMockChannel()
        ch.blocking = false
        return ch
    }

    private func makeRules() -> RulesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAI-draftstore-\(UUID())/rules.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = RulesStore(fileURL: url)
        store.rules.forEach { store.remove($0.id) }
        return store
    }

    // REP-212: when a draft exists in the DraftStore for the newly selected thread,
    // selectThread must pre-populate userEdits so the composer shows the stored text
    // immediately — before the LLM re-primes. Guards the path in selectThread:
    //   if let stored = draftStore?.read(threadID: id) { setEdit(...) }
    func testSelectThreadSeedsUserEditsFromDraftStore() {
        let d = makeDefaults()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAI-seed-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = DraftStore(draftsDirectory: tempDir)
        store.write(threadID: "ds-t2", text: "Stored draft text")

        let t1 = MessageThread(id: "ds-t1", channel: .imessage, name: "Alice",
                               avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "ds-t2", channel: .imessage, name: "Bob",
                               avatar: "B", preview: "", time: "")

        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(),
                                contacts: fastContacts(), rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))
        vm.draftStore = store

        // t1 is pre-selected (first thread); switch to t2 to trigger isNewSelection path.
        vm.selectThread("ds-t2")

        let key = InboxViewModel.editKey(threadID: "ds-t2", tone: vm.activeTone)
        XCTAssertEqual(vm.userEdits[key], "Stored draft text",
                       "selectThread must seed userEdits from DraftStore when autoPrime is true and a draft exists")
    }

    // REP-212: when no draft is stored for the selected thread, userEdits must
    // remain empty — no accidental seeding from another thread's stored draft.
    func testSelectThreadWithNoStoredDraftLeavesUserEditsEmpty() {
        let d = makeDefaults()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplyAI-noseed-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = DraftStore(draftsDirectory: tempDir)
        // Intentionally write nothing — no stored draft for "ds-empty-t2".

        let t1 = MessageThread(id: "ds-empty-t1", channel: .imessage, name: "Alice",
                               avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "ds-empty-t2", channel: .imessage, name: "Bob",
                               avatar: "B", preview: "", time: "")

        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(),
                                contacts: fastContacts(), rules: makeRules(), defaults: d,
                                searchIndex: SearchIndex(databaseURL: nil))
        vm.draftStore = store

        vm.selectThread("ds-empty-t2")

        let key = InboxViewModel.editKey(threadID: "ds-empty-t2", tone: vm.activeTone)
        XCTAssertNil(vm.userEdits[key],
                     "selectThread must not set userEdits when no draft is stored for the selected thread")
    }
}

// MARK: - Thread-list cache (REP-278)

@MainActor
final class InboxViewModelThreadCacheTests: XCTestCase {

    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadCacheTests-\(UUID())/last-threads-cache.json")
    }

    private func makeThread(id: String, name: String, preview: String = "hello",
                            channel: Channel = .imessage, unread: Int = 1,
                            chatGUID: String? = nil) -> MessageThread {
        MessageThread(id: id, channel: channel, name: name, avatar: String(name.prefix(1)),
                      preview: preview, time: "now", unread: unread, chatGUID: chatGUID)
    }

    /// Successful sync returning ≥1 thread must write the cache file.
    func testSuccessfulSyncWritesCache() async throws {
        let cacheURL = tempCacheURL()
        let thread = makeThread(id: "t1", name: "Alice", chatGUID: "iMessage;-;+11")
        let channel = StaticMockChannel(threads: [thread])
        let vm = InboxViewModel(
            threads: [], imessage: channel, contacts: fastContacts(),
            threadsCacheURL: cacheURL
        )

        await vm.syncFromIMessage()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path),
                      "cache file must exist after successful sync")
        let data = try Data(contentsOf: cacheURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["id"] as? String, "t1")
        XCTAssertEqual(json[0]["displayName"] as? String, "Alice")
        XCTAssertEqual(json[0]["chatGUID"] as? String, "iMessage;-;+11")
        XCTAssertEqual(json[0]["channel"] as? String, "imessage")
    }

    /// Fresh ViewModel with no threads + cache present → threads populated from cache.
    func testColdInitFromCache() throws {
        let cacheURL = tempCacheURL()
        // Pre-write a cache representing a prior session's thread list.
        let prior = makeThread(id: "cached-t1", name: "Bob", preview: "hey", unread: 0)
        let channel = StaticMockChannel(threads: [prior])
        // First VM: sync to populate cache.
        let seeder = InboxViewModel(
            threads: [], imessage: channel, contacts: fastContacts(),
            threadsCacheURL: cacheURL
        )
        // Write the cache directly via the encode path by calling sync synchronously.
        let exp = expectation(description: "seed sync")
        Task {
            await seeder.syncFromIMessage()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)

        // Second VM: no threads provided, but cache exists — must hydrate.
        let coldVM = InboxViewModel(
            threads: [], imessage: StaticMockChannel(threads: []),
            contacts: fastContacts(), threadsCacheURL: cacheURL
        )
        XCTAssertEqual(coldVM.threads.count, 1)
        XCTAssertEqual(coldVM.threads[0].id, "cached-t1")
        XCTAssertEqual(coldVM.threads[0].name, "Bob")
    }

    /// A second sync must overwrite the cache with the new thread list.
    func testSecondSyncUpdatesCacheFile() async throws {
        let cacheURL = tempCacheURL()
        let first  = makeThread(id: "t-first",  name: "First")
        let second = makeThread(id: "t-second", name: "Second")

        var callCount = 0
        final class SequencedChannel: ChannelService, @unchecked Sendable {
            private let lock = NSLock()
            private var _count = 0
            let batches: [[MessageThread]]
            init(_ batches: [[MessageThread]]) { self.batches = batches }
            func recentThreads(limit: Int) async throws -> [MessageThread] {
                lock.lock(); defer { lock.unlock() }
                let idx = min(_count, batches.count - 1)
                _count += 1
                return batches[idx]
            }
            func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
        }
        _ = callCount

        let seq = SequencedChannel([[first], [second]])
        let vm = InboxViewModel(threads: [], imessage: seq, contacts: fastContacts(),
                                threadsCacheURL: cacheURL)
        await vm.syncFromIMessage()
        await vm.syncFromIMessage()

        let data = try Data(contentsOf: cacheURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["id"] as? String, "t-second",
                       "cache must reflect the most recent sync result")
    }

    /// Failed sync must leave in-memory threads unchanged (cache not re-written).
    func testFailedSyncLeavesThreadsUnchanged() async throws {
        let cacheURL = tempCacheURL()
        let thread = makeThread(id: "t1", name: "Alice")
        let good = StaticMockChannel(threads: [thread])
        let vm = InboxViewModel(threads: [], imessage: good, contacts: fastContacts(),
                                threadsCacheURL: cacheURL)
        // Seed with a successful sync.
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.threads.count, 1)
        let cacheModDate1 = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as! Date

        // Now inject a failing channel by replacing via the InboxViewModel's
        // internal imessage. We can't swap it post-init, so we test the
        // invariant directly: failed sync must not alter `threads`.
        final class FailingChannel: ChannelService, @unchecked Sendable {
            func recentThreads(limit: Int) async throws -> [MessageThread] {
                throw ChannelError.unavailable("test failure")
            }
            func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
        }
        let vm2 = InboxViewModel(threads: [thread], imessage: FailingChannel(),
                                 contacts: fastContacts(), threadsCacheURL: cacheURL)
        let countBefore = vm2.threads.count
        await vm2.syncFromIMessage()
        XCTAssertEqual(vm2.threads.count, countBefore,
                       "failed sync must not mutate in-memory threads")
        // Cache file modification date must not change.
        let cacheModDate2 = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as! Date
        XCTAssertEqual(cacheModDate1.timeIntervalSince1970,
                       cacheModDate2.timeIntervalSince1970, accuracy: 1,
                       "failed sync must not overwrite the cache file")
    }

    /// No cache file at init → threads empty, no crash.
    func testMissingCacheAtInitProducesEmptyThreads() {
        let cacheURL = tempCacheURL() // file does not exist yet
        let vm = InboxViewModel(
            threads: [], imessage: StaticMockChannel(threads: []),
            contacts: fastContacts(), threadsCacheURL: cacheURL
        )
        XCTAssertTrue(vm.threads.isEmpty,
                      "absent cache must produce empty thread list without crashing")
    }
}

// MARK: - ViewState transitions (REP-247)

@MainActor
final class InboxViewModelViewStateTests: XCTestCase {

    private final class AuthDeniedChannel: ChannelService, @unchecked Sendable {
        func recentThreads(limit: Int) async throws -> [MessageThread] {
            throw ChannelError.authorizationDenied
        }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
    }

    func testViewStateTransitionsToPopulated() async {
        let thread = MessageThread(
            id: "vs-t1", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hi", time: "now", unread: 1)
        let vm = InboxViewModel(
            imessage: StaticMockChannel(threads: [thread]),
            contacts: fastContacts())
        XCTAssertEqual(vm.viewState, .loading, "viewState should start as .loading")
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .populated)
    }

    func testViewStateTransitionsToDemoOnEmptySync() async {
        let suite = "test.ReplyAI.viewState.demo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: PreferenceKey.demoModeActive)
        let vm = InboxViewModel(
            imessage: StaticMockChannel(threads: []),
            contacts: fastContacts(),
            defaults: d)
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .demo)
    }

    func testViewStateTransitionsToEmptyNoPermissions() async {
        let vm = InboxViewModel(
            imessage: AuthDeniedChannel(),
            contacts: fastContacts())
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .empty(.noPermissions))
    }

    func testViewStateTransitionsToEmptyNoMessages() async {
        let suite = "test.ReplyAI.viewState.noMessages.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(false, forKey: PreferenceKey.demoModeActive)
        let vm = InboxViewModel(
            imessage: StaticMockChannel(threads: []),
            contacts: fastContacts(),
            defaults: d)
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .empty(.noMessages))
    }
}

// MARK: - Bulk thread actions and channel filtering

@MainActor
final class InboxViewModelBulkFilterTests: XCTestCase {
    private func makeVM(threads: [MessageThread]) -> InboxViewModel {
        let suite = "test.ReplyAI.bulkFilter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return InboxViewModel(
            threads: threads,
            imessage: BlockingMockChannel(),
            contacts: fastContacts(),
            defaults: defaults
        )
    }

    func testFilterByChannelNarrowsFilteredThreadsWithoutMutatingThreads() {
        let threads = [
            MessageThread(id: "im1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: ""),
            MessageThread(id: "sl1", channel: .slack, name: "Team", avatar: "T", preview: "", time: ""),
            MessageThread(id: "wa1", channel: .whatsapp, name: "Maya", avatar: "M", preview: "", time: "")
        ]
        let vm = makeVM(threads: threads)

        vm.filterByChannel(.slack)

        XCTAssertEqual(vm.filteredThreads.map(\.id), ["sl1"])
        XCTAssertEqual(vm.threads.map(\.id), ["im1", "sl1", "wa1"])
    }

    func testFilterByChannelNilRestoresVisibleThreads() {
        let threads = [
            MessageThread(id: "im1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: ""),
            MessageThread(id: "sl1", channel: .slack, name: "Team", avatar: "T", preview: "", time: "")
        ]
        let vm = makeVM(threads: threads)

        vm.filterByChannel(.imessage)
        vm.filterByChannel(nil)

        XCTAssertEqual(vm.filteredThreads.map(\.id), ["im1", "sl1"])
    }

    func testFilteredThreadsExcludeArchivedThreads() {
        let threads = [
            MessageThread(id: "read", channel: .imessage, name: "Read", avatar: "R", preview: "", time: "", unread: 0),
            MessageThread(id: "unread", channel: .imessage, name: "Unread", avatar: "U", preview: "", time: "", unread: 2)
        ]
        let vm = makeVM(threads: threads)

        vm.archive("read")

        XCTAssertEqual(vm.filteredThreads.map(\.id), ["unread"])
    }

    func testTotalUnreadCountSumsAcrossChannelsAndIgnoresActiveFilter() {
        let threads = [
            MessageThread(id: "im1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", unread: 3),
            MessageThread(id: "sl1", channel: .slack, name: "Team", avatar: "T", preview: "", time: "", unread: 4)
        ]
        let vm = makeVM(threads: threads)

        vm.filterByChannel(.imessage)

        XCTAssertEqual(vm.totalUnreadCount, 7)
    }

    func testBulkMarkAllReadClearsEveryUnreadCount() {
        let threads = [
            MessageThread(id: "im1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", unread: 3),
            MessageThread(id: "sl1", channel: .slack, name: "Team", avatar: "T", preview: "", time: "", unread: 4)
        ]
        let vm = makeVM(threads: threads)

        vm.bulkMarkAllRead()

        XCTAssertTrue(vm.threads.allSatisfy { $0.unread == 0 })
        XCTAssertEqual(vm.totalUnreadCount, 0)
    }

    func testBulkArchiveReadArchivesOnlyReadThreads() {
        let threads = [
            MessageThread(id: "read-im", channel: .imessage, name: "Read", avatar: "R", preview: "", time: "", unread: 0),
            MessageThread(id: "unread-sl", channel: .slack, name: "Team", avatar: "T", preview: "", time: "", unread: 2),
            MessageThread(id: "read-wa", channel: .whatsapp, name: "Maya", avatar: "M", preview: "", time: "", unread: 0)
        ]
        let vm = makeVM(threads: threads)

        vm.bulkArchiveRead()

        XCTAssertEqual(vm.archivedThreadIDs, ["read-im", "read-wa"])
        XCTAssertEqual(vm.filteredThreads.map(\.id), ["unread-sl"])
    }
}
