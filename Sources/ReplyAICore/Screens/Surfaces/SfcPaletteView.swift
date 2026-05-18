import SwiftUI

/// Standalone palette card — what `⌘K` actually presents over the inbox.
///
/// When `searchIndex` is non-nil, live FTS5 results replace the static
/// mock. Invoked both as an overlay on InboxScreen (wired to real data)
/// and as part of the gallery's SfcPaletteView (nil → mock results).
struct PalettePopover: View {
    @State private var query: String = ""
    @State private var results: [SearchIndex.Result] = []
    @State private var pendingQuery: Task<Void, Never>?

    var searchIndex: SearchIndex?
    /// Optional callback — fires when the user hits enter on a result.
    var onJump: ((SearchIndex.Result) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            searchRow
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

            resultsBody

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
        .onChange(of: query) { _, new in rescheduleSearch(for: new) }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.fgMute)
            TextField("Search anyone, anything", text: $query)
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

    @ViewBuilder
    private var resultsBody: some View {
        if searchIndex == nil {
            mockResults
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyState
        } else if results.isEmpty {
            noMatches
        } else {
            liveResults
        }
    }

    // MARK: - Live results (real SearchIndex)

    private var liveResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MESSAGES · \(results.count)")
                .font(Theme.Font.mono(10))
                .tracking(1.0)
                .foregroundStyle(Theme.Color.fgMute)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                        Button {
                            onJump?(r)
                        } label: {
                            searchRowResult(r, active: i == 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(8)
    }

    private func searchRowResult(_ r: SearchIndex.Result, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: Theme.Radius.r8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.72, blue: 0.42),
                            Color(red: 1.0, green: 0.43, blue: 0.57),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
                .overlay(
                    Text(String(r.threadName.prefix(1)))
                        .font(Theme.Font.sans(11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(r.threadName)
                        .font(Theme.Font.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Color.fg)
                        .lineLimit(1)
                    Spacer()
                    Text(r.time)
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Color.fgFaint)
                }
                Text("\"\(r.text)\"")
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Color.fgMute)
                    .lineLimit(2)
            }
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

    // MARK: - Empty + no-match

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("START TYPING")
                .font(Theme.Font.mono(10))
                .tracking(1.0)
                .foregroundStyle(Theme.Color.fgFaint)
            Text("Search across every indexed message in your inbox. Matches thread names, senders, and message body.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noMatches: some View {
        HStack(spacing: 8) {
            Text("No matches")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fgDim)
            Text("·")
                .foregroundStyle(Theme.Color.fgFaint)
            Text("try a different phrasing")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fgMute)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mock (gallery)

    private var mockResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PEOPLE · 2")
                .font(Theme.Font.mono(10))
                .tracking(1.0)
                .foregroundStyle(Theme.Color.fgMute)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            mockPerson(initial: "M", title: "Mom",
                       subtitle: "iMessage · 1,842 messages · last: sunday", active: true)
            mockPerson(initial: "T", title: "Theo Park",
                       subtitle: "iMessage · mentioned \"mom\" in 3 threads", active: false)

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
    }

    private func mockPerson(initial: String, title: String, subtitle: String, active: Bool) -> some View {
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

    // MARK: - Debounced query

    /// Re-runs the search ~120ms after the user stops typing. Cancels
    /// any pending task on new input so we don't stack N searches when
    /// the user holds a key.
    private func rescheduleSearch(for text: String) {
        pendingQuery?.cancel()
        guard let searchIndex else { return }
        let q = text
        pendingQuery = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            let hits = await searchIndex.search(q)
            if Task.isCancelled { return }
            await MainActor.run { self.results = hits }
        }
    }
}

/// `sfc-palette` — gallery view. Blurred inbox behind + dim scrim +
/// palette. The gallery wants the mock result set, so we pass nil.
struct SfcPaletteView: View {
    var body: some View {
        ZStack {
            InboxScreen()
                .blur(radius: 1)
                .opacity(0.5)
                .allowsHitTesting(false)

            Color.black.opacity(0.5).ignoresSafeArea()

            PalettePopover(searchIndex: nil)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 120)
        }
        .frame(minWidth: 1180, minHeight: 720)
    }
}
