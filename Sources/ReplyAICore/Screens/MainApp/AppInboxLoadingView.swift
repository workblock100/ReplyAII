import SwiftUI

/// `app-inbox-loading` — first-sync spinner + skeleton thread rows + progress bar.
struct AppInboxLoadingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        InboxFrame(
            sidebarBadge: .sync,
            threadListOverride: AnyView(loadingList)
        ) {
            VStack(spacing: 14) {
                Text("FIRST SYNC")
                    .font(Theme.Font.mono(11))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.accent)

                Text("Indexing 8,412 messages. This takes ~90 seconds.")
                    .font(Theme.Font.sans(24))
                    .tracking(-0.48)
                    .foregroundStyle(Theme.Color.fg)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                progressBar(fraction: 0.62)

                Text("5,228 / 8,412 · training voice profile locally")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private func progressBar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Theme.Color.accent)
                        .frame(width: geo.size.width * fraction)
                        .shadow(color: Theme.Color.accentGlow, radius: 5)
                }
        }
        .frame(width: 280, height: 4)
    }

    private var loadingList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(rotation))
                Text("Fetching your threads…")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.lineFaint).frame(height: 1) }

            ForEach(0..<8, id: \.self) { _ in skeletonRow }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.035)).frame(width: 200, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.lineFaint).frame(height: 1) }
    }
}

