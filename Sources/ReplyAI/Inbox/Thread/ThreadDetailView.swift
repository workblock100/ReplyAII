import SwiftUI

struct ThreadDetailView: View {
    @Bindable var model: InboxViewModel
    @Environment(DraftEngine.self) private var engine

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.Color.line).frame(height: 1)
                }

            messageStream
                .frame(maxHeight: .infinity)

            ComposerView(model: model)
        }
        .background(Color(red: 0.039, green: 0.043, blue: 0.051)) // #0a0b0d
    }

    // MARK: - Header

    private var header: some View {
        let thread = model.selectedThread
        return HStack(spacing: 12) {
            Avatar(text: thread.avatar, channel: thread.channel, size: 30, cutout: Theme.Color.bg1)
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.name)
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("via \(thread.channel.label.lowercased()) · context: \(thread.contextCount) messages")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            HStack(spacing: 6) {
                MiniButton(title: "Snooze")
                MiniButton(title: "Mark done")
            }
        }
    }

    // MARK: - Messages

    private var messageStream: some View {
        let thread = model.selectedThread
        let msgs = model.messages(for: thread)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    SectionLabel(text: "Today")
                    Spacer()
                }
                .padding(.bottom, 4)

                ForEach(msgs) { MessageBubble(message: $0) }

                // Context card is curated copy on a per-thread basis. Render
                // only when the thread has a real summary attached or when a
                // hand-written fixture summary exists. Hides for everything
                // else so real conversations don't show a "context will land
                // once summarization is wired" placeholder.
                if let summary = thread.contextSummary ?? Fixtures.contextSummary(for: thread.id) {
                    ContextCard(summary: summary)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
    }
}
