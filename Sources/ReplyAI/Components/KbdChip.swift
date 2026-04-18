import SwiftUI

/// Keyboard hint chip rendered in mono ("⌘↵ send").
struct KbdChip: View {
    var keys: String
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys).foregroundStyle(Theme.Color.fgMute)
            Text(label).foregroundStyle(Theme.Color.fgFaint)
        }
        .font(Theme.Font.mono(10))
    }
}
