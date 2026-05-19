import SwiftUI
import AppKit

/// Banner shown above the inbox when Full Disk Access hasn't been
/// granted to the app. Deep-links straight to the FDA pane in System
/// Settings and offers a retry once the user grants permission.
struct FDABanner: View {
    var hint: String
    var onRetry: () -> Void

    /// REP-UI-STR-HOIST-001 view 4 of 5. FDA banner is the highest-stakes
    /// permission prompt in the app — the user is being asked to grant
    /// macOS's most-feared privilege. Pinning the copy makes any softening
    /// or hardening of the wording an explicit PR-review decision.
    enum Strings {
        /// Header copy. NOTE: mentions iMessage — pivot-conflicted per the
        /// 2026-04-23 channel-agnostic pivot. iMessage is the channel that
        /// actually requires FDA (Slack uses OAuth, AppleScript-fallback
        /// uses Automation). Until the banner is gated to only-show when
        /// iMessage is the active channel, this copy stays as-is so the
        /// user understands *why* macOS is asking. Rewriting this to "to
        /// read your messages" without the gating change would confuse
        /// Slack-only users (no FDA prompt would mention FDA).
        static let header = "ReplyAI needs Full Disk Access to read iMessage"

        /// Primary CTA — opens the FDA pane in System Settings.app via
        /// the `x-apple.systempreferences:` deep link. Action verb +
        /// noun phrase; matches "Open inbox" / "Open ReplyAI" elsewhere.
        static let openSystemSettingsLabel = "Open System Settings"

        /// Secondary CTA — re-attempts the chat.db read after the user
        /// grants FDA. Single word; ReplyAI-specific (macOS conventions
        /// would use "Try Again" — we use the shorter form for the
        /// compact banner layout).
        static let retryLabel = "Retry"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Color.warn)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                        .fill(Theme.Color.warn.opacity(0.12))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.header)
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text(hint)
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineLimit(2)
            }
            Spacer()

            Button {
                openFDAPane()
            } label: {
                Text(Strings.openSystemSettingsLabel)
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule(style: .continuous).fill(Theme.Color.accent))
            }
            .buttonStyle(.plain)

            Button(action: onRetry) {
                Text(Strings.retryLabel)
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgDim)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .overlay(
                        Capsule(style: .continuous).stroke(Theme.Color.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.Color.warn.opacity(0.08))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.warn.opacity(0.25)).frame(height: 1) }
    }

    private func openFDAPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
