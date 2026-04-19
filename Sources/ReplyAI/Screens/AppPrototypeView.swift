import SwiftUI

/// Dev-only gallery that mirrors prototype.html: a sidebar of every screen,
/// a top bar showing the current screen's label + index, and the rendered
/// screen filling the rest. Left/right arrows step through screens.
///
/// In a production build we'd gate this behind a debug flag; for v1 it's
/// the default root so we can sweep across all 28 states.
struct AppPrototypeView: View {
    @State private var screen: ScreenID = .appInbox
    @State private var navOpen: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if navOpen {
                ScreenNav(screen: $screen, onClose: { withAnimation(Theme.Motion.std) { navOpen = false } })
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
            }

            VStack(spacing: 0) {
                topBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footerMeta
            }
        }
        .frame(minWidth: 1180, minHeight: 820)
        .background(Theme.Color.bg0)
        .preferredColorScheme(.dark)
        .background(keyboardCommands)
    }

    private var topBar: some View {
        let item = ScreenInventory.item(for: screen)
        let idx = ScreenInventory.index(of: screen)
        return HStack(spacing: 14) {
            Button { withAnimation(Theme.Motion.std) { navOpen.toggle() } } label: {
                Text("☰")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                            .stroke(Theme.Color.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Text(item.label)
                .font(Theme.Font.sans(13, weight: .medium))
                .tracking(-0.13)
                .foregroundStyle(Theme.Color.fg)

            Text("\(String(format: "%02d", idx + 1)) / \(String(format: "%02d", ScreenInventory.allItems.count))")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgFaint)

            Spacer()

            HStack(spacing: 6) {
                navButton(title: "‹ prev") { screen = ScreenInventory.previous(before: screen) }
                navButton(title: "next ›") { screen = ScreenInventory.next(after: screen) }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Color(red: 0.039, green: 0.043, blue: 0.051).opacity(0.7))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }

    private func navButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .overlay(
                    Capsule(style: .continuous).stroke(Theme.Color.lineStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        ZStack {
            // Ambient accent glow behind the screen.
            RadialGradient(
                colors: [Theme.Color.accentGlow, .clear],
                center: .bottom,
                startRadius: 40,
                endRadius: 420
            )
            .blur(radius: 36)
            .opacity(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Screens are designed at 1180×720. We render at intrinsic size and
            // scale down to fit when the host window is smaller.
            GeometryReader { geo in
                let scale = min(1, min(geo.size.width / 1180, geo.size.height / 720))
                ScreenRouter(screen: screen)
                    .frame(width: 1180, height: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 60, y: 40)
                    .scaleEffect(scale, anchor: .center)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            .padding(40)
        }
    }

    private var footerMeta: some View {
        HStack(spacing: 24) {
            HStack(spacing: 6) {
                Text("purpose · ").foregroundStyle(Theme.Color.fgFaint)
                Text(ScreenMeta.purpose(for: screen)).foregroundStyle(Theme.Color.fgMute)
            }
            .font(Theme.Font.mono(12))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(red: 0.039, green: 0.043, blue: 0.051).opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }

    @ViewBuilder
    private var keyboardCommands: some View {
        Color.clear
            .background(
                Button("prev") { screen = ScreenInventory.previous(before: screen) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .opacity(0)
            )
            .background(
                Button("next") { screen = ScreenInventory.next(after: screen) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .opacity(0)
            )
            .background(
                Button("prev-vi") { screen = ScreenInventory.previous(before: screen) }
                    .keyboardShortcut("k", modifiers: [])
                    .opacity(0)
            )
            .background(
                Button("next-vi") { screen = ScreenInventory.next(after: screen) }
                    .keyboardShortcut("j", modifiers: [])
                    .opacity(0)
            )
    }
}

/// Sidebar listing every screen, grouped.
private struct ScreenNav: View {
    @Binding var screen: ScreenID
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 12)

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.Color.accent)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("R")
                                .font(Theme.Font.sans(15, weight: .bold))
                                .foregroundStyle(Theme.Color.accentInk)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ReplyAI")
                            .font(Theme.Font.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.Color.fg)
                        Text("APP PROTOTYPE")
                            .font(Theme.Font.mono(10))
                            .tracking(1.0)
                            .foregroundStyle(Theme.Color.fgMute)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Text("«")
                            .font(Theme.Font.sans(14))
                            .foregroundStyle(Theme.Color.fgMute)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

                ForEach(ScreenInventory.groups, id: \.title) { group in
                    Text(group.title.uppercased())
                        .font(Theme.Font.mono(10))
                        .tracking(1.8)
                        .foregroundStyle(Theme.Color.fgFaint)
                        .padding(.horizontal, 22)
                        .padding(.top, 6)
                        .padding(.bottom, 4)

                    ForEach(group.items) { item in
                        let active = item.id == screen
                        Button { screen = item.id } label: {
                            HStack(spacing: 10) {
                                Text(active ? "●" : "·")
                                    .font(Theme.Font.mono(10))
                                    .foregroundStyle(active ? Theme.Color.accent : Theme.Color.fgFaint)
                                    .frame(minWidth: 4)
                                Text(item.label)
                                    .font(Theme.Font.sans(13))
                                    .foregroundStyle(active ? Theme.Color.fg : Theme.Color.fgDim)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 6)
                            .background(active ? Theme.Color.accent.opacity(0.08) : .clear)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(active ? Theme.Color.accent : .clear)
                                    .frame(width: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 12)
                }

                Divider().background(Theme.Color.line)
                VStack(alignment: .leading, spacing: 6) {
                    Text("use ← / → to step through")
                    Text("j/k also work")
                }
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.055, green: 0.059, blue: 0.071).opacity(0.7))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.Color.line).frame(width: 1) }
    }
}
