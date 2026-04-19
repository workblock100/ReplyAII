import SwiftUI

struct SetShortcutsView: View {
    private let rows: [(k: String, l: String)] = [
        ("⌘↵",    "Send current draft"),
        ("⌘J",    "Regenerate draft"),
        ("⌘/",    "Cycle tone"),
        ("⌘.",    "Dismiss draft"),
        ("⌘K",    "Command palette"),
        ("⌘⇧R",   "Open ReplyAI anywhere"),
        ("↑ ↓",   "Move through threads"),
        ("⌥S",    "Snooze"),
        ("e",     "Mark done & next"),
    ]

    var body: some View {
        SettingsShell(active: .shortcuts) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Shortcuts")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                Text("Click a shortcut to rebind. All shortcuts are listed in the menu bar under ReplyAI → Shortcuts.")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 6)
                    .frame(maxWidth: 520, alignment: .leading)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
                    spacing: 0
                ) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        shortcutRow(r.k, r.l, leftColumn: i % 2 == 0)
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    private func shortcutRow(_ key: String, _ label: String, leftColumn: Bool) -> some View {
        HStack(spacing: 14) {
            KbdKey(text: key)
            Text(label)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fgDim)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
        .overlay(alignment: .trailing) {
            if leftColumn { Rectangle().fill(Theme.Color.line).frame(width: 1) }
        }
    }
}

