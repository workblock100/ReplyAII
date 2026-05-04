import XCTest
@testable import ReplyAI

/// Pins the public surface of `Message`. Author raw values feed both
/// fixture JSON and any future on-disk projection, so renaming a case
/// is a silent migration. Init defaults define what fixtures and mocks
/// get when they don't pass every field — drift here would change
/// behavior in dozens of test sites without the call sites changing.
final class MessageTests: XCTestCase {

    // MARK: - Author raw values

    func testAuthorRawValuesArePersistenceContract() {
        // Renaming either case breaks fixtures and would shift `from` projection.
        XCTAssertEqual(Message.Author.them.rawValue, "them")
        XCTAssertEqual(Message.Author.me.rawValue,   "me")
    }

    func testAuthorRawRoundTrip() {
        XCTAssertEqual(Message.Author(rawValue: "them"), .them)
        XCTAssertEqual(Message.Author(rawValue: "me"),   .me)
        XCTAssertNil(Message.Author(rawValue: "Them"),
                     "raw lookup is case-sensitive — drift would silently fail")
        XCTAssertNil(Message.Author(rawValue: "user"),
                     "unknown raw must be nil, not coerced")
    }

    // MARK: - Init defaults

    func testInitDefaultsForOptionalFields() {
        // Two-argument call site exercised by lots of fixtures.
        let m = Message(from: .them, text: "hi", time: "9:00 AM")
        XCTAssertEqual(m.from, .them)
        XCTAssertEqual(m.text, "hi")
        XCTAssertEqual(m.time, "9:00 AM")
        XCTAssertEqual(m.rowID, 0,
                       "rowID default is 0 — fixtures rely on this for dedup-skip")
        XCTAssertFalse(m.hasAttachment, "hasAttachment default must be false")
        XCTAssertFalse(m.isRead, "isRead default must be false")
        XCTAssertNil(m.deliveredAt, "deliveredAt default must be nil")
    }

    func testInitGeneratesDistinctIDsByDefault() {
        // The UUID default is `UUID()` — two messages built with the same
        // payload should still get distinct identities (Identifiable contract).
        let a = Message(from: .me, text: "hi", time: "9:00 AM")
        let b = Message(from: .me, text: "hi", time: "9:00 AM")
        XCTAssertNotEqual(a.id, b.id, "default id must be a fresh UUID per call")
    }

    // MARK: - Hashable / Equatable

    func testEqualityRequiresEveryFieldToMatch() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let base = Message(id: id, from: .them, text: "hi", time: "9:00",
                           rowID: 42, hasAttachment: true, isRead: true,
                           deliveredAt: date)

        // Identical → equal.
        let same = Message(id: id, from: .them, text: "hi", time: "9:00",
                           rowID: 42, hasAttachment: true, isRead: true,
                           deliveredAt: date)
        XCTAssertEqual(base, same)
        XCTAssertEqual(base.hashValue, same.hashValue)

        // Differing rowID → not equal (rule engine relies on this).
        let diffRow = Message(id: id, from: .them, text: "hi", time: "9:00",
                              rowID: 43, hasAttachment: true, isRead: true,
                              deliveredAt: date)
        XCTAssertNotEqual(base, diffRow)

        // Differing isRead → not equal (unread badge cache invalidates on diff).
        let diffRead = Message(id: id, from: .them, text: "hi", time: "9:00",
                               rowID: 42, hasAttachment: true, isRead: false,
                               deliveredAt: date)
        XCTAssertNotEqual(base, diffRead)
    }

    func testIdentityIsByID() {
        // Identifiable id is `id` (the UUID), not rowID — pin the wiring.
        let id = UUID()
        let m = Message(id: id, from: .me, text: "x", time: "—", rowID: 7)
        XCTAssertEqual(m.id, id)
    }
}
