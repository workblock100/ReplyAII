import SwiftUI

struct SetPrivacyView: View {
    @State private var crashReports = true
    @State private var licenseUpdates = true
    @State private var iCloudSync = false

    var body: some View {
        SettingsShell(active: .privacy) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                Card(padding: 22, borderColor: Theme.Color.accent.opacity(0.2), tint: Theme.Color.accent.opacity(0.04)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "shield")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.Color.accent)
                            Text("Everything stays on this Mac.")
                                .font(Theme.Font.sans(15, weight: .medium))
                                .foregroundStyle(Theme.Color.fg)
                        }
                        Text("No message text leaves your device. The only outbound network calls are license checks and crash reports (both can be disabled below).")
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Color.fgDim)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 22)

                VStack(spacing: 0) {
                    ToggleRow(label: "Send anonymous crash reports", value: $crashReports,
                              helper: "Stacktraces only. No message content, ever.")
                    ToggleRow(label: "Check for license updates",  value: $licenseUpdates)
                    ToggleRow(label: "Use iCloud to sync voice profile to other Macs", value: $iCloudSync,
                              helper: "End-to-end encrypted. You choose.")
                    SettingRow(label: "On-device data", value: "2,014 messages · 14.2 MB · voice profile v34")
                    SettingRow(label: "Export your data", value: "Voice profile, smart rules, and settings as a single .replyai file")
                    SettingRow(label: "Wipe everything ReplyAI has seen",
                               value: "Reset voice profile, clear all cached threads, keep app installed",
                               danger: "Factory reset")
                }
                .padding(.top, 16)
            }
        }
    }
}

