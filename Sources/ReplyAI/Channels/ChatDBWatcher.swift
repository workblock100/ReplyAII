import Foundation

/// File-system watcher for `~/Library/Messages/chat.db` (and its
/// write-ahead log). Coalesces a burst of writes into a single
/// debounced callback so we don't re-sync 10 times per incoming
/// iMessage.
///
/// The Messages app uses SQLite WAL journaling, so most new-message
/// writes land in `chat.db-wal` before being checkpointed into
/// `chat.db`. We watch both paths and fire once.
final class ChatDBWatcher: @unchecked Sendable {
    private let paths: [String]
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "co.replyai.chatdb-watcher", qos: .utility)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fds: [Int32] = []
    private var pending: DispatchWorkItem?
    private let onChange: @Sendable () -> Void

    init(
        paths: [String] = [
            (NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath as String),
            (NSString(string: "~/Library/Messages/chat.db-wal").expandingTildeInPath as String),
        ],
        debounce: TimeInterval = 0.6,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.paths = paths
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    /// Begin watching. Safe to call multiple times — second call is a
    /// no-op while already running.
    func start() {
        guard sources.isEmpty else { return }
        for path in paths {
            guard let src = makeSource(for: path) else { continue }
            src.resume()
            sources.append(src)
        }
    }

    func stop() {
        for s in sources { s.cancel() }
        for fd in fds where fd >= 0 { close(fd) }
        sources.removeAll()
        fds.removeAll()
        pending?.cancel()
        pending = nil
    }

    // MARK: - Private

    private func makeSource(for path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        fds.append(fd)

        let mask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename, .revoke]
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: mask, queue: queue
        )

        src.setEventHandler { [weak self] in
            self?.scheduleFire()
        }

        src.setCancelHandler {
            close(fd)
        }

        return src
    }

    /// Coalesce the current burst of events into a single fire after
    /// the debounce window elapses. Exposed at package level so tests
    /// can exercise the debounce logic without racing real fsevents.
    func scheduleFire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
