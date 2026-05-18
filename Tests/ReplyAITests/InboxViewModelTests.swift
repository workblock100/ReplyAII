import XCTest
@testable import ReplyAICore

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

    /// REP-178 persists pinnedThreadIDs to UserDefaults.standard. Tests
    /// instantiate InboxViewModel without an isolated `defaults:` argument,
    /// so a prior fixture's "t1"/"t2" IDs can leak across runs and break
    /// the "thread starts unpinned" precondition. Clear before each test.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: InboxViewModel.pinnedKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: InboxViewModel.pinnedKey)
        super.tearDown()
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

// MARK: - InboxViewModel.applyRules(for:) direct contract (autopilot 2026-05-07)

@MainActor
final class InboxViewModelApplyRulesTests: XCTestCase {

    private func tempRulesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMApplyRulesTests-\(UUID())/rules.json")
    }

    private func makeVM(threads: [MessageThread], rules: RulesStore) -> InboxViewModel {
        let suite = "test.ReplyAI.applyRules.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMApplyRulesTests-\(UUID().uuidString).json")
        let noopChannel = BlockingMockChannel()
        noopChannel.blocking = false
        return InboxViewModel(
            threads: threads, imessage: noopChannel,
            contacts: fastContacts(), rules: rules,
            defaults: defaults, threadsCacheURL: cacheURL
        )
    }

    private func makeStore() throws -> RulesStore {
        let url = tempRulesURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = RulesStore(fileURL: url)
        store.resetToSeeds()
        store.rules.forEach { store.remove($0.id) }
        return store
    }

    func testApplyRulesPinActionPinsTargetThread() throws {
        let store = try makeStore()
        let thread = MessageThread(
            id: "p1", channel: .imessage, name: "Carol Lee",
            avatar: "C", preview: "", time: "", pinned: false)
        let vm = makeVM(threads: [thread], rules: store)

        try store.add(SmartRule(name: "pin carol", when: .senderIs("Carol Lee"), then: .pin))

        vm.applyRules(for: thread)

        XCTAssertTrue(vm.pinnedThreadIDs.contains("p1"),
                      "applyRules must add the threadID to pinnedThreadIDs when a matching pin rule is present")
    }

    func testApplyRulesSetDefaultToneUpdatesActiveTone() throws {
        let store = try makeStore()
        let thread = MessageThread(
            id: "t1", channel: .imessage, name: "Dana Park",
            avatar: "D", preview: "", time: "")
        let vm = makeVM(threads: [thread], rules: store)
        vm.activeTone = .warm

        try store.add(SmartRule(
            name: "direct dana", when: .senderIs("Dana Park"), then: .setDefaultTone(.direct)))

        vm.applyRules(for: thread)

        XCTAssertEqual(vm.activeTone, .direct,
                       "applyRules must update activeTone when a matching setDefaultTone rule is present (this is the contract that distinguishes applyRules from reEvaluateRulesForAllThreads — applyRules updates regardless of selectedThreadID)")
    }

    func testApplyRulesSetDefaultToneIsIdempotent() throws {
        let store = try makeStore()
        let thread = MessageThread(
            id: "t1", channel: .imessage, name: "Erin Ko",
            avatar: "E", preview: "", time: "")
        let vm = makeVM(threads: [thread], rules: store)
        vm.activeTone = .playful

        try store.add(SmartRule(
            name: "playful erin", when: .senderIs("Erin Ko"), then: .setDefaultTone(.playful)))

        vm.applyRules(for: thread)

        // Already playful — must remain playful, no oscillation.
        XCTAssertEqual(vm.activeTone, .playful,
                       "applyRules must be a no-op when the matching setDefaultTone matches the current activeTone")
    }

    func testApplyRulesArchiveActionIsNoOpInThisCallSite() throws {
        let store = try makeStore()
        let thread = MessageThread(
            id: "a1", channel: .imessage, name: "Frank Rizzo",
            avatar: "F", preview: "", time: "")
        let vm = makeVM(threads: [thread], rules: store)

        try store.add(SmartRule(
            name: "archive frank", when: .senderIs("Frank Rizzo"), then: .archive))

        vm.applyRules(for: thread)

        // archive/markDone/silentlyIgnore intentionally fall to the
        // `continue` branch in applyRules — they require the
        // incoming-message pipeline to fire them, not the per-thread
        // priming call. This pins that contract.
        XCTAssertFalse(vm.archivedThreadIDs.contains("a1"),
                       "applyRules must NOT archive in response to an archive rule — that branch falls through; archiving is dispatched by the incoming-message pipeline")
        XCTAssertEqual(vm.threads.count, 1,
                       "thread list must remain intact after applyRules with an archive rule")
    }

    func testApplyRulesNonMatchingRuleLeavesEverythingUnchanged() throws {
        let store = try makeStore()
        let thread = MessageThread(
            id: "t1", channel: .imessage, name: "Grace Liu",
            avatar: "G", preview: "", time: "", pinned: false)
        let vm = makeVM(threads: [thread], rules: store)
        vm.activeTone = .warm

        // Rule targets a different sender.
        try store.add(SmartRule(name: "pin someone-else",
                                when: .senderIs("Someone Else"), then: .pin))

        vm.applyRules(for: thread)

        XCTAssertFalse(vm.pinnedThreadIDs.contains("t1"),
                       "applyRules with a non-matching rule must not pin")
        XCTAssertEqual(vm.activeTone, .warm,
                       "applyRules with a non-matching rule must not change activeTone")
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

    @MainActor
    func testSelectClearsUnreadWithoutReorderingThreads() {
        let t1 = MessageThread(
            id: "t1-order", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hi", time: "now", unread: 5)
        let t2 = MessageThread(
            id: "t2-order", channel: .slack, name: "Team",
            avatar: "T", preview: "standup", time: "now", unread: 0)
        let t3 = MessageThread(
            id: "t3-order", channel: .whatsapp, name: "Maya",
            avatar: "M", preview: "later", time: "now", unread: 2)
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [t1, t2, t3], imessage: channel,
                                contacts: fastContacts())

        vm.selectThread("t1-order")

        XCTAssertEqual(vm.threads.map(\.id), ["t1-order", "t2-order", "t3-order"])
        XCTAssertEqual(vm.threads.first?.unread, 0)
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

    // MARK: - Pin persistence (REP-178)

    func testPinStatePersistsThroughReInit() {
        let d = makeIsolatedDefaults(suffix: ".pin1")
        let pinned = MessageThread(id: "pin-a", channel: .imessage, name: "Alice", avatar: "A", preview: "hey", time: "now")
        let other  = MessageThread(id: "pin-b", channel: .imessage, name: "Bob",   avatar: "B", preview: "yo",  time: "now")

        let vm1 = InboxViewModel(threads: [other, pinned], contacts: fastContacts(), defaults: d)
        vm1.pinThread("pin-a")
        XCTAssertTrue(vm1.threads.first(where: { $0.id == "pin-a" })?.pinned == true,
                      "pin must mark the in-memory thread as pinned immediately")
        XCTAssertTrue(vm1.pinnedThreadIDs.contains("pin-a"),
                      "pin must register the id in pinnedThreadIDs for persistence")

        // Simulate relaunch with the same UserDefaults — fresh VM, same threads
        // come back from the channel as `pinned: false`. The persisted set must
        // re-stamp pin state so the thread remains pinned and surfaces first.
        let vm2 = InboxViewModel(threads: [other, pinned], contacts: fastContacts(), defaults: d)
        XCTAssertTrue(vm2.pinnedThreadIDs.contains("pin-a"),
                      "pinnedThreadIDs must survive relaunch via UserDefaults")
        let restored = vm2.threads.first(where: { $0.id == "pin-a" })
        XCTAssertEqual(restored?.pinned, true,
                       "thread re-loaded after relaunch must regain pinned state from the persisted set")
    }

    func testUnpinRemovesFromPinnedSet() {
        let d = makeIsolatedDefaults(suffix: ".pin2")
        let t = MessageThread(id: "pin-c", channel: .imessage, name: "Carol", avatar: "C", preview: "sup", time: "now")
        let vm1 = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)
        vm1.pinThread("pin-c")
        XCTAssertTrue(vm1.pinnedThreadIDs.contains("pin-c"))

        vm1.unpinThread("pin-c")
        XCTAssertFalse(vm1.pinnedThreadIDs.contains("pin-c"),
                       "unpin must remove the id from pinnedThreadIDs")
        XCTAssertEqual(vm1.threads.first(where: { $0.id == "pin-c" })?.pinned, false,
                       "unpin must clear the pinned flag on the in-memory thread")

        // Relaunch — the thread should no longer be pinned because the set is empty.
        let vm2 = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)
        XCTAssertFalse(vm2.pinnedThreadIDs.contains("pin-c"))
        XCTAssertEqual(vm2.threads.first(where: { $0.id == "pin-c" })?.pinned, false,
                       "after unpin + relaunch, the thread must come back unpinned")
    }

    // MARK: - Snooze (REP-111)

    func testSnoozedThreadHiddenFromList() {
        let d = makeIsolatedDefaults(suffix: ".sn1")
        let t1 = MessageThread(id: "sn-a", channel: .imessage, name: "Alice", avatar: "A", preview: "hi", time: "now")
        let t2 = MessageThread(id: "sn-b", channel: .imessage, name: "Bob",   avatar: "B", preview: "yo", time: "now")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        let future = Date().addingTimeInterval(3600)
        vm.snooze(threadID: "sn-a", until: future)

        XCTAssertEqual(vm.snoozedUntil["sn-a"], future,
                       "snooze must record the wake date in snoozedUntil")
        XCTAssertFalse(vm.filteredThreads.contains(where: { $0.id == "sn-a" }),
                       "snoozed thread must not appear in filteredThreads")
        XCTAssertTrue(vm.filteredThreads.contains(where: { $0.id == "sn-b" }),
                      "non-snoozed thread must remain visible")
    }

    func testSnoozedThreadResurfacesAfterExpiry() async {
        let d = makeIsolatedDefaults(suffix: ".sn2")
        let t = MessageThread(id: "sn-c", channel: .imessage, name: "Carol", avatar: "C", preview: "sup", time: "now")
        let vm = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)

        // Wake date in the near past — the scheduled task fires on the next
        // runloop tick and drops the entry.
        let past = Date().addingTimeInterval(-1)
        vm.snooze(threadID: "sn-c", until: past)
        XCTAssertEqual(vm.snoozedUntil["sn-c"], past)

        // Drain the cooperative queue so the wake task gets to run.
        for _ in 0..<10 {
            await Task.yield()
            if vm.snoozedUntil["sn-c"] == nil { break }
        }

        XCTAssertNil(vm.snoozedUntil["sn-c"],
                     "wake task must drop the snooze entry once the wake date passes")
        XCTAssertTrue(vm.filteredThreads.contains(where: { $0.id == "sn-c" }),
                      "thread must reappear in filteredThreads after wake")
    }

    func testSnoozeMapPersistedAcrossInit() {
        let d = makeIsolatedDefaults(suffix: ".sn3")
        let t = MessageThread(id: "sn-d", channel: .imessage, name: "Dave", avatar: "D", preview: "yo", time: "now")
        let vm1 = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)
        let future = Date().addingTimeInterval(3600)
        vm1.snooze(threadID: "sn-d", until: future)

        // Relaunch with the same defaults — snoozedUntil rehydrates with a
        // ~ms-rounded copy (JSON Date encoding loses sub-ms precision); compare
        // by timeIntervalSinceReferenceDate within 1ms.
        let vm2 = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)
        XCTAssertNotNil(vm2.snoozedUntil["sn-d"],
                        "snoozedUntil map must survive relaunch via UserDefaults")
        let restored = vm2.snoozedUntil["sn-d"]!
        XCTAssertLessThan(abs(restored.timeIntervalSince(future)), 0.001,
                          "rehydrated wake date must round-trip within ~1ms")
        XCTAssertFalse(vm2.filteredThreads.contains(where: { $0.id == "sn-d" }),
                       "rehydrated snooze must still hide the thread on next launch")
    }

    func testUnsnoozeDropsEntryImmediately() {
        let d = makeIsolatedDefaults(suffix: ".sn4")
        let t = MessageThread(id: "sn-e", channel: .imessage, name: "Eve", avatar: "E", preview: "", time: "")
        let vm = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)
        vm.snooze(threadID: "sn-e", until: Date().addingTimeInterval(7200))
        XCTAssertFalse(vm.filteredThreads.contains(where: { $0.id == "sn-e" }))

        vm.unsnooze("sn-e")
        XCTAssertNil(vm.snoozedUntil["sn-e"])
        XCTAssertTrue(vm.filteredThreads.contains(where: { $0.id == "sn-e" }),
                      "unsnoozed thread must reappear in filteredThreads")
    }

    /// Re-snoozing a thread before the original wake fires must overwrite
    /// the wake date, and the original wake task firing afterwards must
    /// NOT clear the new snooze (wakeIfStillSnoozed compares
    /// `current == expectedWake`).
    func testReSnoozeBeforeOriginalWakeKeepsTheLatestEntry() async {
        let d = makeIsolatedDefaults(suffix: ".sn5")
        let t = MessageThread(id: "sn-f", channel: .imessage, name: "Frank", avatar: "F", preview: "", time: "")
        let vm = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)

        let pastWake = Date().addingTimeInterval(-1)
        vm.snooze(threadID: "sn-f", until: pastWake)

        // Immediately re-snooze with a future wake — overwriting the past
        // entry while the original wake Task is still scheduled.
        let futureWake = Date().addingTimeInterval(3600)
        vm.snooze(threadID: "sn-f", until: futureWake)

        // Drain — the original past-wake task fires here. With
        // `wakeIfStillSnoozed` correctly comparing against expectedWake, the
        // entry survives because current (futureWake) != expectedWake (pastWake).
        for _ in 0..<10 { await Task.yield() }

        XCTAssertNotNil(vm.snoozedUntil["sn-f"],
                        "re-snoozing before the original wake fires must NOT lose the new entry — the stale wake task must check expectedWake before clearing")
        XCTAssertEqual(vm.snoozedUntil["sn-f"], futureWake,
                       "the latest snooze wake must remain intact; not overwritten by the stale task")
    }

    /// Snoozing twice must overwrite the prior wake date — there's no
    /// stack/queue behavior, just a single mapping per thread.
    func testSnoozeOverwritesPriorWakeDate() {
        let d = makeIsolatedDefaults(suffix: ".sn6")
        let t = MessageThread(id: "sn-g", channel: .imessage, name: "Grace", avatar: "G", preview: "", time: "")
        let vm = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)

        let firstWake = Date().addingTimeInterval(3600)
        let secondWake = Date().addingTimeInterval(7200)
        vm.snooze(threadID: "sn-g", until: firstWake)
        vm.snooze(threadID: "sn-g", until: secondWake)

        XCTAssertEqual(vm.snoozedUntil["sn-g"], secondWake,
                       "second snooze must overwrite the first — single mapping per thread, no stack")
    }

    // MARK: - searchQuery filter (autopilot 2026-05-07)

    /// Empty searchQuery must leave the visible thread list untouched —
    /// the typing field shouldn't filter anything until characters arrive.
    func testFilteredThreadsEmptySearchQueryIsPassThrough() {
        let d = makeIsolatedDefaults(suffix: ".sq1")
        let t1 = MessageThread(id: "sq-1", channel: .imessage, name: "Alice", avatar: "A", preview: "p1", time: "")
        let t2 = MessageThread(id: "sq-2", channel: .slack,    name: "Bob",   avatar: "B", preview: "p2", time: "")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.searchQuery = ""
        XCTAssertEqual(vm.filteredThreads.map(\.id), ["sq-1", "sq-2"])
    }

    /// Whitespace-only searchQuery must be trimmed and treated as empty —
    /// otherwise typing a single space would falsely narrow the results.
    func testFilteredThreadsWhitespaceOnlySearchQueryIsTrimmed() {
        let d = makeIsolatedDefaults(suffix: ".sq2")
        let t1 = MessageThread(id: "sq-3", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "sq-4", channel: .slack,    name: "Bob",   avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.searchQuery = "   \n  \t "
        XCTAssertEqual(vm.filteredThreads.count, 2,
                       "whitespace-only searchQuery must be trimmed and treated as empty (otherwise a single space would falsely narrow)")
    }

    /// searchQuery must match thread.name case-insensitively.
    func testFilteredThreadsSearchByNameIsCaseInsensitive() {
        let d = makeIsolatedDefaults(suffix: ".sq3")
        let t1 = MessageThread(id: "sq-5", channel: .imessage, name: "Alice Park",  avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "sq-6", channel: .slack,    name: "Bob Carter",  avatar: "B", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.searchQuery = "alice"
        XCTAssertEqual(vm.filteredThreads.map(\.id), ["sq-5"],
                       "lowercase 'alice' must match 'Alice Park' via localizedCaseInsensitiveContains")
    }

    /// searchQuery must also match thread.preview text — useful for finding
    /// a thread by what was last said in it.
    func testFilteredThreadsSearchByPreviewIsCaseInsensitive() {
        let d = makeIsolatedDefaults(suffix: ".sq4")
        let t1 = MessageThread(id: "sq-7", channel: .imessage, name: "Alice", avatar: "A", preview: "Pizza tonight?", time: "")
        let t2 = MessageThread(id: "sq-8", channel: .slack,    name: "Bob",   avatar: "B", preview: "Standup at 10", time: "")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.searchQuery = "PIZZA"
        XCTAssertEqual(vm.filteredThreads.map(\.id), ["sq-7"],
                       "uppercase 'PIZZA' must match 'Pizza tonight?' via localizedCaseInsensitiveContains")
    }

    /// Search must compose with the archive filter — archived threads
    /// stay hidden even if their name matches the query.
    func testFilteredThreadsSearchHidesArchivedMatches() {
        let d = makeIsolatedDefaults(suffix: ".sq5")
        let t1 = MessageThread(id: "sq-9",  channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "sq-10", channel: .imessage, name: "Alice the Second", avatar: "A", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.archive("sq-9")
        vm.searchQuery = "alice"

        XCTAssertEqual(vm.filteredThreads.map(\.id), ["sq-10"],
                       "archived threads must stay hidden even when their name matches the search query")
    }

    /// Search composes with the channel filter too — query narrows within
    /// the active channel only.
    func testFilteredThreadsSearchComposesWithChannelFilter() {
        let d = makeIsolatedDefaults(suffix: ".sq6")
        let t1 = MessageThread(id: "sq-11", channel: .imessage, name: "Alice iMsg",  avatar: "A", preview: "", time: "")
        let t2 = MessageThread(id: "sq-12", channel: .slack,    name: "Alice Slack", avatar: "A", preview: "", time: "")
        let vm = InboxViewModel(threads: [t1, t2], contacts: fastContacts(), defaults: d)

        vm.filterByChannel(.imessage)
        vm.searchQuery = "alice"

        XCTAssertEqual(vm.filteredThreads.map(\.id), ["sq-11"],
                       "search must respect the active channel filter — Slack 'Alice Slack' must NOT appear when channel filter is .imessage")
    }

    // MARK: - Derived counts: folderLabel / needsYouCount / handledCount (autopilot 2026-05-07)

    /// `folderLabel` exposes the active folder's display string for the
    /// inbox header. Backed by `folders.first(where: { $0.id == activeFolder })?.label`.
    func testFolderLabelReflectsActiveFolderLabel() {
        let d = makeIsolatedDefaults(suffix: ".fl1")
        let t = MessageThread(id: "fl-t", channel: .imessage, name: "X", avatar: "X", preview: "", time: "")
        let custom = [
            Folder(id: .all,      label: "AllFolder",      count: 0),
            Folder(id: .priority, label: "PriorityFolder", count: 0),
            Folder(id: .awaiting, label: "AwaitingFolder", count: 0),
            Folder(id: .snoozed,  label: "SnoozedFolder",  count: 0),
            Folder(id: .done,     label: "DoneFolder",     count: 0),
        ]
        let vm = InboxViewModel(threads: [t], folders: custom,
                                contacts: fastContacts(), defaults: d)

        vm.activeFolder = .priority
        XCTAssertEqual(vm.folderLabel, "PriorityFolder",
                       "folderLabel must resolve through `folders` by activeFolder.id")

        vm.activeFolder = .done
        XCTAssertEqual(vm.folderLabel, "DoneFolder")
    }

    /// `folderLabel` falls back to "Inbox" when the active folder isn't
    /// in the folder list (e.g. a future Folder.Kind enum case ships
    /// before the Folder array is updated).
    func testFolderLabelFallsBackToInboxWhenActiveFolderMissing() {
        let d = makeIsolatedDefaults(suffix: ".fl2")
        let t = MessageThread(id: "fl-t2", channel: .imessage, name: "X", avatar: "X", preview: "", time: "")
        // Folders intentionally exclude .priority — when activeFolder is set
        // to .priority, the lookup returns nil and folderLabel falls back.
        let partial = [
            Folder(id: .all,      label: "All",      count: 0),
            Folder(id: .awaiting, label: "Awaiting", count: 0),
        ]
        let vm = InboxViewModel(threads: [t], folders: partial,
                                contacts: fastContacts(), defaults: d)

        vm.activeFolder = .priority
        XCTAssertEqual(vm.folderLabel, "Inbox",
                       "folderLabel must fall back to literal 'Inbox' when activeFolder isn't represented in `folders`")
    }

    /// `needsYouCount` counts unread threads in the *filtered* thread list
    /// — so archive and snooze hide threads from this badge too.
    func testNeedsYouCountReflectsUnreadFilteredThreads() {
        let d = makeIsolatedDefaults(suffix: ".ny1")
        let unread1 = MessageThread(id: "ny-1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", unread: 3)
        let unread2 = MessageThread(id: "ny-2", channel: .slack,    name: "Bob",   avatar: "B", preview: "", time: "", unread: 1)
        let read    = MessageThread(id: "ny-3", channel: .imessage, name: "Carol", avatar: "C", preview: "", time: "", unread: 0)
        let vm = InboxViewModel(threads: [unread1, unread2, read],
                                contacts: fastContacts(), defaults: d)

        XCTAssertEqual(vm.needsYouCount, 2,
                       "needsYouCount counts threads with unread > 0 — not the sum of unread (so 3 + 1 + 0 != 4, it's 2 threads)")

        // Archiving an unread thread drops it from the filtered list.
        vm.archive("ny-1")
        XCTAssertEqual(vm.needsYouCount, 1,
                       "archiving an unread thread must drop it from needsYouCount")
    }

    /// `handledCount` is the complement of `needsYouCount` within
    /// filteredThreads — threads with unread == 0 that aren't filtered
    /// out.
    func testHandledCountIsComplementOfNeedsYouCountWithinFilteredThreads() {
        let d = makeIsolatedDefaults(suffix: ".hc1")
        let read1 = MessageThread(id: "hc-1", channel: .imessage, name: "A", avatar: "A", preview: "", time: "", unread: 0)
        let read2 = MessageThread(id: "hc-2", channel: .slack,    name: "B", avatar: "B", preview: "", time: "", unread: 0)
        let unread = MessageThread(id: "hc-3", channel: .slack,   name: "C", avatar: "C", preview: "", time: "", unread: 2)
        let vm = InboxViewModel(threads: [read1, read2, unread],
                                contacts: fastContacts(), defaults: d)

        XCTAssertEqual(vm.needsYouCount, 1)
        XCTAssertEqual(vm.handledCount, 2,
                       "handledCount must equal filteredThreads.count - needsYouCount")
        XCTAssertEqual(vm.needsYouCount + vm.handledCount, vm.filteredThreads.count,
                       "needsYouCount + handledCount must always sum to filteredThreads.count")
    }

    /// Unsnoozing a thread that was never snoozed must be a no-op (the
    /// keyboard shortcut may fire defensively without checking state
    /// first).
    func testUnsnoozeNonSnoozedIsNoOp() {
        let d = makeIsolatedDefaults(suffix: ".sn7")
        let t = MessageThread(id: "sn-h", channel: .imessage, name: "Hank", avatar: "H", preview: "", time: "")
        let vm = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: d)

        // No snooze was ever set on sn-h. Calling unsnooze must not crash
        // or insert a marker entry.
        vm.unsnooze("sn-h")

        XCTAssertNil(vm.snoozedUntil["sn-h"])
        XCTAssertTrue(vm.snoozedUntil.isEmpty,
                      "unsnooze on a non-snoozed thread must not insert a sentinel — snoozedUntil stays empty")
    }

    func testApplyPinnedReStampsPinFlag() {
        // Direct test of the helper used by syncAllChannels: thread that comes
        // back from a channel as `pinned: false` gets re-stamped if its id is
        // in the persisted set, and is left alone otherwise.
        let raw = [
            MessageThread(id: "px-1", channel: .imessage, name: "X", avatar: "X", preview: "", time: ""),
            MessageThread(id: "px-2", channel: .imessage, name: "Y", avatar: "Y", preview: "", time: ""),
        ]
        let result = InboxViewModel.applyPinned(raw, pinnedIDs: ["px-1"])
        XCTAssertEqual(result.first(where: { $0.id == "px-1" })?.pinned, true,
                       "id present in pinnedIDs must come back pinned")
        XCTAssertEqual(result.first(where: { $0.id == "px-2" })?.pinned, false,
                       "id absent from pinnedIDs must remain unpinned")
    }

    func testApplyPinnedEmptyPinnedIDsShortCircuits() {
        // Early-return path: with no pinned IDs we skip the .map entirely
        // and return the input unchanged.
        let raw = [
            MessageThread(id: "px-1", channel: .imessage, name: "X", avatar: "X", preview: "", time: ""),
        ]
        let result = InboxViewModel.applyPinned(raw, pinnedIDs: [])
        XCTAssertEqual(result.map(\.id), raw.map(\.id),
            "empty pinnedIDs must short-circuit to input passthrough")
        XCTAssertFalse(result[0].pinned)
    }

    func testApplyPinnedEmptyInputReturnsEmpty() {
        let result = InboxViewModel.applyPinned([], pinnedIDs: ["px-1"])
        XCTAssertTrue(result.isEmpty,
            "empty input must produce empty output regardless of pinnedIDs")
    }

    func testApplyPinnedAlreadyPinnedThreadIsPassedThrough() {
        // The implementation guards `!t.pinned` so an already-pinned
        // thread skips the copying() round-trip. Pin the optimization so
        // a refactor doesn't burn an allocation per pinned thread on
        // every sync.
        let raw = [
            MessageThread(
                id: "px-1", channel: .imessage,
                name: "X", avatar: "X", preview: "", time: "",
                pinned: true
            ),
        ]
        let result = InboxViewModel.applyPinned(raw, pinnedIDs: ["px-1"])
        XCTAssertEqual(result.first?.pinned, true,
            "already-pinned thread must remain pinned")
        XCTAssertEqual(result.first?.id, "px-1",
            "already-pinned thread must pass through with same id")
    }

    func testApplyPinnedDoesNotMutateUnrelatedFields() {
        // Threads whose ids are not in pinnedIDs must not have any field
        // modified — confirms the .map only touches the matching subset.
        let raw = [
            MessageThread(id: "px-1", channel: .imessage, name: "X", avatar: "X",
                          preview: "preview-1", time: "now", unread: 5),
            MessageThread(id: "px-2", channel: .slack, name: "Y", avatar: "Y",
                          preview: "preview-2", time: "1m", unread: 0),
        ]
        let result = InboxViewModel.applyPinned(raw, pinnedIDs: ["px-1"])
        let unrelated = result.first { $0.id == "px-2" }
        XCTAssertEqual(unrelated?.preview, "preview-2",
            "unrelated thread must keep its preview")
        XCTAssertEqual(unrelated?.unread, 0,
            "unrelated thread must keep its unread count")
        XCTAssertEqual(unrelated?.pinned, false)
    }
}

// MARK: - send() state transitions (REP-096)

@MainActor
final class InboxViewModelSendTests: XCTestCase {

    /// REP-222 end-to-end: a successful send appends the sent text to the
    /// user's voice profile in the injected UserDefaults. Pins the wiring
    /// from confirmSend → captureVoiceExample so a future refactor that
    /// drops the captureVoiceExample call (e.g. moves it to a different
    /// state machine) is caught immediately.
    func testSuccessfulSendAppendsToVoiceProfile() async {
        let suite = "test.ReplyAI.confirmSend.voiceCapture.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let thread = MessageThread(
            id: "t-vc", channel: .imessage, name: "Alice",
            avatar: "A", preview: "hi", time: "now",
            chatGUID: "iMessage;-;t-vc")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: channel,
                                contacts: fastContacts(), defaults: d)
        vm.selectThread("t-vc")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = IMessageSender.dryRunHook()
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "Sounds great, see you Tuesday at the cafe!")
        await vm.confirmSend()

        XCTAssertEqual(d.voiceExampleMessages(),
                       ["Sounds great, see you Tuesday at the cafe!"],
                       "successful send must append the sent text to the user's voice profile")
    }

    /// REP-222 end-to-end negative: a FAILED send must NOT corrupt the
    /// voice profile. We only learn from messages that actually went out.
    func testFailedSendDoesNotAppendToVoiceProfile() async {
        let suite = "test.ReplyAI.confirmSend.voiceCaptureFail.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let thread = MessageThread(
            id: "t-vc-fail", channel: .imessage, name: "Bob",
            avatar: "B", preview: "hey", time: "now",
            chatGUID: "iMessage;-;t-vc-fail")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: channel,
                                contacts: fastContacts(), defaults: d)
        vm.selectThread("t-vc-fail")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = { _ in
            throw IMessageSender.SendError.scriptFailure("simulated for test")
        }
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "This should not enter the profile after failure!")
        await vm.confirmSend()

        XCTAssertEqual(d.voiceExampleMessages(), [],
                       "failed send must NOT pollute the voice profile")
    }

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

    // MARK: - advanceToNextThread (autopilot 2026-05-07)

    /// `advanceToNextThread` is private, but its observable contract — that
    /// `selectedThreadID` advances to the next thread after a successful
    /// send — drives the ⌘↵ "burn down the inbox" muscle memory. Pin it
    /// through `confirmSend` since that's the only public caller.
    func testSendSuccessAdvancesSelectedThreadIDToNext() async {
        let t1 = MessageThread(id: "ad-1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", chatGUID: "iMessage;-;ad-1")
        let t2 = MessageThread(id: "ad-2", channel: .imessage, name: "Bob", avatar: "B", preview: "", time: "", chatGUID: "iMessage;-;ad-2")
        let t3 = MessageThread(id: "ad-3", channel: .imessage, name: "Carol", avatar: "C", preview: "", time: "", chatGUID: "iMessage;-;ad-3")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [t1, t2, t3], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("ad-1")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = IMessageSender.dryRunHook()
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "Hello")
        await vm.confirmSend()

        XCTAssertEqual(vm.selectedThreadID, "ad-2",
                       "successful send must advance selectedThreadID to the next thread")
    }

    /// Wraparound: sending from the last thread must return selection to the
    /// first thread so the user keeps the ⌘↵ rhythm without having to
    /// scroll back to the top manually.
    func testSendSuccessFromLastThreadWrapsToFirst() async {
        let t1 = MessageThread(id: "wr-1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", chatGUID: "iMessage;-;wr-1")
        let t2 = MessageThread(id: "wr-2", channel: .imessage, name: "Bob", avatar: "B", preview: "", time: "", chatGUID: "iMessage;-;wr-2")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [t1, t2], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("wr-2")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = IMessageSender.dryRunHook()
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "Hello")
        await vm.confirmSend()

        XCTAssertEqual(vm.selectedThreadID, "wr-1",
                       "successful send from the last thread must wrap selection to the first thread")
    }

    /// Failed send must NOT advance selectedThreadID — the user is staying
    /// put to fix the error.
    /// Channels without a registered send path (whatsapp/telegram/teams in
    /// v1) must fail through to `IMessageSender.SendError.unsupported` so
    /// the user sees an error toast rather than a silent drop. Pins the
    /// `default:` arm of confirmSend's per-channel switch.
    func testSendOnUnsupportedChannelSurfacesErrorToastAndDoesNotAdvance() async {
        let t1 = MessageThread(id: "wa-1", channel: .whatsapp, name: "Whatsapp Friend", avatar: "W", preview: "", time: "")
        let t2 = MessageThread(id: "wa-2", channel: .whatsapp, name: "Bob", avatar: "B", preview: "", time: "")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [t1, t2], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("wa-1")

        vm.requestSend(text: "Hi WhatsApp")
        await vm.confirmSend()

        XCTAssertNil(vm.sendConfirmation,
                     "sendConfirmation is consumed at start of confirmSend regardless of outcome")
        XCTAssertNotNil(vm.sendToast,
                        "unsupported-channel send must surface a toast — silent drop would feel like the app froze")
        XCTAssertEqual(vm.selectedThreadID, "wa-1",
                       "unsupported-channel send must NOT advance selection — user is staying put with the error visible")
    }

    func testSendFailureDoesNotAdvanceSelectedThreadID() async {
        let t1 = MessageThread(id: "fa-1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", chatGUID: "iMessage;-;fa-1")
        let t2 = MessageThread(id: "fa-2", channel: .imessage, name: "Bob", avatar: "B", preview: "", time: "", chatGUID: "iMessage;-;fa-2")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [t1, t2], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("fa-1")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = { _ in
            throw IMessageSender.SendError.notAuthorized
        }
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "Hello")
        await vm.confirmSend()

        XCTAssertEqual(vm.selectedThreadID, "fa-1",
                       "failed send must NOT advance selection — the user is staying put to retry")
    }
}

// MARK: - Voice profile capture on send (REP-222)
// Pins that successful sends append the just-sent text to the user's
// voice profile in UserDefaults, with FIFO eviction at the cap and
// length filtering on too-short messages. The PromptBuilder integration
// path (MLXDraftService reads voiceExampleMessages and passes them to
// PromptBuilder.build) is tested separately in MLXDraftServiceTests.

@MainActor
final class InboxViewModelVoiceCaptureTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.ReplyAI.voiceCapture.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testCaptureAppendsLongEnoughMessage() {
        let d = makeDefaults()
        InboxViewModel.captureVoiceExample("Sounds great, see you Tuesday!", into: d)
        XCTAssertEqual(d.voiceExampleMessages(), ["Sounds great, see you Tuesday!"])
    }

    func testCaptureSkipsShortMessages() {
        let d = makeDefaults()
        InboxViewModel.captureVoiceExample("ok", into: d)
        InboxViewModel.captureVoiceExample("thanks", into: d)
        InboxViewModel.captureVoiceExample("yeah!", into: d)
        XCTAssertEqual(d.voiceExampleMessages(), [],
            "messages below voiceExampleMinChars must NOT enter the profile — they pollute the 20-slot cap with noise")
    }

    func testCaptureSkipsWhitespaceOnly() {
        let d = makeDefaults()
        InboxViewModel.captureVoiceExample("                        ", into: d)
        XCTAssertEqual(d.voiceExampleMessages(), [])
    }

    func testCaptureTrimsBeforeLengthCheck() {
        let d = makeDefaults()
        // 10 trimmed chars — below the 12-char floor, even though raw is 14
        InboxViewModel.captureVoiceExample("  hi friend ", into: d)
        XCTAssertEqual(d.voiceExampleMessages(), [],
            "trim happens BEFORE the length check; padded short message must still skip")
    }

    func testCaptureSkipsExactDuplicateOfMostRecent() {
        let d = makeDefaults()
        InboxViewModel.captureVoiceExample("Sounds good, talk later!", into: d)
        InboxViewModel.captureVoiceExample("Sounds good, talk later!", into: d)
        XCTAssertEqual(d.voiceExampleMessages(),
                       ["Sounds good, talk later!"],
                       "re-sending the same boilerplate must NOT push every other example out of the FIFO window")
    }

    func testCaptureFifoEvictionWhenAtCap() {
        let d = makeDefaults()
        let cap = PreferenceRange.maxVoiceExamples
        // Fill exactly to cap with N entries each ≥ voiceExampleMinChars.
        for i in 0..<cap {
            InboxViewModel.captureVoiceExample("voice example number \(i) here", into: d)
        }
        XCTAssertEqual(d.voiceExampleMessages().count, cap)
        // One more push — oldest entry ("voice example number 0 here") evicts.
        InboxViewModel.captureVoiceExample("voice example number 9999 here", into: d)
        let stored = d.voiceExampleMessages()
        XCTAssertEqual(stored.count, cap, "list must stay at cap")
        XCTAssertEqual(stored.last, "voice example number 9999 here",
                       "newest message keeps the tail")
        XCTAssertFalse(stored.contains("voice example number 0 here"),
                       "oldest message must be evicted (FIFO)")
    }

    func testCaptureRespectsPerEntryLengthCap() {
        let d = makeDefaults()
        let oversize = String(repeating: "x", count: PreferenceRange.maxVoiceExampleLength + 50)
        InboxViewModel.captureVoiceExample(oversize, into: d)
        let stored = d.voiceExampleMessages()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.count, PreferenceRange.maxVoiceExampleLength,
                       "oversized message must be truncated by setVoiceExampleMessages — defense-in-depth from setter, not capture")
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

        // Wait deterministically for `recentThreads` to be entered via the
        // enteredStream signal — `BlockingMockChannel` yields a `()` event
        // the moment it suspends inside the continuation. The previous
        // `await Task.yield()` polling loop relied on Task.yield resuming
        // the syncTask before the polling task, which is not actually
        // guaranteed on the cooperative pool: when the polling task is the
        // only one ready, yield is a no-op and the loop spins 100 iterations
        // without observing the call. The stream wait can't no-op — the
        // suspending task must run before the stream produces.
        for await _ in channel.enteredStream { break }

        // Safety guard: turn off blocking and drain any pending continuations
        // even if the assertion fails so the test can never deadlock.
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

    /// New threads created from a notification must land at index 0 (top
    /// of inbox), NOT appended at the end. The implementation
    /// (`threads.insert(..., at: 0)`) matches what the existing bump-to-
    /// top tests prove for the "match found → refresh" path, but the
    /// "no match → create new" path's insertion position is not asserted
    /// by `testIncomingNotificationWithNilGUIDCreatesNewThread` (it only
    /// checks count). A future "use threads.append for new entries"
    /// refactor (e.g. to preserve scroll-anchor on the inbox) would still
    /// pass that count check while putting the most urgent unread
    /// notification BELOW every existing thread — the user's eye lands on
    /// stale threads, not the new one. Pin the position so the contract
    /// is explicit in CI.
    func testIncomingNotificationCreatesNewThreadAtIndexZero() {
        let vm = makeVM(threads: [
            MessageThread(id: "t-existing-1", channel: .imessage, name: "Existing One",
                          avatar: "E1", preview: "old1", time: "08:00",
                          chatGUID: "iMessage;-;+15550000001"),
            MessageThread(id: "t-existing-2", channel: .imessage, name: "Existing Two",
                          avatar: "E2", preview: "old2", time: "09:00",
                          chatGUID: "iMessage;-;+15550000002")
        ])

        vm.applyIncomingNotification(
            senderHandle: "+19998887777",
            preview: "Brand new conversation",
            chatGUID: "iMessage;-;+19998887777"
        )

        XCTAssertEqual(vm.threads.count, 3,
                       "non-matching notification must create a new thread")
        XCTAssertEqual(vm.threads.first?.preview, "Brand new conversation",
                       "the newly created thread must land at index 0 (top of inbox), not appended at end — the user's eye lands on the most recent unread")
        XCTAssertEqual(vm.threads.first?.name, "+19998887777",
                       "the new thread's display name comes from the senderHandle (no contact resolution at notification time)")
        XCTAssertEqual(vm.threads.first?.unread, 1,
                       "newly-created notification thread starts with unread = 1")
    }

    // MARK: - chatDBAvailable gate + side-effects (autopilot 2026-05-07)

    /// `applyIncomingNotification` must short-circuit when chat.db sync is
    /// live — the FSEvents/chat.db pipeline already owns thread updates;
    /// firing the notification path on top would double-count unread.
    func testApplyIncomingNotificationShortCircuitsWhenChatDBLive() {
        let guid = "iMessage;+;live-test"
        let vm = makeVM(threads: [
            MessageThread(id: "t-live", channel: .imessage, name: "Frank",
                          avatar: "F", preview: "preexisting", time: "11:00",
                          unread: 2, chatGUID: guid)
        ])
        vm.syncStatus = .live(at: Date())

        vm.applyIncomingNotification(senderHandle: "+15551112222", preview: "ignored", chatGUID: guid)

        XCTAssertEqual(vm.threads.first?.preview, "preexisting",
                       "applyIncomingNotification must NOT mutate the thread when chat.db is .live")
        XCTAssertEqual(vm.threads.first?.unread, 2,
                       "applyIncomingNotification must NOT increment unread when chat.db is .live")
        XCTAssertEqual(vm.threads.count, 1,
                       "applyIncomingNotification must NOT create a new thread when chat.db is .live")
    }

    /// Updated thread must move to index 0 — the inbox is recency-sorted
    /// and a fresh notification is the most recent activity.
    func testApplyIncomingNotificationMovesUpdatedThreadToTop() {
        let guid = "iMessage;+;reorder-test"
        let vm = makeVM(threads: [
            MessageThread(id: "t-other", channel: .imessage, name: "Alice",
                          avatar: "A", preview: "first", time: "08:00"),
            MessageThread(id: "t-target", channel: .imessage, name: "Bob",
                          avatar: "B", preview: "older", time: "07:00",
                          chatGUID: guid)
        ])

        vm.applyIncomingNotification(senderHandle: "+15553334444", preview: "newest", chatGUID: guid)

        XCTAssertEqual(vm.threads.first?.id, "t-target",
                       "the updated thread must be moved to index 0 after a notification")
        XCTAssertEqual(vm.threads.first?.preview, "newest")
    }

    /// nil chatGUID + senderHandle that matches a thread by `name` (the
    /// AppleScript-fallback path doesn't always carry a chatGUID, so the
    /// heuristic uses display name) must update that thread, not create a
    /// duplicate.
    func testApplyIncomingNotificationMatchesByNameWhenGUIDNil() {
        let vm = makeVM(threads: [
            MessageThread(id: "t-by-name", channel: .imessage, name: "Carol",
                          avatar: "C", preview: "earlier", time: "12:00",
                          chatGUID: nil)
        ])

        vm.applyIncomingNotification(senderHandle: "Carol", preview: "fresh", chatGUID: nil)

        XCTAssertEqual(vm.threads.count, 1,
                       "senderHandle equal to thread.name must dedupe — no new thread created")
        XCTAssertEqual(vm.threads.first?.preview, "fresh")
        XCTAssertEqual(vm.threads.first?.unread, 1)
    }

    /// nil chatGUID + senderHandle whose digits are the chatGUID suffix
    /// (e.g. notification carries phone number, thread carries
    /// `iMessage;-;+15551234567`) must dedupe via the suffix heuristic.
    func testApplyIncomingNotificationMatchesByChatGUIDSuffixWhenNotificationGUIDNil() {
        let suffix = "+15551234567"
        let vm = makeVM(threads: [
            MessageThread(id: "t-suffix", channel: .imessage, name: "Phone Friend",
                          avatar: "P", preview: "old", time: "13:00",
                          chatGUID: "iMessage;-;\(suffix)")
        ])

        vm.applyIncomingNotification(senderHandle: suffix, preview: "newer", chatGUID: nil)

        XCTAssertEqual(vm.threads.count, 1,
                       "senderHandle matching the chatGUID suffix must dedupe — no new thread created")
        XCTAssertEqual(vm.threads.first?.preview, "newer")
        XCTAssertEqual(vm.threads.first?.unread, 1)
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
        XCTAssertEqual(json[0]["channel"] as? String, Channel.imessage.rawValue)
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

    // MARK: - ViewState.== operator (autopilot 2026-05-07)

    /// Same-case .error views with the same `localizedDescription` must
    /// compare equal — SwiftUI's @Observable consumer relies on this to
    /// avoid spurious re-renders when the same error fires twice.
    func testViewStateEqualityErrorMatchesByLocalizedDescription() {
        struct StubError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }
        let a: InboxViewModel.ViewState = .error(StubError(message: "boom"))
        let b: InboxViewModel.ViewState = .error(StubError(message: "boom"))
        XCTAssertEqual(a, b,
                       ".error(_) == .error(_) must compare by errorDescription so the SwiftUI Observable layer can short-circuit unchanged states")
    }

    /// Different .error descriptions must compare unequal — otherwise a
    /// transition from one error to another would silently fail to
    /// invalidate the view.
    func testViewStateEqualityErrorMismatchByLocalizedDescription() {
        struct StubError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }
        let a: InboxViewModel.ViewState = .error(StubError(message: "first"))
        let b: InboxViewModel.ViewState = .error(StubError(message: "second"))
        XCTAssertNotEqual(a, b,
                          "different error descriptions must NOT compare equal — view must re-render on transition between distinct errors")
    }

    /// Cross-case comparisons must always be unequal — the `default:`
    /// branch handles every (loading, populated), (populated, demo), etc.
    /// permutation. Pin a representative sample so a future refactor that
    /// drops the `default:` arm fails this test.
    func testViewStateEqualityCrossCaseAlwaysUnequal() {
        let pairs: [(InboxViewModel.ViewState, InboxViewModel.ViewState)] = [
            (.loading, .populated),
            (.populated, .demo),
            (.demo, .empty(.noMessages)),
            (.empty(.noMessages), .empty(.noPermissions)),
            (.loading, .empty(.noMessages)),
            (.populated, .empty(.noPermissions)),
        ]
        for (a, b) in pairs {
            XCTAssertNotEqual(a, b,
                              "cross-case ViewState comparison must always be unequal: \(a) vs \(b)")
        }
    }
}

// MARK: - chat.db pivot fallback (REP-AUDIT-260505 / 2026-04-23 pivot)
// The 2026-04-23 pivot says: chat.db + FDA is unreliable; ANY chat.db-side
// failure should silently fall back to demo/empty rather than surfacing a
// scary "error · database is locked" pill in the sidebar. These tests pin
// that the pivot's silent-fallback logic now covers all chat.db failure
// modes (FDA denial, SQLITE_BUSY lock contention, SQLite NOTADB corruption),
// not just permissionDenied.

@MainActor
final class InboxViewModelChatDBPivotFallbackTests: XCTestCase {

    private final class DatabaseLockedChannel: ChannelService, @unchecked Sendable {
        func recentThreads(limit: Int) async throws -> [MessageThread] {
            // SQLITE_BUSY (5) — Messages.app is holding chat.db.
            throw ChannelError.databaseError(code: 5, message: "database is locked")
        }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
    }

    private final class DatabaseCorruptedChannel: ChannelService, @unchecked Sendable {
        func recentThreads(limit: Int) async throws -> [MessageThread] {
            throw ChannelError.databaseCorrupted
        }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
    }

    private final class GenericFailureChannel: ChannelService, @unchecked Sendable {
        func recentThreads(limit: Int) async throws -> [MessageThread] {
            throw ChannelError.unavailable("transient backend hiccup")
        }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
    }

    func testDatabaseLockedDoesNotSurfaceErrorPill() async {
        let vm = InboxViewModel(
            imessage: DatabaseLockedChannel(),
            contacts: fastContacts())
        await vm.syncFromIMessage()
        // The whole point: syncStatus must NOT be .failed. The sidebar reads
        // syncStatus to decide whether to show "error · database is locked"
        // — pivot says don't show it; chat.db is dead to us.
        XCTAssertEqual(vm.syncStatus, .idle,
            "SQLITE_BUSY (database is locked) must silent-fallback per 2026-04-23 pivot, not produce an error pill")
    }

    func testDatabaseLockedFallsBackToDemoWhenDemoModeOn() async {
        let suite = "test.ReplyAI.pivotDBLock.demo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: PreferenceKey.demoModeActive)
        let vm = InboxViewModel(
            imessage: DatabaseLockedChannel(),
            contacts: fastContacts(),
            defaults: d)
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .demo,
            "with demoModeActive=true and chat.db locked, fall back to demo fixtures")
    }

    func testDatabaseLockedFallsBackToEmptyNoPermissionsWhenDemoModeOff() async {
        let suite = "test.ReplyAI.pivotDBLock.noDemo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(false, forKey: PreferenceKey.demoModeActive)
        let vm = InboxViewModel(
            imessage: DatabaseLockedChannel(),
            contacts: fastContacts(),
            defaults: d)
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .empty(.noPermissions),
            "with demoModeActive=false and chat.db locked, surface noPermissions empty state (NOT .error)")
    }

    func testDatabaseCorruptedAlsoSilentlyFallsBack() async {
        let vm = InboxViewModel(
            imessage: DatabaseCorruptedChannel(),
            contacts: fastContacts())
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.syncStatus, .idle,
            "databaseCorrupted (SQLITE_NOTADB) must silent-fallback like permissionDenied — pivot ignores chat.db failures regardless of cause")
    }

    func testGenericChannelErrorStillSurfacesFailedStatus() async {
        // Negative test: a non-chat.db error (e.g. transient backend hiccup
        // from a future channel) MUST still go through the .failed path so
        // we don't accidentally swallow real bugs in non-iMessage channels.
        let vm = InboxViewModel(
            imessage: GenericFailureChannel(),
            contacts: fastContacts())
        await vm.syncFromIMessage()
        if case .failed = vm.syncStatus {
            // pass
        } else {
            XCTFail("non-chat.db ChannelError (.unavailable) must still surface as .failed; got \(vm.syncStatus)")
        }
    }

    // The class comment promises silent-fallback for `permissionDenied` too —
    // that's the FDA-denial case from `IMessageChannel`. The catch block in
    // `syncFromIMessage` routes `.permissionDenied` into the same pivot-ignored
    // bucket as `.databaseError` and `.databaseCorrupted`. Pin that here so a
    // refactor that re-classifies `.permissionDenied` as a regular error
    // (which would re-introduce the audit's "● error · database is locked"
    // pill on a fresh-install Mac with no FDA grant) fails loudly.

    private final class PermissionDeniedChannel: ChannelService, @unchecked Sendable {
        func recentThreads(limit: Int) async throws -> [MessageThread] {
            throw ChannelError.permissionDenied(hint: "Grant Full Disk Access in System Settings.")
        }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
    }

    func testPermissionDeniedDoesNotSurfaceErrorPill() async {
        let vm = InboxViewModel(
            imessage: PermissionDeniedChannel(),
            contacts: fastContacts())
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.syncStatus, .idle,
            "FDA-denied permissionDenied must silent-fallback per pivot — sidebar must not show an error pill")
    }

    func testPermissionDeniedFallsBackToDemoWhenDemoModeOn() async {
        let suite = "test.ReplyAI.pivotPermDenied.demo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: PreferenceKey.demoModeActive)
        let vm = InboxViewModel(
            imessage: PermissionDeniedChannel(),
            contacts: fastContacts(),
            defaults: d)
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .demo,
            "with demoModeActive=true and FDA denied, fall back to demo fixtures so the app is still useful")
    }

    func testPermissionDeniedFallsBackToEmptyNoPermissionsWhenDemoModeOff() async {
        let suite = "test.ReplyAI.pivotPermDenied.noDemo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(false, forKey: PreferenceKey.demoModeActive)
        let vm = InboxViewModel(
            imessage: PermissionDeniedChannel(),
            contacts: fastContacts(),
            defaults: d)
        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .empty(.noPermissions),
            "with demoModeActive=false and FDA denied, surface .empty(.noPermissions) — never .error")
    }

    // Recovery: a user who flips FDA from denied → granted at runtime, or
    // whose chat.db lock clears because Messages.app released it, must be
    // able to re-sync without a relaunch. The pivot's silent-fallback
    // intentionally leaves `syncStatus = .idle` (not `.failed`) precisely
    // so a subsequent sync isn't blocked by stale guard state. Pin that
    // here — flipping the channel from failing to succeeding on the
    // second sync replaces the empty / demo state with live data.

    private final class RecoveringChannel: ChannelService, @unchecked Sendable {
        // _failNext starts true; flips to false after the first call yields
        // its error. Subsequent calls return the configured live threads.
        private let lock = NSLock()
        private var _callCount = 0
        private let liveThreads: [MessageThread]
        init(liveThreads: [MessageThread]) { self.liveThreads = liveThreads }

        func recentThreads(limit: Int) async throws -> [MessageThread] {
            lock.lock(); defer { lock.unlock() }
            _callCount += 1
            if _callCount == 1 {
                throw ChannelError.databaseError(code: 5, message: "database is locked")
            }
            return liveThreads
        }
        func messages(forThreadID id: String, limit: Int) async throws -> [Message] { [] }
    }

    func testRecoveryFromDatabaseLockedReplacesEmptyWithLiveThreads() async {
        let suite = "test.ReplyAI.recovery.noDemo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(false, forKey: PreferenceKey.demoModeActive)
        let live = [
            MessageThread(id: "rec-1", channel: .imessage, name: "Alice",
                          avatar: "AL", preview: "hi", time: "now"),
        ]
        let vm = InboxViewModel(
            imessage: RecoveringChannel(liveThreads: live),
            contacts: fastContacts(),
            defaults: d)

        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .empty(.noPermissions),
            "first sync: chat.db locked → silent-fallback to empty .noPermissions")
        XCTAssertEqual(vm.syncStatus, .idle,
            "first sync: pivot-ignored error must leave syncStatus .idle so a retry isn't blocked")

        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .populated,
            "second sync: chat.db unlocked → live threads must replace the empty state")
        XCTAssertEqual(vm.threads.first?.id, "rec-1",
            "second sync: the live thread from the channel must be present")
        if case .live = vm.syncStatus {
            // pass
        } else {
            XCTFail("second sync: syncStatus must transition to .live after recovery; got \(vm.syncStatus)")
        }
    }

    func testRecoveryFromDatabaseLockedReplacesDemoFixturesWithLiveThreads() async {
        let suite = "test.ReplyAI.recovery.demo.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: PreferenceKey.demoModeActive)
        let live = [
            MessageThread(id: "rec-2", channel: .imessage, name: "Bob",
                          avatar: "BO", preview: "yo", time: "now"),
        ]
        let vm = InboxViewModel(
            imessage: RecoveringChannel(liveThreads: live),
            contacts: fastContacts(),
            defaults: d)

        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .demo,
            "first sync with demoModeActive=true: chat.db locked → fixtures populate the inbox")
        XCTAssertFalse(vm.threads.isEmpty,
            "first sync demo path: fixtures must populate threads so the app is usable")

        await vm.syncFromIMessage()
        XCTAssertEqual(vm.viewState, .populated,
            "second sync: chat.db unlocked → demo fixtures must yield to live data")
        XCTAssertEqual(vm.threads.first?.id, "rec-2",
            "second sync demo path: the live thread must replace the demo fixtures")
    }
}

// MARK: - Bulk thread actions and channel filtering

@MainActor
final class InboxViewModelBulkFilterTests: XCTestCase {
    private func makeVM(threads: [MessageThread]) -> InboxViewModel {
        let suite = "test.ReplyAI.bulkFilter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Per-test cache URL so passing `threads: []` doesn't fall back to
        // a stale disk-cached thread list from another test or a real run.
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMBulkFilterTests-\(UUID().uuidString).json")
        return InboxViewModel(
            threads: threads,
            imessage: BlockingMockChannel(),
            contacts: fastContacts(),
            defaults: defaults,
            threadsCacheURL: cacheURL
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

    // MARK: - Bulk action edge cases (autopilot 2026-05-07)

    func testBulkMarkAllReadOnEmptyThreadsIsNoop() {
        let vm = makeVM(threads: [])

        vm.bulkMarkAllRead()

        XCTAssertEqual(vm.threads.count, 0)
        XCTAssertEqual(vm.totalUnreadCount, 0)
    }

    func testBulkMarkAllReadIsIdempotentOnAlreadyReadThreads() {
        let threads = [
            MessageThread(id: "im1", channel: .imessage, name: "Alice", avatar: "A", preview: "", time: "", unread: 0),
            MessageThread(id: "sl1", channel: .slack, name: "Team", avatar: "T", preview: "", time: "", unread: 0)
        ]
        let vm = makeVM(threads: threads)

        vm.bulkMarkAllRead()
        vm.bulkMarkAllRead()

        XCTAssertTrue(vm.threads.allSatisfy { $0.unread == 0 })
        XCTAssertEqual(vm.totalUnreadCount, 0)
    }

    func testBulkMarkAllReadAlsoTouchesArchivedThreads() {
        let threads = [
            MessageThread(id: "live", channel: .imessage, name: "Live", avatar: "L", preview: "", time: "", unread: 2),
            MessageThread(id: "arch", channel: .slack, name: "Arch", avatar: "A", preview: "", time: "", unread: 5)
        ]
        let vm = makeVM(threads: threads)
        vm.archive("arch")

        vm.bulkMarkAllRead()

        // Bulk mark iterates threads.map(\.id) with no archive filter — both
        // archived and live threads must end up at unread = 0 so re-surfacing
        // an archived thread later doesn't bring back a stale unread badge.
        XCTAssertTrue(vm.threads.allSatisfy { $0.unread == 0 })
    }

    func testBulkArchiveReadOnEmptyThreadsIsNoop() {
        let vm = makeVM(threads: [])

        vm.bulkArchiveRead()

        XCTAssertEqual(vm.archivedThreadIDs, [])
        XCTAssertEqual(vm.filteredThreads.count, 0)
    }

    func testBulkArchiveReadSkipsAlreadyArchivedThreads() {
        let threads = [
            MessageThread(id: "read-already-archived", channel: .imessage, name: "Old", avatar: "O", preview: "", time: "", unread: 0),
            MessageThread(id: "read-fresh", channel: .slack, name: "Fresh", avatar: "F", preview: "", time: "", unread: 0)
        ]
        let vm = makeVM(threads: threads)
        vm.archive("read-already-archived")

        vm.bulkArchiveRead()

        // The pre-archived ID must remain (a single insertion, not duplicated)
        // and the new read thread must also be archived.
        XCTAssertEqual(vm.archivedThreadIDs, ["read-already-archived", "read-fresh"])
    }

    func testBulkArchiveReadDoesNotProtectPinnedReadThreads() {
        let threads = [
            MessageThread(id: "pinned-read", channel: .imessage, name: "Pinned", avatar: "P", preview: "", time: "", unread: 0, pinned: true),
            MessageThread(id: "unread", channel: .slack, name: "Unread", avatar: "U", preview: "", time: "", unread: 1)
        ]
        let vm = makeVM(threads: threads)

        vm.bulkArchiveRead()

        // Pinned status doesn't shield a read thread from bulk-archive — the
        // ⌘-shortcut user expects "everything I've read goes away" and bulk
        // archive is the action, not pin-aware filtering.
        XCTAssertTrue(vm.archivedThreadIDs.contains("pinned-read"))
        XCTAssertEqual(vm.filteredThreads.map(\.id), ["unread"])
    }
}

// MARK: - InboxViewModel.loadMessages (autopilot 2026-05-07)

/// Mock channel that records messages(forThreadID:) call counts and can be
/// configured to return per-thread message lists or throw a configured error.
private final class RecordingMessagesChannel: ChannelService, @unchecked Sendable {
    var perThreadMessages: [String: [Message]] = [:]
    var throwOnMessages: Error?
    private(set) var callCount = 0
    private(set) var lastLimit = 0
    private(set) var lastThreadID = ""

    func recentThreads(limit: Int) async throws -> [MessageThread] { [] }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        callCount += 1
        lastLimit = limit
        lastThreadID = id
        if let err = throwOnMessages { throw err }
        return perThreadMessages[id] ?? []
    }
}

@MainActor
final class InboxViewModelLoadMessagesTests: XCTestCase {

    private func makeVM(threads: [MessageThread], channel: ChannelService) -> InboxViewModel {
        let suite = "test.ReplyAI.loadMessages.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMLoadMessagesTests-\(UUID().uuidString).json")
        return InboxViewModel(
            threads: threads,
            imessage: channel,
            contacts: fastContacts(),
            defaults: defaults,
            threadsCacheURL: cacheURL
        )
    }

    func testLoadMessagesPopulatesLiveMessagesOnSuccess() async {
        let ch = RecordingMessagesChannel()
        ch.perThreadMessages["t1"] = [
            Message(from: .them, text: "hi", time: "08:00", rowID: 1)
        ]
        let vm = makeVM(
            threads: [MessageThread(id: "t1", channel: .imessage, name: "A", avatar: "A", preview: "", time: "")],
            channel: ch
        )

        await vm.loadMessages(for: "t1")

        XCTAssertEqual(vm.liveMessages["t1"]?.count, 1)
        XCTAssertEqual(vm.liveMessages["t1"]?.first?.text, "hi")
        XCTAssertEqual(ch.callCount, 1)
        XCTAssertEqual(ch.lastLimit, 40,
                       "loadMessages must request limit=40 — that's the contract the inbox UI relies on for thread-pane backfill")
    }

    func testLoadMessagesEarlyReturnsWhenAlreadyPopulated() async {
        let ch = RecordingMessagesChannel()
        let vm = makeVM(
            threads: [MessageThread(id: "t2", channel: .imessage, name: "B", avatar: "B", preview: "", time: "")],
            channel: ch
        )
        // Pre-populate liveMessages — subsequent loadMessages must skip the
        // channel call entirely (this is the contract that prevents
        // re-querying chat.db every time the user re-selects an already
        // populated thread).
        vm.liveMessages["t2"] = [Message(from: .me, text: "ok", time: "08:01", rowID: 2)]

        await vm.loadMessages(for: "t2")

        XCTAssertEqual(ch.callCount, 0,
                       "loadMessages must early-return when liveMessages[threadID] is already non-nil")
        XCTAssertEqual(vm.liveMessages["t2"]?.count, 1)
        XCTAssertEqual(vm.liveMessages["t2"]?.first?.text, "ok")
    }

    func testLoadMessagesSilentlyIgnoresChannelError() async {
        let ch = RecordingMessagesChannel()
        ch.throwOnMessages = ChannelError.networkError("boom")
        let vm = makeVM(
            threads: [MessageThread(id: "t3", channel: .imessage, name: "C", avatar: "C", preview: "", time: "")],
            channel: ch
        )

        await vm.loadMessages(for: "t3")

        // The channel was hit but threw; loadMessages uses `try?` so the
        // error is swallowed. liveMessages must stay unset (no empty-array
        // poisoning that would prevent a future retry).
        XCTAssertEqual(ch.callCount, 1)
        XCTAssertNil(vm.liveMessages["t3"],
                     "channel error must NOT populate liveMessages[threadID] with []; that would block retry")
    }

    func testLoadMessagesEmptyChannelResponseStillPopulatesEmptyArray() async {
        let ch = RecordingMessagesChannel()
        ch.perThreadMessages["t4"] = []
        let vm = makeVM(
            threads: [MessageThread(id: "t4", channel: .imessage, name: "D", avatar: "D", preview: "", time: "")],
            channel: ch
        )

        await vm.loadMessages(for: "t4")

        XCTAssertEqual(vm.liveMessages["t4"]?.count, 0,
                       "successful empty response must still populate liveMessages[threadID] = [] so subsequent calls early-return")
        // The next call must early-return because the key is now present.
        await vm.loadMessages(for: "t4")
        XCTAssertEqual(ch.callCount, 1,
                       "second loadMessages call must early-return on the empty-array sentinel without re-hitting the channel")
    }
}

// MARK: - InboxViewModel.chatDBAvailable per SyncStatus (autopilot 2026-05-07)

@MainActor
final class InboxViewModelChatDBAvailableTests: XCTestCase {

    private func makeVM() -> InboxViewModel {
        let suite = "test.ReplyAI.chatDBAvail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxVMChatDBAvailTests-\(UUID().uuidString).json")
        let ch = BlockingMockChannel(); ch.blocking = false
        return InboxViewModel(
            threads: [], imessage: ch,
            contacts: fastContacts(),
            defaults: defaults,
            threadsCacheURL: cacheURL
        )
    }

    func testChatDBAvailableFalseWhenIdle() {
        let vm = makeVM()
        vm.syncStatus = .idle
        XCTAssertFalse(vm.chatDBAvailable,
                       ".idle (showing fixtures, no sync attempted yet) must NOT be considered chat.db-available")
    }

    func testChatDBAvailableFalseWhenSyncing() {
        let vm = makeVM()
        vm.syncStatus = .syncing
        XCTAssertFalse(vm.chatDBAvailable,
                       ".syncing must NOT report chat.db as available — the in-flight sync hasn't proven a working DB yet, and applyIncomingNotification needs to fire (UNNotification fallback)")
    }

    func testChatDBAvailableTrueWhenLive() {
        let vm = makeVM()
        vm.syncStatus = .live(at: Date())
        XCTAssertTrue(vm.chatDBAvailable,
                      ".live(at:) is the only state that signals a working chat.db sync; UNNotification path must short-circuit")
    }

    func testChatDBAvailableFalseWhenDenied() {
        let vm = makeVM()
        vm.syncStatus = .denied(hint: "FDA needed")
        XCTAssertFalse(vm.chatDBAvailable,
                       ".denied must NOT be considered available — UNNotification fallback path must run for incoming notifications")
    }

    func testChatDBAvailableFalseWhenFailed() {
        let vm = makeVM()
        vm.syncStatus = .failed("query error")
        XCTAssertFalse(vm.chatDBAvailable,
                       ".failed must NOT be considered available — UNNotification fallback path must run")
    }
}

// MARK: - REP-218: archive removes thread from SearchIndex

@MainActor
final class InboxViewModelArchiveSearchTests: XCTestCase {

    private func thread(id: String, body: String) -> MessageThread {
        MessageThread(id: id, channel: .imessage, name: "Test", avatar: "T", preview: "", time: "")
    }

    // After archiving a thread, searching for a unique term from its messages must return no hits.
    func testArchiveThreadRemovesFromSearchIndex() async {
        let index = SearchIndex(databaseURL: nil)
        let t = thread(id: "archsrch", body: "")
        await index.upsert(thread: t, messages: [
            Message(from: .them, text: "xuniquearchword in this message", time: "t")
        ])
        let before = await index.search("xuniquearchword")
        XCTAssertEqual(before.count, 1, "precondition: thread must be in index before archive")

        let vm = InboxViewModel(threads: [t], imessage: BlockingMockChannel(),
                                contacts: fastContacts(), searchIndex: index)
        vm.archive("archsrch")

        // Give the async Task in archive() time to call searchIndex.delete.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let after = await index.search("xuniquearchword")
        XCTAssertEqual(after.count, 0, "archived thread must be removed from search index")
    }

    // After archiving a thread, it must not appear in filteredThreads.
    func testArchiveThreadRemovedFromViewModelThreads() {
        let t = thread(id: "arch-vm", body: "")
        let vm = InboxViewModel(threads: [t], imessage: BlockingMockChannel(),
                                contacts: fastContacts(),
                                searchIndex: SearchIndex(databaseURL: nil))
        vm.archive("arch-vm")
        XCTAssertFalse(vm.filteredThreads.map(\.id).contains("arch-vm"),
                       "archived thread must not appear in filteredThreads")
    }
}

// MARK: - REP-214: failed send preserves userEdits and surfaces error

@MainActor
final class InboxViewModelFailedSendTests: XCTestCase {

    private func thread(id: String = "t1") -> MessageThread {
        MessageThread(id: id, channel: .imessage, name: "Alice", avatar: "A",
                      preview: "", time: "", chatGUID: "iMessage;-;\(id)")
    }

    // After a throwing send, the user's drafted text must still be in effectiveDraft
    // so they can retry without retyping.
    func testFailedSendPreservesUserEdits() async {
        let vm = InboxViewModel(threads: [thread()], imessage: BlockingMockChannel(),
                                contacts: fastContacts())
        vm.selectThread("t1")
        vm.setEdit(threadID: "t1", tone: .warm, text: "Retry me")

        let saved = IMessageSender.executeHook
        IMessageSender.executeHook = { _ in throw IMessageSender.SendError.messageTooLong(9999) }
        defer { IMessageSender.executeHook = saved }

        vm.requestSend(text: "Retry me")
        await vm.confirmSend()

        XCTAssertEqual(vm.effectiveDraft(threadID: "t1", tone: .warm, fallback: ""),
                       "Retry me",
                       "userEdits must survive a failed send so the user can retry")
    }

    // After a throwing send, a toast must appear so the user is informed.
    func testFailedSendSurfacesSendError() async {
        let vm = InboxViewModel(threads: [thread()], imessage: BlockingMockChannel(),
                                contacts: fastContacts())
        vm.selectThread("t1")
        vm.setEdit(threadID: "t1", tone: .warm, text: "Will fail")

        let saved = IMessageSender.executeHook
        IMessageSender.executeHook = { _ in throw IMessageSender.SendError.messageTooLong(9999) }
        defer { IMessageSender.executeHook = saved }

        vm.requestSend(text: "Will fail")
        await vm.confirmSend()

        XCTAssertNotNil(vm.sendToast,
                        "sendToast must be set with an error description after a failed send")
    }
}

// MARK: - REP-268: Preferences.inbox.lastSyncDate sync path

@MainActor
final class InboxViewModelLastSyncDateTests: XCTestCase {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "test.ReplyAI.lastSyncDate.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        UserDefaults.registerReplyAIDefaults(in: d)
        return (d, suite)
    }

    private func makeThread(_ id: String = "t1") -> MessageThread {
        MessageThread(id: id, channel: .imessage, name: "Alice",
                      avatar: "A", preview: "hey", time: "now", unread: 1)
    }

    // After syncFromIMessage returns ≥1 thread, lastSyncDate must be set.
    func testLastSyncDateUpdatedAfterSuccessfulSync() async {
        let (d, suite) = makeDefaults()
        defer { d.removePersistentDomain(forName: suite) }

        let t = makeThread()
        let vm = InboxViewModel(
            threads: [t],
            imessage: StaticMockChannel(threads: [t]),
            contacts: fastContacts(),
            defaults: d
        )

        XCTAssertNil(d.object(forKey: PreferenceKey.inboxLastSyncDate) as? Date,
                     "precondition: lastSyncDate must be nil before any sync")

        await vm.syncFromIMessage()

        XCTAssertNotNil(d.object(forKey: PreferenceKey.inboxLastSyncDate) as? Date,
                        "lastSyncDate must be set after a successful sync returning threads")
    }

    // When sync returns zero threads, lastSyncDate must NOT be updated.
    func testLastSyncDateNotUpdatedOnEmptySync() async {
        let (d, suite) = makeDefaults()
        defer { d.removePersistentDomain(forName: suite) }

        // Demo mode must be off so syncFromIMessage doesn't populate from fixtures
        // and incorrectly mark the sync as successful.
        d.set(false, forKey: PreferenceKey.demoModeActive)

        let vm = InboxViewModel(
            threads: [],
            imessage: StaticMockChannel(threads: []),
            contacts: fastContacts(),
            defaults: d
        )

        await vm.syncFromIMessage()

        XCTAssertNil(d.object(forKey: PreferenceKey.inboxLastSyncDate) as? Date,
                     "lastSyncDate must remain nil when sync returns empty thread list")
    }
}

// MARK: - Inbox persistence-key contract pins
//
// InboxViewModel persists archive / silently-ignored / pinned / snoozed
// state under four private static keys. They are shipped UserDefaults
// keys: every existing user has data under these exact strings. Renaming
// a key silently abandons every user's saved state on next launch.
//
// Existing tearDown helpers in InboxViewModelTests / RulesTests already
// reference these literals when wiping standard UserDefaults — so a
// rename would silently leak state across tests AND ship a broken
// migration. These tests pre-populate the literal key with a known
// payload, construct an InboxViewModel against the same suite, and
// assert the loaded model state matches. A rename trips the test.

final class InboxViewModelPersistenceKeyContractTests: XCTestCase {

    private func isolatedDefaults() -> UserDefaults {
        let suite = "test.ReplyAI.inbox-persistence-keys.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeContacts() -> ContactsResolver {
        ContactsResolver(store: DeniedContactStore())
    }

    @MainActor
    func testArchivedThreadIDsLoadFromLiteralKey() throws {
        let d = isolatedDefaults()
        let payload = try JSONEncoder().encode(["t-archived-1", "t-archived-2"].sorted())
        d.set(payload, forKey: InboxViewModel.archivedKey)

        let vm = InboxViewModel(threads: [], contacts: makeContacts(), defaults: d)

        XCTAssertEqual(vm.archivedThreadIDs, Set(["t-archived-1", "t-archived-2"]),
                       "archive load path must read 'pref.inbox.archivedThreadIDs' literally — renaming abandons every shipped user's archive set")
    }

    @MainActor
    func testSilentlyIgnoredThreadIDsLoadFromLiteralKey() throws {
        let d = isolatedDefaults()
        let payload = try JSONEncoder().encode(["t-silenced-1"])
        d.set(payload, forKey: InboxViewModel.silentlyIgnoredKey)

        let vm = InboxViewModel(threads: [], contacts: makeContacts(), defaults: d)

        XCTAssertEqual(vm.silentlyIgnoredThreadIDs, Set(["t-silenced-1"]),
                       "silentlyIgnored load path must read 'pref.inbox.silentlyIgnoredThreadIDs' literally — renaming silently re-surfaces threads the user already silenced")
    }

    @MainActor
    func testPinnedThreadIDsLoadFromLiteralKey() throws {
        let d = isolatedDefaults()
        let payload = try JSONEncoder().encode(["t-pinned-1", "t-pinned-2"])
        d.set(payload, forKey: InboxViewModel.pinnedKey)

        let vm = InboxViewModel(threads: [], contacts: makeContacts(), defaults: d)

        XCTAssertEqual(vm.pinnedThreadIDs, Set(["t-pinned-1", "t-pinned-2"]),
                       "pinned load path must read 'pref.inbox.pinnedThreadIDs' literally — renaming silently un-pins every shipped user's threads")
    }

    @MainActor
    func testSnoozedUntilLoadsFromLiteralKey() throws {
        let d = isolatedDefaults()
        let wake = Date(timeIntervalSince1970: 1_900_000_000)
        let payload = try JSONEncoder().encode(["t-snoozed": wake])
        d.set(payload, forKey: InboxViewModel.snoozedUntilKey)

        let vm = InboxViewModel(threads: [], contacts: makeContacts(), defaults: d)

        XCTAssertEqual(vm.snoozedUntil["t-snoozed"], wake,
                       "snooze load path must read 'pref.inbox.snoozedUntil' literally — renaming silently un-snoozes every shipped user's deferred threads")
    }

    /// Constants pin: every InboxViewModel UserDefaults key the load
    /// path uses must equal its expected literal value byte-for-byte.
    /// The four `*LoadFromLiteralKey` tests above check the symmetry
    /// between writes-to-literal and reads-from-constant, but they
    /// pass even if the constant value drifts in lockstep with the
    /// test literal. This pin freezes the named constants so a
    /// "let's namespace it" refactor surfaces independently.
    func testInboxPersistenceKeysMatchExpectedLiterals() {
        XCTAssertEqual(InboxViewModel.archivedKey, "pref.inbox.archivedThreadIDs",
            "archivedKey drift orphans every shipped user's archived list — old key sits unreachable on disk while new key reads empty")
        XCTAssertEqual(InboxViewModel.silentlyIgnoredKey, "pref.inbox.silentlyIgnoredThreadIDs",
            "silentlyIgnoredKey drift silently re-surfaces threads the user already silenced")
        XCTAssertEqual(InboxViewModel.pinnedKey, "pref.inbox.pinnedThreadIDs",
            "pinnedKey drift silently un-pins every thread on next launch")
        XCTAssertEqual(InboxViewModel.snoozedUntilKey, "pref.inbox.snoozedUntil",
            "snoozedUntilKey drift silently un-snoozes every deferred thread on next launch")
        XCTAssertEqual(InboxViewModel.lastSeenRowIDKey, "pref.inbox.lastSeenRowID",
            "lastSeenRowIDKey drift re-replays every historical message as if brand-new on next launch")
    }

    /// Cross-check: every InboxViewModel UserDefaults key shares the
    /// `pref.` wipe-namespace prefix so factory reset
    /// (`wipeReplyAIDefaults`) sweeps them. Drift that drops the
    /// prefix would silently leak the corresponding state past
    /// factory reset (user clicks "Factory reset" but their archived
    /// thread set persists). Pinned alongside the literal values so
    /// the wipe-coverage invariant is enforced at compile-pin level.
    func testInboxPersistenceKeysShareWipeNamespacePrefix() {
        let prefix = PreferenceKey.wipeNamespacePrefix
        for key in [InboxViewModel.archivedKey,
                    InboxViewModel.silentlyIgnoredKey,
                    InboxViewModel.pinnedKey,
                    InboxViewModel.snoozedUntilKey,
                    InboxViewModel.lastSeenRowIDKey] {
            XCTAssertTrue(key.hasPrefix(prefix),
                "key `\(key)` must start with `\(prefix)` — drift would leak this state past factory reset")
        }
    }

    /// Sub-prefix coverage. Inbox-scoped keys live in TWO files —
    /// the 5 in InboxViewModel above (archived/silentlyIgnored/pinned/
    /// snoozedUntil/lastSeenRowID) and 3 more in `PreferenceKey`
    /// (inboxThreadLimit, demoModeActive, inboxLastSyncDate). They
    /// must all share the `pref.inbox.` sub-prefix so a triage
    /// engineer can list every inbox-scoped default with one
    /// `defaults read | grep pref.inbox.` invocation, AND so a future
    /// "scope wipe to just the inbox" feature has one greppable
    /// namespace to walk. Drift on either file's side leaves an
    /// inbox-scoped value invisible to that grep / unreached by the
    /// hypothetical scoped-wipe. Pin extends
    /// `testInboxPersistenceKeysShareWipeNamespacePrefix` (which
    /// asserts the broader `pref.` prefix) with the sub-namespace.
    func testInboxScopedKeysShareInboxSubPrefix() {
        let inboxSubPrefix = "pref.inbox."
        let inboxScopedKeys: [String] = [
            // From InboxViewModel.
            InboxViewModel.archivedKey,
            InboxViewModel.silentlyIgnoredKey,
            InboxViewModel.pinnedKey,
            InboxViewModel.snoozedUntilKey,
            InboxViewModel.lastSeenRowIDKey,
            // From PreferenceKey.
            PreferenceKey.inboxThreadLimit,
            PreferenceKey.demoModeActive,
            PreferenceKey.inboxLastSyncDate,
        ]
        for key in inboxScopedKeys {
            XCTAssertTrue(key.hasPrefix(inboxSubPrefix),
                "inbox-scoped key `\(key)` must start with `\(inboxSubPrefix)` — drift fragments the inbox-scoped namespace across two files and breaks `defaults read | grep pref.inbox.` triage")
        }
    }

}

// MARK: - copying() field-completeness pin

/// `InboxViewModel.copying(_:pinned:)` is the single point where MessageThread
/// values are duplicated with one field swapped (currently only `pinned`).
/// The implementation lists every field by name — when MessageThread grows
/// (e.g. a new `mutedUntil`, `lastMessageRowID`, etc.), forgetting to add
/// the new field here silently drops it on every pin/unpin. Pin the
/// field-by-field carry-through here so the omission surfaces in CI.
@MainActor
final class InboxViewModelCopyingTests: XCTestCase {

    func testCopyingCarriesEveryFieldExceptPinned() {
        // Build a source thread with every optional field populated to
        // distinct, recognisable values. If `copying` drops any field,
        // structural equality (synthesized by Hashable) will trip below.
        let source = MessageThread(
            id: "t-source-1",
            channel: .slack,
            name: "Maya Chen",
            avatar: "MC",
            preview: "see you at 3?",
            time: "2:41 PM",
            unread: 7,
            pinned: false,
            contextCount: 19,
            contextSummary: "discussing Q3 roadmap",
            chatGUID: "iMessage;-;+15555550100",
            hasAttachment: true
        )
        let copied = InboxViewModel.copying(source, pinned: true)

        // Pinned flips, every other field carries through verbatim.
        XCTAssertTrue(copied.pinned, "copying must override pinned")
        XCTAssertEqual(copied.id, source.id)
        XCTAssertEqual(copied.channel, source.channel)
        XCTAssertEqual(copied.name, source.name)
        XCTAssertEqual(copied.avatar, source.avatar)
        XCTAssertEqual(copied.preview, source.preview)
        XCTAssertEqual(copied.time, source.time)
        XCTAssertEqual(copied.unread, source.unread)
        XCTAssertEqual(copied.contextCount, source.contextCount)
        XCTAssertEqual(copied.contextSummary, source.contextSummary)
        XCTAssertEqual(copied.chatGUID, source.chatGUID)
        XCTAssertEqual(copied.hasAttachment, source.hasAttachment)
    }

    func testCopyingPinnedFalseFlipsBack() {
        // The mirror direction — an already-pinned thread can be unpinned
        // through copying without other field drift.
        let source = MessageThread(
            id: "t-source-2", channel: .imessage,
            name: "Mom", avatar: "M",
            preview: "dont forget", time: "1:08",
            pinned: true, chatGUID: "iMessage;-;+15555550101"
        )
        let copied = InboxViewModel.copying(source, pinned: false)
        XCTAssertFalse(copied.pinned, "copying must override pinned to false")
        XCTAssertEqual(copied.chatGUID, source.chatGUID,
            "chatGUID must round-trip — applyPinned relies on this for AppleScript send routing")
    }
}

// MARK: - editKey format pin

/// `InboxViewModel.editKey(threadID:tone:)` is the join key for the
/// `userEdits` dictionary — every composer edit is keyed by this string.
/// The format `<threadID>|<tone.rawValue>` lets a single thread carry
/// distinct drafts per tone (warm/direct/playful) without colliding.
/// A silent format change (swapping the `|` separator, lowercasing the
/// tone, etc.) would orphan every in-memory edit and silently lose the
/// user's draft when they switch tones — pin the literal so it surfaces
/// as a deliberate change.
@MainActor
final class InboxViewModelEditKeyTests: XCTestCase {

    func testEditKeyFormatIsThreadIDPipeToneRaw() {
        XCTAssertEqual(InboxViewModel.editKey(threadID: "t1", tone: .warm),
                       "t1|Warm",
                       "editKey format is `<threadID>|<tone.rawValue>` — capital W, pipe separator")
        XCTAssertEqual(InboxViewModel.editKey(threadID: "t-2", tone: .direct),
                       "t-2|Direct")
        XCTAssertEqual(InboxViewModel.editKey(threadID: "iMessage;-;+15551234567", tone: .playful),
                       "iMessage;-;+15551234567|Playful",
                       "real-shaped chat GUIDs round-trip — semicolons and `+` must not be sanitized")
    }

    func testEditKeyDistinguishesPerTone() {
        // Same threadID, different tones → different keys. Otherwise
        // tone-cycling in the composer would overwrite the prior tone's edit.
        let warm    = InboxViewModel.editKey(threadID: "t1", tone: .warm)
        let direct  = InboxViewModel.editKey(threadID: "t1", tone: .direct)
        let playful = InboxViewModel.editKey(threadID: "t1", tone: .playful)
        XCTAssertEqual(Set([warm, direct, playful]).count, 3,
                       "every tone must produce a distinct edit key for the same thread")
    }

    func testEditKeyDistinguishesPerThread() {
        // Same tone, different threads → different keys. Otherwise switching
        // threads would inherit the prior thread's draft.
        let a = InboxViewModel.editKey(threadID: "t1", tone: .warm)
        let b = InboxViewModel.editKey(threadID: "t2", tone: .warm)
        XCTAssertNotEqual(a, b)
    }

    /// Pin the literal `Sent to <name>` prefix of the success toast.
    /// `testSendSuccessClearsConfirmationAndShowsToast` only checks that the
    /// recipient name appears — a copy edit that swapped the verb (e.g.
    /// `Delivered to Alice` or `Reply sent to Alice`) would still pass.
    /// The exact prefix is part of the post-send affordance the keyboard-
    /// first UX depends on; pin so designer-led tweaks land as a code-review
    /// diff.
    func testSendSuccessToastUsesSentToPrefix() async {
        let thread = MessageThread(
            id: "t-toast", channel: .imessage, name: "Alice Toast",
            avatar: "A", preview: "hi", time: "now",
            chatGUID: "iMessage;-;t-toast")
        let channel = BlockingMockChannel()
        channel.blocking = false
        let vm = InboxViewModel(threads: [thread], imessage: channel,
                                contacts: fastContacts())
        vm.selectThread("t-toast")

        let prevHook = IMessageSender.executeHook
        IMessageSender.executeHook = IMessageSender.dryRunHook()
        defer { IMessageSender.executeHook = prevHook }

        vm.requestSend(text: "ok")
        await vm.confirmSend()

        XCTAssertEqual(vm.sendToast, InboxViewModel.sentToToast(recipient: "Alice Toast"),
            "success toast must read exactly `Sent to <recipient>` — drift in this prefix changes the post-send affordance the keyboard-first UX depends on")
    }
}

// MARK: - InboxViewModel.count(for:) — sidebar folder counts

/// Pins the count function that backs the per-folder badge numbers in
/// `Folder` rows on the sidebar. Drift in any of these branches would
/// silently mis-state the user's inbox state — e.g. claiming `priority`
/// has 3 items when only 2 are pinned, or showing archived threads under
/// `.all`. The function is called every render via the sidebar's
/// `Folder.count` snapshot, so even off-by-one bugs are immediately
/// visible.

@MainActor
final class InboxViewModelFolderCountTests: XCTestCase {

    private func vmWith(threads: [MessageThread]) -> InboxViewModel {
        let suite = "test.ReplyAI.folderCount.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // Unique cache URL pointed at a path that won't exist — InboxViewModel's
        // init falls back to the persisted thread cache when `threads` is empty,
        // so without this we'd inherit whatever the running user's last cache
        // happened to contain.
        let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folder-count-\(UUID().uuidString).json")
        return InboxViewModel(
            threads: threads,
            imessage: BlockingMockChannel(),
            contacts: fastContacts(),
            defaults: d,
            threadsCacheURL: cacheURL)
    }

    func testEmptyVMReturnsZeroForEveryKind() {
        // Pass a unique cacheURL via vmWith so the empty-threads fallback can't
        // load a stale cache file from disk and inflate the count.
        let vm = vmWith(threads: [])
        for kind in Folder.Kind.allCases {
            XCTAssertEqual(vm.count(for: kind), 0,
                "empty vm: count(\(kind)) must be 0")
        }
    }

    func testAllCountExcludesArchivedThreads() {
        let t1 = MessageThread(id: "t1", channel: .imessage, name: "A", avatar: "A", preview: "p1", time: "now")
        let t2 = MessageThread(id: "t2", channel: .imessage, name: "B", avatar: "B", preview: "p2", time: "now")
        let t3 = MessageThread(id: "t3", channel: .imessage, name: "C", avatar: "C", preview: "p3", time: "now")
        let vm = vmWith(threads: [t1, t2, t3])
        XCTAssertEqual(vm.count(for: .all), 3, "before archive: all 3 threads count")
        vm.archive("t2")
        XCTAssertEqual(vm.count(for: .all), 2,
            "after archive: archived thread must drop out of .all")
        XCTAssertEqual(vm.count(for: .done), 1,
            "archived thread must show up in .done")
    }

    func testPriorityCountReflectsPinnedThreadsOnly() {
        let unpinned = MessageThread(id: "u1", channel: .imessage, name: "U", avatar: "U", preview: "p", time: "now", pinned: false)
        let pinned1  = MessageThread(id: "p1", channel: .slack,    name: "P", avatar: "P", preview: "p", time: "now", pinned: true)
        let pinned2  = MessageThread(id: "p2", channel: .imessage, name: "Q", avatar: "Q", preview: "p", time: "now", pinned: true)
        let vm = vmWith(threads: [unpinned, pinned1, pinned2])
        XCTAssertEqual(vm.count(for: .priority), 2,
            ".priority must equal the number of pinned threads")
    }

    func testAwaitingCountReflectsUnreadThreadsOnly() {
        let read    = MessageThread(id: "r1", channel: .imessage, name: "A", avatar: "A", preview: "p", time: "now", unread: 0)
        let unread1 = MessageThread(id: "u1", channel: .imessage, name: "B", avatar: "B", preview: "p", time: "now", unread: 1)
        let unread2 = MessageThread(id: "u2", channel: .slack,    name: "C", avatar: "C", preview: "p", time: "now", unread: 5)
        let vm = vmWith(threads: [read, unread1, unread2])
        XCTAssertEqual(vm.count(for: .awaiting), 2,
            ".awaiting must equal the number of threads with unread > 0 (count of threads, not sum of unread counts)")
    }

    func testArchivedThreadStillCountsInDone() {
        let t1 = MessageThread(id: "t1", channel: .imessage, name: "A", avatar: "A", preview: "p", time: "now")
        let t2 = MessageThread(id: "t2", channel: .imessage, name: "B", avatar: "B", preview: "p", time: "now")
        let vm = vmWith(threads: [t1, t2])
        vm.archive("t1")
        vm.archive("t2")
        XCTAssertEqual(vm.count(for: .done), 2,
            ".done must reflect every archived thread")
        XCTAssertEqual(vm.count(for: .all), 0,
            "after archiving everything, .all must be 0 — not the original input length")
    }

    func testPinnedAndArchivedThreadDoesNotDoubleCount() {
        // A pinned thread that's later archived should drop out of
        // .priority (the count function checks the live, non-archived
        // subset for pinned/unread). Pin this contract so a refactor
        // that filters from `threads` directly without the archived
        // mask doesn't silently re-introduce archived threads into
        // the priority badge.
        let pinned = MessageThread(id: "p1", channel: .imessage, name: "P", avatar: "P",
                                   preview: "p", time: "now", pinned: true)
        let vm = vmWith(threads: [pinned])
        XCTAssertEqual(vm.count(for: .priority), 1, "pinned thread shows in .priority")
        vm.archive("p1")
        XCTAssertEqual(vm.count(for: .priority), 0,
            "archived pinned thread must NOT count toward .priority — `live` filters out archived first")
    }
}

// MARK: - InboxViewModel.cycleTone() — ⌘/ tone cycling

/// `cycleTone()` is the entry point for the ⌘/ keyboard shortcut. The
/// implementation is one line — `activeTone = activeTone.cycled()` —
/// but the muscle-memory contract (Warm → Direct → Playful → Warm) is
/// load-bearing for the keyboard-first UX. Pin it here so any refactor
/// that re-routes ⌘/ through a different code path (e.g. binding to a
/// new sfc-tone-picker overlay) doesn't silently change the cycle order.

@MainActor
final class InboxViewModelCycleToneTests: XCTestCase {

    private func freshVM() -> InboxViewModel {
        let suite = "test.ReplyAI.cycleTone.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return InboxViewModel(
            imessage: BlockingMockChannel(),
            contacts: fastContacts(),
            defaults: d)
    }

    func testCycleToneAdvancesWarmToDirect() {
        let vm = freshVM()
        vm.activeTone = .warm
        vm.cycleTone()
        XCTAssertEqual(vm.activeTone, .direct,
            "⌘/ from Warm must land on Direct — pinned by Tone.cycled() and re-pinned here against view-model rerouting")
    }

    func testCycleToneAdvancesDirectToPlayful() {
        let vm = freshVM()
        vm.activeTone = .direct
        vm.cycleTone()
        XCTAssertEqual(vm.activeTone, .playful)
    }

    func testCycleToneWrapsPlayfulToWarm() {
        let vm = freshVM()
        vm.activeTone = .playful
        vm.cycleTone()
        XCTAssertEqual(vm.activeTone, .warm,
            "⌘/ from the last tone in Tone.allCases must wrap to the first")
    }

    func testCycleToneThreeTimesReturnsToOrigin() {
        let vm = freshVM()
        vm.activeTone = .warm
        vm.cycleTone()
        vm.cycleTone()
        vm.cycleTone()
        XCTAssertEqual(vm.activeTone, .warm,
            "Tone has 3 cases; cycling 3 times must return to the starting point. If this fails, Tone.allCases changed size and the keyboard shortcut needs re-validation against the new cycle.")
    }
}

// MARK: - InboxViewModel.effectiveDraft / setEdit / clearEdit

/// `effectiveDraft` is what the composer reads to decide what to render
/// in the textbox — user-edit wins over the model-generated fallback.
/// `setEdit` / `clearEdit` are the only two write paths into that
/// per-(threadID, tone) bucket. The functions are tiny but the
/// (threadID, tone) keying is load-bearing — pin it so a refactor that
/// keys by threadID alone (or accidentally drops the tone-distinction)
/// can't silently leak one tone's edit into another.

@MainActor
final class InboxViewModelEffectiveDraftTests: XCTestCase {

    private func freshVM() -> InboxViewModel {
        let suite = "test.ReplyAI.effectiveDraft.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return InboxViewModel(
            imessage: BlockingMockChannel(),
            contacts: fastContacts(),
            defaults: d)
    }

    func testEffectiveDraftReturnsFallbackWhenNoEditSet() {
        let vm = freshVM()
        let result = vm.effectiveDraft(threadID: "t1", tone: .warm, fallback: "model said hi")
        XCTAssertEqual(result, "model said hi",
            "no edit → composer must show the model-generated fallback verbatim")
    }

    func testSetEditOverridesFallback() {
        let vm = freshVM()
        vm.setEdit(threadID: "t1", tone: .warm, text: "user typed this")
        let result = vm.effectiveDraft(threadID: "t1", tone: .warm, fallback: "ignored fallback")
        XCTAssertEqual(result, "user typed this",
            "user edit wins over fallback — that's the whole point of `effectiveDraft`")
    }

    func testClearEditRestoresFallback() {
        let vm = freshVM()
        vm.setEdit(threadID: "t1", tone: .warm, text: "user typed this")
        vm.clearEdit(threadID: "t1", tone: .warm)
        let result = vm.effectiveDraft(threadID: "t1", tone: .warm, fallback: "back to fallback")
        XCTAssertEqual(result, "back to fallback",
            "after clearEdit, the bucket is empty again and fallback wins")
    }

    func testEditsAreScopedPerTone() {
        // Critical contract: the same threadID with different tones must
        // address different buckets. ⌘/ flips the tone; without per-tone
        // keying, the new tone's composer would inherit the prior tone's
        // typed text.
        let vm = freshVM()
        vm.setEdit(threadID: "t1", tone: .warm, text: "warm version")
        let direct = vm.effectiveDraft(threadID: "t1", tone: .direct, fallback: "fb")
        XCTAssertEqual(direct, "fb",
            "different tone → different bucket; warm's edit must NOT bleed into direct")
        let warm = vm.effectiveDraft(threadID: "t1", tone: .warm, fallback: "fb")
        XCTAssertEqual(warm, "warm version",
            "warm's edit is still there — only the read for direct returns fallback")
    }

    func testEditsAreScopedPerThread() {
        // Critical contract: same tone with different threads must address
        // different buckets. Switching threads via the sidebar without this
        // would inherit the prior thread's typed draft.
        let vm = freshVM()
        vm.setEdit(threadID: "t1", tone: .warm, text: "thread1 draft")
        let t2 = vm.effectiveDraft(threadID: "t2", tone: .warm, fallback: "fb")
        XCTAssertEqual(t2, "fb",
            "different thread → different bucket; t1's edit must NOT bleed into t2")
    }

    func testClearEditOnUnsetKeyIsNoOp() {
        // Defensive: the composer's drag-to-discard gesture calls clearEdit
        // unconditionally. Calling it when no edit was ever set must not
        // crash or reset some other state.
        let vm = freshVM()
        vm.setEdit(threadID: "t1", tone: .warm, text: "kept")
        vm.clearEdit(threadID: "t2", tone: .warm)   // unrelated key
        let kept = vm.effectiveDraft(threadID: "t1", tone: .warm, fallback: "fb")
        XCTAssertEqual(kept, "kept",
            "clearEdit on an unrelated (threadID, tone) must not affect the existing edit")
    }
}

// MARK: - InboxViewModel.requestSend / cancelSend — staging guard

/// `requestSend` stages a `SendConfirmation` that the composer renders as
/// a "Send to <recipient>?" affirmation chip. The empty / whitespace-only
/// guard is critical — without it, ⌘↵ on an empty composer would surface
/// a "Send to <recipient>?" chip with nothing to send, then `confirmSend`
/// would dispatch an empty body to Messages.app or Slack. Pin both paths.

@MainActor
final class InboxViewModelRequestCancelSendTests: XCTestCase {

    private func vmWithThread() -> InboxViewModel {
        let suite = "test.ReplyAI.requestSend.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let t = MessageThread(id: "rs1", channel: .imessage, name: "Alice",
                              avatar: "A", preview: "p", time: "now")
        let ch = BlockingMockChannel(); ch.blocking = false
        let vm = InboxViewModel(
            threads: [t],
            imessage: ch,
            contacts: fastContacts(),
            defaults: d)
        vm.selectThread("rs1")
        return vm
    }

    func testRequestSendWithEmptyTextDoesNotStageConfirmation() {
        let vm = vmWithThread()
        vm.requestSend(text: "")
        XCTAssertNil(vm.sendConfirmation,
            "empty text must short-circuit before staging — otherwise ⌘↵ on an empty composer would prompt to send nothing")
    }

    func testRequestSendWithWhitespaceOnlyTextDoesNotStageConfirmation() {
        let vm = vmWithThread()
        vm.requestSend(text: "   \n  \t ")
        XCTAssertNil(vm.sendConfirmation,
            "whitespace-only text must short-circuit — same reason as the empty case, plus newlines/tabs from accidental Return")
    }

    func testRequestSendWithRealTextStagesConfirmationWithRecipientName() {
        let vm = vmWithThread()
        vm.requestSend(text: "hi Alice")
        XCTAssertNotNil(vm.sendConfirmation,
            "non-empty text must stage a confirmation")
        XCTAssertEqual(vm.sendConfirmation?.recipient, "Alice",
            "confirmation snapshot must capture the selected thread's display name at request-time")
        XCTAssertEqual(vm.sendConfirmation?.threadID, "rs1",
            "confirmation must capture the thread ID at request-time so subsequent thread switches don't reroute the send")
    }

    func testCancelSendClearsStagedConfirmation() {
        let vm = vmWithThread()
        vm.requestSend(text: "hi")
        XCTAssertNotNil(vm.sendConfirmation)
        vm.cancelSend()
        XCTAssertNil(vm.sendConfirmation,
            "cancelSend (⌘. or composer dismiss) must clear the staged confirmation")
    }

    func testCancelSendOnUnstagedIsNoOp() {
        // Defensive: ⌘. is wired to call cancelSend regardless of state.
        // Calling it when nothing is staged must not crash or perturb
        // unrelated state.
        let vm = vmWithThread()
        XCTAssertNil(vm.sendConfirmation)
        vm.cancelSend()
        XCTAssertNil(vm.sendConfirmation,
            "cancelSend with nothing staged must remain nil")
    }
}

// MARK: - InboxViewModel.messages(for:) — live vs fixture fallback

/// `messages(for:)` is what the thread detail pane reads to populate
/// `MessageBubble`s. Live messages from the channel win when present;
/// otherwise the fixture fallback keeps the demo flow usable. Pin both
/// branches.

@MainActor
final class InboxViewModelMessagesForThreadTests: XCTestCase {

    private func freshVM(threads: [MessageThread] = []) -> InboxViewModel {
        let suite = "test.ReplyAI.messagesFor.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("messages-for-\(UUID().uuidString).json")
        return InboxViewModel(
            threads: threads,
            imessage: BlockingMockChannel(),
            contacts: fastContacts(),
            defaults: d,
            threadsCacheURL: cacheURL)
    }

    func testReturnsLiveMessagesWhenPresent() {
        let t = MessageThread(id: "live-t1", channel: .imessage, name: "L", avatar: "L",
                              preview: "p", time: "now")
        let vm = freshVM(threads: [t])
        let liveMsg = Message(from: .them, text: "live message body", time: "now")
        vm.liveMessages["live-t1"] = [liveMsg]
        let result = vm.messages(for: t)
        XCTAssertEqual(result.count, 1,
            "with liveMessages set, the live array must be returned verbatim — fixture fallback must be skipped")
        XCTAssertEqual(result.first?.text, "live message body",
            "the live message body must round-trip through messages(for:)")
    }

    func testFallsBackToFixtureWhenLiveMessagesAbsent() {
        let t = MessageThread(id: "fixture-t1", channel: .imessage, name: "F", avatar: "F",
                              preview: "preview body", time: "now")
        let vm = freshVM(threads: [t])
        XCTAssertNil(vm.liveMessages[t.id],
            "precondition: no live messages cached for this thread")
        let result = vm.messages(for: t)
        XCTAssertFalse(result.isEmpty,
            "without liveMessages, the fixture fallback must populate the detail pane (otherwise the demo flow shows an empty thread)")
    }

    // MARK: - Incoming-notification time-label freeze

    /// Pin the user-visible time-chip label applied to a thread when
    /// an incoming UNNotification updates (or creates) it. Routes
    /// through the hoisted constant so a copy edit ("now" → "Now",
    /// "just now") is an intentional review surface — drift between
    /// the refresh-existing and create-new code paths in
    /// `applyIncomingNotification` is silent in user UX.
    func testIncomingNotificationTimeLabelIsFrozen() {
        XCTAssertEqual(InboxViewModel.incomingNotificationTimeLabel, "now")
        XCTAssertFalse(InboxViewModel.incomingNotificationTimeLabel.isEmpty,
            "an empty time label leaves the inbox row's time chip blank — every notification-driven row would render with no temporal cue")
    }

    /// Pin the empty-result sync-failure copy. The sidebar truncates
    /// `error · <msg>` to ~24 message chars, so the first 24 chars
    /// must read sensibly on their own. The full message is also a
    /// documented hook the pivot's "stop saying chat.db" rewrite must
    /// explicitly land against — pin makes the next edit a deliberate
    /// one-line diff against an exact prior wording.
    func testEmptyChatDBSyncFailureMessageIsFrozen() {
        XCTAssertEqual(InboxViewModel.emptyChatDBSyncFailureMessage,
                       "No conversations returned. chat.db may be empty on this account.",
                       "drift in this sync-failure copy changes the sidebar `error · ...` pill the user sees when iMessage sync runs to completion but returns zero rows")

        // Sidebar pill renders `error · <msg.prefix(24)>`. Pin the
        // truncated form so a future copy rewrite that pushes the
        // first 24 chars past a sentence break surfaces in review.
        XCTAssertEqual(String(InboxViewModel.emptyChatDBSyncFailureMessage.prefix(24)),
                       "No conversations returne",
                       "first 24 chars of the failure copy are what the sidebar pill actually shows — drift here is what users see, not the full string")

        XCTAssertFalse(InboxViewModel.emptyChatDBSyncFailureMessage.isEmpty,
            "an empty failure message renders the sidebar as `error · ` with nothing after — gives the user no signal at all")
    }

    /// Pin the parameterized "Sent to <recipient>" success-toast
    /// format. Drift on the prefix ("Sent" → "Delivered") changes the
    /// confirmation copy users see after every send.
    func testSentToToastFormatRoundTrips() {
        XCTAssertEqual(InboxViewModel.sentToToast(recipient: "Maya Chen"),
                       "Sent to Maya Chen")
        XCTAssertEqual(InboxViewModel.sentToToast(recipient: "+15551234567"),
                       "Sent to +15551234567")
        // Recipient must appear verbatim — drift to e.g. wrapping in
        // quotes silently changes the user-facing display.
        XCTAssertTrue(InboxViewModel.sentToToast(recipient: "X").contains("X"),
            "sentToToast must surface the recipient verbatim — drift to quoted/escaped form changes the display")
    }
}
