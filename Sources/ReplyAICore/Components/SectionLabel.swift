import SwiftUI

/// Uppercase mono section label ("INBOXES", "CHANNELS", "TODAY").
struct SectionLabel: View {
    var text: String
    var tracking: CGFloat = 1.6   // ≈ 0.1em at 10px

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.mono(10))
            .tracking(tracking)
            .foregroundStyle(Theme.Color.fgFaint)
    }
}
