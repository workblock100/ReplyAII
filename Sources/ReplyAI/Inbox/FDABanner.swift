import SwiftUI
import AppKit

/// Banner shown above the inbox when Full Disk Access hasn't been
/// granted to the app. Deep-links straight to the FDA pane in System
/// Settings and offers a retry once the user grants permission.
struct FDABanner: View {
    var hint: String
    var onRetry: () -> Void

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

            VStack(alignment: .leading, spacing: 2) {
                Text("ReplyAI needs Full Disk Access to read iMessage")
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
                Text("Open System Settings")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule(style: .continuous).fill(Theme.Color.accent))
            }
            .buttonStyle(.plain)

            Button(action: onRetry) {
                Text("Retry")
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
