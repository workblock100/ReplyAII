import SwiftUI

struct SetAccountView: View {
    var body: some View {
        SettingsShell(active: .account) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Account")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                Card(padding: 22) {
                    HStack(spacing: 18) {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.79, green: 0.64, blue: 1.00),
                                         Color(red: 0.48, green: 0.36, blue: 1.00)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text("JS")
                                    .font(Theme.Font.sans(18, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Jordan Song")
                                .font(Theme.Font.sans(17, weight: .medium))
                                .foregroundStyle(Theme.Color.fg)
                            Text("jordan@songhome.co")
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Color.fgMute)
                            Text("PRO · RENEWS MAY 14")
                                .font(Theme.Font.mono(10))
                                .tracking(1.0)
                                .foregroundStyle(Theme.Color.accent)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            GhostButton(title: "Manage billing", height: 32, fontSize: 12)
                            GhostButton(title: "Sign out",       height: 32, fontSize: 12)
                        }
                    }
                }
                .padding(.top, 22)

                VStack(spacing: 0) {
                    SettingRow(label: "Name",         value: "Jordan Song")
                    SettingRow(label: "Email",        value: "jordan@songhome.co")
                    SettingRow(label: "Paired Macs",  value: "2 of 3",            helper: "Mac Studio · MacBook Air")
                    SettingRow(label: "Plan",         value: "Pro · $12/mo",      danger: "Downgrade to Free")
                }
                .padding(.top, 16)
            }
        }
    }
}

