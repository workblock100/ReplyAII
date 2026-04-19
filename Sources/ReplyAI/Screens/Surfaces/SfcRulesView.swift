import SwiftUI

/// `sfc-rules` — Smart Rules builder. If-this-then-that automation surface.
struct SfcRulesView: View {
    @State private var rules: [Rule] = [
        .init(when: "Any message contains a 2FA code",                then: "Archive & copy code",                 active: true),
        .init(when: "Slack DM from @maya-chen with \"deck\"",          then: "Draft in Direct tone, pin to top",    active: true),
        .init(when: "WhatsApp voice memo > 30s",                       then: "Auto-transcribe + summarize first",   active: true),
        .init(when: "Newsletter from any @*substack.com",              then: "Archive silently",                    active: false),
    ]

    struct Rule: Identifiable {
        let id = UUID()
        let when: String
        let then: String
        var active: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 28)  // traffic lights gap

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Text("Smart Rules")
                        .font(Theme.Font.sans(28))
                        .tracking(-0.56)
                        .foregroundStyle(Theme.Color.fg)
                    Text("4 ACTIVE")
                        .font(Theme.Font.mono(10))
                        .tracking(1.0)
                        .foregroundStyle(Theme.Color.fgMute)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Theme.Color.lineStrong, lineWidth: 1)
                        )
                    Spacer()
                    PrimaryButton(title: "+ New rule")
                }

                Text("If-this-then-that for your inbox. Rules run on your Mac, never on our servers.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 8)
                    .frame(maxWidth: 580, alignment: .leading)

                VStack(spacing: 10) {
                    ForEach($rules) { $rule in
                        ruleCard(rule: $rule)
                    }
                }
                .padding(.top, 24)
            }
            .padding(40)
        }
        .frame(minWidth: 1180, minHeight: 720, alignment: .topLeading)
        .background(Theme.Color.bg1)
    }

    private func ruleCard(rule: Binding<Rule>) -> some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHEN")
                        .font(Theme.Font.mono(10))
                        .tracking(0.9)
                        .foregroundStyle(Theme.Color.accent)
                    Text(rule.wrappedValue.when)
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Color.fg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("THEN")
                        .font(Theme.Font.mono(10))
                        .tracking(0.9)
                        .foregroundStyle(Theme.Color.fgMute)
                    Text(rule.wrappedValue.then)
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Color.fgDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PillToggle(value: rule.active)
                    .padding(.top, 4)

                Button("Edit") {}
                    .buttonStyle(.plain)
                    .font(Theme.Font.sans(11, weight: .medium))
                    .foregroundStyle(Theme.Color.fgDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
        }
    }
}
