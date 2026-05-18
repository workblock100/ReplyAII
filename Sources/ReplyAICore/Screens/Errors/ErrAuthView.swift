import SwiftUI

/// `err-auth` — WhatsApp multi-device pairing expired; show a QR to re-pair.
struct ErrAuthView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                    .fill(Theme.Color.warn.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                            .stroke(Theme.Color.warn.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "shield")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Color.warn)
            }

            Text("Your WhatsApp session expired.")
                .font(Theme.Font.sans(32))
                .tracking(-0.64)
                .foregroundStyle(Theme.Color.fg)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            Text("WhatsApp logs out multi-device sessions after 30 days of no phone activity. Scan the QR code from your phone to pair again.")
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Color.fgMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            qrCodePlaceholder
                .frame(width: 180, height: 180)

            GhostButton(title: "Use a different phone")
            Spacer()
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg1)
    }

    /// Static 7×7 QR-like grid matching the JSX's visual placeholder.
    private var qrCodePlaceholder: some View {
        let on: Set<Int> = [0,1,2,4,5,6,7,11,13,14,16,19,21,22,23,25,27,28,30,31,34,36,37,39,41,43,44,46,47,48]
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.r14, style: .continuous)
                .fill(Color.white)
            GeometryReader { geo in
                let cell = geo.size.width / 7
                ForEach(0..<49, id: \.self) { i in
                    if on.contains(i) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: cell, height: cell)
                            .position(
                                x: CGFloat(i % 7) * cell + cell / 2,
                                y: CGFloat(i / 7) * cell + cell / 2
                            )
                    }
                }
            }
            .padding(20)
        }
    }
}

