import SwiftUI

/// `ob-shortcuts` — keyboard cheatsheet (9 shortcuts, 3×3 grid).
struct ObShortcutsView: View {
    private let keys: [(k: String, d: String)] = [
        ("⌘↵",   "Send the current draft"),
        ("⌘J",   "Regenerate draft"),
        ("⌘/",   "Cycle tone (warm → direct → playful)"),
        ("⌘.",   "Dismiss draft, write your own"),
        ("⌘K",   "Open command palette"),
        ("⌘⇧R",  "Open ReplyAI from anywhere"),
        ("↑↓",   "Move through threads"),
        ("⌥S",   "Snooze"),
        ("e",    "Mark done & next"),
    ]

    var body: some View {
        OnboardingStage(
            step: 8, total: 9,
            eyebrow: "Keyboard tour",
            title: Text("Nine shortcuts. ")
                + Text("That's the whole app.")
                    .font(Theme.Font.serifItalic(38))
                    .foregroundColor(Theme.Color.fgDim)
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(keys, id: \.k) { row in
                    Card(padding: 16) {
                        HStack(spacing: 14) {
                            KbdKey(text: row.k, minWidth: 44, size: 13)
                            Text(row.d)
                                .font(Theme.Font.sans(13))
                                .foregroundStyle(Theme.Color.fgDim)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Print & continue", icon: "arrow.right")
        } secondary: {
            GhostButton(title: "Show me the cheatsheet PDF")
        }
    }
}
