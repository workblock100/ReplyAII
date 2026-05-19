import SwiftUI
import AppKit

/// Banner shown above the inbox when ReplyAI is running in Limited Mode
/// — i.e. `Preferences.demoModeActive == true`. The user is seeing demo
/// fixture threads rather than real conversations because no channel has
/// returned data yet (FDA denied + Slack disconnected + AppleScript silent).
///
/// REP-259: this is the user-facing affordance for the 2026-04-23 pivot's
/// "app must be valuable with zero permissions granted" promise. The
/// banner exists so the user understands what they're looking at *and*
/// has a one-click path to grant permissions when ready.
///
/// Lifecycle: dismissable per-session via the close button (`onDismiss`).
/// Re-shows on next launch until `demoModeActive` flips to `false` (which
/// happens automatically the first time `syncFromIMessage()` or any other
/// channel sync returns ≥1 real thread — REP-228).
struct LimitedModeBanner: View {
    var onOpenSettings: () -> Void
    var onDismiss: () -> Void

    /// User-visible copy pinned in a single place. Drift here would force
    /// the LimitedModeBannerTests string-pin tests to fail; updating the
    /// pin in tests + here on the same commit is the intended workflow.
    enum Strings {
        static let title       = "You're in Limited Mode"
        static let body        = "These are demo conversations. Grant permissions to see your real messages."
        static let openCTA     = "Open Settings"
        static let dismissHint = "Dismiss"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                        .fill(Theme.Color.accent.opacity(0.12))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.title)
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text(Strings.body)
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineLimit(2)
            }
            Spacer()

            Button(action: onOpenSettings) {
                Text(Strings.openCTA)
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule(style: .continuous).fill(Theme.Color.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.openCTA)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.fgDim)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Capsule(style: .continuous).stroke(Theme.Color.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.dismissHint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.Color.accent.opacity(0.06))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.accent.opacity(0.20)).frame(height: 1) }
    }
}
