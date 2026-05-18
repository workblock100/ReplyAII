import SwiftUI

/// `cmp-custom` — natural-language instruction steering a single draft.
struct CmpCustomView: View {
    @State private var instruction: String = "make it sound less corporate and add a joke"

    var body: some View {
        InboxFrame {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

                VStack(alignment: .leading, spacing: 10) {
                    incomingBubble
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                composer
                    .background(Color(red: 0.043, green: 0.047, blue: 0.058))
                    .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(text: "RV", channel: .slack, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ravi (Linear)")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("slack")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var incomingBubble: some View {
        HStack {
            Text("shipped the new billing flow — stripe webhooks are live")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .frame(maxWidth: 400, alignment: .leading)
            Spacer()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.accent)
                Text("CUSTOM INSTRUCTION")
                    .font(Theme.Font.mono(11))
                    .tracking(0.9)
                    .foregroundStyle(Theme.Color.accent)
            }

            HStack(spacing: 8) {
                Text("/")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
                TextField("", text: $instruction)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fg)
                Spacer()
                Text("↵ apply")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                    .fill(Theme.Color.accent.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                    .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
            )
            .padding(.top, 8)

            draftWell
                .padding(.top, 10)

            Text("Custom instructions let you steer a single draft without changing your default tone.")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgFaint)
                .padding(.top, 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var draftWell: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("Billing flow, finally unshackled from its corporate shackles. Will stare at the Loom lovingly when it lands.")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fg)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
            Caret().padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

