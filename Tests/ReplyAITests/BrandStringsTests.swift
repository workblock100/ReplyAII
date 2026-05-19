import XCTest
@testable import ReplyAICore

/// REP-UI-STR-HOIST-002 — pin the brand identity constants and assert
/// no SwiftUI view reintroduces inline `Text("R")` or `Text("ReplyAI")`
/// after the consolidation. The drift-enumeration test is the
/// load-bearing one: if someone adds a new view with inline brand
/// literals, the test fails with a precise path:line pointer.
final class BrandStringsTests: XCTestCase {

    func testBrandLetterIsFrozen() {
        XCTAssertEqual(BrandStrings.letter, "R",
            "brand glyph must remain `R` — single uppercase letter; a rebrand updates this single constant and propagates to ~8 view sites at once")
    }

    func testBrandNameIsFrozen() {
        XCTAssertEqual(BrandStrings.name, "ReplyAI",
            "brand wordmark must remain `ReplyAI` — a rebrand updates this single constant and propagates to ~5 standalone-label view sites at once")
    }

    /// The brand glyph is intentionally a single character; the wordmark
    /// is intentionally short enough to fit beside the glyph in a 28-pt
    /// header chip without truncation.
    func testBrandLengthInvariants() {
        XCTAssertEqual(BrandStrings.letter.count, 1,
            "brand glyph must be exactly one character")
        XCTAssertLessThanOrEqual(BrandStrings.name.count, 10,
            "brand wordmark must be ≤ 10 chars to fit beside the glyph")
    }

    /// Walk every `.swift` file under `Sources/ReplyAICore/` and assert
    /// no source line contains the inline brand-literal forms that the
    /// REP-UI-STR-HOIST-002 consolidation pass eliminated. This catches
    /// the regression where a future view is authored with inline
    /// `Text("R")` / `Text("ReplyAI")` instead of `BrandStrings.letter`
    /// / `BrandStrings.name`. The test is in the test target so it runs
    /// against the source tree, not against the compiled module.
    ///
    /// Pattern-matched literals only — we deliberately allow:
    /// - String *sentences* that contain "ReplyAI" inside natural-language
    ///   copy (e.g. "ReplyAI will type this into Messages as you.")
    /// - The brand-name constant itself in `BrandStrings.swift`
    /// - Test files that reference the literals to pin them
    func testNoInlineBrandLiterals() throws {
        let repoRoot = try repoRootURL()
        let sourcesURL = repoRoot.appendingPathComponent("Sources/ReplyAICore")
        guard FileManager.default.fileExists(atPath: sourcesURL.path) else {
            // Test bundle running outside the repo (rare; e.g. installed
            // test bundle without source tree). Skip silently rather than
            // fail — the canonical run is `swift test` from the repo root.
            throw XCTSkip("Sources/ReplyAICore not reachable from the test bundle; this drift check only runs in-repo")
        }

        let inlineLetter = "Text(\"R\")"
        let inlineName = "Text(\"ReplyAI\")"
        var offenders: [String] = []

        let enumerator = FileManager.default.enumerator(at: sourcesURL,
                                                       includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            // Skip the BrandStrings module itself — the canonical literal
            // lives there.
            if url.lastPathComponent == "BrandStrings.swift" { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            for (lineIdx, line) in content.components(separatedBy: "\n").enumerated() {
                if line.contains(inlineLetter) || line.contains(inlineName) {
                    let relativePath = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
                    offenders.append("\(relativePath):\(lineIdx + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty,
            "inline brand literals re-introduced; use BrandStrings.letter / BrandStrings.name instead:\n  " + offenders.joined(separator: "\n  "))
    }

    /// Locate the repo root by walking up from this test file until we
    /// see `Package.swift`. `Bundle.module` gives the test resources
    /// bundle, not the repo, so we use `#filePath` instead.
    private func repoRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        throw XCTSkip("could not locate Package.swift from \(#filePath)")
    }
}
