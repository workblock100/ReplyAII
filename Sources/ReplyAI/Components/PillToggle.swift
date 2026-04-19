import SwiftUI

/// 36×20 pill toggle matching the JSX rules toggle + settings privacy toggle.
struct PillToggle: View {
    @Binding var value: Bool
    var action: (() -> Void)? = nil

    init(value: Binding<Bool>, action: (() -> Void)? = nil) {
        self._value = value
        self.action = action
    }

    var body: some View {
        Button {
            withAnimation(Theme.Motion.fast) { value.toggle() }
            action?()
        } label: {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(value ? Theme.Color.accent : Color.white.opacity(0.1))
                Circle()
                    .fill(value ? Theme.Color.accentInk : Theme.Color.fgDim)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .frame(width: 36, height: 20)
        }
        .buttonStyle(.plain)
    }
}
