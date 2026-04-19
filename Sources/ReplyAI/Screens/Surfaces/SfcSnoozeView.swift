import SwiftUI

/// `sfc-snooze` — snooze picker anchored to a thread row, with backdrop.
struct SfcSnoozeView: View {
    private struct Option { let label: String; let sub: String }
    private let options: [Option] = [
        .init(label: "Later today",       sub: "6:00 PM"),
        .init(label: "Tomorrow morning",  sub: "Sat 8:00 AM"),
        .init(label: "Tomorrow evening",  sub: "Sat 6:00 PM"),
        .init(label: "This weekend",      sub: "Sun 10:00 AM"),
        .init(label: "Next week",         sub: "Mon 9:00 AM"),
        .init(label: "In a month",        sub: "May 19"),
        .init(label: "When they reply",   sub: "auto"),
        .init(label: "Pick a date…",      sub: ""),
    ]
    private let highlightedIndex = 2

    var body: some View {
        ZStack {
            InboxScreen()
                .blur(radius: 1)
                .opacity(0.4)
                .allowsHitTesting(false)

            Color.black.opacity(0.5).ignoresSafeArea()

            picker
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 140)
                .padding(.trailing, 80)
        }
        .frame(minWidth: 1180, minHeight: 720)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SNOOZE · MAYA CHEN")
                .font(Theme.Font.mono(12))
                .tracking(1.0)
                .foregroundStyle(Theme.Color.fgMute)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                HStack {
                    Text(opt.label)
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.fg)
                    Spacer()
                    Text(opt.sub)
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Color.fgMute)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                        .fill(i == highlightedIndex ? Theme.Color.accent.opacity(0.08) : .clear)
                )
            }
        }
        .padding(10)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Color(red: 0.078, green: 0.086, blue: 0.102).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 60, y: 30)
    }
}
