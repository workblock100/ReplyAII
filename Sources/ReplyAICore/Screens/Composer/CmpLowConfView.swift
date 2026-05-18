import SwiftUI

/// `cmp-lowconf` — unknown sender, no context; app refuses to guess.
struct CmpLowConfView: View {
    var body: some View {
        InboxFrame {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("hey, free thursday?")
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Color.fg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        Spacer()
                    }
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
            Avatar(text: "☎", channel: .sms, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("+1 (415) 555-0892")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("sms · unknown contact")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("LOW CONFIDENCE")
                    .font(Theme.Font.mono(10))
                    .tracking(0.9)
                    .foregroundStyle(Theme.Color.warn)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Theme.Color.warn.opacity(0.4), lineWidth: 1)
                    )
                Text("Unknown sender · no context history")
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("I don't have enough context on this person to write in your voice. Reply manually, or tell me who they are:")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fgDim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(["a friend", "a recruiter", "a vendor", "a mistake"], id: \.self) { opt in
                        Button {} label: {
                            Text(opt)
                                .font(Theme.Font.sans(11))
                                .foregroundStyle(Theme.Color.fgDim)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                    .fill(Theme.Color.warn.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                    .stroke(Theme.Color.warn.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}

