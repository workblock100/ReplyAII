import SwiftUI

/// `set-model` — real on-device model status. The toggle wires into
/// `PreferenceKey.useMLX` (also read by `InboxScreen` to swap StubLLMService
/// for MLXDraftService). The "Active model" + "Cache" cards reflect actual
/// disk state and the toggled mode rather than fixture text.
struct SetModelView: View {
    @AppStorage(PreferenceKey.useMLX) private var useMLX = PreferenceDefaults.useMLX
    @State private var cacheStatus: CacheStatus = .unknown

    /// Hard-coded to match MLXDraftService's default — surfacing it here
    /// keeps the Settings UI honest about what would actually load.
    private let modelID: String = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    private let modelDisplayName: String = "Llama-3.2-3B · 4-bit"

    enum CacheStatus: Equatable {
        case unknown
        case notDownloaded
        case downloaded(sizeBytes: Int64)
    }

    var body: some View {
        SettingsShell(active: .model) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Model")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                HStack(alignment: .top, spacing: 12) {
                    activeCard.frame(maxWidth: .infinity)
                    cacheCard.frame(maxWidth: .infinity)
                }
                .padding(.top, 24)

                mlxToggleCard
                    .padding(.top, 16)

                privacyNote
                    .padding(.top, 16)
            }
        }
        .task { refreshCacheStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCacheStatus()
        }
    }

    private var activeCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVE MODE")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(useMLX ? Theme.Color.accent : Theme.Color.fgMute)
                Text(useMLX ? modelDisplayName : "Stub (instant fixtures)")
                    .font(Theme.Font.sans(22))
                    .tracking(-0.44)
                    .foregroundStyle(Theme.Color.fg)
                    .padding(.top, 8)
                Text(useMLX ? modelID : "MLX off — drafts come from a deterministic stub")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cacheCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MODEL CACHE")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                Text(cacheHeading)
                    .font(Theme.Font.sans(22))
                    .tracking(-0.44)
                    .foregroundStyle(Theme.Color.fg)
                    .padding(.top, 8)
                Text(cacheDetail)
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mlxToggleCard: some View {
        Card(padding: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("USE ON-DEVICE MODEL")
                        .font(Theme.Font.mono(10))
                        .tracking(1.0)
                        .foregroundStyle(useMLX ? Theme.Color.accent : Theme.Color.fgMute)
                    Text("Route drafts through MLX running locally on this Mac.")
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Color.fg)
                    Text("First enable downloads \(modelDisplayName) (~2 GB) into ~/Library/Caches/huggingface/hub/. New drafts will be slow until download + first load finishes (~60–120s on Apple Silicon). After that, ~80 tok/s. Turning this off re-routes to the stub — the cached weights stay on disk.")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Color.fgMute)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PillToggle(value: $useMLX)
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Text("Drafts never leave your Mac. The on-device model runs entirely in your process; no API calls.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }

    // MARK: - Cache state

    private var cacheHeading: String {
        switch cacheStatus {
        case .unknown:                       return "Checking…"
        case .notDownloaded:                 return "Not yet downloaded"
        case .downloaded(let bytes):         return formatBytes(bytes)
        }
    }

    private var cacheDetail: String {
        switch cacheStatus {
        case .unknown:
            return "—"
        case .notDownloaded:
            return useMLX
                ? "First draft after enabling will trigger the download."
                : "Enable the toggle below to download Llama-3.2-3B (~2 GB)."
        case .downloaded:
            return "Cached at ~/Library/Caches/huggingface/hub/"
        }
    }

    /// Walk the HuggingFace cache directory to estimate total bytes occupied
    /// by any downloaded model snapshots. Returns `.notDownloaded` if the
    /// directory is missing or empty.
    private func refreshCacheStatus() {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Caches/huggingface/hub")
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            cacheStatus = .notDownloaded
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            cacheStatus = .notDownloaded
            return
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        cacheStatus = total > 0 ? .downloaded(sizeBytes: total) : .notDownloaded
    }

    private func formatBytes(_ n: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: n)
    }
}
