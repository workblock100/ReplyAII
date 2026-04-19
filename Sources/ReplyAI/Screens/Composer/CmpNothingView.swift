import SwiftUI

/// `cmp-nothing` — closed thread, advance to next.
struct CmpNothingView: View {
    var body: some View {
        InboxFrame {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

                HStack {
                    Spacer()
                    Text("love you, see you sunday ♥")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                                .fill(Theme.Color.accent)
                        )
                        .frame(maxWidth: 400, alignment: .trailing)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                VStack(spacing: 4) {
                    Text("You already closed this one.")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.fgDim)
                    Text("next up: Ravi (Linear) — press e or ↓")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Color.fgMute)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .background(Color(red: 0.043, green: 0.047, blue: 0.058))
                .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(text: "M", channel: .imessage, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mom")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("imessage")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
}

