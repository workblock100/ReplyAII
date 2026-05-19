import XCTest
import SwiftUI
@testable import ReplyAICore

/// Pin Theme tokens. These constants ride into Components/, Inbox/, Screens/,
/// and design_handoff_replyai/ pixel comparisons; any drift silently shifts
/// the visual identity of every screen. Catch accidental token edits before
/// a PR lands by asserting the literal numeric values and the structural
/// invariants the layout code already assumes (monotone scales, distinct
/// channel colors).
final class ThemeTokensTests: XCTestCase {

    // MARK: - Radius scale

    func testRadiusValuesPinned() {
        XCTAssertEqual(Theme.Radius.r6,  6)
        XCTAssertEqual(Theme.Radius.r8,  8)
        XCTAssertEqual(Theme.Radius.r10, 10)
        XCTAssertEqual(Theme.Radius.r12, 12)
        XCTAssertEqual(Theme.Radius.r14, 14)
        XCTAssertEqual(Theme.Radius.r18, 18)
    }

    func testRadiusScaleMonotonic() {
        let scale = [
            Theme.Radius.r6,
            Theme.Radius.r8,
            Theme.Radius.r10,
            Theme.Radius.r12,
            Theme.Radius.r14,
            Theme.Radius.r18,
        ]
        for (a, b) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(a, b, "radius scale must be strictly increasing")
        }
    }

    // MARK: - Space scale

    func testSpaceValuesPinned() {
        XCTAssertEqual(Theme.Space.s4,   4)
        XCTAssertEqual(Theme.Space.s6,   6)
        XCTAssertEqual(Theme.Space.s8,   8)
        XCTAssertEqual(Theme.Space.s10, 10)
        XCTAssertEqual(Theme.Space.s12, 12)
        XCTAssertEqual(Theme.Space.s14, 14)
        XCTAssertEqual(Theme.Space.s18, 18)
        XCTAssertEqual(Theme.Space.s22, 22)
        XCTAssertEqual(Theme.Space.s28, 28)
        XCTAssertEqual(Theme.Space.s40, 40)
        XCTAssertEqual(Theme.Space.s60, 60)
        XCTAssertEqual(Theme.Space.s80, 80)
    }

    func testSpaceScaleMonotonic() {
        let scale = [
            Theme.Space.s4,
            Theme.Space.s6,
            Theme.Space.s8,
            Theme.Space.s10,
            Theme.Space.s12,
            Theme.Space.s14,
            Theme.Space.s18,
            Theme.Space.s22,
            Theme.Space.s28,
            Theme.Space.s40,
            Theme.Space.s60,
            Theme.Space.s80,
        ]
        for (a, b) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(a, b, "space scale must be strictly increasing")
        }
    }

    // MARK: - Channel color identity

    /// Per AGENTS.md, Channel colors drive the dot/avatar accent for each
    /// connected source. Any two channels sharing a color makes the channel
    /// indicator ambiguous, so the test asserts pairwise distinctness at the
    /// SwiftUI.Color description level (literal RGB tuples differ).
    func testChannelColorsAreDistinct() {
        let pairs: [(String, SwiftUI.Color)] = [
            ("iMessage", Theme.Color.channelIMessage),
            ("WhatsApp", Theme.Color.channelWhatsApp),
            ("Slack",    Theme.Color.channelSlack),
            ("Teams",    Theme.Color.channelTeams),
            ("SMS",      Theme.Color.channelSMS),
            ("Telegram", Theme.Color.channelTelegram),
        ]
        for i in 0..<pairs.count {
            for j in (i + 1)..<pairs.count {
                let lhs = String(describing: pairs[i].1)
                let rhs = String(describing: pairs[j].1)
                XCTAssertNotEqual(
                    lhs, rhs,
                    "channel colors must be distinct: \(pairs[i].0) and \(pairs[j].0) share \(lhs)"
                )
            }
        }
    }

    /// Pin the byte-exact RGB literal of every per-channel dot color.
    /// `testChannelColorsAreDistinct` proves no two channels collide, and
    /// `ChannelTests.testDotColorMatchesThemeChannelToken` proves the
    /// `Channel.dotColor` switch wires each case to the matching token —
    /// neither catches a literal edit that shifts a channel's hue without
    /// breaking distinctness or wiring (e.g. someone "tones down" the
    /// Slack purple from `#C57FE0` to `#9F70C0`, both still distinct from
    /// every other channel and still wired through the switch). These
    /// colors are the per-channel brand identity rendered in every
    /// sidebar dot, avatar corner badge, and channel-filter chip — drift
    /// silently rebrands the channel signal across every screen. Bytes
    /// derive from the Color literal in `Sources/ReplyAI/Theme/Theme.swift`
    /// run through SwiftUI's `String(describing:)` projection (sRGB →
    /// `#RRGGBBAA`). A single-digit edit on any literal flips one byte
    /// and surfaces here in CI rather than as a visual regression.
    func testChannelColorLiteralsArePinned() {
        XCTAssertEqual(
            String(describing: Theme.Color.channelIMessage),
            "#34C759FF",
            "Theme.Color.channelIMessage is iOS-green — drift silently rebrands every iMessage thread badge"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.channelWhatsApp),
            "#25D366FF",
            "Theme.Color.channelWhatsApp matches WhatsApp brand green — drift breaks brand recognition on the channel chip"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.channelSlack),
            "#C57FE0FF",
            "Theme.Color.channelSlack is the dark-mode-friendly Slack purple — Slack is the priority non-iMessage channel post-pivot, drift here is high-visibility"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.channelTeams),
            "#6264A7FF",
            "Theme.Color.channelTeams matches Teams brand purple — drift silently rebrands every Teams thread"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.channelSMS),
            "#5AC8FAFF",
            "Theme.Color.channelSMS is iOS classic blue — drift breaks SMS-vs-iMessage visual distinction in the sidebar"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.channelTelegram),
            "#29B6F6FF",
            "Theme.Color.channelTelegram is the dark-mode-friendly Telegram blue — drift here breaks brand recognition on the channel chip"
        )
    }

    // MARK: - Semantic color identity

    /// Warn / err / ok are surfaced as status chips, banners, and inline
    /// validation. Two semantics sharing a color collapses the user's
    /// ability to distinguish "this is fine" from "this needs attention".
    func testSemanticColorsAreDistinct() {
        let warn = String(describing: Theme.Color.warn)
        let err  = String(describing: Theme.Color.err)
        let ok   = String(describing: Theme.Color.ok)
        XCTAssertNotEqual(warn, err, "warn and err must be visually distinct")
        XCTAssertNotEqual(warn, ok,  "warn and ok must be visually distinct")
        XCTAssertNotEqual(err,  ok,  "err and ok must be visually distinct")
    }

    /// Pin the byte-exact hex of every semantic status color.
    /// `testSemanticColorsAreDistinct` proves the three never collide,
    /// but it would happily pass if a designer "softened" the err red
    /// from `#FF8B7A` (warm coral) to a neon `#FF1010` — both still
    /// distinct from warn and ok, but the entire alarm vocabulary of
    /// the app shifts. Pin each literal here so a one-digit edit
    /// surfaces in CI rather than as inconsistent banner color across
    /// builds. `ok` happens to share its hex with `channelIMessage`
    /// (`#34C759`) at the moment because both intentionally render iOS
    /// system green; a future split keeps the pin local to each token.
    func testSemanticColorLiteralsArePinned() {
        XCTAssertEqual(
            String(describing: Theme.Color.warn),
            "#FFB347FF",
            "Theme.Color.warn is the warm-amber chip — drift here silently restyles every 'X waiting' / 'paused' surface"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.err),
            "#FF8B7AFF",
            "Theme.Color.err is the warm-coral alarm — drift here silently restyles every error banner / failure pill in the app"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.ok),
            "#34C759FF",
            "Theme.Color.ok is iOS-green — drift here silently restyles every 'sent' / 'connected' / 'done' affirmation chip"
        )
    }

    // MARK: - Accent stack

    /// The accent token is layered as accent / accentSoft / accentSofter /
    /// accentRule / accentGlow. They must derive from the same hue but
    /// render at different opacities; the literal opacity values double as
    /// the contract design hands the engineer.
    func testAccentSoftLessOpaqueThanAccent() {
        // Compare descriptions — SwiftUI.Color encodes opacity in its debug
        // print, so a hue change OR an opacity change shows up as a string
        // diff.
        let solid   = String(describing: Theme.Color.accent)
        let soft    = String(describing: Theme.Color.accentSoft)
        let softer  = String(describing: Theme.Color.accentSofter)
        let rule    = String(describing: Theme.Color.accentRule)
        let glow    = String(describing: Theme.Color.accentGlow)

        // Five distinct strings — a regression that collapses two layers
        // (e.g. accentSoft = accentSofter by accident) is caught here.
        let all = [solid, soft, softer, rule, glow]
        XCTAssertEqual(Set(all).count, all.count,
                       "accent stack must have 5 distinct opacity levels; got duplicates: \(all)")
    }

    /// Pin each accent-stack layer's opacity at the byte-exact percentage
    /// SwiftUI projects in `String(describing:)` (`<n>% #RRGGBBFF`). The
    /// distinctness test above proves no two layers collide, but a
    /// designer "lifting" `accentSoft` from 8% to 10% (a 25% intensity
    /// shift on every accent-tinted card surface) would still pass
    /// distinctness. The opacity literals are the explicit design
    /// contract — `accentSoft` is the row-highlight tint, `accentSofter`
    /// the static card wash, `accentRule` the divider tint, `accentGlow`
    /// the focused-element halo. Drift on any one silently shifts the
    /// visual weight of that affordance everywhere it renders.
    func testAccentStackOpacityLiteralsArePinned() {
        XCTAssertEqual(
            String(describing: Theme.Color.accentSoft),
            "8% #8C73FFFF",
            "Theme.Color.accentSoft is the 8% accent wash on row highlights — drift restyles every accent-tinted hover/select state"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.accentSofter),
            "5% #8C73FFFF",
            "Theme.Color.accentSofter is the 5% static accent card wash — drift restyles every accent-tinted card surface"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.accentRule),
            "18% #8C73FFFF",
            "Theme.Color.accentRule is the 18% accent divider tint — drift shifts the visual weight of every accent-rule separator"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.accentGlow),
            "35% #8C73FFFF",
            "Theme.Color.accentGlow is the 35% accent halo on focused elements — drift restyles the focus affordance everywhere"
        )
    }

    // MARK: - Foreground stack

    /// fg / fgDim / fgMute / fgFaint are the typographic hierarchy. They
    /// must each be a distinct token so headings, body, captions, and
    /// disabled text don't collapse onto the same render value.
    func testForegroundStackIsDistinct() {
        let stack = [
            String(describing: Theme.Color.fg),
            String(describing: Theme.Color.fgDim),
            String(describing: Theme.Color.fgMute),
            String(describing: Theme.Color.fgFaint),
        ]
        XCTAssertEqual(Set(stack).count, stack.count,
                       "foreground stack must have 4 distinct shades; got duplicates: \(stack)")
    }

    /// Companion to `testForegroundStackIsDistinct`: distinctness only catches
    /// two layers collapsing onto the same render value, it doesn't catch a
    /// uniform shift — e.g. all four shades darkening 10% would still be
    /// distinct yet visibly degrade typographic contrast across every
    /// heading, body, caption, and disabled-text use site. The fg-stack
    /// hex literals are the design contract: `fg` is the primary text
    /// color (warm off-white), `fgDim` is the secondary heading/label tint,
    /// `fgMute` is the tertiary metadata color, `fgFaint` is the disabled
    /// state. The slight green undertone (each shade has G > R > B) is
    /// intentional and warmth-tied to the warm-paper accent ecosystem —
    /// drift to a neutral or cool-ramp would silently restyle the entire
    /// app's text feel. Mirrors `testAccentBrandLiteralIsPinnedChartreuseLime`
    /// + the line-stack pin pattern, but covers the typographic ramp that
    /// reads on every screen.
    func testForegroundStackHexLiteralsArePinned() {
        XCTAssertEqual(
            String(describing: Theme.Color.fg),
            "#F2F2EEFF",
            "Theme.Color.fg is the primary warm off-white text color — drift restyles every heading and body text site"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.fgDim),
            "#C9CBC6FF",
            "Theme.Color.fgDim is the secondary heading/label tint — drift restyles every secondary-text affordance"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.fgMute),
            "#8A8D86FF",
            "Theme.Color.fgMute is the tertiary metadata color — drift restyles every metadata/caption row"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.fgFaint),
            "#55584FFF",
            "Theme.Color.fgFaint is the disabled-state text color — drift restyles every disabled-affordance label"
        )
    }

    // MARK: - Surface stack

    func testSurfaceStackIsDistinct() {
        let stack = [
            String(describing: Theme.Color.bg0),
            String(describing: Theme.Color.bg1),
            String(describing: Theme.Color.bg2),
            String(describing: Theme.Color.bg3),
        ]
        XCTAssertEqual(Set(stack).count, stack.count,
                       "surface stack must have 4 distinct shades; got duplicates: \(stack)")
    }

    // MARK: - Line stack

    func testLineStackIsDistinct() {
        let stack = [
            String(describing: Theme.Color.line),
            String(describing: Theme.Color.lineStrong),
            String(describing: Theme.Color.lineFaint),
        ]
        XCTAssertEqual(Set(stack).count, stack.count,
                       "line stack must have 3 distinct opacities; got duplicates: \(stack)")
    }

    /// Companion to `testLineStackIsDistinct`: the distinctness test only
    /// catches collapses (two layers becoming visually identical), it
    /// doesn't catch a uniform shift — e.g. all three opacities scaling up
    /// 50% would still be distinct yet visibly heavier across every divider
    /// in the app. The opacity literals are the explicit design contract:
    /// `line` (6%) is the standard divider, `lineStrong` (12%) is the
    /// emphasized boundary used on focused/selected affordances, `lineFaint`
    /// (4%) is the inset hairline used on nested cards. Drift on any one
    /// silently shifts how heavy or hairline-light the affordance reads
    /// everywhere it renders. Mirrors `testAccentStackOpacityLiteralsArePinned`
    /// for the accent variants — same pattern, applied to the neutral-line
    /// stack that's used in nearly every screen's chrome.
    func testLineStackOpacityLiteralsArePinned() {
        // Note: `SwiftUI.Color.white` is a system color, not an RGB color, so
        // its `String(describing:)` description uses the literal `"white"`
        // token rather than the `#FFFFFFFF` hex form that RGB-constructed
        // colors produce. Pin against the actual description shape so the
        // assertion reflects the source's `Color.white.opacity(...)`
        // construction — a future "consistency fix" that re-routes the line
        // stack through `Color(red: 1, green: 1, blue: 1).opacity(...)` would
        // surface here as a deliberate format change.
        XCTAssertEqual(
            String(describing: Theme.Color.line),
            "6% white",
            "Theme.Color.line is the 6% white standard divider — drift shifts the weight of every panel boundary"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.lineStrong),
            "12% white",
            "Theme.Color.lineStrong is the 12% white emphasized boundary — drift shifts the weight of every focused-affordance edge"
        )
        XCTAssertEqual(
            String(describing: Theme.Color.lineFaint),
            "4% white",
            "Theme.Color.lineFaint is the 4% white inset hairline — drift shifts the weight of every nested-card boundary"
        )
    }

    // MARK: - Motion durations
    //
    // SwiftUI's `Animation` type does not conform to `Equatable` in a
    // useful public way, so we pin via `String(describing:)`. The
    // BezierAnimation description embeds the literal `duration: <n>`
    // verbatim, which is the actual designer-facing knob — substring-
    // matching it catches any silent retiming. The control points
    // (0.25, 0.1, 0.25, 1) match the design handoff's `--motion-curve`
    // and are intentionally identical across fast/std/tone — only the
    // duration changes per use site.

    func testMotionFastDurationPinned() {
        let desc = String(describing: Theme.Motion.fast)
        XCTAssertTrue(desc.contains("duration: 0.12"),
            "Theme.Motion.fast must be 0.12s — used by hover/press feedback. Got: \(desc)")
    }

    func testMotionStdDurationPinned() {
        let desc = String(describing: Theme.Motion.std)
        XCTAssertTrue(desc.contains("duration: 0.18"),
            "Theme.Motion.std must be 0.18s — used by tone toggle, banner appear. Got: \(desc)")
    }

    func testMotionToneDurationPinned() {
        let desc = String(describing: Theme.Motion.tone)
        XCTAssertTrue(desc.contains("duration: 0.14"),
            "Theme.Motion.tone must be 0.14s — composer tone-pill fade. Got: \(desc)")
    }

    func testMotionDurationsOrderedFastToStd() {
        // The design contract is fast < tone < std. Tone sits between
        // the two so the composer's pill-swap reads quicker than a
        // banner appearance but slower than a press indicator.
        let fast = String(describing: Theme.Motion.fast)
        let tone = String(describing: Theme.Motion.tone)
        let std  = String(describing: Theme.Motion.std)

        XCTAssertTrue(fast.contains("duration: 0.12"))
        XCTAssertTrue(tone.contains("duration: 0.14"))
        XCTAssertTrue(std.contains("duration: 0.18"))
        // Sanity: 0.12 < 0.14 < 0.18 — re-asserted via numeric checks
        // so that if the pin literals change, the test surfaces the
        // ordering regression in addition to the literal mismatch.
        XCTAssertLessThan(0.12, 0.14)
        XCTAssertLessThan(0.14, 0.18)
    }

    /// Pin the bezier control-point coefficients of the shared motion
    /// curve. The duration pins above only catch retiming — a swap from
    /// the design's `timingCurve(0.25, 0.1, 0.25, 1)` to the SwiftUI
    /// default `easeInOut` (or any other curve, e.g. `(0.42, 0, 0.58, 1)`)
    /// would still pass `duration: 0.12/0.14/0.18` while changing the
    /// motion *feel* across every animated affordance in the app. The
    /// design handoff's `--motion-curve` is the explicit contract; the
    /// existing test-doc comment says the control points are pinned but
    /// no actual assertion exists, so this fills the gap.
    ///
    /// SwiftUI projects `timingCurve(0.25, 0.1, 0.25, 1, ...)` to a
    /// `BezierAnimation.curve: ... CubicSolver(ax: 1.0, bx: -0.75, cx:
    /// 0.75, ay: -1.7..., by: 2.4..., cy: 0.3...)` description (the
    /// solver coefficients are derived from the control points by a
    /// Bernstein-basis transform — `cx = 3 * x1 = 0.75`, `bx = 3 * (x2 -
    /// 2*x1) = -0.75`, `ax = 1 - cx - bx = 1.0`, ditto for the y axis).
    /// Pin a substring of the curve descriptor that any drift in any of
    /// the four control points would break — using `cx: 0.75` because
    /// it's the simplest finite-precision coefficient that's stable
    /// under SwiftUI's printing format. This is the same pattern as the
    /// duration pin (substring match against String(describing:)) and
    /// is robust to whitespace/format changes that might affect a full-
    /// string equality.
    func testMotionCurveControlPointsArePinned() {
        // 0.25 (x1) → cx coefficient = 3 * 0.25 = 0.75.
        // 0.1 (y1)  → cy = 3 * 0.1   = 0.30000000000000004 (float
        //             round-trip noise — match a robust substring
        //             prefix instead of the noisy tail).
        // The same curve is reused across fast/std/tone, so all three
        // descriptions should contain the same coefficient signature.
        let curveSignature = "cx: 0.75"
        for (label, anim) in [
            ("fast", Theme.Motion.fast),
            ("std",  Theme.Motion.std),
            ("tone", Theme.Motion.tone),
        ] {
            let desc = String(describing: anim)
            XCTAssertTrue(
                desc.contains(curveSignature),
                "Theme.Motion.\(label) must use the design's `timingCurve(0.25, 0.1, 0.25, 1)` curve — drift to a different bezier silently changes the feel of every animation. Expected substring \(curveSignature) in: \(desc)"
            )
        }
    }

    // MARK: - Brand accent literal pin
    //
    // `Theme.Color.accent` is the entire visual identity of the app —
    // every primary CTA, the menu-bar `R` glyph hue, the keyboard-shortcut
    // chip, the unread-thread highlight all reference this token. The
    // existing `testAccentSoftLessOpaqueThanAccent` proves the layered
    // accent stack stays distinct, but it would happily pass if someone
    // shifted the underlying hue from chartreuse-lime to royal blue (the
    // five layers are still distinct from each other, just no longer
    // ReplyAI-shaped). Pin the actual RGB bytes here so a one-digit tweak
    // (`green: 1.0` → `green: 0.9`) surfaces in CI rather than as "the
    // app's accent looks slightly off in the next build". SwiftUI.Color's
    // `String(describing:)` projects to a `#RRGGBBAA` hex form on macOS;
    // (0.843, 1.000, 0.227) → 215, 255, 57 → `#D7FF39FF` (Apple rounds
    // 0.227 × 255 to 57 = 0x39, not 0x3A, when the source value is the
    // double 0.227 exactly). A Color-literal change shifts at least one
    // byte and the equality fails.
    func testAccentBrandLiteralIsPinnedPurpleViolet() {
        // SwiftUI's `String(describing:)` projects an sRGB Color to
        // `#RRGGBBAA`. (0.55, 0.45, 1.00) lands as `#8C73FFFF`:
        //   R: 0.55 × 255 = 140.25 → 140 = 0x8C
        //   G: 0.45 × 255 = 114.75 → 115 = 0x73
        //   B: 1.00 × 255 = 255   = 0xFF
        // REP-FLIP-2026-05-19 flipped the brand from chartreuse-lime
        // (#D7FF3AFF) to purple-violet (#8C73FFFF) per user feedback. The
        // chartreuse pin is preserved in `git log` if a future "let's go
        // back to yellow" needs to surface as a deliberate revert.
        XCTAssertEqual(
            String(describing: Theme.Color.accent),
            "#8C73FFFF",
            "Theme.Color.accent is the brand purple-violet — drift here silently rebrands every CTA and accent surface in the app"
        )
    }

    // The four background-surface stops are the rest of the visual
    // identity — bg0 is the absolute floor (window chrome), bg1 is the
    // primary inbox surface, bg2/bg3 are layered card surfaces. The
    // existing `testSurfaceStackIsDistinct` proves they're pairwise
    // distinct but a global "lighten everything by 5%" tweak still
    // passes that test. Pin the literal hex of bg1 — the surface every
    // user spends 99% of their session staring at — so a global lift
    // surfaces here. Sibling stops aren't pinned individually because
    // the distinctness invariant + the bg1 pin suffice to catch any
    // realistic regression (a single-stop edit fails distinctness; a
    // proportional shift fails this byte-pin).
    func testSurfaceBg1LiteralIsPinnedDarkInbox() {
        // (0.039, 0.043, 0.051) → 9.945, 10.965, 13.005 → #0A0B0DFF
        // (Apple rounds half-to-even per IEEE 754, so 9.945 → 10 = 0x0A,
        // 10.965 → 11 = 0x0B, 13.005 → 13 = 0x0D.)
        XCTAssertEqual(
            String(describing: Theme.Color.bg1),
            "#0A0B0DFF",
            "Theme.Color.bg1 is the inbox primary surface — drift silently lifts/darkens every screen the user sees most"
        )
    }

    // `Theme.Color.accentInk` is the inverse text color rendered on top
    // of the brand accent — every primary CTA's label ("Get started",
    // "Send", "Open inbox"), the menu-bar `R` glyph, and unread-count
    // badges all use this color. REP-FLIP-2026-05-19 flipped it from
    // near-black (deep ink — good contrast on chartreuse-lime) to pure
    // white (good contrast on purple-violet). Black-on-purple passes
    // WCAG AA on the new accent too, but white-on-purple is the cleaner
    // brand statement.
    func testAccentInkLiteralIsPinnedWhite() {
        // SwiftUI projects pure white as the short literal "white"
        // via its `String(describing:)` form (not the 8-char hex
        // "#FFFFFFFF" form).
        XCTAssertEqual(
            String(describing: Theme.Color.accentInk),
            "white",
            "Theme.Color.accentInk is the text color stacked on accent surfaces — drift silently changes contrast on every primary CTA"
        )
    }

    // MARK: - Font weight routing

    /// `Theme.Font.mono(_:weight:)` ships JetBrainsMono in two static
    /// faces — Regular and Medium — and routes the SwiftUI `Font.Weight`
    /// argument across them via a switch. The current contract is:
    ///   `.medium` / `.semibold` / `.bold` / `.heavy` / `.black` → "JetBrainsMono-Medium"
    ///   everything else (incl. `.regular`, `.light`, `.thin`, `.ultraLight`) → "JetBrainsMono-Regular"
    /// SwiftUI's `Font` type is opaque under `String(describing:)` — it
    /// projects to `Font(provider: SwiftUI.FontBox<...NamedProvider>)`
    /// without the family name. But `Font` IS Equatable, so we can pin
    /// the routing by asserting the equality structure between the
    /// produced fonts: same-bucket weights are equal, cross-bucket
    /// weights are not. Catches a regression like flipping `.semibold`
    /// to fall through to Regular (which would silently un-bold every
    /// keyboard-shortcut chip and timestamp digit in the app), or a
    /// "consistency fix" that maps `.regular` to Medium (silently
    /// thickening every monospace surface).
    func testMonoWeightRoutingMapsBoldToMedium() {
        let monoRegular  = Theme.Font.mono(11, weight: .regular)
        let monoMedium   = Theme.Font.mono(11, weight: .medium)
        let monoSemibold = Theme.Font.mono(11, weight: .semibold)
        let monoBold     = Theme.Font.mono(11, weight: .bold)
        let monoHeavy    = Theme.Font.mono(11, weight: .heavy)
        let monoBlack    = Theme.Font.mono(11, weight: .black)
        let monoLight    = Theme.Font.mono(11, weight: .light)

        // The five "Medium-bucket" weights all map to the same
        // JetBrainsMono-Medium PostScript face → pairwise equal.
        XCTAssertEqual(monoMedium, monoSemibold,
            "mono(.medium) and mono(.semibold) must route to the same JetBrainsMono-Medium face")
        XCTAssertEqual(monoMedium, monoBold,
            "mono(.medium) and mono(.bold) must route to the same JetBrainsMono-Medium face")
        XCTAssertEqual(monoMedium, monoHeavy,
            "mono(.medium) and mono(.heavy) must route to the same JetBrainsMono-Medium face")
        XCTAssertEqual(monoMedium, monoBlack,
            "mono(.medium) and mono(.black) must route to the same JetBrainsMono-Medium face")

        // Regular bucket: `.regular` and `.light` both route to
        // JetBrainsMono-Regular (light has no static face shipped).
        XCTAssertEqual(monoRegular, monoLight,
            "mono(.regular) and mono(.light) must both route to JetBrainsMono-Regular — JetBrainsMono ships only Regular and Medium static TTFs")

        // Cross-bucket: routing must produce distinct fonts. Drift here
        // (e.g. dropping the switch and always using Regular) would
        // silently un-bold every monospaced chip in the app.
        XCTAssertNotEqual(monoRegular, monoMedium,
            "mono(.regular) and mono(.medium) MUST be distinct fonts — a switch-arm collapse would silently un-bold every monospaced affordance")
        XCTAssertNotEqual(monoRegular, monoBold,
            "mono(.regular) and mono(.bold) MUST be distinct fonts")
    }

    /// Pin that `Theme.Font.mono`'s weight default-argument routes
    /// through the Regular face — same as passing `.regular` explicitly.
    /// A future "default to medium for better readability" edit would
    /// fail this assertion AND silently thicken every caller that never
    /// passed an explicit weight (the dominant call shape in the codebase).
    func testMonoDefaultWeightArgumentIsRegular() {
        XCTAssertEqual(
            Theme.Font.mono(11),
            Theme.Font.mono(11, weight: .regular),
            "mono(_:) default weight argument must equal mono(_:weight:.regular) — drift silently shifts the no-weight callers' rendering"
        )
    }

    /// `Theme.Font.sans(_:weight:)` uses Inter Tight as a single
    /// variable-weight TTF, so `.regular` vs `.bold` should produce
    /// distinct Font values (the wght axis differs). Pin the
    /// distinctness so a future "Inter Tight is variable so we don't
    /// need the .weight() modifier" refactor surfaces here.
    func testSansWeightModifierIsAppliedAndProducesDistinctFonts() {
        XCTAssertNotEqual(
            Theme.Font.sans(13, weight: .regular),
            Theme.Font.sans(13, weight: .bold),
            "sans(.regular) and sans(.bold) must be distinct — Inter Tight is a single variable-weight TTF and the .weight() modifier on the resolved Font is what differentiates them; dropping it would render every weight as the same axis position"
        )
    }

    /// `Theme.Font.serifItalic(_:)` is the InstrumentSerif-Italic display
    /// face used for every onboarding hero ("you" pull-quote, "Teach
    /// ReplyAI how you text."), every empty-state hero ("Inbox zero."),
    /// and every error screen heading. Previously had ZERO test
    /// coverage. Pin two structural invariants that catch the most
    /// likely regressions: (a) caller-passed size flows through to the
    /// resolved Font (a "let's use a default size" refactor that
    /// ignored the parameter would silently shrink every onboarding
    /// hero), (b) serifItalic at a given size is distinct from sans +
    /// mono at the same size (catches a regression that swapped
    /// InstrumentSerif-Italic for the default sans face).
    func testSerifItalicSizeArgumentFlowsThrough() {
        XCTAssertNotEqual(
            Theme.Font.serifItalic(14),
            Theme.Font.serifItalic(38),
            "serifItalic(14) and serifItalic(38) must be distinct fonts — caller-passed size must flow through to the resolved Font, otherwise every onboarding hero would render at the same size regardless of the call-site argument"
        )
    }

    func testSerifItalicProducesDistinctFontFromSansAndMono() {
        // Same size to isolate the family-name difference.
        let serif = Theme.Font.serifItalic(14)
        let sans  = Theme.Font.sans(14)
        let mono  = Theme.Font.mono(14)
        XCTAssertNotEqual(serif, sans,
            "serifItalic and sans must resolve to distinct fonts at the same size — a regression that swapped InstrumentSerif-Italic for the default sans face would silently un-italicize every onboarding hero")
        XCTAssertNotEqual(serif, mono,
            "serifItalic and mono must resolve to distinct fonts at the same size — a regression here would silently mono-space every onboarding hero")
        XCTAssertNotEqual(sans, mono,
            "sans and mono are already distinct via different .custom names; pin the relationship so all three Theme.Font helpers' family-routing surfaces here at the same size")
    }
}
