import SwiftUI

/// `ob-tone` — pick default tone (warm / direct / polished / playful).
struct ObToneView: View {
    private struct Option: Identifiable { let id: String; let t: String; let sub: String; let ex: String }
    private let options: [Option] = [
        .init(id: "warm",     t: "Warm",
              sub: "Friendly, sometimes emoji, ends with ♥ or 🙏",
              ex: "\"Already in the deck pretending to be helpful 🙏 — comments landing soon.\""),
        .init(id: "direct",   t: "Direct",
              sub: "Short, lowercase, gets to the point",
              ex: "\"on it. comments on 4–9 before 4.\""),
        .init(id: "polished", t: "Polished",
              sub: "Full sentences, minimal punctuation",
              ex: "\"Taking a look now — I'll leave inline comments on slides 4 through 9 before the meeting.\""),
        .init(id: "playful",  t: "Playful",
              sub: "Dry wit, occasional emoji, banter",
              ex: "\"Already in the deck pretending to be helpful 🫡 — comments inbound.\""),
    ]

    @State private var pick = "warm"

    var body: some View {
        OnboardingStage(
            step: 7, total: 9,
            eyebrow: "Default tone",
            title: Text("Pick a tone ReplyAI should start with.")
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(options) { opt in
                    toneCard(opt)
                }
            }
            .padding(.top, 8)
        } cta: {
            PrimaryButton(title: "Set as default", icon: "arrow.right")
        } secondary: {
            Text("You'll still see all three on every draft.")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }

    private func toneCard(_ opt: Option) -> some View {
        let active = pick == opt.id
        return Button {
            withAnimation(Theme.Motion.std) { pick = opt.id }
        } label: {
            Card(
                padding: 20,
                borderColor: active ? Theme.Color.accent.opacity(0.35) : Theme.Color.line,
                tint: active ? Theme.Color.accent.opacity(0.06) : nil
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(active ? Theme.Color.accent : Theme.Color.lineStrong, lineWidth: 2)
                                .frame(width: 14, height: 14)
                            if active {
                                Circle().fill(Theme.Color.accent).frame(width: 14, height: 14)
                            }
                        }
                        Text(opt.t)
                            .font(Theme.Font.sans(15, weight: .medium))
                            .foregroundStyle(Theme.Color.fg)
                    }
                    Text(opt.sub)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Color.fgMute)
                    Text(opt.ex)
                        .font(Theme.Font.serifItalic(14))
                        .foregroundStyle(Theme.Color.fgDim)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
