import SwiftUI

/// `ob-permissions` — deep-links into System Settings panes.
struct ObPermissionsView: View {
    private struct Perm { let icon: String; let t: String; let tag: String; let d: String; let status: Status
        enum Status { case granted, needs, skip
            var color: Color {
                switch self {
                case .granted: Theme.Color.accent
                case .needs:   Theme.Color.warn
                case .skip:    Theme.Color.fgFaint
                }
            }
            var label: String {
                switch self {
                case .granted: "Granted"
                case .needs:   "Grant"
                case .skip:    "Skip"
                }
            }
        }
    }

    private let perms: [Perm] = [
        .init(icon: "shield", t: "Full Disk Access", tag: "Required for iMessage",
              d: "To read Messages.app's local chat database. macOS will ask you to approve in System Settings.",
              status: .granted),
        .init(icon: "keyboard", t: "Accessibility", tag: "Required for global shortcuts",
              d: "So ⌘⇧R opens the composer from anywhere, including other apps.",
              status: .needs),
        .init(icon: "bubble.left", t: "Notifications", tag: "Recommended",
              d: "We'll only notify you for things that actually need a reply — never for 2FA codes or bots.",
              status: .needs),
        .init(icon: "gearshape", t: "Shortcuts & Focus", tag: "Optional",
              d: "Register as a Shortcuts app so you can build your own reply automations.",
              status: .skip),
    ]

    var body: some View {
        OnboardingStage(
            step: 3, total: 9,
            eyebrow: "System permissions",
            title: Text("A few macOS permissions ReplyAI needs.")
        ) {
            VStack(spacing: 10) {
                ForEach(perms, id: \.t) { p in
                    permCard(p)
                }
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Continue", icon: "arrow.right")
        } secondary: {
            GhostButton(title: "Skip for now")
        }
    }

    private func permCard(_ p: Perm) -> some View {
        Card(padding: 20) {
            HStack(spacing: 16) {
                OnboardingIconChip(name: p.icon, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(p.t)
                            .font(Theme.Font.sans(14, weight: .medium))
                            .foregroundStyle(Theme.Color.fg)
                        Text(p.tag.uppercased())
                            .font(Theme.Font.mono(10))
                            .tracking(0.9)
                            .foregroundStyle(Theme.Color.fgMute)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Theme.Color.lineStrong, lineWidth: 1)
                            )
                    }
                    Text(p.d)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Color.fgMute)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(p.status.label)
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(p.status.color)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        Capsule(style: .continuous)
                            .fill(p.status == .granted ? Theme.Color.accent.opacity(0.08) : Color.white.opacity(0.03))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(p.status.color, lineWidth: 1)
                    )
            }
        }
    }
}
