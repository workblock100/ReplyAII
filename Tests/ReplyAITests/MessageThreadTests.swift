import XCTest
@testable import ReplyAI

final class MessageThreadTests: XCTestCase {

    // MARK: - Default values

    func testDefaultsMatchInitSignature() {
        let t = MessageThread(
            id: "T1", channel: .imessage,
            name: "Maya Lee", avatar: "ML",
            preview: "see you then", time: "10:14 AM"
        )
        // Defaults documented in init signature.
        XCTAssertEqual(t.unread, 0)
        XCTAssertFalse(t.pinned)
        XCTAssertEqual(t.contextCount, 41)
        XCTAssertNil(t.contextSummary)
        XCTAssertNil(t.chatGUID)
        XCTAssertFalse(t.hasAttachment)
    }

    // MARK: - Identifiable / Hashable

    func testIdentityIsBackedByID() {
        let a = MessageThread(id: "X", channel: .slack, name: "n", avatar: "A",
                              preview: "p", time: "t")
        let b = MessageThread(id: "X", channel: .slack, name: "n", avatar: "A",
                              preview: "p", time: "t")
        // Identifiable.id passthrough — used as ForEach key everywhere.
        XCTAssertEqual(a.id, "X")
        XCTAssertEqual(a.id, b.id)
    }

    func testHashableEqualityRespectsAllFields() {
        let base = MessageThread(id: "T", channel: .imessage, name: "n",
                                 avatar: "A", preview: "p", time: "t",
                                 unread: 0, pinned: false)
        let differingUnread = MessageThread(id: "T", channel: .imessage, name: "n",
                                            avatar: "A", preview: "p", time: "t",
                                            unread: 5, pinned: false)
        XCTAssertNotEqual(base, differingUnread,
            "two threads differing only in unread count must compare unequal")
    }

    func testHashableSameContentsHashEqual() {
        let a = MessageThread(id: "T", channel: .imessage, name: "n", avatar: "A",
                              preview: "p", time: "t", unread: 3,
                              chatGUID: "iMessage;-;+15551234567")
        let b = MessageThread(id: "T", channel: .imessage, name: "n", avatar: "A",
                              preview: "p", time: "t", unread: 3,
                              chatGUID: "iMessage;-;+15551234567")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - chatGUID + hasAttachment carry-through

    func testChatGUIDIsPassedThroughVerbatim() {
        let groupGUID = "iMessage;+;chat1234567890"
        let t = MessageThread(id: "G", channel: .imessage, name: "Group",
                              avatar: "G", preview: "x", time: "t",
                              chatGUID: groupGUID)
        XCTAssertEqual(t.chatGUID, groupGUID,
            "chatGUID must be stored verbatim — IMessageSender uses it directly")
    }

    func testHasAttachmentDefaultsFalseAndCanBeSet() {
        let off = MessageThread(id: "A", channel: .imessage, name: "n", avatar: "A",
                                preview: "p", time: "t")
        let on = MessageThread(id: "A", channel: .imessage, name: "n", avatar: "A",
                               preview: "p", time: "t", hasAttachment: true)
        XCTAssertFalse(off.hasAttachment)
        XCTAssertTrue(on.hasAttachment)
    }
}

final class MessageModelTests: XCTestCase {

    func testAuthorRawValuesAreStable() {
        // .them and .me ship into fixtures + any future JSON projections.
        XCTAssertEqual(Message.Author.them.rawValue, "them")
        XCTAssertEqual(Message.Author.me.rawValue, "me")
    }

    func testDefaultsMatchInitSignature() {
        let m = Message(from: .them, text: "hi", time: "10:00 AM")
        XCTAssertEqual(m.rowID, 0,
            "rowID defaults to 0 — fixtures and mocks that don't care about dedup")
        XCTAssertFalse(m.hasAttachment)
        XCTAssertFalse(m.isRead)
        XCTAssertNil(m.deliveredAt)
    }

    func testEachInstanceGetsADistinctUUIDByDefault() {
        let a = Message(from: .me, text: "x", time: "t")
        let b = Message(from: .me, text: "x", time: "t")
        XCTAssertNotEqual(a.id, b.id,
            "default UUID must be regenerated per init — id is not content-stable")
    }

    func testExplicitIDIsRespected() {
        let id = UUID()
        let m = Message(id: id, from: .them, text: "x", time: "t")
        XCTAssertEqual(m.id, id)
    }

    func testHashableEqualityRespectsRowID() {
        let id = UUID()
        let a = Message(id: id, from: .them, text: "x", time: "t", rowID: 1)
        let b = Message(id: id, from: .them, text: "x", time: "t", rowID: 2)
        XCTAssertNotEqual(a, b,
            "two messages differing only in rowID must compare unequal — the rule engine dedups by rowID")
    }
}

// MARK: - REP-XX: per-field equality contract

/// Pin that every field contributes to MessageThread equality / hash. The
/// rule engine and SwiftUI selection use the synthesized `==` to detect
/// thread changes; if any field stops contributing, the inbox would miss
/// updates (e.g. an unread-count bump or a pinned-state flip would fail
/// to invalidate the cached row and the UI would lag the model).
final class MessageThreadEqualityFieldsTests: XCTestCase {

    private func base() -> MessageThread {
        MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "p", time: "t", unread: 0, pinned: false,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;-;+15551234567",
            hasAttachment: false
        )
    }

    func testEqualityRespectsChannel() {
        let other = MessageThread(
            id: "T", channel: .slack, name: "n", avatar: "A",
            preview: "p", time: "t", unread: 0, pinned: false,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;-;+15551234567", hasAttachment: false
        )
        XCTAssertNotEqual(base(), other,
            "channel difference must break equality — channel-filtered views depend on it")
    }

    func testEqualityRespectsPinned() {
        let other = MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "p", time: "t", unread: 0, pinned: true,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;-;+15551234567", hasAttachment: false
        )
        XCTAssertNotEqual(base(), other,
            "pinned-state flip must break equality so the sidebar reorders")
    }

    func testEqualityRespectsChatGUID() {
        let other = MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "p", time: "t", unread: 0, pinned: false,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;+;chat1234567890",  // group instead of 1:1
            hasAttachment: false
        )
        XCTAssertNotEqual(base(), other,
            "chatGUID difference must break equality — IMessageSender routes by it")
    }

    func testEqualityRespectsContextSummary() {
        let other = MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "p", time: "t", unread: 0, pinned: false,
            contextCount: 41, contextSummary: "summary changed",
            chatGUID: "iMessage;-;+15551234567", hasAttachment: false
        )
        XCTAssertNotEqual(base(), other,
            "contextSummary change must invalidate the row's cache")
    }

    func testEqualityRespectsHasAttachment() {
        let other = MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "p", time: "t", unread: 0, pinned: false,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;-;+15551234567", hasAttachment: true
        )
        XCTAssertNotEqual(base(), other,
            "hasAttachment flip must break equality — rule engine reads this column instead of the 📎 sentinel")
    }

    func testEqualityRespectsPreviewAndTime() {
        let differingPreview = MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "different", time: "t", unread: 0, pinned: false,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;-;+15551234567", hasAttachment: false
        )
        XCTAssertNotEqual(base(), differingPreview,
            "preview text drives the sidebar row label — must contribute to equality")

        let differingTime = MessageThread(
            id: "T", channel: .imessage, name: "n", avatar: "A",
            preview: "p", time: "yesterday", unread: 0, pinned: false,
            contextCount: 41, contextSummary: nil,
            chatGUID: "iMessage;-;+15551234567", hasAttachment: false
        )
        XCTAssertNotEqual(base(), differingTime,
            "time chip auto-ticks; the row must invalidate when it advances")
    }
}
