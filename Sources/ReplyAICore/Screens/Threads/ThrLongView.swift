import SwiftUI

/// `thr-long` — 412-message DM summarized at the top, latest message pinned below.
struct ThrLongView: View {
    private let summaryPoints: [String] = [
        "Maya is leading the Q2 brand refresh. Deadline is May 14.",
        "You agreed to own the hero, the pricing section, and the marketing site footer.",
        "Unresolved: the pricing page still has the old lime accent Maya flagged last Tuesday.",
        "Today: she's asking for review on slides 4–9 before the 4pm.",
    ]

    var body: some View {
        InboxFrame {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryCard
                        HStack {
                            Spacer()
                            Text("LATEST · 2:41 PM")
                                .font(Theme.Font.mono(10))
                                .tracking(1.0)
                                .foregroundStyle(Theme.Color.fgFaint)
                            Spacer()
                        }
                        latestMessage
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                composer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(text: "MC", channel: .slack, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Maya Chen")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("slack · dm · 412 messages, last 3 weeks")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("THREAD SUMMARY · 412 MESSAGES")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.accent)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(summaryPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Color.fgDim)
                        Text(point)
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Color.fgDim)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Theme.Color.accentSofter)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private var latestMessage: some View {
        HStack {
            Text("can you review the deck before 4? slides 4–9 especially")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fg)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
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
                .frame(maxWidth: 440, alignment: .leading)
            Spacer()
        }
    }

    private var composer: some View {
        HStack(alignment: .top, spacing: 2) {
            Text("Looking now — I'll leave inline comments on 4–9 before 4. Also, I want to revisit the pricing accent you flagged Tuesday; can we do a quick pass together after?")
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
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color(red: 0.043, green: 0.047, blue: 0.058))
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }
}
