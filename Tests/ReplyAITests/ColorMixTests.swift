import XCTest
import SwiftUI
import AppKit
@testable import ReplyAICore

/// Pin the math on `Color.mix(with:amount:)`. The avatar gradient uses this
/// to compute a darker endpoint from each channel's dot color, so the
/// linear mix has to actually move toward the second color and clamp the
/// amount parameter — a mis-clamped value would produce out-of-gamut RGB
/// (rendered as grey) and the avatar gradient would lose its channel
/// identity.
final class ColorMixTests: XCTestCase {

    private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        // SwiftUI Color → NSColor → sRGB components. Same conversion the
        // implementation under test uses, so any mismatch here would also
        // break the avatar at render time.
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    private func assertClose(
        _ actual: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        _ expected: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        accuracy: CGFloat = 0.005,
        file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertEqual(actual.r, expected.r, accuracy: accuracy, "red component", file: file, line: line)
        XCTAssertEqual(actual.g, expected.g, accuracy: accuracy, "green component", file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, "blue component", file: file, line: line)
        XCTAssertEqual(actual.a, expected.a, accuracy: accuracy, "alpha component", file: file, line: line)
    }

    func testZeroAmountReturnsOriginal() {
        // amount=0 means "stay on the first color" — the gradient's top-
        // leading endpoint is unmodified.
        let red = Color(red: 1, green: 0, blue: 0)
        let mixed = red.mix(with: .black, amount: 0)
        assertClose(components(mixed), (1, 0, 0, 1))
    }

    func testFullAmountReturnsOther() {
        // amount=1 means "fully the second color" — gradient's bottom-
        // trailing endpoint at maximum darkness mix.
        let red = Color(red: 1, green: 0, blue: 0)
        let mixed = red.mix(with: .black, amount: 1)
        assertClose(components(mixed), (0, 0, 0, 1))
    }

    func testHalfAmountIsLinearMidpoint() {
        // 50/50 mix in sRGB lands on the geometric middle of each
        // component. Not perceptual (that would need oklab), but the
        // implementation explicitly says "approximate" — pin the linear
        // behavior so a future swap to perceptual mixing is a deliberate
        // visual change visible in this test.
        let red = Color(red: 1, green: 0, blue: 0)
        let mixed = red.mix(with: .black, amount: 0.5)
        assertClose(components(mixed), (0.5, 0, 0, 1))
    }

    func testNegativeAmountIsClampedToZero() {
        // Defensive clamp: out-of-range amounts shouldn't escape the
        // [0, 1] interpolation interval and produce out-of-gamut RGB.
        let red = Color(red: 1, green: 0, blue: 0)
        let mixed = red.mix(with: .black, amount: -0.5)
        assertClose(components(mixed), (1, 0, 0, 1))
    }

    func testAmountAboveOneIsClampedToOne() {
        let red = Color(red: 1, green: 0, blue: 0)
        let mixed = red.mix(with: .black, amount: 1.7)
        assertClose(components(mixed), (0, 0, 0, 1))
    }

    func testAlphaMixesAlongsideRGB() {
        // The implementation interpolates alpha too — a fully-opaque source
        // mixed with a transparent target lands at intermediate alpha. The
        // avatar gradient uses opaque colors so this branch is rarely hit
        // in production, but it's worth pinning so a future "alpha is
        // hardcoded to 1.0" optimization shows up as a deliberate change.
        let opaque = Color(red: 0, green: 0, blue: 0, opacity: 1.0)
        let transparent = Color(red: 0, green: 0, blue: 0, opacity: 0.0)
        let mixed = opaque.mix(with: transparent, amount: 0.5)
        XCTAssertEqual(components(mixed).a, 0.5, accuracy: 0.005,
            "alpha must interpolate as 0.5 at 50% mix")
    }

    func testMixIsCommutativeAtFiftyPercent() {
        // a.mix(with: b, 0.5) == b.mix(with: a, 0.5) — required for the
        // avatar gradient to look the same regardless of which dot color
        // is "primary" and which is the darken target. Catches a future
        // refactor that accidentally swaps the t/(1-t) terms.
        let red = Color(red: 1, green: 0, blue: 0)
        let blue = Color(red: 0, green: 0, blue: 1)
        let ab = red.mix(with: blue, amount: 0.5)
        let ba = blue.mix(with: red, amount: 0.5)
        let abc = components(ab)
        let bac = components(ba)
        assertClose(abc, bac)
    }
}
