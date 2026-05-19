import SwiftUI

/// Privacy Settings pane. The privacy story is the product's primary
/// trust mechanism — the LLM runs on-device, message text never leaves
/// the Mac, and the only outbound network calls are license checks and
/// crash reports (both opt-out). The view binds three `@AppStorage`
/// keys directly so toggles persist instantly without round-tripping
/// through the view model — the user never wants to wonder whether a
/// privacy toggle "took."
struct SetPrivacyView: View {
    @AppStorage(PreferenceKey.crashReports)   private var crashReports   = PreferenceDefaults.crashReports
    @AppStorage(PreferenceKey.licenseUpdates) private var licenseUpdates = PreferenceDefaults.licenseUpdates
    @AppStorage(PreferenceKey.iCloudSync)     private var iCloudSync     = PreferenceDefaults.iCloudSync
    /// Stats refresh strategy: read on appearance, re-read on every
    /// settings-tab switch. Stats can drift mid-session as the user
    /// fires rules / sends drafts, but the privacy screen isn't a
    /// live dashboard — a manual refresh on revisit is enough.
    @State private var counters: Stats.CountersForUI = .init(
        draftsGenerated: 0,
        draftsSent: 0,
        messagesIndexed: 0,
        rulesMatchedCount: 0,
        rulesFiredTotal: 0,
        rulesFiredByAction: [:]
    )

    /// Format an integer counter with thousand separators so a real-user
    /// number (e.g. 12,304 messages indexed) renders the way the user
    /// expects, not as the wall-of-digits `12304`.
    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Acceptance rate — drafts sent over drafts generated. Returns
    /// `"—"` when zero drafts have been generated to avoid a 0/0 NaN
    /// crash or a misleading "0%" badge.
    private var acceptancePercent: String {
        guard counters.draftsGenerated > 0 else { return "—" }
        let pct = Int((Double(counters.draftsSent) / Double(counters.draftsGenerated) * 100.0).rounded())
        return "\(pct)%"
    }

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

                // REP-045: surface Stats counters so the user can see what
                // the app has actually done on-device. Stats are read on
                // first appear + re-read on .onAppear when the user navigates
                // back to this pane — a static snapshot is fine because the
                // privacy screen isn't a live dashboard.
                Text("Activity")
                    .font(Theme.Font.sans(11, weight: .medium))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    SettingRow(label: "Drafts generated", value: fmt(counters.draftsGenerated))
                    SettingRow(label: "Drafts sent",
                               value: "\(fmt(counters.draftsSent)) · \(acceptancePercent) sent of generated")
                    SettingRow(label: "Messages indexed", value: fmt(counters.messagesIndexed))
                    SettingRow(label: "Rules fired",
                               value: counters.rulesFiredTotal == 0
                                   ? "0"
                                   : "\(fmt(counters.rulesFiredTotal)) total · \(counters.rulesFiredByAction.count) action types")
                }

                Text("Settings")
                    .font(Theme.Font.sans(11, weight: .medium))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ToggleRow(label: "Send anonymous crash reports", value: $crashReports,
                              helper: "Stacktraces only. No message content, ever.")
                    ToggleRow(label: "Check for license updates",  value: $licenseUpdates)
                    ToggleRow(label: "Use iCloud to sync voice profile to other Macs", value: $iCloudSync,
                              helper: "End-to-end encrypted. You choose.")
                    SettingRow(label: "Export your data", value: "Voice profile, smart rules, and settings as a single .replyai file")
                    SettingRow(label: "Wipe everything ReplyAI has seen",
                               value: "Reset voice profile, clear all cached threads, keep app installed",
                               danger: "Factory reset",
                               dangerAction: { UserDefaults.wipeReplyAIDefaults() })
                }
            }
            .onAppear { counters = Stats.shared.countersForUI() }
        }
    }
}

