import XCTest
import SwiftUI
@testable import ReplyAICore

/// Test-local alias — `SettingsShell` is generic over `Content: View`, so the
/// nested `Tab` enum can't be referenced as `SettingsShell.Tab` without
/// pinning a concrete content type. `EmptyView` keeps the alias inert.
private typealias SettingsTab = SettingsShell<EmptyView>.Tab

/// Pins `SettingsShell.Tab` raw values + labels. Both render verbatim into
/// the Settings sidebar nav (raw value as the Identifiable.id, label as the
/// visible row text), and Tab cases line up 1:1 with the six Settings
/// screens (set-account / set-voice / set-channels / set-shortcuts /
/// set-privacy / set-model — see ScreenInventoryTests). A silent rename
/// here would either drift the nav copy or break any future deep-link that
/// references a tab by its raw value.
final class SettingsShellTabTests: XCTestCase {

    func testAllCasesShape() {
        // Order drives sidebar row layout — Account is intentionally first
        // because it's the most-trafficked tab, then voice/channels for
        // setup, then shortcuts/privacy/model for power-user surfaces.
        XCTAssertEqual(
            SettingsTab.allCases,
            [.account, .voice, .channels, .shortcuts, .privacy, .model],
            "Settings sidebar order must remain account → voice → channels → shortcuts → privacy → model"
        )
    }

    func testRawValuesAreStable() {
        // Tab raw values double as Identifiable.id; renaming a case orphans
        // any future deep-link or persisted "lastSettingsTab" preference.
        XCTAssertEqual(SettingsTab.account.rawValue,   "account")
        XCTAssertEqual(SettingsTab.voice.rawValue,     "voice")
        XCTAssertEqual(SettingsTab.channels.rawValue,  "channels")
        XCTAssertEqual(SettingsTab.shortcuts.rawValue, "shortcuts")
        XCTAssertEqual(SettingsTab.privacy.rawValue,   "privacy")
        XCTAssertEqual(SettingsTab.model.rawValue,     "model")
    }

    func testLabelsAreStable() {
        // Visible sidebar copy. The "Voice profile" label intentionally
        // diverges from the raw value for readability — pin the divergence
        // so a "make it match" cleanup doesn't quietly retitle nav rows.
        XCTAssertEqual(SettingsTab.account.label,   "Account")
        XCTAssertEqual(SettingsTab.voice.label,     "Voice profile")
        XCTAssertEqual(SettingsTab.channels.label,  "Channels")
        XCTAssertEqual(SettingsTab.shortcuts.label, "Shortcuts")
        XCTAssertEqual(SettingsTab.privacy.label,   "Privacy")
        XCTAssertEqual(SettingsTab.model.label,     "Model")
    }

    func testIDMatchesRawValue() {
        // Identifiable.id must mirror rawValue or the SwiftUI selection
        // binding silently breaks (sidebar selection → wrong content).
        for tab in SettingsTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue, "id must mirror rawValue for \(tab)")
        }
    }

    func testRawRoundTrip() {
        for tab in SettingsTab.allCases {
            XCTAssertEqual(SettingsTab(rawValue: tab.rawValue), tab,
                           "round-trip failed for \(tab)")
        }
    }

    func testEveryLabelIsNonEmpty() {
        // Defense in depth: an empty label would render a blank sidebar row.
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.label.isEmpty, "label is empty for \(tab)")
        }
    }

    func testTabsAlignWithSetScreenIDs() {
        // The Settings sidebar sits one level above the per-screen content
        // (set-account, set-voice, …). Tab raw values should be the suffix
        // of their corresponding ScreenID raw value — drift here means the
        // nav row and the content screen no longer line up.
        let pairs: [(SettingsTab, ScreenID)] = [
            (.account,   .setAccount),
            (.voice,     .setVoice),
            (.channels,  .setChannels),
            (.shortcuts, .setShortcuts),
            (.privacy,   .setPrivacy),
            (.model,     .setModel),
        ]
        for (tab, screen) in pairs {
            XCTAssertTrue(
                screen.rawValue.hasSuffix("-\(tab.rawValue)"),
                "ScreenID '\(screen.rawValue)' must end with '-\(tab.rawValue)' to match SettingsShell.Tab.\(tab)"
            )
        }
    }

    func testRawValuesAreUniqueAcrossTabs() {
        // Identifiable.id collisions silently break the SwiftUI selection
        // binding — two rows with the same id make ForEach swap them
        // unpredictably on selection. Defense against a future copy-paste
        // adding a duplicate raw value.
        let raws = SettingsTab.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count,
            "tab rawValues must be unique; got duplicates in \(raws)")
    }

    func testLabelsAreUniqueAcrossTabs() {
        // Two sidebar rows with identical labels are an immediate UX bug —
        // the user can't distinguish destinations. Lock the contract here
        // so a future "split this section into two" refactor must give
        // each new section its own label.
        let labels = SettingsTab.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count,
            "tab labels must be unique; got duplicates in \(labels)")
    }

    func testInitFromUnknownRawValueReturnsNil() {
        // Defensive: a future "lastSettingsTab" pref restoring from disk
        // could carry a stale value after a tab rename or removal. The
        // initializer must reject unknown values cleanly so the caller
        // can fall back to .account rather than crash decode.
        XCTAssertNil(SettingsTab(rawValue: ""))
        XCTAssertNil(SettingsTab(rawValue: "Account"),
            "raw values are lowercase — case-sensitive decode")
        XCTAssertNil(SettingsTab(rawValue: "voice "),
            "trailing whitespace must not decode")
        XCTAssertNil(SettingsTab(rawValue: "deprecated-tab"))
    }

    func testAllCasesCountMatchesSetScreenIDCount() {
        // The SettingsShell tab list and the Settings ScreenID prefix list
        // must remain in lockstep. If a tab is added without the matching
        // ScreenID (or vice-versa) the navigation surface is half-wired
        // and the alignment test above can't catch the missing case.
        let setScreens = ScreenID.allCases.filter { $0.rawValue.hasPrefix("set-") }
        XCTAssertEqual(SettingsTab.allCases.count, setScreens.count,
            "tab count (\(SettingsTab.allCases.count)) must equal set- ScreenID count (\(setScreens.count))")
    }
}
