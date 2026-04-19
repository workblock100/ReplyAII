import SwiftUI

/// Standalone palette card — what `⌘K` actually presents over the inbox.
/// Separated from `SfcPaletteView` so the gallery can render a blurred
/// inbox behind it without doubling up on overlays.
struct PalettePopover: View {
    @State private var query: String = "dinner with mom"

    var body: some View {
        VStack(spacing: 0) {
            searchRow
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

            VStack(alignment: .leading, spacing: 0) {
                Text("PEOPLE · 2")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                personResult(
                    initial: "M",
                    title: "Mom",
                    subtitle: "iMessage · 1,842 messages · last: sunday",
                    active: true
                )
                personResult(
                    initial: "T",
                    title: "Theo Park",
                    subtitle: "iMessage · mentioned \"mom\" in 3 threads",
                    active: false
                )

                Text("RECALLED FROM MESSAGES · 1")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\"dont forget sundays dinner ♥\"")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.fg)
                    Text("Mom · iMessage · 1:08 PM today")
                        .font(Theme.Font.sans(11))
                        .foregroundStyle(Theme.Color.fgMute)
                }
                .padding(10)
            }
            .padding(8)

            footerHints
                .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
        }
        .frame(width: 680)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r18, style: .continuous)
                .fill(Color(red: 0.078, green: 0.086, blue: 0.102).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 60, y: 30)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.fgMute)
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Font.sans(17))
                .foregroundStyle(Theme.Color.fg)
            Text("⌘K")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgFaint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func personResult(initial: String, title: String, subtitle: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.72, blue: 0.42),
                             Color(red: 1.0, green: 0.43, blue: 0.57)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 26, height: 26)
                .overlay(
                    Text(initial)
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fg)
                Text(subtitle)
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            if active {
                Text("↵ open")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(active ? Theme.Color.accent.opacity(0.08) : .clear)
        )
    }

    private var footerHints: some View {
        HStack(spacing: 16) {
            Text("↵ open")
            Text("⌘↵ jump & reply")
            Text("⎋ dismiss")
            Spacer()
        }
        .font(Theme.Font.mono(10))
        .foregroundStyle(Theme.Color.fgFaint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// `sfc-palette` — gallery view. Blurred inbox behind + dim scrim + palette.
struct SfcPaletteView: View {
    var body: some View {
        ZStack {
            InboxScreen()
                .blur(radius: 1)
                .opacity(0.5)
                .allowsHitTesting(false)

            Color.black.opacity(0.5).ignoresSafeArea()

            PalettePopover()
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 120)
        }
        .frame(minWidth: 1180, minHeight: 720)
    }
}
