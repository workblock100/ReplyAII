import XCTest
import UserNotifications
@testable import ReplyAI

// MARK: - Test doubles

/// Mock notification center that records category registrations and
/// authorization requests without touching the real UNUserNotificationCenter.
private final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private(set) var registeredCategories: Set<UNNotificationCategory> = []
    private(set) var authorizationRequestCount: Int = 0
    private(set) var setCategoriesCallCount: Int = 0
    /// Records the most recent options bitmask passed to requestAuthorization.
    /// Pinning the bitmask catches drift like silently dropping `.badge` —
    /// which would orphan the menu-bar unread badge without any compile-
    /// time signal.
    private(set) var lastRequestedOptions: UNAuthorizationOptions = []
    var stubbedStatus: UNAuthorizationStatus = .notDetermined
    var authorizationGranted: Bool = true
    /// When set, requestAuthorization throws this error instead of returning.
    /// Lets tests verify NotificationCoordinator's `try?` swallowing.
    var authorizationError: Error?

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.lock(); registeredCategories = categories; setCategoriesCallCount += 1; lock.unlock()
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.lock()
        authorizationRequestCount += 1
        lastRequestedOptions = options
        let err = authorizationError
        let granted = authorizationGranted
        lock.unlock()
        if let err { throw err }
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        lock.lock(); let s = stubbedStatus; lock.unlock(); return s
    }
}

private struct StubError: Error {}

// MARK: - Tests

@MainActor
final class NotificationCoordinatorTests: XCTestCase {

    // MARK: - REP-028: testCategoryRegisteredOnLaunch

    func testCategoryRegisteredOnLaunch() async {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.setUp()

        // The "REPLY" action must appear inside one of the registered categories.
        let allActionIDs = center.registeredCategories
            .flatMap { $0.actions }
            .map { $0.identifier }
        XCTAssertTrue(
            allActionIDs.contains(NotificationCoordinator.replyActionID),
            "Expected 'REPLY' action to be registered; got \(allActionIDs)"
        )
        // The category itself should carry the expected identifier.
        let categoryIDs = center.registeredCategories.map { $0.identifier }
        XCTAssertTrue(
            categoryIDs.contains(NotificationCoordinator.categoryID),
            "Expected '\(NotificationCoordinator.categoryID)' category; got \(categoryIDs)"
        )
    }

    // MARK: - Constant literals — notification-shade contract
    //
    // categoryID and replyActionID are persisted into every scheduled
    // UNNotificationRequest. A rename orphans every in-flight or
    // background-scheduled notification — they carry the old category,
    // tap-to-reply doesn't match, and the user's reply silently fails
    // to register. Pin the literal values so a rename surfaces in code
    // review and the human can ship a migration alongside it.

    func testCategoryIDLiteralIsPinned() {
        XCTAssertEqual(NotificationCoordinator.categoryID, "REPLYAI_THREAD",
            "renaming categoryID orphans every previously-scheduled notification's tap-to-reply action")
    }

    func testReplyActionIDLiteralIsPinned() {
        XCTAssertEqual(NotificationCoordinator.replyActionID, "REPLY",
            "renaming replyActionID makes the inline-reply button on every previously-scheduled notification a no-op")
    }

    func testInlineReplyButtonCopyIsPinned() async {
        // The action title ("Reply") and text-input button title ("Send")
        // and placeholder ("Your reply…") all render directly in the
        // notification shade. Designer-led tweaks should land as a
        // code-review diff.
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        await coordinator.setUp()

        let action = center.registeredCategories
            .flatMap { $0.actions }
            .first(where: { $0.identifier == NotificationCoordinator.replyActionID })
        let textInput = action as? UNTextInputNotificationAction
        XCTAssertNotNil(textInput, "the reply action must be a UNTextInputNotificationAction so the user can type inline")

        XCTAssertEqual(action?.title, "Reply",
            "Reply action title ships verbatim to the notification shade — pin so a rephrase shows up in code review")
        XCTAssertEqual(textInput?.textInputButtonTitle, "Send",
            "Send button title ships verbatim — pin so a rephrase shows up in code review")
        XCTAssertEqual(textInput?.textInputPlaceholder, "Your reply…",
            "Placeholder ships verbatim — pin so a rephrase shows up in code review")
    }

    // MARK: - REP-028: testDelegateExtractsReplyText

    func testDelegateExtractsReplyText() async {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)

        // InboxViewModel needs channel + contacts. Use the DeniedContactStore
        // pattern from InboxViewModelTests so no system dialogs fire.
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        // Drive handleReply directly — avoids constructing a real
        // UNNotificationResponse (which requires a UNNotification + trigger).
        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: "Hey, sounds great!",
            notificationID: "thread-42"
        )

        XCTAssertNotNil(inbox.pendingNotificationReply,
            "pendingNotificationReply should be set after a reply action")
        XCTAssertEqual(inbox.pendingNotificationReply?.threadID, "thread-42")
        XCTAssertEqual(inbox.pendingNotificationReply?.text, "Hey, sounds great!")
    }

    // MARK: - REP-028: testAuthorizationSkippedIfGranted

    func testAuthorizationSkippedIfGranted() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .authorized   // already granted
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.setUp()

        XCTAssertEqual(
            center.authorizationRequestCount, 0,
            "requestAuthorization must not be called when status is already .authorized"
        )
    }

    // MARK: - Authorization options bitmask contract
    //
    // Both `setUp()` and `requestPermissionIfNeeded()` request
    // `[.alert, .badge, .sound]`. Each bit is load-bearing for a
    // distinct user-visible feature; dropping one silently degrades
    // that feature without any compile-time signal.
    //   - .alert : the inline-reply notification banner itself
    //   - .badge : the menu-bar unread count (REP-044) and Dock icon
    //   - .sound : the chime that wakes the user from focus mode
    // A refactor that "simplifies" the mask to `.alert` alone would
    // pass tests that only check `requestAuthorization was called` —
    // these pin the actual bits.

    func testSetUpRequestsAlertBadgeAndSoundOptions() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .notDetermined
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.setUp()

        XCTAssertEqual(center.authorizationRequestCount, 1,
                       "precondition: setUp must request authorization once on .notDetermined")
        XCTAssertEqual(center.lastRequestedOptions, NotificationCoordinator.authorizationRequestOptions,
                       "setUp() must route through Self.authorizationRequestOptions; drift means the constant became dead code while the call site froze a private literal")
    }

    func testRequestPermissionIfNeededRequestsAlertBadgeAndSoundOptions() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .notDetermined
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.requestPermissionIfNeeded()

        XCTAssertEqual(center.authorizationRequestCount, 1,
                       "precondition: requestPermissionIfNeeded must request once on .notDetermined")
        XCTAssertEqual(center.lastRequestedOptions, NotificationCoordinator.authorizationRequestOptions,
                       "requestPermissionIfNeeded must route through Self.authorizationRequestOptions — drift between paths produces a TCC dialog whose granted bitmask depends on which call site ran first")
    }

    /// Pin the literal value of `authorizationRequestOptions` itself. The
    /// path-equality tests above only prove both sites *route through* the
    /// constant; this test proves the constant has the right flags. Both
    /// matter — the sites could correctly route through a constant whose
    /// value silently drifted to e.g. `[.alert, .sound]` (no menu-bar
    /// badge) or `[.alert, .badge]` (silent notifications for focus-mode
    /// users). Pin the bitmask so a quiet "tighten the prompt" edit shows
    /// up here and prompts a deliberate review.
    func testAuthorizationRequestOptionsBitmaskIsAlertBadgeSound() {
        let expected: UNAuthorizationOptions = [.alert, .badge, .sound]
        XCTAssertEqual(NotificationCoordinator.authorizationRequestOptions, expected,
                       "authorizationRequestOptions drift drops a user-visible surface — .alert (banner copy), .badge (menu-bar count), .sound (focus-mode chime). All three are part of the unified-inbox premise.")
    }

    // MARK: - foreground presentation options contract
    //
    // When a message notification arrives while the app is foregrounded,
    // `willPresent` returns `[.banner, .sound]` so the user still sees
    // and hears the alert. Without `.banner` macOS silently suppresses
    // foregrounded notifications — a user who is checking the inbox would
    // never see incoming messages from other channels, defeating the
    // unified-inbox premise. Without `.sound`, focus-mode users miss the
    // audio cue. The willPresent callback is `nonisolated` and takes a
    // real UNNotification (which has no public init), so the bitmask is
    // hoisted to a static constant the test can pin directly.

    func testForegroundPresentationOptionsBitmaskIsBannerAndSound() {
        let expected: UNNotificationPresentationOptions = [.banner, .sound]
        XCTAssertEqual(NotificationCoordinator.foregroundPresentationOptions, expected,
                       "foreground notification presentation must include .banner (visible alert) and .sound (audio cue) — see test rationale")
    }

    // MARK: - edge cases

    func testHandleReplyIgnoresWrongActionIdentifier() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        coordinator.handleReply(actionIdentifier: "DISMISS", userText: "hello", notificationID: "t1")

        XCTAssertNil(inbox.pendingNotificationReply,
            "Non-REPLY action identifier must not set pendingNotificationReply")
    }

    func testHandleReplyIgnoresEmptyText() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: "",
            notificationID: "t1"
        )

        XCTAssertNil(inbox.pendingNotificationReply,
            "Empty reply text must not set pendingNotificationReply")
    }

    /// `nil` userText (the `userText: String?` param) is the actual UN
    /// representation when a non-text-input action fires; pin the silent
    /// drop so a refactor that replaces `let text = userText` with a
    /// non-optional default ("") doesn't accidentally start propagating
    /// blank replies through to IMessageSender.
    func testHandleReplyIgnoresNilText() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: nil,
            notificationID: "t1"
        )

        XCTAssertNil(inbox.pendingNotificationReply,
            "nil reply text must not set pendingNotificationReply (the optional unwrap is the gate)")
    }

    /// An empty `notificationID` reaches `pendingNotificationReply`
    /// verbatim — the gate at this layer only screens action identifier
    /// and text. Pin the current behaviour so a future tightening to
    /// also reject empty IDs is a deliberate change visible here, and so
    /// downstream consumeNotificationReply's "thread not found" silent
    /// drop continues to act as the safety net.
    func testHandleReplyAcceptsEmptyNotificationIDVerbatim() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: "ok",
            notificationID: ""
        )

        guard let pending = inbox.pendingNotificationReply else {
            XCTFail("empty notificationID must still set pendingNotificationReply at this layer")
            return
        }
        XCTAssertEqual(pending.threadID, "",
            "threadID must be passed through verbatim — the empty-string filter is downstream in consumeNotificationReply")
        XCTAssertEqual(pending.text, "ok")
    }

    func testAuthorizationRequestedWhenNotDetermined() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .notDetermined
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.setUp()

        XCTAssertEqual(
            center.authorizationRequestCount, 1,
            "requestAuthorization must be called exactly once when status is .notDetermined"
        )
    }

    // MARK: - REP-078: handleNotificationResponse coverage

    func testHandleResponseSetsPendingReply() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: "Sounds good!",
            notificationID: "thread-99"
        )

        XCTAssertNotNil(inbox.pendingNotificationReply,
            "handleReply with valid inputs must set pendingNotificationReply")
        XCTAssertEqual(inbox.pendingNotificationReply?.threadID, "thread-99")
        XCTAssertEqual(inbox.pendingNotificationReply?.text, "Sounds good!")
    }

    func testHandleResponseMissingUserTextIsNoOp() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox

        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: nil,
            notificationID: "thread-42"
        )

        XCTAssertNil(inbox.pendingNotificationReply,
            "nil userText must be a no-op — pendingNotificationReply must remain nil")
    }

    func testHandleResponseMissingThreadIDIsNoOp() {
        // Empty notificationID means the coordinator forwards a blank threadID.
        // InboxViewModel discards unknown thread IDs; this test confirms no crash
        // and no pendingNotificationReply set when inbox is nil.
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        // Intentionally leave inbox nil — simulates the case where the coordinator
        // fires before InboxViewModel is ready. Must not crash.
        coordinator.handleReply(
            actionIdentifier: NotificationCoordinator.replyActionID,
            userText: "text",
            notificationID: "some-id"
        )
        // inbox is nil so pendingNotificationReply was never set — no crash is the assertion.
        XCTAssertNil(coordinator.inbox, "inbox must still be nil after handleReply with no inbox set")
    }

    // MARK: - REP-235: incoming message capture

    func testIncomingNotificationFiresCallback() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        var fired = false
        coordinator.onIncomingMessage = { _, _ in fired = true }

        coordinator.handleIncomingNotification(
            categoryID: "com.apple.iMessage",
            senderHandle: "+15551234567",
            preview: "Hello there"
        )

        XCTAssertTrue(fired, "onIncomingMessage must fire for a non-reply-category notification")
    }

    func testIncomingNotificationParsesFields() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        var capturedHandle: String?
        var capturedPreview: String?
        coordinator.onIncomingMessage = { handle, preview in
            capturedHandle = handle
            capturedPreview = preview
        }

        coordinator.handleIncomingNotification(
            categoryID: "com.apple.iMessage",
            senderHandle: "+15559876543",
            preview: "Hey, are you free tonight?"
        )

        XCTAssertEqual(capturedHandle, "+15559876543",
            "onIncomingMessage must receive the senderHandle passed to handleIncomingNotification")
        XCTAssertEqual(capturedPreview, "Hey, are you free tonight?",
            "onIncomingMessage must receive the preview body passed to handleIncomingNotification")
    }

    func testReplyNotificationDoesNotFireIncomingCallback() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        var fired = false
        coordinator.onIncomingMessage = { _, _ in fired = true }

        // Simulate a notification whose category is the inline-reply category.
        coordinator.handleIncomingNotification(
            categoryID: NotificationCoordinator.categoryID,
            senderHandle: "+15551234567",
            preview: "Some text"
        )

        XCTAssertFalse(fired,
            "onIncomingMessage must NOT fire when the categoryID matches the inline-reply category")
    }

    // MARK: - REP-263: chatGUID extraction from userInfo

    func testChatGUIDExtractedFromCKChatIdentifier() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        var capturedGUID: String?
        let inbox = InboxViewModel()
        coordinator.inbox = inbox
        // Intercept via onIncomingMessage to verify the GUID reaches applyIncomingNotification.
        // We seed the inbox with a thread whose chatGUID matches so we can observe
        // the update path vs the create path.
        let existingGUID = "iMessage;+;chat1111"
        inbox.threads = [
            MessageThread(id: "t1", channel: .imessage, name: "Alice",
                          avatar: "A", preview: "old", time: "10:00",
                          chatGUID: existingGUID)
        ]

        // handleIncomingNotification with the primary key should route through to inbox.
        coordinator.handleIncomingNotification(
            categoryID: "com.apple.iMessage",
            senderHandle: "+15551112222",
            preview: "Hi!",
            chatGUID: existingGUID
        )

        // Thread count should stay 1 (updated in place, not duplicated).
        XCTAssertEqual(inbox.threads.count, 1,
            "thread count must not grow when chatGUID matches an existing thread")
        XCTAssertEqual(inbox.threads.first?.preview, "Hi!",
            "existing thread preview must be updated to the new message body")
    }

    func testChatGUIDFallsBackToCKChatGUID() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox
        let existingGUID = "iMessage;-;+15559998888"
        inbox.threads = [
            MessageThread(id: "t2", channel: .imessage, name: "Bob",
                          avatar: "B", preview: "old preview", time: "09:00",
                          chatGUID: existingGUID)
        ]

        // Use the fallback key (CKChatGUID) — handleIncomingNotification accepts it directly.
        coordinator.handleIncomingNotification(
            categoryID: "com.apple.iMessage",
            senderHandle: "+15559998888",
            preview: "Morning",
            chatGUID: existingGUID   // represents what willPresent extracts from CKChatGUID
        )

        XCTAssertEqual(inbox.threads.count, 1,
            "fallback CKChatGUID key must also prevent thread duplication")
        XCTAssertEqual(inbox.threads.first?.preview, "Morning",
            "thread preview must update when matched via CKChatGUID fallback")
    }

    func testEmptyChatGUIDFallsBackToSenderHandleMatching() {
        // Regression pin for the present-but-empty chatGUID bug: a malformed
        // notification with `userInfo["CKChatIdentifier"] = ""` previously
        // bypassed the senderHandle/name fallback in applyIncomingNotification
        // and silently created a duplicate thread per notification. After the
        // fix, handleIncomingNotification normalizes `Some("")` to nil so the
        // existing thread is matched by name and updated in place.
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        let inbox = InboxViewModel()
        coordinator.inbox = inbox
        // Seed a thread with NO chatGUID — the realistic shape for a thread
        // created from a previous notification before chat.db sync runs.
        inbox.threads = [
            MessageThread(id: "t-empty", channel: .imessage, name: "Carol",
                          avatar: "C", preview: "previous", time: "11:00",
                          chatGUID: nil)
        ]

        coordinator.handleIncomingNotification(
            categoryID: "com.apple.iMessage",
            senderHandle: "Carol",
            preview: "newer",
            chatGUID: ""   // present-but-empty — must NOT cause duplication
        )

        XCTAssertEqual(inbox.threads.count, 1,
            "empty chatGUID must be normalized to nil so the senderHandle/name fallback runs")
        XCTAssertEqual(inbox.threads.first?.preview, "newer",
            "existing thread must be updated when matched by name fallback")
    }

    // MARK: - REP-255: requestPermissionIfNeeded

    func testRequestPermissionCalledWhenUndetermined() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .notDetermined
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.requestPermissionIfNeeded()

        XCTAssertEqual(
            center.authorizationRequestCount, 1,
            "requestAuthorization must be called once when status is .notDetermined"
        )
    }

    func testRequestPermissionNotCalledWhenAuthorized() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .authorized
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.requestPermissionIfNeeded()

        XCTAssertEqual(
            center.authorizationRequestCount, 0,
            "requestAuthorization must not be called when status is already .authorized"
        )
    }

    func testRequestPermissionNotCalledWhenDenied() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .denied
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.requestPermissionIfNeeded()

        XCTAssertEqual(
            center.authorizationRequestCount, 0,
            "requestAuthorization must not be called when status is .denied"
        )
    }

    // MARK: - error swallowing + idempotency

    /// requestAuthorization throwing must be swallowed by `try?` — setUp() must
    /// complete normally even when the user disallows the permission dialog
    /// (which UN propagates back as an error).
    func testSetUpSwallowsAuthorizationError() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .notDetermined
        center.authorizationError = StubError()
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.setUp() // must not throw, must not crash

        XCTAssertEqual(center.authorizationRequestCount, 1,
            "request must still have been attempted exactly once")
        XCTAssertEqual(center.setCategoriesCallCount, 1,
            "categories must still be registered even when auth request fails")
    }

    /// Same swallow guarantee for requestPermissionIfNeeded — InboxViewModel.init
    /// calls this without await error handling.
    func testRequestPermissionIfNeededSwallowsError() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .notDetermined
        center.authorizationError = StubError()
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.requestPermissionIfNeeded() // must not throw

        XCTAssertEqual(center.authorizationRequestCount, 1)
    }

    /// Calling setUp() twice when status is already .authorized after the first
    /// call must NOT issue a second authorization request. The status guard is
    /// the idempotency mechanism — categories may re-register, auth must not.
    func testSetUpIsIdempotentWhenAlreadyAuthorized() async {
        let center = MockNotificationCenter()
        center.stubbedStatus = .authorized
        let coordinator = NotificationCoordinator(center: center)

        await coordinator.setUp()
        await coordinator.setUp()

        XCTAssertEqual(center.authorizationRequestCount, 0,
            "two setUp() calls when authorized must not issue any auth requests")
        // Categories may re-register on each setUp — that's fine, no user-visible cost.
        XCTAssertGreaterThanOrEqual(center.setCategoriesCallCount, 1)
    }

    /// onIncomingMessage callback fires even when inbox is nil. The callback is
    /// the public hook for code that needs to react to incoming pushes (e.g.
    /// menu bar badge); it must not depend on inbox liveness.
    func testIncomingNotificationFiresCallbackEvenWithoutInbox() {
        let center = MockNotificationCenter()
        let coordinator = NotificationCoordinator(center: center)
        // Intentionally leave inbox nil.
        var fired = false
        coordinator.onIncomingMessage = { _, _ in fired = true }

        coordinator.handleIncomingNotification(
            categoryID: "com.apple.iMessage",
            senderHandle: "+15551112222",
            preview: "Yo"
        )

        XCTAssertTrue(fired,
            "onIncomingMessage callback must fire regardless of inbox liveness")
        XCTAssertNil(coordinator.inbox, "inbox must remain nil — no side-effect bound it")
    }

    // MARK: - Wire-format constant pin (REPLYAI_THREAD / REPLY)
    //
    // categoryID and replyActionID are the identifiers macOS uses to
    // route inline-reply actions back to the app, and they appear in
    // any notifications that are scheduled but not yet fired. Renaming
    // them is a soft-migration: in-flight notifications that already
    // carry the old category/action identifier won't route correctly
    // to the new handler. Pin the literal strings so a careless rename
    // surfaces as a test failure that prompts a migration plan.

    func testCategoryIDIsStableWireFormat() {
        XCTAssertEqual(NotificationCoordinator.categoryID, "REPLYAI_THREAD",
            "categoryID is persisted in scheduled notifications — renaming requires a migration")
    }

    func testReplyActionIDIsStableWireFormat() {
        XCTAssertEqual(NotificationCoordinator.replyActionID, "REPLY",
            "replyActionID is persisted in scheduled notifications — renaming requires a migration")
    }
}
