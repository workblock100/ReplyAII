import Foundation

/// Persists draft text to disk so the composer can be pre-populated on next
/// launch without waiting for the LLM to regenerate a draft the user already
/// refined. Files live in ~/Library/Application Support/ReplyAI/drafts/ and
/// are pruned when they are older than 7 days.
final class DraftStore: Sendable {

    private let draftsDirectory: URL

    /// Production init uses ~/Library/Application Support/ReplyAI/drafts/.
    /// Tests inject a temp-directory URL so no real files are written.
    init(draftsDirectory: URL? = nil) {
        if let url = draftsDirectory {
            self.draftsDirectory = url
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.draftsDirectory = appSupport
                .appendingPathComponent("ReplyAI", isDirectory: true)
                .appendingPathComponent("drafts", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.draftsDirectory,
            withIntermediateDirectories: true
        )
        pruneStale()
    }

    // MARK: - Read / Write

    /// Persist draft text for a thread. The file name is derived from the
    /// thread ID so re-writes are idempotent.
    /// No-ops on an empty threadID — `fileURL(for: "")` would otherwise
    /// produce `.md` (a hidden filename), and both `listStoredDraftIDs`
    /// and `pruneStale` skip hidden files. The result would be a draft
    /// silently written to disk that no API can ever read back or prune.
    /// Caller error; refuse rather than corrupt on-disk state.
    func write(threadID: String, text: String) {
        guard !threadID.isEmpty else { return }
        let url = fileURL(for: threadID)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Return the persisted draft text for a thread, or nil if none exists.
    /// Symmetric with `write` — nil on empty threadID rather than reading
    /// the hidden `.md` slot.
    func read(threadID: String) -> String? {
        guard !threadID.isEmpty else { return nil }
        let url = fileURL(for: threadID)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Remove the persisted draft for a thread (e.g. after send or archive).
    /// Symmetric with `write` — no-op on empty threadID.
    func delete(threadID: String) {
        guard !threadID.isEmpty else { return }
        try? FileManager.default.removeItem(at: fileURL(for: threadID))
    }

    /// Returns the thread IDs of every persisted draft. Each .md filename stem
    /// is the sanitized thread ID; callers can cross-reference against live
    /// threads to detect orphaned entries whose threads have been deleted.
    func listStoredDraftIDs() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: draftsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        return (enumerator.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - Prune

    /// Default retention window in days. After this many days without
    /// modification a draft is pruned from `~/Library/Application Support/
    /// ReplyAI/drafts/`. Drift here changes user-visible draft retention
    /// without an API change — pinned in `DraftStoreTests`.
    static let defaultPruneDays = 7

    /// Remove draft files that are older than `defaultPruneDays`. Called
    /// once from init so stale drafts don't accumulate indefinitely.
    func pruneStale(olderThan days: Int = DraftStore.defaultPruneDays) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let enumerator = FileManager.default.enumerator(
            at: draftsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = attrs.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private func fileURL(for threadID: String) -> URL {
        // Sanitize threadID so it is safe as a filename component.
        let safe = threadID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        return draftsDirectory.appendingPathComponent("\(safe).md")
    }
}
