import XCTest
@testable import ReplyAI

/// Pins the public surface of `Folder.Kind` and `Tone`. Both are persisted
/// (Folder.Kind via `Preferences.lastSelectedFolder`, Tone via rules.json
/// and the per-thread draft cache), so any rename or case removal is a
/// silent data migration. These tests fail loudly when the contract drifts.
final class FolderKindTests: XCTestCase {

    func testAllCasesShape() {
        // The sidebar renders `allCases` in declaration order; if the order or
        // count drifts the layout shifts and persisted "lastSelectedFolder"
        // strings stop matching their previous case.
        XCTAssertEqual(Folder.Kind.allCases,
                       [.all, .priority, .awaiting, .snoozed, .done],
                       "sidebar bucket order must remain stable for layout + persistence")
    }

    func testRawValuesArePersistenceContract() {
        // Persisted into Preferences.lastSelectedFolder. Renaming = migration.
        XCTAssertEqual(Folder.Kind.all.rawValue,      "all")
        XCTAssertEqual(Folder.Kind.priority.rawValue, "priority")
        XCTAssertEqual(Folder.Kind.awaiting.rawValue, "awaiting")
        XCTAssertEqual(Folder.Kind.snoozed.rawValue,  "snoozed")
        XCTAssertEqual(Folder.Kind.done.rawValue,     "done")
    }

    func testRawRoundTrip() {
        for kind in Folder.Kind.allCases {
            XCTAssertEqual(Folder.Kind(rawValue: kind.rawValue), kind,
                           "\(kind) failed raw-value round-trip")
        }
    }
}

final class ToneTests: XCTestCase {

    func testAllCasesShape() {
        // Order drives the ⌘/ cycle and the picker layout — both surfaces
        // would silently re-shuffle if a case were inserted in the middle.
        XCTAssertEqual(Tone.allCases, [.warm, .direct, .playful],
                       "tone cycle order must remain warm → direct → playful")
    }

    func testRawValuesArePersistenceContract() {
        // Persisted into rules.json (setDefaultTone action) and per-thread
        // draft cache keys; renaming a case orphans every saved rule.
        XCTAssertEqual(Tone.warm.rawValue,    "Warm")
        XCTAssertEqual(Tone.direct.rawValue,  "Direct")
        XCTAssertEqual(Tone.playful.rawValue, "Playful")
    }

    func testCycledAdvancesOneStep() {
        XCTAssertEqual(Tone.warm.cycled(),    .direct)
        XCTAssertEqual(Tone.direct.cycled(),  .playful)
    }

    func testCycledWrapsAtEnd() {
        XCTAssertEqual(Tone.playful.cycled(), .warm,
                       "the last case must wrap back to the first so the composer always lands on a valid tone")
    }

    func testCycledIsTotal() {
        // Cycling through every case must visit each tone exactly once and
        // return to the starting tone.
        var visited: [Tone] = []
        var current: Tone = .warm
        for _ in 0..<Tone.allCases.count {
            visited.append(current)
            current = current.cycled()
        }
        XCTAssertEqual(Set(visited).count, Tone.allCases.count,
                       "each tone must appear exactly once in a full cycle")
        XCTAssertEqual(current, .warm,
                       "cycling allCases.count times must return to the starting tone")
    }

    func testCodableRoundTrip() throws {
        for tone in Tone.allCases {
            let data = try JSONEncoder().encode(tone)
            let decoded = try JSONDecoder().decode(Tone.self, from: data)
            XCTAssertEqual(decoded, tone, "\(tone) failed Codable round-trip")
        }
    }

    func testIDMatchesRawValue() {
        // Identifiable conformance keys SwiftUI lists; if id drifts from
        // rawValue the picker selection silently breaks.
        for tone in Tone.allCases {
            XCTAssertEqual(tone.id, tone.rawValue)
        }
    }
}
