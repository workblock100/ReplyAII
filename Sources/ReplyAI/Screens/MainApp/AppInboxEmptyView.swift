import SwiftUI

/// `app-inbox-empty` — inbox-zero reward state.
struct AppInboxEmptyView: View {
    var body: some View {
        InboxFrame(
            threadListOverride: AnyView(emptyThreadList)
        ) {
            VStack(spacing: 12) {
                Text("You replied to everyone.")
                    .font(Theme.Font.serifItalic(42))
                    .tracking(-1.05)
                    .foregroundStyle(Theme.Color.fg)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Text("ReplyAI is watching all 5 channels. We'll surface the next thing when it arrives.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fgMute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Text("42 replied today · 3h 18m saved")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgFaint)
                    .padding(.top, 20)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyThreadList: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("🌿").font(.system(size: 48))
            Text("Inbox zero.")
                .font(Theme.Font.sans(15, weight: .medium))
                .foregroundStyle(Theme.Color.fg)
            Text("Nothing needs you right now. Take a breath.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

