// ReplyAI — SwiftUI theme translation.
// Ported from design_handoff_replyai/Theme.swift.
// Keep token names aligned with tokens.css so designers and engineers speak the same dialect.

import SwiftUI

enum Theme {
    enum Color {
        // Surfaces
        static let bg0 = SwiftUI.Color(red: 0.027, green: 0.031, blue: 0.039)
        static let bg1 = SwiftUI.Color(red: 0.039, green: 0.043, blue: 0.051)
        static let bg2 = SwiftUI.Color(red: 0.043, green: 0.047, blue: 0.058)
        static let bg3 = SwiftUI.Color(red: 0.063, green: 0.071, blue: 0.090)

        // Foreground
        static let fg       = SwiftUI.Color(red: 0.949, green: 0.949, blue: 0.933)
        static let fgDim    = SwiftUI.Color(red: 0.788, green: 0.796, blue: 0.776)
        static let fgMute   = SwiftUI.Color(red: 0.541, green: 0.553, blue: 0.525)
        static let fgFaint  = SwiftUI.Color(red: 0.333, green: 0.345, blue: 0.310)

        // Lines
        static let line       = SwiftUI.Color.white.opacity(0.06)
        static let lineStrong = SwiftUI.Color.white.opacity(0.12)
        static let lineFaint  = SwiftUI.Color.white.opacity(0.04)

        // Accent
        static let accent     = SwiftUI.Color(red: 0.843, green: 1.000, blue: 0.227)
        static let accentInk  = SwiftUI.Color(red: 0.039, green: 0.043, blue: 0.051)
        static let accentSoft = SwiftUI.Color(red: 0.843, green: 1.000, blue: 0.227).opacity(0.08)
        static let accentSofter = SwiftUI.Color(red: 0.843, green: 1.000, blue: 0.227).opacity(0.05)
        static let accentRule = SwiftUI.Color(red: 0.843, green: 1.000, blue: 0.227).opacity(0.18)
        static let accentGlow = SwiftUI.Color(red: 0.843, green: 1.000, blue: 0.227).opacity(0.35)

        // Semantic
        static let warn = SwiftUI.Color(red: 1.000, green: 0.702, blue: 0.278)
        static let err  = SwiftUI.Color(red: 1.000, green: 0.545, blue: 0.478)
        static let ok   = SwiftUI.Color(red: 0.204, green: 0.780, blue: 0.349)

        // Channels
        static let channelIMessage = SwiftUI.Color(red: 0.204, green: 0.780, blue: 0.349)
        static let channelWhatsApp = SwiftUI.Color(red: 0.145, green: 0.827, blue: 0.400)
        static let channelSlack    = SwiftUI.Color(red: 0.773, green: 0.498, blue: 0.878)
        static let channelTeams    = SwiftUI.Color(red: 0.384, green: 0.392, blue: 0.655)
        static let channelSMS      = SwiftUI.Color(red: 0.353, green: 0.784, blue: 0.980)
        static let channelTelegram = SwiftUI.Color(red: 0.161, green: 0.714, blue: 0.965)
    }

    enum Font {
        /// SwiftUI's `.weight(...)` on a `.custom(...)` font is unreliable:
        /// it does not automatically pick a separately-registered face. We
        /// resolve to per-weight PostScript names ourselves so Inter Tight
        /// Medium / SemiBold actually render.
        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            let name: String
            switch weight {
            case .bold, .heavy, .black: name = "InterTight-Bold"
            case .semibold:             name = "InterTight-SemiBold"
            case .medium:               name = "InterTight-Medium"
            default:                    name = "InterTight-Regular"
            }
            return .custom(name, size: size, relativeTo: .body)
        }

        static func serifItalic(_ size: CGFloat) -> SwiftUI.Font {
            .custom("InstrumentSerif-Italic", size: size, relativeTo: .title)
        }

        static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            let name: String
            switch weight {
            case .medium, .semibold, .bold, .heavy, .black: name = "JetBrainsMono-Medium"
            default:                                         name = "JetBrainsMono-Regular"
            }
            return .custom(name, size: size, relativeTo: .caption)
        }
    }

    enum Radius {
        static let r6:   CGFloat = 6
        static let r8:   CGFloat = 8
        static let r10:  CGFloat = 10
        static let r12:  CGFloat = 12
        static let r14:  CGFloat = 14
        static let r18:  CGFloat = 18
    }

    enum Space {
        static let s4:  CGFloat = 4
        static let s6:  CGFloat = 6
        static let s8:  CGFloat = 8
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s18: CGFloat = 18
        static let s22: CGFloat = 22
        static let s28: CGFloat = 28
        static let s40: CGFloat = 40
        static let s60: CGFloat = 60
        static let s80: CGFloat = 80
    }

    enum Motion {
        static let fast: Animation = .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12)
        static let std:  Animation = .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.18)
        static let tone: Animation = .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)
    }
}
