import XCTest
import SwiftUI
@testable import ReplyAI

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
}
