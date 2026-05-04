import XCTest
@testable import ReplyAI

final class ScreenInventoryTests: XCTestCase {
    func testEveryScreenIDIsInInventory() {
        let inventoryIDs = Set(ScreenInventory.allItems.map(\.id))
        let enumIDs = Set(ScreenID.allCases)
        XCTAssertEqual(inventoryIDs, enumIDs, "ScreenInventory must list every ScreenID case")
    }

    func testInventoryMatchesEnum() {
        // README claims "28 screens" but counting groups gives 34.
        // Trust the enum as the source of truth.
        XCTAssertEqual(ScreenInventory.allItems.count, ScreenID.allCases.count)
    }

    func testNextWrapsAround() {
        let last = ScreenInventory.allItems.last!.id
        let first = ScreenInventory.allItems.first!.id
        XCTAssertEqual(ScreenInventory.next(after: last), first)
    }

    func testPreviousWrapsAround() {
        let first = ScreenInventory.allItems.first!.id
        let last = ScreenInventory.allItems.last!.id
        XCTAssertEqual(ScreenInventory.previous(before: first), last)
    }

    func testEveryScreenHasPurpose() {
        for id in ScreenID.allCases {
            let purpose = ScreenMeta.purpose(for: id)
            XCTAssertFalse(purpose.isEmpty, "missing purpose for \(id.rawValue)")
        }
    }

    func testGroupsCoverAllItems() {
        let grouped = ScreenInventory.groups.flatMap(\.items).map(\.id)
        XCTAssertEqual(Set(grouped), Set(ScreenID.allCases))
        XCTAssertEqual(grouped.count, ScreenID.allCases.count, "no duplicates across groups")
    }

    // MARK: - Group invariants

    func testEveryGroupHasNonEmptyTitleAndItems() {
        for group in ScreenInventory.groups {
            XCTAssertFalse(group.title.isEmpty, "group title must not be empty")
            XCTAssertFalse(group.items.isEmpty, "group '\(group.title)' must not be empty")
        }
    }

    func testEveryItemLabelIsNonEmpty() {
        for item in ScreenInventory.allItems {
            XCTAssertFalse(item.label.isEmpty,
                "label for \(item.id.rawValue) must not be empty")
        }
    }

    // MARK: - item(for:) / index(of:)

    func testItemLookupReturnsMatchingItemForEveryID() {
        for id in ScreenID.allCases {
            XCTAssertEqual(ScreenInventory.item(for: id).id, id)
        }
    }

    func testIndexOfIsContiguousAndZeroBased() {
        var indexes = Set<Int>()
        for id in ScreenID.allCases {
            indexes.insert(ScreenInventory.index(of: id))
        }
        XCTAssertEqual(indexes, Set(0..<ScreenID.allCases.count),
            "indexes must cover [0, count) without gaps")
    }

    // MARK: - next/previous as inverses

    func testNextAndPreviousAreInverses() {
        for id in ScreenID.allCases {
            XCTAssertEqual(
                ScreenInventory.previous(before: ScreenInventory.next(after: id)),
                id,
                "previous(next(\(id))) should equal \(id)"
            )
        }
    }

    // MARK: - Stable raw values (persistence-shaped)

    func testKnownRawValuesAreStable() {
        // These string IDs ship into app-shell.jsx + persistence; renaming a
        // case is a migration, not a refactor. Lock the public surface here.
        XCTAssertEqual(ScreenID.obWelcome.rawValue, "ob-welcome")
        XCTAssertEqual(ScreenID.appInbox.rawValue, "app-inbox")
        XCTAssertEqual(ScreenID.sfcPalette.rawValue, "sfc-palette")
        XCTAssertEqual(ScreenID.setAccount.rawValue, "set-account")
        XCTAssertEqual(ScreenID.errDisconnected.rawValue, "err-disconnected")
    }
}
