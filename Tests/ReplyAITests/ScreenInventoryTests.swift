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
}
