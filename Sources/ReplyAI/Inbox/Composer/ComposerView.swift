import SwiftUI

struct ComposerView: View {
    @Bindable var model: InboxViewModel
    @Environment(DraftEngine.self) private var engine

    var body: some View {
        let thread = model.selectedThread
        let state = engine.state(threadID: thread.id, tone: model.activeTone)

        return VStack(alignment: .leading, spacing: 0) {
            headerRow(tone: model.activeTone)
                .padding(.bottom, 8)

            draftWell(thread: thread, state: state)

            kbdHints
                .padding(.top, 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color(red: 0.043, green: 0.047, blue: 0.058)) // #0b0c0f
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.line).frame(height: 1)
        }
        // Keep a draft in flight whenever thread or tone changes.
        .task(id: TaskKey(threadID: thread.id, tone: model.activeTone)) {
            engine.prime(thread: thread, tone: model.activeTone, history: model.messages(for: thread))
        }
    }

    // MARK: - Header

    private func headerRow(tone: Tone) -> some View {
        HStack {
            Text("ReplyAI draft · \(tone.rawValue)")
                .font(Theme.Font.mono(11))
                .tracking(0.9)  // ≈ 0.08em at 11px
                .textCase(.uppercase)
                .foregroundStyle(Theme.Color.fgMute)
            Spacer()
            TonePills(selection: $model.activeTone)
        }
    }

    // MARK: - Draft well

    @ViewBuilder
    private func draftWell(thread: MessageThread, state: DraftEngine.DraftState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isLowConfidence, !state.isStreaming {
                lowConfidenceBody
            } else {
                draftBody(text: state.text, isStreaming: state.isStreaming)
            }

            HStack(spacing: 8) {
                Text("Learned from \(Fixtures.replyCount(for: thread.channel).formatted()) of your \(thread.channel.label) replies")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgFaint)
                Spacer(minLength: 8)
                MiniButton(title: "Shorten")
                MiniButton(title: "Regenerate") {
                    engine.regenerate(thread: thread, tone: model.activeTone, history: model.messages(for: thread))
                }
                MiniButton(title: "Send ↵", kind: .primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func draftBody(text: String, isStreaming: Bool) -> some View {
        HStack(alignment: .top, spacing: 2) {
            Text(text)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fg)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
            if isStreaming { Caret().padding(.top, 2) }
            Spacer(minLength: 0)
        }
        .animation(Theme.Motion.fast, value: text)
    }

    /// cmp-lowconf fallback — model declines to guess and asks for a hint.
    private var lowConfidenceBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.warn)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Not sure how to reply.")
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(Theme.Color.fg)
                Text("Give me a one-line hint and I'll draft in your voice.")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgDim)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Keyboard hints

    private var kbdHints: some View {
        HStack(spacing: 14) {
            KbdChip(keys: "⌘↵", label: "send")
            KbdChip(keys: "⌘J", label: "regenerate")
            KbdChip(keys: "⌘/", label: "tone")
            KbdChip(keys: "⌘.", label: "dismiss")
            Spacer()
        }
    }

    private struct TaskKey: Hashable { let threadID: String; let tone: Tone }
}
