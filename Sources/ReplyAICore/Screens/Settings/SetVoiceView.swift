import SwiftUI

/// Voice profile Settings pane. Reads the user's voice examples — the
/// recent sends auto-captured by `InboxViewModel.captureVoiceExample` and
/// fed back into draft generation through `PromptBuilder.build(voiceExamples:)`
/// — and renders three cards:
///   1. Header with the live example count.
///   2. "Recent examples" — the actual stored strings, truncated for display.
///   3. "Profile strength" — a meter of count / `maxVoiceExamples`.
///
/// REP-222 wired the data path; this view replaces the original static
/// "2,014 messages" / "92%" placeholders with the live UserDefaults read
/// so the user can see their profile evolving and clear it if they want.
struct SetVoiceView: View {
    /// Injected for tests. Production reads from `.standard` so an
    /// out-of-band capture (e.g. from an inbox send while Settings is
    /// open) is reflected on the next `.onAppear` cycle.
    private let defaults: UserDefaults

    /// Cached snapshot of the stored examples. Re-loaded on `.onAppear`
    /// and after `Clear profile`. SwiftUI re-renders the dependent cards
    /// whenever this changes.
    @State private var examples: [String] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var body: some View {
        SettingsShell(active: .voice) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Voice profile")
                    .font(Theme.Font.sans(26))
                    .tracking(-0.52)
                    .foregroundStyle(Theme.Color.fg)

                Text(SetVoiceView.headerCopy(exampleCount: examples.count))
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fgMute)
                    .padding(.top, 6)
                    .frame(maxWidth: 520, alignment: .leading)

                HStack(alignment: .top, spacing: 12) {
                    examplesCard.frame(maxWidth: .infinity)
                    strengthCard.frame(maxWidth: .infinity)
                }
                .padding(.top, 24)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        examples = defaults.voiceExampleMessages()
    }

    private func clear() {
        defaults.setVoiceExampleMessages([])
        reload()
    }

    /// Header copy that reads accurately whether the user has 0, 1, or N
    /// examples. Pinned by `SetVoiceViewTests.testHeaderCopy*` so a future
    /// "Fine-tuned on N messages" copy edit doesn't accidentally regress
    /// to the static "2,014" prototype string.
    static func headerCopy(exampleCount: Int) -> String {
        switch exampleCount {
        case 0:
            return "ReplyAI learns your voice from messages you send. Send a few replies and they'll show up here."
        case 1:
            return "Built from 1 message you've sent. Updates automatically with every send."
        default:
            return "Built from \(exampleCount) messages you've sent. Updates automatically with every send."
        }
    }

    /// Strength percentage = stored examples / cap, rounded to nearest
    /// percent. Capped at 100 in case `voiceExampleMessages()` ever
    /// exceeds `maxVoiceExamples` (defense-in-depth against a future
    /// migration that bumped the cap downward without trimming).
    /// Pinned by `SetVoiceViewTests.testStrengthPercent*`.
    static func strengthPercent(exampleCount: Int) -> Int {
        let cap = PreferenceRange.maxVoiceExamples
        guard cap > 0 else { return 0 }
        let raw = Int((Double(exampleCount) / Double(cap)) * 100.0)
        return min(100, max(0, raw))
    }

    /// Display copy below the strength meter — actionable rather than
    /// decorative ("send N more for a full profile" beats "92%"). Pinned
    /// by `SetVoiceViewTests.testStrengthHint*`.
    static func strengthHint(exampleCount: Int) -> String {
        let cap = PreferenceRange.maxVoiceExamples
        let remaining = max(0, cap - exampleCount)
        if remaining == 0 {
            return "Profile is full. New sends replace the oldest examples (FIFO)."
        } else if remaining == 1 {
            return "1 more send to fill the profile."
        } else {
            return "\(remaining) more sends to fill the profile."
        }
    }

    /// Single-line preview of one stored example. Stored examples can be
    /// up to `maxVoiceExampleLength` (500) chars; the card is narrow so
    /// truncate to a readable preview length and trim trailing whitespace
    /// before truncation. Pinned by `SetVoiceViewTests.testExamplePreview*`.
    static func examplePreview(_ example: String, displayLength: Int = 80) -> String {
        let trimmed = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > displayLength else { return trimmed }
        return String(trimmed.prefix(displayLength)) + "…"
    }

    private var examplesCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT EXAMPLES")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.accent)

                if examples.isEmpty {
                    Text("No examples yet. Send a few messages — replies longer than 12 characters will appear here.")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Color.fgMute)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(examples.suffix(5).reversed().enumerated()), id: \.offset) { _, ex in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(Theme.Font.sans(13))
                                    .foregroundStyle(Theme.Color.fgMute)
                                Text(SetVoiceView.examplePreview(ex))
                                    .font(Theme.Font.sans(13))
                                    .foregroundStyle(Theme.Color.fgDim)
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if examples.count > 5 {
                        Text("+ \(examples.count - 5) older")
                            .font(Theme.Font.sans(11))
                            .foregroundStyle(Theme.Color.fgFaint)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var strengthCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PROFILE STRENGTH")
                    .font(Theme.Font.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.fgMute)
                Text("\(SetVoiceView.strengthPercent(exampleCount: examples.count))%")
                    .font(Theme.Font.sans(48))
                    .tracking(-1.92)
                    .foregroundStyle(Theme.Color.fg)

                GeometryReader { geo in
                    let pct = Double(SetVoiceView.strengthPercent(exampleCount: examples.count)) / 100.0
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Theme.Color.accent)
                                .frame(width: geo.size.width * pct)
                                .shadow(color: Theme.Color.accentGlow, radius: 5)
                        }
                }
                .frame(height: 6)

                Text(SetVoiceView.strengthHint(exampleCount: examples.count))
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Color.fgMute)

                HStack(spacing: 8) {
                    GhostButton(title: "Clear profile", height: 32, fontSize: 12) {
                        clear()
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
