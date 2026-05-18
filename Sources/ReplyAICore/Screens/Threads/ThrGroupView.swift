import SwiftUI

/// `thr-group` — Slack group with @mention callout.
struct ThrGroupView: View {
    private struct Msg { let who: String; let time: String; let text: String }
    private let messages: [Msg] = [
        .init(who: "Jamie P.",  time: "2:18 PM", text: "honestly the v3 hero looks insane"),
        .init(who: "Mira K.",   time: "2:19 PM", text: "agree — but the lime accent reads too aggressive on the pricing section imo"),
        .init(who: "Jamie P.",  time: "2:22 PM", text: "idk mira, i think it's doing a lot of the heavy lifting"),
        .init(who: "Maya Chen", time: "2:41 PM", text: "@you can you weigh in? bringing it to the 4pm"),
    ]
    private let hues: [Double] = [0, 60, 120, 180]

    var body: some View {
        InboxFrame {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            messageRow(m, hue: hues[i % hues.count])
                        }
                        taggedCallout
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                composer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.Color.channelSlack, Theme.Color.channelSlack.mix(with: .black, amount: 0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 30, height: 30)
                .overlay(
                    Text("#").font(Theme.Font.sans(14, weight: .semibold)).foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("#design-crit")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("slack · 12 members · 3 typing")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            HStack(spacing: 6) {
                MiniButton(title: "Mute")
                MiniButton(title: "Leave")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func messageRow(_ m: Msg, hue: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(Color(hue: hue / 360, saturation: 0.5, brightness: 0.5))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(m.who.prefix(1)))
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.who)
                        .font(Theme.Font.sans(12, weight: .medium))
                        .foregroundStyle(Theme.Color.fg)
                    Text(m.time)
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Color.fgFaint)
                }
                Text(m.text)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fgDim)
            }
            Spacer()
        }
    }

    private var taggedCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("You're tagged")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
            }
            Text("Maya asked for your take on the lime accent before the 4pm review.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Theme.Color.accentSofter)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(Theme.Color.accentRule, lineWidth: 1)
        )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRAFT · DIRECT (GROUP CHAT MODE)")
                .font(Theme.Font.mono(11))
                .tracking(0.9)
                .foregroundStyle(Theme.Color.fgMute)
            HStack(alignment: .top, spacing: 2) {
                Text("with jamie — but mira's right that it needs more air around pricing. ship it for today, dial the chroma by thurs?")
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
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color(red: 0.043, green: 0.047, blue: 0.058))
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }
}

