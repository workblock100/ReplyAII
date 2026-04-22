import Foundation

/// File-system watcher for `~/Library/Messages/chat.db` (and its
/// write-ahead log). Coalesces a burst of writes into a single
/// debounced callback so we don't re-sync 10 times per incoming
/// iMessage.
///
/// The Messages app uses SQLite WAL journaling, so most new-message
/// writes land in `chat.db-wal` before being checkpointed into
/// `chat.db`. We watch both paths and fire once.
///
/// When the system cancels a DispatchSource (e.g. `chat.db` is moved
/// or the FD becomes invalid during iCloud sync), the watcher
/// schedules a restart with exponential backoff starting at
/// `restartDelay`, doubling each attempt up to 60 s. Call
/// `stopWatching()` for intentional shutdown — that prevents restart.
final class ChatDBWatcher: @unchecked Sendable {
    private let paths: [String]
    private let debounce: TimeInterval
    /// Initial delay before first restart attempt; doubles on each retry, capped at 60 s.
    let restartDelay: TimeInterval
    private let queue = DispatchQueue(label: "co.replyai.chatdb-watcher", qos: .utility)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fds: [Int32] = []
    private var pending: DispatchWorkItem?
    private let onChange: @Sendable () -> Void

    // Thread-safe stopped flag — set on intentional shutdown to block restart.
    private let stopped = Locked<Bool>(false)
    // Tracks restart attempts to compute exponential backoff.
    // Package-internal so tests can verify scheduling without waiting for the delay.
    let restartCount = Locked<Int>(0)

    init(
        paths: [String] = [
            (NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath as String),
            (NSString(string: "~/Library/Messages/chat.db-wal").expandingTildeInPath as String),
        ],
        debounce: TimeInterval = 0.6,
        restartDelay: TimeInterval = 5.0,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.paths = paths
        self.debounce = debounce
        self.restartDelay = restartDelay
        self.onChange = onChange
    }

    deinit { stopWatching() }

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

    /// Cancel all FS sources and prevent any pending restart from firing.
    /// Use this for intentional shutdown (e.g. FDA revoked, app teardown).
    func stopWatching() {
        stopped.withLock { $0 = true }
        for s in sources { s.cancel() }
        for fd in fds where fd >= 0 { close(fd) }
        sources.removeAll()
        fds.removeAll()
        pending?.cancel()
        pending = nil
    }

    /// Alias kept for call sites that pre-date `stopWatching()`.
    func stop() { stopWatching() }

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

        src.setCancelHandler { [weak self] in
            close(fd)
            guard let self = self, !self.stopped.withLock({ $0 }) else { return }
            self.scheduleRestart()
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

    /// Schedule a restart with exponential backoff via DispatchQueue.main.
    private func scheduleRestart() {
        let count = restartCount.withLock { n -> Int in
            let c = n
            n += 1
            return c
        }
        let delay = min(restartDelay * pow(2.0, Double(count)), 60.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.stopped.withLock({ $0 }) else { return }
            self.sources.removeAll()
            self.fds.removeAll()
            self.start()
        }
    }

    /// Exposed at package level so tests can trigger the same recovery path
    /// as a system-initiated cancel without real DispatchSource objects.
    func simulateSystemCancel() {
        queue.sync { [weak self] in
            guard let self = self, !self.stopped.withLock({ $0 }) else { return }
            self.scheduleRestart()
        }
    }
}
