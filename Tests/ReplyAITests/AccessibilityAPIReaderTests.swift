import XCTest
@testable import ReplyAICore

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
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Alice"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Bob"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Carol"),
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
        let row  = MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Alice")
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
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Alice"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: ""),        // empty → skip
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: nil),       // nil   → skip
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Bob"),
        ]
        let root = MockAXElement(role: "AXApplication", children: rows)

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Alice", "Bob"])
    }

    func testCollectsRowsFromDeeplyNestedSubtree() {
        // Real Messages.app sidebar has wrapping AXScrollArea / AXOutline / AXGroup
        // before the AXRow leaves. Collector must recurse to arbitrary depth.
        let leaves: [any AXElement] = [
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Mom"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Group: Family"),
        ]
        let group = MockAXElement(role: "AXGroup",      children: leaves)
        let outline = MockAXElement(role: "AXOutline",  children: [group])
        let scroll = MockAXElement(role: "AXScrollArea", children: [outline])
        let window = MockAXElement(role: "AXWindow",    children: [scroll])
        let app    = MockAXElement(role: "AXApplication", children: [window])

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: app),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Mom", "Group: Family"])
    }

    func testIgnoresNonRowElementsEvenWithTitle() {
        // AXButton, AXText, AXStaticText — anything that's not AXRow must
        // be ignored even if it carries a title attribute. Otherwise we'd
        // pick up "Send", "Search", or column headers in the sidebar.
        let mixed: [any AXElement] = [
            MockAXElement(role: "AXButton",    title: "Send"),
            MockAXElement(role: "AXStaticText", title: "Search"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole,       title: "Alice"),
            MockAXElement(role: "AXText",      title: "Footer"),
        ]
        let root = MockAXElement(role: "AXApplication", children: mixed)

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Alice"])
    }

    func testPreservesOrderAcrossMultipleSubtrees() {
        // The Messages sidebar can be split into Pinned + Unpinned regions.
        // Order across regions is meaningful (most-recent first) — collection
        // must walk subtrees in order, not by depth/breadth interleaving.
        let pinnedRows: [any AXElement] = [
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Pinned 1"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Pinned 2"),
        ]
        let unpinnedRows: [any AXElement] = [
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Recent A"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Recent B"),
        ]
        let pinnedGroup = MockAXElement(role: "AXGroup", children: pinnedRows)
        let unpinnedGroup = MockAXElement(role: "AXGroup", children: unpinnedRows)
        let root = MockAXElement(role: "AXApplication", children: [pinnedGroup, unpinnedGroup])

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Pinned 1", "Pinned 2", "Recent A", "Recent B"])
    }

    func testReturnsEmptyWhenRootElementIsNil() {
        // Real-world cause: Messages.app is in the middle of launching and
        // AXUIElementCreateApplication briefly returns no usable root.
        let factory = MockAXElementFactory(root: nil)
        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    factory,
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), [])
        XCTAssertEqual(factory.capturedPID, 1, "factory still called for the PID even when root resolves to nil")
    }

    // MARK: - additional traversal contract

    func testRootElementAsRowIsCollected() {
        // collectNames(from:) checks the *passed* element as well as its
        // descendants. If Messages.app ever returns a sidebar root that is
        // itself an AXRow (some AX trees look like this when the conversation
        // list is the only window content), the root's title must still
        // surface — otherwise we'd silently drop the only conversation.
        let root = MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Solo conversation")

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Solo conversation"])
    }

    func testNestedAXRowInsideAXRowAllCollected() {
        // AXOutline trees can produce parent rows with disclosure children
        // that are themselves AXRow elements. The collector recurses into
        // every child unconditionally, so both parent and nested rows must
        // appear in the output — the rule engine downstream dedups on
        // chatGUID, not on AX titles.
        let child = MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Child row")
        let parent = MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "Parent row", children: [child])
        let root = MockAXElement(role: "AXOutline", children: [parent])

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Parent row", "Child row"],
                       "parent row title must appear before its nested children (DFS preorder)")
    }

    func testWhitespaceOnlyTitleIsKept() {
        // Behavior pin: the skip rule is `!title.isEmpty`, not "isBlank".
        // A title of `"   "` (all spaces) survives the filter today. If a
        // future change tightens this, this test will fail loudly so we
        // can decide deliberately whether to drop it.
        let row = MockAXElement(role: AccessibilityAPIReader.conversationRowRole, title: "   ")
        let root = MockAXElement(role: "AXApplication", children: [row])

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["   "],
                       "whitespace-only titles are not currently treated as empty")
    }

    func testRoleMatchIsExactNotPrefixOrSuffix() {
        // The role check is `element.role == "AXRow"`. AX exposes related but
        // distinct roles ("AXRowHeader", "AXOutlineRow", lowercase variants
        // from non-Apple apps). None should be confused with AXRow — a
        // looser match would surface column headers as conversations.
        let near: [any AXElement] = [
            MockAXElement(role: "AXRowHeader", title: "Header"),
            MockAXElement(role: "AXOutlineRow", title: "Outline child"),
            MockAXElement(role: "axrow",       title: "lower"),
            MockAXElement(role: "AXRow ",      title: "trailing space"),
            MockAXElement(role: AccessibilityAPIReader.conversationRowRole,       title: "Real row"),
        ]
        let root = MockAXElement(role: "AXApplication", children: near)

        let reader = AccessibilityAPIReader(
            pidProvider:       { 1 },
            elementFactory:    MockAXElementFactory(root: root),
            isTrustedProvider: { true }
        )

        XCTAssertEqual(reader.conversationNames(), ["Real row"],
                       "only the exact AXRow role should match — adjacent role names are ignored")
    }

    /// `AccessibilityAPIReader.conversationRowRole` is the AX role string
    /// `collectNames` matches descendants against. Drift to `"AXListRow"`,
    /// `"AXTableRow"`, etc. silently returns [] from `conversationNames()`
    /// without throwing — the user sees an empty sidebar fallback while the
    /// Accessibility grant remains valid. Pin the literal so a "let's
    /// normalize role names" edit lands in code review.
    func testConversationRowRoleConstantIsAXRow() {
        XCTAssertEqual(AccessibilityAPIReader.conversationRowRole, "AXRow",
                       "drift in conversationRowRole silently returns [] from conversationNames() — Messages.app sidebar rows always emit role 'AXRow'")
    }
}
