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
                .tracking(0.9)
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
                editableDraft(thread: thread, state: state)
            }

            HStack(spacing: 8) {
                Text("Learned from \(Fixtures.replyCount(for: thread.channel).formatted()) of your \(thread.channel.label) replies")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgFaint)
                Spacer(minLength: 8)
                MiniButton(title: "Shorten")
                MiniButton(title: "Regenerate") {
                    // Clear the user's edit so the new stream can replace it.
                    model.clearEdit(threadID: thread.id, tone: model.activeTone)
                    engine.regenerate(
                        thread: thread,
                        tone: model.activeTone,
                        history: model.messages(for: thread)
                    )
                }
                MiniButton(title: "Send ↵", kind: .primary) {
                    let text = currentDraftText(thread: thread, state: state)
                    guard !text.isEmpty else { return }
                    model.requestSend(text: text)
                }
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

    /// Editable TextEditor bound via the view model so both the composer
    /// and `⌘↵` always read the same text. When the engine is still
    /// streaming and the user hasn't edited, we write each chunk straight
    /// into `userEdits` so their edits can pick up from whatever the model
    /// produced.
    @ViewBuilder
    private func editableDraft(thread: MessageThread, state: DraftEngine.DraftState) -> some View {
        let binding = Binding<String>(
            get: { model.effectiveDraft(threadID: thread.id, tone: model.activeTone, fallback: state.text) },
            set: { model.setEdit(threadID: thread.id, tone: model.activeTone, text: $0) }
        )

        ZStack(alignment: .topLeading) {
            TextEditor(text: binding)
                .scrollContentBackground(.hidden)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fg)
                .lineSpacing(3.5)
                .frame(minHeight: 48)

            if state.isStreaming {
                // Streaming caret sits at the top-trailing edge so it
                // doesn't land inside the text editor's text rect.
                HStack { Spacer(); Caret() }
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                    .allowsHitTesting(false)
            }
        }
        // Streamed chunks into the TextEditor — `set` on the binding
        // routes them through userEdits so the user can immediately edit.
        .onChange(of: state.text) { _, newValue in
            let key = InboxViewModel.editKey(threadID: thread.id, tone: model.activeTone)
            if model.userEdits[key] == nil || state.isStreaming {
                model.userEdits[key] = newValue
            }
        }
    }

    private func currentDraftText(thread: MessageThread, state: DraftEngine.DraftState) -> String {
        model.effectiveDraft(threadID: thread.id, tone: model.activeTone, fallback: state.text)
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
