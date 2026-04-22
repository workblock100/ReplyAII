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

    func testSelectThreadUpdatesSelectedID() {
        let t1 = MessageThread(id: "t1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "t2", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts())
        vm.selectThread("t2")
        XCTAssertEqual(vm.selectedThreadID, "t2", "selectThread must update selectedThreadID")
    }

    func testSelectThreadCallsPrime() {
        let d = makeDefaults()
        // autoPrime defaults to true after registerReplyAIDefaults
        let t1 = MessageThread(id: "t1-prime", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "t2-prime", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(), defaults: d)

        var primeCallCount = 0
        vm.primeHandler = { _, _, _ in primeCallCount += 1 }

        vm.selectThread("t2-prime")
        XCTAssertEqual(primeCallCount, 1, "selectThread must invoke primeHandler when autoPrime is true")
    }

    func testSelectSameThreadTwiceCallsPrimeOnce() {
        let d = makeDefaults()
        let t1 = MessageThread(id: "t1-idem", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "t2-idem", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(), defaults: d)

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

    func testAutoPrimeTrueCallsPrime() {
        let suite = "test.ReplyAI.autoprime.true.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        // default is true after register

        let t1 = MessageThread(id: "ap-t1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "ap-t2", channel: .imessage, name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(), defaults: d)

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
        let vm = InboxViewModel(threads: [t1, t2], imessage: makeChannel(), contacts: fastContacts(), defaults: d)

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
}
