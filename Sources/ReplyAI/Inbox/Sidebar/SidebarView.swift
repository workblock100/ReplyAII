import SwiftUI

struct SidebarView: View {
    @Bindable var model: InboxViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reserve vertical room for the macOS traffic lights that sit above us.
            Spacer().frame(height: 28)

            brandRow
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            searchPill
                .padding(.horizontal, 8)

            SectionLabel(text: "Inboxes")
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)

            foldersNav
                .padding(.horizontal, 8)

            SectionLabel(text: "Channels")
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 6)

            channelsList
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            Divider().background(Color.white.opacity(0.05))
            userFooter
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 220, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.063, green: 0.071, blue: 0.090), // #101217
                    Color(red: 0.047, green: 0.051, blue: 0.067)  // #0c0d11
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Color.line).frame(width: 1)
        }
    }

    // MARK: - Sections

    private var brandRow: some View {
        HStack(spacing: 8) {
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
            Text("⌘K")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgFaint)
        }
    }

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.fgMute)
            Text("Search anyone, anything")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var foldersNav: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.folders) { folder in
                folderRow(folder)
            }
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        let active = folder.id == model.activeFolder
        return Button {
            withAnimation(Theme.Motion.std) { model.activeFolder = folder.id }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? Theme.Color.accent : Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text(folder.label)
                    .font(Theme.Font.sans(13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.Color.fg : Theme.Color.fgDim)
                Spacer()
                Text("\(folder.count)")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                    .fill(active ? Theme.Color.accent.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var channelsList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.channels) { channel in
                HStack(spacing: 10) {
                    ChannelDot(channel: channel, size: 8, cutout: .clear)
                    Text(channel.rawValue.capitalized)
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.fgDim)
                    Spacer()
                    Text("•")
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Color.fgFaint)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private var userFooter: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.79, green: 0.64, blue: 1.00),
                             Color(red: 0.48, green: 0.36, blue: 1.00)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 26, height: 26)
                .overlay(
                    Text("JS")
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Jordan Song")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
                Text("pro · mac")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.Color.fgMute)
        }
    }
}
