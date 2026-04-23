import XCTest
@testable import ReplyAI

final class DraftStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testDraftPersistsAcrossReinit() {
        let store1 = DraftStore(draftsDirectory: tmpDir)
        store1.write(threadID: "thread-abc", text: "Hello world")

        let store2 = DraftStore(draftsDirectory: tmpDir)
        XCTAssertEqual(store2.read(threadID: "thread-abc"), "Hello world")
    }

    func testUnknownThreadReturnsNil() {
        let store = DraftStore(draftsDirectory: tmpDir)
        XCTAssertNil(store.read(threadID: "does-not-exist"))
    }

    func testStaleDraftsArePruned() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "old-thread", text: "stale")

        // Back-date the file's modification timestamp to 8 days ago.
        let fileURL = tmpDir.appendingPathComponent("old-thread.md")
        let eightDaysAgo = Date().addingTimeInterval(-8 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: eightDaysAgo],
            ofItemAtPath: fileURL.path
        )

        // A fresh store prunes on init.
        let store2 = DraftStore(draftsDirectory: tmpDir)
        XCTAssertNil(store2.read(threadID: "old-thread"))
    }

    func testFreshDraftsAreNotPruned() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "fresh-thread", text: "keep me")

        // File is brand new — should survive prune.
        let store2 = DraftStore(draftsDirectory: tmpDir)
        XCTAssertEqual(store2.read(threadID: "fresh-thread"), "keep me")
    }

    func testDeleteRemovesDraft() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "to-delete", text: "ephemeral")
        store.delete(threadID: "to-delete")
        XCTAssertNil(store.read(threadID: "to-delete"))
    }

    func testThreadIDWithSpecialCharsIsSanitized() {
        let store = DraftStore(draftsDirectory: tmpDir)
        let tricky = "iMessage:+;chat12345/extra"
        store.write(threadID: tricky, text: "sanitized")
        XCTAssertEqual(store.read(threadID: tricky), "sanitized")
    }

    func testOverwriteReplacesExistingDraft() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "t1", text: "original")
        store.write(threadID: "t1", text: "updated")
        XCTAssertEqual(store.read(threadID: "t1"), "updated")
    }
}
