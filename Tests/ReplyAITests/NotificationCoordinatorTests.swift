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
    var stubbedStatus: UNAuthorizationStatus = .notDetermined
    var authorizationGranted: Bool = true

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.lock(); registeredCategories = categories; lock.unlock()
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.lock(); authorizationRequestCount += 1; lock.unlock()
        return authorizationGranted
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        lock.lock(); let s = stubbedStatus; lock.unlock(); return s
    }
}

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
}
