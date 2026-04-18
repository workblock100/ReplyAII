import SwiftUI

/// Blinking caret shown while the draft is streaming in.
/// README calls for a 1.1s pulse on the active draft — we run two phases
/// so the caret doesn't look like a cursor but like a breath.
struct Caret: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Theme.Color.accent)
            .frame(width: 7, height: 14)
            .opacity(on ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
            .accessibilityHidden(true)
    }
}
