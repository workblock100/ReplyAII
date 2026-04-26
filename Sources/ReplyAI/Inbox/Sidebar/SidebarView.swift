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

            syncChip
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

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
            TextField("Search anyone, anything", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fg)
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.fgFaint)
                }
                .buttonStyle(.plain)
            }
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
                Text("\(model.count(for: folder.id))")
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
                channelRow(channel)
            }
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let active = model.activeChannelFilter == channel
        return Button {
            withAnimation(Theme.Motion.std) {
                model.filterByChannel(active ? nil : channel)
            }
        } label: {
            HStack(spacing: 10) {
                ChannelDot(channel: channel, size: 8, cutout: .clear)
                Text(channel.label)
                    .font(Theme.Font.sans(13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.Color.fg : Theme.Color.fgDim)
                Spacer()
                Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? Theme.Color.accent : Theme.Color.fgFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                    .fill(active ? Theme.Color.accent.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(active ? "Show all channels" : "Filter \(channel.label)")
    }

    private var syncChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor.opacity(0.6), radius: 3)
            Text(syncLabel)
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgMute)
            Spacer()
        }
    }

    private var dotColor: Color {
        switch model.syncStatus {
        case .live:                      return Theme.Color.accent
        case .syncing:                   return Theme.Color.warn
        case .denied, .failed:           return Theme.Color.err
        case .idle:                      return Theme.Color.fgFaint
        }
    }

    private var syncLabel: String {
        switch model.syncStatus {
        case .idle:               return "fixtures · ⌘R to sync"
        case .syncing:            return "syncing…"
        case .live(let at):       return "live · \(relativeString(for: at))"
        case .denied:             return "needs full disk access"
        case .failed(let msg):    return "error · \(msg.prefix(24))"
        }
    }

    private func relativeString(for date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        return m < 60 ? "\(m)m ago" : "\(m / 60)h ago"
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
