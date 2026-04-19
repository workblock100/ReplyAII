import SwiftUI

struct SetVoiceView: View {
    var body: some View {
        SettingsShell(active: .voice) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Voice profile")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                Text("Fine-tuned on 2,014 of your own messages. Updates automatically each week.")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 6)
                    .frame(maxWidth: 520, alignment: .leading)

                HStack(alignment: .top, spacing: 12) {
                    signalsCard.frame(maxWidth: .infinity)
                    strengthCard.frame(maxWidth: .infinity)
                }
                .padding(.top, 24)
            }
        }
    }

    private var signalsCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SIGNALS IT LEARNED")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.accent)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "lowercase in casual chat, Title-Case in work",
                        "heart emoji only with family",
                        "\"tmrw\" for tomorrow, never \"tmr\"",
                        "rarely uses exclamation points",
                        "sign-offs: \"—J\" for work, nothing for friends",
                    ], id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Color.fgMute)
                            Text(point)
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Color.fgDim)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var strengthCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PROFILE STRENGTH")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                Text("92%")
                    .font(Theme.Font.sans(48))
                    .tracking(-1.92)
                    .foregroundStyle(Theme.Color.fg)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Theme.Color.accent)
                                .frame(width: geo.size.width * 0.92)
                                .shadow(color: Theme.Color.accentGlow, radius: 5)
                        }
                }
                .frame(height: 6)

                Text("Retrain with your latest 500 messages for a 4% bump.")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgMute)

                HStack(spacing: 8) {
                    PrimaryButton(title: "Retrain now", height: 32, fontSize: 12)
                    GhostButton(title: "Export profile", height: 32, fontSize: 12)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

