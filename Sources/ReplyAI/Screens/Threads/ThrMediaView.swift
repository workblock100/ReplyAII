import SwiftUI

/// `thr-media` — WhatsApp image + voice memo with translated transcript.
struct ThrMediaView: View {
    var body: some View {
        InboxFrame {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.line).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        imageMessage
                        voiceMemoWithTranscript
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                composer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(text: "LF", channel: .whatsapp, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lena Fischer")
                    .font(Theme.Font.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.fg)
                Text("whatsapp · Berlin · last seen 12m ago")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    // MARK: - Messages

    private var imageMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.29, green: 0.35, blue: 0.48),
                             Color(red: 0.16, green: 0.19, blue: 0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                diagonalHatchPattern
                Text("IMG_2041.jpg · 2.4 MB")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.leading, 12)
                    .padding(.bottom, 10)
            }
            .frame(width: 280, height: 180)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous))

            Text("yesterday 6:41 PM")
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.fgFaint)
        }
    }

    /// Repeating 12×12 diagonal line motif — pure decoration.
    private var diagonalHatchPattern: some View {
        Canvas { ctx, size in
            let path = Path { p in
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 12
                }
            }
            ctx.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
        }
    }

    private var voiceMemoWithTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            voiceMemoBubble
            transcriptCard
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var voiceMemoBubble: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Text("▶")
                        .font(Theme.Font.sans(14, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                )
            waveform
                .frame(height: 24)
                .frame(maxWidth: .infinity)
            Text("0:34")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// 32 bars with sine-driven heights, matching the JSX (4 + |sin(i*0.7)| * 20).
    private var waveform: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<32, id: \.self) { i in
                let h = 4 + abs(sin(Double(i) * 0.7)) * 20
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.Color.fgDim)
                    .frame(width: 2, height: h)
            }
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRANSCRIPT · TRANSLATED FROM GERMAN")
                .font(Theme.Font.mono(10))
                .tracking(0.9)
                .foregroundStyle(Theme.Color.accent)
            Text("\"Hey! So I was thinking — for Berlin on the 24th, could we push it to the 25th? Flights are cheaper and we'd still have the weekend. Let me know!\"")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgDim)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                .fill(Theme.Color.accentSofter)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                .stroke(Theme.Color.accentRule, lineWidth: 1)
        )
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRAFT · WARM (IN ENGLISH, SHE REPLIES IN GERMAN)")
                .font(Theme.Font.mono(11))
                .tracking(0.9)
                .foregroundStyle(Theme.Color.fgMute)
            HStack(alignment: .top, spacing: 2) {
                Text("25th works! Let me grab the flight tonight — same airport?")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Color.fg)
                    .lineSpacing(3.5)
                    .fixedSize(horizontal: false, vertical: true)
                Caret().padding(.top, 2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.r12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color(red: 0.043, green: 0.047, blue: 0.058))
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
    }
}
