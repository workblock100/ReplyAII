import SwiftUI

/// Two-column shell shared by all six Settings screens.
/// Left: 240px nav. Right: flexible content with 40px padding and its own scroll.
struct SettingsShell<Content: View>: View {
    enum Tab: String, CaseIterable, Identifiable {
        case account, voice, channels, shortcuts, privacy, model
        var id: String { rawValue }
        var label: String {
            switch self {
            case .account:   "Account"
            case .voice:     "Voice profile"
            case .channels:  "Channels"
            case .shortcuts: "Shortcuts"
            case .privacy:   "Privacy"
            case .model:     "Model"
            }
        }
    }

    var active: Tab
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.Color.line).frame(width: 1)
                }

            ScrollView {
                content()
                    .padding(40)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 1180, minHeight: 720)
        .background(Theme.Color.bg1)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 28)   // traffic-light gap
            Text("SETTINGS")
                .font(Theme.Font.mono(10))
                .tracking(1.8)
                .foregroundStyle(Theme.Color.fgFaint)
                .padding(.horizontal, 22)
                .padding(.bottom, 10)

            ForEach(Tab.allCases) { tab in
                tabRow(tab)
            }
            Spacer()
        }
    }

    private func tabRow(_ tab: Tab) -> some View {
        let on = tab == active
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(on ? Theme.Color.accent : Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
            Text(tab.label)
                .font(Theme.Font.sans(13, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.Color.fg : Theme.Color.fgDim)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(on ? Theme.Color.accent.opacity(0.10) : .clear)
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Shared row primitives

/// Grid row: label | value (+ optional helper mono line) | optional destructive action.
struct SettingRow: View {
    var label: String
    var value: String
    var helper: String? = nil
    var danger: String? = nil
    var dangerAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fgDim)
                .frame(width: 180, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fg)
                if let helper {
                    Text(helper)
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Color.fgMute)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let danger {
                Button(action: dangerAction) {
                    Text(danger)
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
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }
}

/// Grid row with a pill toggle on the right.
struct ToggleRow: View {
    var label: String
    @Binding var value: Bool
    var helper: String? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fg)
                if let helper {
                    Text(helper)
                        .font(Theme.Font.sans(11))
                        .foregroundStyle(Theme.Color.fgMute)
                }
            }
            Spacer()
            PillToggle(value: $value)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }
}

/// Label / 18px value pair used inside Model cards.
struct StatBlock: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Font.mono(10))
                .tracking(0.9)
                .foregroundStyle(Theme.Color.fgMute)
            Text(value)
                .font(Theme.Font.sans(18))
                .tracking(-0.36)
                .foregroundStyle(Theme.Color.fg)
        }
    }
}
