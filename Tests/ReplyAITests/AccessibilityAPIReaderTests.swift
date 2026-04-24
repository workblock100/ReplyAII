import XCTest
@testable import ReplyAI

// MARK: - Mock helpers

/// Fully controllable AX element for test trees.
struct MockAXElement: AXElement {
    var role: String?
    var title: String?
    var children: [any AXElement]

    init(role: String? = nil, title: String? = nil, children: [any AXElement] = []) {
        self.role     = role
        self.title    = title
        self.children = children
    }
}

/// Records the PID it was called with; returns the configured root.
final class MockAXElementFactory: AXElementFactory {
    let root: (any AXElement)?
    private(set) var capturedPID: pid_t?

    init(root: (any AXElement)? = nil) {
        self.root = root
    }

    func rootElement(forPID pid: pid_t) -> (any AXElement)? {
        capturedPID = pid
        return root
    }
}

// MARK: - Tests

final class AccessibilityAPIReaderTests: XCTestCase {

    // MARK: - REP-258: conversation names from mock element tree

    func testReturnsConversationNamesFromMockTree() {
        // Build a tree: Application → Window → List → three AXRow elements
        let rows: [any AXElement] = [
            MockAXElement(role: "AXRow", title: "Alice"),
            MockAXElement(role: "AXRow", title: "Bob"),
            MockAXElement(role: "AXRow", title: "Carol"),
        ]
        let list   = MockAXElement(role: "AXList",        children: rows)
        let window = MockAXElement(role: "AXWindow",      children: [list])
        let app    = MockAXElement(role: "AXApplication", children: [window])

        let factory = MockAXElementFactory(root: app)
        let reader  = AccessibilityAPIReader(
            pidProvider:       { 12345 },
            elementFactory:    factory,
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Alice", "Bob", "Carol"])
    }

    func testReturnsEmptyWhenAccessibilityNotTrusted() {
        let row  = MockAXElement(role: "AXRow", title: "Alice")
        let root = MockAXElement(role: "AXApplication", children: [row])

        let reader = AccessibilityAPIReader(
            pidProvider:       { 12345 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { false }   // Accessibility not granted
        )

        XCTAssertEqual(reader.conversationNames(), [],
                       "must return [] without touching AX when not trusted")
    }

    func testReturnsEmptyWhenSidebarIsEmpty() {
        // Tree exists but no AXRow elements under the window
        let window = MockAXElement(role: "AXWindow", children: [])
        let app    = MockAXElement(role: "AXApplication", children: [window])

        let reader = AccessibilityAPIReader(
            pidProvider:       { 99 },
            elementFactory:    MockAXElementFactory(root: app),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), [])
    }

    func testFactoryReceivesCorrectPID() {
        // The reader must pass the PID it got from pidProvider to the factory.
        let factory = MockAXElementFactory(root: nil)
        let reader  = AccessibilityAPIReader(
            pidProvider:       { 42 },
            elementFactory:    factory,
            isTrustedProvider: { true }
        )

        _ = reader.conversationNames()
        XCTAssertEqual(factory.capturedPID, 42,
                       "factory must receive the PID returned by pidProvider")
    }

    func testReturnsEmptyWhenMessagesNotRunning() {
        // pidProvider returns nil (Messages not running)
        let factory = MockAXElementFactory(root: MockAXElement(role: "AXApplication"))
        let reader  = AccessibilityAPIReader(
            pidProvider:       { nil },
            elementFactory:    factory,
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), [])
        XCTAssertNil(factory.capturedPID,
                     "factory must not be called when Messages.app is not running")
    }

    func testRowWithEmptyTitleIsSkipped() {
        // AXRow with empty title must not appear in results
        let rows: [any AXElement] = [
            MockAXElement(role: "AXRow", title: "Alice"),
            MockAXElement(role: "AXRow", title: ""),        // empty → skip
            MockAXElement(role: "AXRow", title: nil),       // nil   → skip
            MockAXElement(role: "AXRow", title: "Bob"),
        ]
        let root = MockAXElement(role: "AXApplication", children: rows)

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Alice", "Bob"])
    }
}
