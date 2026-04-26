import SwiftUI
import Contacts
import UserNotifications
#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

/// `ob-permissions` — actually-live permission checks + grant flow.
///
/// Each card reflects the real current TCC state and the button triggers
/// the right action for that permission:
///   • Full Disk Access  — opens System Settings (no API to request from app)
///   • Contacts          — calls `CNContactStore.requestAccess(for: .contacts)`
///   • Notifications     — calls `UNUserNotificationCenter.requestAuthorization`
///   • Accessibility     — opens System Settings (no in-process request API)
///
/// The view re-polls on appearance and every time the app becomes active so
/// returning from System Settings reflects the new state without a relaunch.
struct ObPermissionsView: View {
    enum Status: Equatable {
        case granted
        case needs
        case denied
        case skip

        var color: Color {
            switch self {
            case .granted: Theme.Color.accent
            case .needs:   Theme.Color.warn
            case .denied:  Theme.Color.warn
            case .skip:    Theme.Color.fgFaint
            }
        }
        var label: String {
            switch self {
            case .granted: "Granted"
            case .needs:   "Grant"
            case .denied:  "Denied"
            case .skip:    "Skip"
            }
        }
    }

    enum Kind: Hashable {
        case fullDiskAccess
        case contacts
        case notifications
        case accessibility
    }

    @State private var statuses: [Kind: Status] = [
        .fullDiskAccess: .needs,
        .contacts:       .needs,
        .notifications:  .needs,
        .accessibility:  .skip,
    ]

    var body: some View {
        OnboardingStage(
            step: 3, total: 9,
            eyebrow: "System permissions",
            title: Text("A few macOS permissions ReplyAI needs.")
        ) {
            VStack(spacing: 10) {
                permCard(
                    icon: "shield",
                    title: "Full Disk Access",
                    tag: "Required for iMessage",
                    detail: "Read Messages.app's local chat database. macOS will ask you to approve in System Settings.",
                    kind: .fullDiskAccess
                )
                permCard(
                    icon: "person.crop.circle",
                    title: "Contacts",
                    tag: "Recommended",
                    detail: "Resolve phone numbers to the names you have saved. Without this, threads display as raw phone numbers.",
                    kind: .contacts
                )
                permCard(
                    icon: "bubble.left",
                    title: "Notifications",
                    tag: "Recommended",
                    detail: "We'll only notify you for things that actually need a reply — never for 2FA codes or bots.",
                    kind: .notifications
                )
                permCard(
                    icon: "keyboard",
                    title: "Accessibility",
                    tag: "Required for ⌘⇧R",
                    detail: "So the global shortcut opens the composer from anywhere, including other apps.",
                    kind: .accessibility
                )
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Continue", icon: "arrow.right")
        } secondary: {
            GhostButton(title: "Skip for now")
        }
        .task { refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAll()
        }
    }

    // MARK: - Card

    private func permCard(icon: String, title: String, tag: String, detail: String, kind: Kind) -> some View {
        let status = statuses[kind] ?? .needs
        return Card(padding: 20) {
            HStack(spacing: 16) {
                OnboardingIconChip(name: icon, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(Theme.Font.sans(14, weight: .medium))
                            .foregroundStyle(Theme.Color.fg)
                        Text(tag.uppercased())
                            .font(Theme.Font.mono(10))
                            .tracking(0.9)
                            .foregroundStyle(Theme.Color.fgMute)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule(style: .continuous).stroke(Theme.Color.lineStrong, lineWidth: 1))
                    }
                    Text(detail)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Color.fgMute)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    request(kind)
                } label: {
                    Text(status.label)
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(status == .granted ? Theme.Color.accent.opacity(0.08) : Color.white.opacity(0.03))
                        )
                        .overlay(Capsule(style: .continuous).stroke(status.color, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(status == .granted)
            }
        }
    }

    // MARK: - State refresh

    private func refreshAll() {
        statuses[.fullDiskAccess] = currentFDA()
        statuses[.contacts]       = currentContacts()
        statuses[.accessibility]  = currentAccessibility()
        Task { @MainActor in
            statuses[.notifications] = await currentNotifications()
        }
    }

    // MARK: - Per-permission state checks

    private func currentFDA() -> Status {
        // No public API to query FDA. Probe by trying to read the chat.db
        // header bytes. Returns granted on success, needs otherwise.
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Messages/chat.db")
        guard let fh = FileHandle(forReadingAtPath: path) else { return .needs }
        defer { try? fh.close() }
        do {
            // SQLite header is 16 bytes "SQLite format 3\0".
            let header = try fh.read(upToCount: 16) ?? Data()
            return header.starts(with: Array("SQLite format 3\0".utf8)) ? .granted : .needs
        } catch {
            return .needs
        }
    }

    private func currentContacts() -> Status {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return .granted
        case .denied, .restricted:  return .denied
        case .notDetermined:        return .needs
        @unknown default:           return .needs
        }
    }

    private func currentAccessibility() -> Status {
        // AXIsProcessTrusted returns whether the process is in the
        // Accessibility allowlist. Pass false for the prompt option so
        // we don't trigger the system dialog from this status check.
        AXIsProcessTrustedWithOptions(nil) ? .granted : .needs
    }

    @MainActor
    private func currentNotifications() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied:                                return .denied
        case .notDetermined:                         return .needs
        @unknown default:                            return .needs
        }
    }

    // MARK: - Per-permission requests

    private func request(_ kind: Kind) {
        switch kind {
        case .fullDiskAccess:
            // No in-process API — open the Settings pane.
            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .contacts:
            Task { @MainActor in
                let store = CNContactStore()
                _ = try? await store.requestAccess(for: .contacts)
                refreshAll()
            }
        case .notifications:
            Task { @MainActor in
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                refreshAll()
            }
        case .accessibility:
            // Same constraint as FDA — no in-process request API.
            openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    private func openSettings(_ url: String) {
        guard let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}
