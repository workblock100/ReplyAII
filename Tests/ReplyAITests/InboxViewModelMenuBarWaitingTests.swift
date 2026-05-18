import XCTest
@testable import ReplyAICore

/// Pins the contract for `InboxViewModel.menuBarWaitingThreads` — the
/// computed property the MenuBarExtra popover reads to render its
/// "N waiting" list and the MenuBar icon's badge count.
///
/// Existing coverage in `RulesTests` exercises this property only via
/// the silentlyIgnore rule action. These tests pin the four invariants
/// that the menu-bar UI silently relies on:
///
/// 1. unread == 0 → never appears (the menu shouldn't surface noise).
/// 2. unread > 0 → appears unless silently-ignored.
/// 3. silentlyIgnoredThreadIDs filters out unread threads (a rule-action
///    contract that the menu bar honors so an autonomous "ignore newsletter"
///    rule doesn't keep pinging the user).
/// 4. The set is read fresh from `threads` on every access — no caching —
///    so a sync that mutates the underlying array is reflected immediately
///    in the next menu-bar render.
///
/// Without these tests, a refactor that adds caching, drops the
/// silentlyIgnoredThreadIDs filter, or inverts the unread predicate
/// would silently break the menu bar without any compile error.
@MainActor
final class InboxViewModelMenuBarWaitingTests: XCTestCase {

    private struct DeniedContactStore: ContactsStoring {
        func currentAccess() -> ContactsResolver.Access { .denied }
        func requestAccess() async -> ContactsResolver.Access { .denied }
        func lookup(handle: String) -> String? { nil }
    }

    private func fastContacts() -> ContactsResolver {
        ContactsResolver(store: DeniedContactStore())
    }

    private func thread(id: String, unread: Int) -> MessageThread {
        MessageThread(
            id: id,
            channel: .imessage,
            name: "Thread \(id)",
            avatar: "T",
            preview: "preview \(id)",
            time: "now",
            unread: unread
        )
    }

    /// Per-test UserDefaults so silentlyIgnoredThreadIDs persistence doesn't
    /// leak between tests. The InboxViewModel reads the suite at init time.
    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.replyai.MenuBarWaiting.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        return d
    }

    // MARK: - Invariant 1: unread == 0 is invisible

    func testReadThreadDoesNotAppearInWaiting() {
        let read = thread(id: "read", unread: 0)
        let vm = InboxViewModel(threads: [read], contacts: fastContacts(), defaults: freshDefaults())
        XCTAssertTrue(vm.menuBarWaitingThreads.isEmpty,
            "thread with unread == 0 must never appear in menuBarWaitingThreads — the menu only surfaces things that need user attention")
    }

    func testAllReadInboxIsEmpty() {
        let threads = [thread(id: "a", unread: 0), thread(id: "b", unread: 0), thread(id: "c", unread: 0)]
        let vm = InboxViewModel(threads: threads, contacts: fastContacts(), defaults: freshDefaults())
        XCTAssertEqual(vm.menuBarWaitingThreads.count, 0)
    }

    // MARK: - Invariant 2: unread > 0 is visible by default

    func testUnreadThreadAppearsInWaiting() {
        let unread = thread(id: "needs-you", unread: 3)
        let vm = InboxViewModel(threads: [unread], contacts: fastContacts(), defaults: freshDefaults())
        let waitingIDs = vm.menuBarWaitingThreads.map(\.id)
        XCTAssertEqual(waitingIDs, ["needs-you"])
    }

    func testMixedReadAndUnreadOnlyShowsUnread() {
        let threads = [
            thread(id: "read",    unread: 0),
            thread(id: "unread1", unread: 1),
            thread(id: "read2",   unread: 0),
            thread(id: "unread2", unread: 2),
        ]
        let vm = InboxViewModel(threads: threads, contacts: fastContacts(), defaults: freshDefaults())
        let waitingIDs = Set(vm.menuBarWaitingThreads.map(\.id))
        XCTAssertEqual(waitingIDs, Set(["unread1", "unread2"]))
    }

    // MARK: - Invariant 3: silentlyIgnored filters out

    func testSilentlyIgnoredUnreadThreadIsHidden() {
        let unread = thread(id: "ignored-newsletter", unread: 5)
        let visible = thread(id: "real-message", unread: 1)
        let vm = InboxViewModel(threads: [unread, visible], contacts: fastContacts(), defaults: freshDefaults())
        vm.silentlyIgnoredThreadIDs = ["ignored-newsletter"]
        let waitingIDs = vm.menuBarWaitingThreads.map(\.id)
        XCTAssertEqual(waitingIDs, ["real-message"],
            "silentlyIgnoredThreadIDs must filter out unread threads — that's what the silentlyIgnore rule action exists to do for menu-bar noise control")
    }

    func testSilentlyIgnoredEmptyDoesNotFilterAnything() {
        let unread = thread(id: "u1", unread: 1)
        let vm = InboxViewModel(threads: [unread], contacts: fastContacts(), defaults: freshDefaults())
        vm.silentlyIgnoredThreadIDs = []
        XCTAssertEqual(vm.menuBarWaitingThreads.map(\.id), ["u1"])
    }

    func testSilentlyIgnoringEveryThreadEmptiesWaiting() {
        let threads = [thread(id: "a", unread: 1), thread(id: "b", unread: 2), thread(id: "c", unread: 3)]
        let vm = InboxViewModel(threads: threads, contacts: fastContacts(), defaults: freshDefaults())
        vm.silentlyIgnoredThreadIDs = ["a", "b", "c"]
        XCTAssertTrue(vm.menuBarWaitingThreads.isEmpty,
            "all-ignored should produce inbox-zero in the menu, even if every thread has unread")
    }

    func testSilentlyIgnoringReadThreadsHasNoEffect() {
        // Edge case: a rule that ignores already-read threads must not
        // accidentally hide any unread thread. The unread predicate is
        // evaluated independently of the ignore set.
        let threads = [
            thread(id: "read-and-ignored", unread: 0),
            thread(id: "unread",            unread: 1),
        ]
        let vm = InboxViewModel(threads: threads, contacts: fastContacts(), defaults: freshDefaults())
        vm.silentlyIgnoredThreadIDs = ["read-and-ignored"]
        XCTAssertEqual(vm.menuBarWaitingThreads.map(\.id), ["unread"])
    }

    // MARK: - Invariant 4: live read, no caching

    func testWaitingReflectsLiveThreadsArray() {
        let initial = [thread(id: "a", unread: 0)]
        let vm = InboxViewModel(threads: initial, contacts: fastContacts(), defaults: freshDefaults())
        XCTAssertTrue(vm.menuBarWaitingThreads.isEmpty)

        // Replace the threads array directly — what a live sync does after
        // recentThreads() returns. The next access must reflect the new state.
        vm.threads = [thread(id: "a", unread: 0), thread(id: "b", unread: 4)]
        XCTAssertEqual(vm.menuBarWaitingThreads.map(\.id), ["b"],
            "menuBarWaitingThreads must read `threads` live on every access — caching here would leave the menu bar stale after a sync")
    }

    func testWaitingReflectsUnreadCountChange() {
        let t = thread(id: "x", unread: 1)
        let vm = InboxViewModel(threads: [t], contacts: fastContacts(), defaults: freshDefaults())
        XCTAssertEqual(vm.menuBarWaitingThreads.count, 1)

        // Marking read = swapping the thread for a 0-unread copy. Next read
        // must drop it from the waiting list.
        vm.threads = [thread(id: "x", unread: 0)]
        XCTAssertTrue(vm.menuBarWaitingThreads.isEmpty)
    }

    // MARK: - Invariant 5: order is preserved from `threads`
    //
    // The MenuBarExtra popover renders waiting threads top-to-bottom in
    // the order this property emits them. The implementation is a plain
    // `Array.filter`, which preserves source order — but the existing
    // `testMixedReadAndUnreadOnlyShowsUnread` projects through `Set(...)`,
    // which loses order. A future refactor that switches to e.g.
    // `threads.sorted(by: { $0.time > $1.time }).filter(...)` (recency-
    // sort the menu) or to a Dictionary-backed lookup would still pass
    // every existing assertion while silently changing the menu's row
    // order — confusing for users who learned where each thread sits.
    // Pin the source-order invariant so any reordering edit lands as a
    // deliberate code-review diff, not a stealth UX change.
    func testWaitingPreservesSourceOrderFromThreadsArray() {
        let threads = [
            thread(id: "first-unread",  unread: 1),
            thread(id: "read-middle",   unread: 0),
            thread(id: "second-unread", unread: 7),
            thread(id: "third-unread",  unread: 2),
        ]
        let vm = InboxViewModel(threads: threads, contacts: fastContacts(), defaults: freshDefaults())
        XCTAssertEqual(
            vm.menuBarWaitingThreads.map(\.id),
            ["first-unread", "second-unread", "third-unread"],
            "menuBarWaitingThreads must preserve the order of `threads` — the menu-bar popover surfaces rows top-to-bottom in this order; a sort-on-the-way-out refactor would still pass set-based tests"
        )
    }

    // Same invariant under the silently-ignored filter — pin separately
    // because a refactor could introduce ordering drift only inside the
    // ignore-filter branch (e.g. `threads.subtract(ignored).sorted(...)`).
    func testWaitingPreservesSourceOrderEvenWithSilentlyIgnored() {
        let threads = [
            thread(id: "unread-a",  unread: 1),
            thread(id: "ignored",   unread: 9),
            thread(id: "unread-b",  unread: 1),
        ]
        let vm = InboxViewModel(threads: threads, contacts: fastContacts(), defaults: freshDefaults())
        vm.silentlyIgnoredThreadIDs = ["ignored"]
        XCTAssertEqual(
            vm.menuBarWaitingThreads.map(\.id),
            ["unread-a", "unread-b"],
            "filter ordering must be preserved when silentlyIgnoredThreadIDs removes mid-list rows"
        )
    }
}
