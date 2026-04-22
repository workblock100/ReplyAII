import SwiftUI

/// `sfc-rules` — Smart Rules builder. Wired to the on-disk RulesStore,
/// so toggles and additions persist across launches.
struct SfcRulesView: View {
    @State private var store = RulesStore()

    private var activeCount: Int { store.rules.filter(\.active).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 28)  // traffic lights gap

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Text("Smart Rules")
                        .font(Theme.Font.sans(28))
                        .tracking(-0.56)
                        .foregroundStyle(Theme.Color.fg)
                    Text("\(activeCount) ACTIVE")
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
                    PrimaryButton(title: "+ New rule") {
                        try? store.add(SmartRule(
                            name: "New rule — edit me",
                            when: .textContains("TODO"),
                            then: .pin,
                            active: false
                        ))
                    }
                }

                Text("If-this-then-that for your inbox. Rules run on your Mac, never on our servers.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 8)
                    .frame(maxWidth: 580, alignment: .leading)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.rules) { rule in
                            ruleCard(rule)
                        }
                    }
                    .padding(.top, 24)
                }
            }
            .padding(40)
        }
        .frame(minWidth: 1180, minHeight: 720, alignment: .topLeading)
        .background(Theme.Color.bg1)
    }

    private func ruleCard(_ rule: SmartRule) -> some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHEN")
                        .font(Theme.Font.mono(10))
                        .tracking(0.9)
                        .foregroundStyle(Theme.Color.accent)
                    Text(rule.name)
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Color.fg)
                        .lineLimit(2)
                    Text(humanize(predicate: rule.when))
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Color.fgMute)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("THEN")
                        .font(Theme.Font.mono(10))
                        .tracking(0.9)
                        .foregroundStyle(Theme.Color.fgMute)
                    Text(humanize(action: rule.then))
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Color.fgDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PillToggle(value: toggleBinding(for: rule))
                    .padding(.top, 4)

                Button {
                    store.remove(rule.id)
                } label: {
                    Text("Remove")
                        .font(Theme.Font.sans(11, weight: .medium))
                        .foregroundStyle(Theme.Color.err)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Theme.Color.err.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleBinding(for rule: SmartRule) -> Binding<Bool> {
        Binding(
            get: { rule.active },
            set: { _ in store.toggle(rule.id) }
        )
    }

    // MARK: - Display helpers

    private func humanize(predicate: RulePredicate) -> String {
        switch predicate {
        case .senderIs(let s):          return "sender is \"\(s)\""
        case .senderContains(let s):    return "sender contains \"\(s)\""
        case .channelIs(let ch):        return "channel is \(ch.label.lowercased())"
        case .textContains(let s):      return "text contains \"\(s)\""
        case .textMatchesRegex(let r):  return "text matches /\(r)/"
        case .isUnread:                 return "is unread"
        case .senderUnknown:            return "sender not in contacts"
        case .isGroupChat:              return "is a group chat"
        case .hasAttachment:            return "has attachment"
        case .and(let clauses):
            return clauses.map { humanize(predicate: $0) }.joined(separator: " AND ")
        case .or(let clauses):
            return clauses.map { humanize(predicate: $0) }.joined(separator: " OR ")
        case .not(let p):
            return "NOT (\(humanize(predicate: p)))"
        }
    }

    private func humanize(action: RuleAction) -> String {
        switch action {
        case .archive:                return "Archive"
        case .pin:                    return "Pin to top"
        case .markDone:               return "Mark done"
        case .silentlyIgnore:         return "Archive silently"
        case .setDefaultTone(let t):  return "Default tone → \(t.rawValue)"
        }
    }
}
