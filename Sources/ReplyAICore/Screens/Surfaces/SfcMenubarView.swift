import SwiftUI

/// `sfc-menubar` — NSStatusItem popover with 3 waiting threads + CTAs.
/// Full viewport = simulated desktop with fake menu bar, popover anchored top-right.
struct SfcMenubarView: View {
    private struct Item { let name: String; let channel: Channel; let preview: String; let unread: Int }
    private let items: [Item] = [
        .init(name: "Maya Chen",     channel: .slack,    preview: "can you review the deck…",     unread: 2),
        .init(name: "Ravi (Linear)", channel: .slack,    preview: "shipped the new billing flow", unread: 1),
        .init(name: "Lena Fischer",  channel: .whatsapp, preview: "Are we still on for Berlin?",  unread: 1),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            fakeDesktop

            popover
                .padding(.top, 36)
                .padding(.trailing, 80)
        }
        .frame(minWidth: 1180, minHeight: 720)
    }

    private var fakeDesktop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.102, green: 0.149, blue: 0.251),
                Color(red: 0.039, green: 0.043, blue: 0.051),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .top) { fakeMenuBar }
        .overlay(alignment: .bottomLeading) {
            Text("Click the R in your menu bar, or press ⌘⇧R anywhere on your Mac.")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.leading, 40)
                .padding(.bottom, 40)
        }
    }

    private var fakeMenuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "applelogo").font(.system(size: 12))
            Text("Finder").font(Theme.Font.sans(11, weight: .medium))
            Text("File").font(Theme.Font.sans(11))
            Text("Edit").font(Theme.Font.sans(11))
            Spacer()
            HStack(spacing: 10) {
                Text("R").foregroundStyle(Theme.Color.accent).font(Theme.Font.sans(11, weight: .bold))
                Text("100%").font(Theme.Font.sans(11))
                Text("Fri 2:41 PM").font(Theme.Font.sans(11))
            }
        }
        .foregroundStyle(Theme.Color.fg)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(red: 0.055, green: 0.059, blue: 0.071).opacity(0.9))
    }

    private var popover: some View {
        VStack(spacing: 0) {
            header
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Avatar(text: String(item.name.prefix(1)), channel: item.channel, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(Theme.Font.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.Color.fg)
                        Text(item.preview)
                            .font(Theme.Font.sans(11))
                            .foregroundStyle(Theme.Color.fgMute)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(item.unread)")
                        .font(Theme.Font.sans(9, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule(style: .continuous).fill(Theme.Color.accent))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.lineFaint).frame(height: 1) }
            }

            HStack(spacing: 8) {
                PrimaryButton(title: "Open inbox", height: 30, fontSize: 12)
                    .frame(maxWidth: .infinity)
                GhostButton(title: "Quiet", height: 30, fontSize: 12)
            }
            .padding(14)
        }
        .frame(width: 380)
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

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.Color.accent)
                .frame(width: 22, height: 22)
                .overlay(
                    Text("R")
                        .font(Theme.Font.sans(13, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                )
            Text("ReplyAI")
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundStyle(Theme.Color.fg)
            Spacer()
            Text("3 waiting")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgMute)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
