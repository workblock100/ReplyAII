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

    // MARK: - REP-147: concurrent write+read for same threadID is race-free

    func testConcurrentWriteReadNoCrash() {
        let store = DraftStore(draftsDirectory: tmpDir)
        let texts = (0..<10).map { "concurrent write \($0)" }

        DispatchQueue.concurrentPerform(iterations: 20) { i in
            if i < 10 {
                store.write(threadID: "race-thread", text: texts[i])
            } else {
                _ = store.read(threadID: "race-thread")
            }
        }
        // Reaching here without crash = pass.
    }

    func testConcurrentWriteResultIsValid() {
        let store = DraftStore(draftsDirectory: tmpDir)

        DispatchQueue.concurrentPerform(iterations: 20) { i in
            if i < 10 {
                store.write(threadID: "valid-race", text: "write-\(i)")
            } else {
                _ = store.read(threadID: "valid-race")
            }
        }

        // After all concurrent ops, read must return a non-empty string written by one of the writers.
        let result = store.read(threadID: "valid-race")
        XCTAssertNotNil(result, "post-race read must return a valid string")
        if let r = result {
            XCTAssertTrue(r.hasPrefix("write-"), "result must be one of the written values, got: \(r)")
        }
    }

    // MARK: - REP-176: 7-day prune threshold boundary

    func testPruneRemovesFilesOlderThanSevenDays() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "rep176-old", text: "stale content")

        let fileURL = tmpDir.appendingPathComponent("rep176-old.md")
        let eightDaysAgo = Date().addingTimeInterval(-8 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: eightDaysAgo],
            ofItemAtPath: fileURL.path
        )

        let store2 = DraftStore(draftsDirectory: tmpDir)
        XCTAssertNil(store2.read(threadID: "rep176-old"),
                     "file aged 8 days must be pruned on init (threshold is 7 days)")
    }

    func testPrunePreservesFilesNewerThanSevenDays() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "rep176-recent", text: "recent content")

        let fileURL = tmpDir.appendingPathComponent("rep176-recent.md")
        let sixDaysAgo = Date().addingTimeInterval(-6 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: sixDaysAgo],
            ofItemAtPath: fileURL.path
        )

        let store2 = DraftStore(draftsDirectory: tmpDir)
        XCTAssertEqual(store2.read(threadID: "rep176-recent"), "recent content",
                       "file aged 6 days must survive init (below 7-day threshold)")
    }

    // MARK: - REP-163: listStoredDraftIDs

    func testListStoredDraftIDsEmptyStore() {
        let store = DraftStore(draftsDirectory: tmpDir)
        XCTAssertEqual(store.listStoredDraftIDs(), [],
                       "empty store must return an empty list")
    }

    func testListStoredDraftIDsReturnsAllSavedIDs() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "thread-A", text: "draft A")
        store.write(threadID: "thread-B", text: "draft B")
        store.write(threadID: "thread-C", text: "draft C")

        let ids = Set(store.listStoredDraftIDs())
        XCTAssertEqual(ids, ["thread-A", "thread-B", "thread-C"],
                       "must return one ID per saved draft")
    }

    func testListStoredDraftIDsExcludesDeletedEntry() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "keep-me", text: "still here")
        store.write(threadID: "delete-me", text: "going away")

        store.delete(threadID: "delete-me")
        let ids = store.listStoredDraftIDs()

        XCTAssertTrue(ids.contains("keep-me"),
                      "non-deleted ID must remain in list")
        XCTAssertFalse(ids.contains("delete-me"),
                       "deleted ID must not appear in list")
    }

    func testListStoredDraftIDsIsOrderIndependent() {
        let store = DraftStore(draftsDirectory: tmpDir)
        let threadIDs = ["zeta", "alpha", "mu"]
        threadIDs.forEach { store.write(threadID: $0, text: "content") }

        let returned = Set(store.listStoredDraftIDs())
        let expected = Set(threadIDs)
        XCTAssertEqual(returned, expected,
                       "listing must be order-independent — set equality suffices")
    }

    // MARK: - Defensive paths

    /// Empty draft text must round-trip as the empty string, not nil. The
    /// composer treats nil ("never had a draft") and "" ("user cleared the
    /// draft") differently — a clear-then-relaunch must come back empty,
    /// not regenerate from scratch. This is the regression that turns
    /// "I cleared this on purpose" into "the LLM keeps refilling it."
    func testEmptyDraftRoundTripsAsEmptyStringNotNil() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "cleared", text: "")
        XCTAssertEqual(store.read(threadID: "cleared"), "",
            "empty-string write must round-trip as empty, not as nil")
        XCTAssertTrue(store.listStoredDraftIDs().contains("cleared"),
            "empty draft still occupies a slot — listing must include it")
    }

    /// Empty threadID is refused on every API. Without the guards,
    /// `fileURL(for: "")` resolves to a `.md` (hidden) file:
    ///   - `write("", "x")` would silently write to disk
    ///   - `read("")` would return that text
    ///   - `listStoredDraftIDs()` would NOT see it (skipsHiddenFiles)
    ///   - `pruneStale()` would NEVER prune it (also skipsHiddenFiles)
    /// Net effect: orphan drafts that accumulate forever, invisible to
    /// every observability surface. Refuse the operation outright.
    func testEmptyThreadIDIsRefusedOnEveryAPI() {
        let store = DraftStore(draftsDirectory: tmpDir)

        store.write(threadID: "", text: "would-be-orphan")
        XCTAssertNil(store.read(threadID: ""),
            "empty threadID write must be a no-op, so read still returns nil")
        XCTAssertFalse(store.listStoredDraftIDs().contains(""),
            "empty threadID must never appear in listStoredDraftIDs (would-be hidden file is unreadable anyway)")

        // delete on empty must also be a no-op — symmetric with write
        store.delete(threadID: "")  // must not throw / log
    }

    /// `delete()` on a thread that never had a persisted draft must be a
    /// silent no-op. The inbox calls delete after every send/archive
    /// without checking presence first; throwing or printing here would
    /// flood logs with phantom errors for every never-drafted thread.
    func testDeleteOnUnknownThreadIsSilentNoOp() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.delete(threadID: "never-existed")
        XCTAssertNil(store.read(threadID: "never-existed"),
            "delete on absent thread leaves state unchanged")
        XCTAssertTrue(store.listStoredDraftIDs().isEmpty,
            "delete on absent thread must not create a marker file")
    }

    /// Custom prune horizon must be honored. Default is 7 days; passing a
    /// smaller value (e.g. 1 day for an aggressive sweep before
    /// factory-reset migration) needs to actually prune the 2-day-old
    /// drafts that the default would keep. Pinning so a future refactor
    /// of the cutoff math doesn't silently ignore the parameter.
    func testPruneStaleHonorsCustomHorizon() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "two-day-old", text: "content")

        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400)
        let fileURL = tmpDir.appendingPathComponent("two-day-old.md")
        try FileManager.default.setAttributes(
            [.modificationDate: twoDaysAgo],
            ofItemAtPath: fileURL.path
        )

        // Default horizon (7 days) keeps it; explicit 1-day horizon drops it.
        store.pruneStale(olderThan: 7)
        XCTAssertEqual(store.read(threadID: "two-day-old"), "content",
            "default horizon must keep a 2-day-old draft")

        store.pruneStale(olderThan: 1)
        XCTAssertNil(store.read(threadID: "two-day-old"),
            "1-day horizon must prune the 2-day-old draft")
    }

    /// `listStoredDraftIDs` reflects the filesystem after `pruneStale`
    /// runs at the next init. A stale entry should disappear from the
    /// list along with the file — the list method does not cache.
    func testListStoredDraftIDsExcludesPrunedEntries() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: "old", text: "stale")
        store.write(threadID: "fresh", text: "keep")

        // Back-date the "old" file so the next init prunes it.
        let oldURL = tmpDir.appendingPathComponent("old.md")
        let eightDaysAgo = Date().addingTimeInterval(-8 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: eightDaysAgo],
            ofItemAtPath: oldURL.path
        )

        // Fresh init triggers prune.
        let store2 = DraftStore(draftsDirectory: tmpDir)
        let ids = store2.listStoredDraftIDs()
        XCTAssertFalse(ids.contains("old"),
            "pruned entry must drop out of the listing")
        XCTAssertTrue(ids.contains("fresh"),
            "non-stale entries must remain in the listing")
    }

    // MARK: - Filename sanitization defense-in-depth

    /// Pin that the on-disk filename actually drops the `/` and `:`
    /// characters in real chat GUIDs (`iMessage;-;+15551234567` is fine,
    /// but `iMessage:+;chat12345/extra` would otherwise create a
    /// subdirectory and fail to write). The existing round-trip test
    /// passes if write+read sanitize the same way, even if the disk
    /// filename were broken — this test verifies the disk side directly
    /// via `listStoredDraftIDs()` so a future change to the sanitizer
    /// (e.g. switching to URL-percent-encoding) shows up here as a
    /// deliberate filename-shape change.
    func testSanitizedFilenameContainsNoPathSeparators() {
        let store = DraftStore(draftsDirectory: tmpDir)
        let tricky = "iMessage:+;chat12345/extra"
        store.write(threadID: tricky, text: "x")

        let stored = store.listStoredDraftIDs()
        XCTAssertEqual(stored.count, 1)
        let onDisk = stored[0]
        XCTAssertFalse(onDisk.contains("/"),
            "on-disk filename stem must not contain `/` — would create a subdirectory")
        XCTAssertFalse(onDisk.contains(":"),
            "on-disk filename stem must not contain `:` — Finder reserved separator")
    }

    /// Pin that a path-traversal-style threadID writes inside the drafts
    /// directory rather than escaping it. The sanitizer turns `/` into
    /// `_`, so `../../etc/passwd` becomes a single innocuous filename
    /// stem `.._.._etc_passwd`. Without this defense a malicious or
    /// accidental threadID could land outside `draftsDirectory`,
    /// corrupting unrelated user data. This is a defense-in-depth pin —
    /// production threadIDs are chat GUIDs, not user input — but the
    /// invariant is cheap to enforce in tests so a future refactor that
    /// drops the sanitizer surfaces here.
    func testTraversalStyleThreadIDStaysInsideDraftsDirectory() throws {
        let store = DraftStore(draftsDirectory: tmpDir)
        let traversal = "../../etc/passwd"
        store.write(threadID: traversal, text: "x")

        // Round-trip succeeds — the file is reachable by the same threadID.
        XCTAssertEqual(store.read(threadID: traversal), "x")

        // Nothing leaked outside the drafts directory: the parent of tmpDir
        // must not now contain an `etc/` subdirectory or a `passwd` file.
        let parent = tmpDir.deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: parent.appendingPathComponent("etc").path),
            "no `etc/` directory should exist beside the drafts directory after a traversal-style threadID write")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: parent.appendingPathComponent("passwd").path),
            "no `passwd` file should exist beside the drafts directory")

        // Enumerate the drafts directory directly (without the hidden-file
        // filter that listStoredDraftIDs applies) so we can pin that the
        // single file actually written has no `/` in its on-disk name.
        let entries = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        let mdFiles = entries.filter { $0.pathExtension == "md" }
        XCTAssertEqual(mdFiles.count, 1,
            "exactly one .md file must land in the drafts directory")
        XCTAssertFalse(mdFiles[0].lastPathComponent.contains("/"),
            "the on-disk filename must not preserve any path separators from the input")
    }

    /// Pin a known limitation of `listStoredDraftIDs()`: when a threadID
    /// starts with a literal `.`, the on-disk filename is hidden (POSIX
    /// dot-prefix convention) and the enumerator's `skipsHiddenFiles`
    /// option silently drops it from the listing — even though
    /// `read()`/`delete()` for that threadID still work correctly. This
    /// is the surface that `testTraversalStyleThreadIDStaysInsideDraftsDirectory`
    /// trips over for `../../...` inputs (sanitized prefix is `..`). Pin
    /// the behavior here so a future change to the enumerator (e.g.
    /// dropping the hidden-files skip) is a deliberate edit visible in
    /// this test rather than a quiet surface change.
    func testListStoredDraftIDsSkipsDotPrefixedFilenames() {
        let store = DraftStore(draftsDirectory: tmpDir)
        store.write(threadID: ".dotty", text: "hidden")
        store.write(threadID: "visible", text: "shown")

        // read() works for both — the round-trip path doesn't enumerate.
        XCTAssertEqual(store.read(threadID: ".dotty"), "hidden")
        XCTAssertEqual(store.read(threadID: "visible"), "shown")

        // listStoredDraftIDs() drops the dot-prefixed entry due to
        // FileManager's skipsHiddenFiles option.
        let listed = store.listStoredDraftIDs()
        XCTAssertEqual(listed, ["visible"],
            "listStoredDraftIDs must currently drop dot-prefixed filenames; pin the behavior so a future enumerator change surfaces here")
    }

}
