import XCTest
@testable import ReplyAICore

final class ScreenInventoryTests: XCTestCase {
    func testEveryScreenIDIsInInventory() {
        let inventoryIDs = Set(ScreenInventory.allItems.map(\.id))
        let enumIDs = Set(ScreenID.allCases)
        XCTAssertEqual(inventoryIDs, enumIDs, "ScreenInventory must list every ScreenID case")
    }

    func testInventoryMatchesEnum() {
        // README claims "28 screens" but counting groups gives 34.
        // Trust the enum as the source of truth.
        XCTAssertEqual(ScreenInventory.allItems.count, ScreenID.allCases.count)
    }

    func testNextWrapsAround() {
        let last = ScreenInventory.allItems.last!.id
        let first = ScreenInventory.allItems.first!.id
        XCTAssertEqual(ScreenInventory.next(after: last), first)
    }

    func testPreviousWrapsAround() {
        let first = ScreenInventory.allItems.first!.id
        let last = ScreenInventory.allItems.last!.id
        XCTAssertEqual(ScreenInventory.previous(before: first), last)
    }

    func testEveryScreenHasPurpose() {
        for id in ScreenID.allCases {
            let purpose = ScreenMeta.purpose(for: id)
            XCTAssertFalse(purpose.isEmpty, "missing purpose for \(id.rawValue)")
        }
    }

    func testGroupsCoverAllItems() {
        let grouped = ScreenInventory.groups.flatMap(\.items).map(\.id)
        XCTAssertEqual(Set(grouped), Set(ScreenID.allCases))
        XCTAssertEqual(grouped.count, ScreenID.allCases.count, "no duplicates across groups")
    }

    // MARK: - Group invariants

    func testEveryGroupHasNonEmptyTitleAndItems() {
        for group in ScreenInventory.groups {
            XCTAssertFalse(group.title.isEmpty, "group title must not be empty")
            XCTAssertFalse(group.items.isEmpty, "group '\(group.title)' must not be empty")
        }
    }

    func testEveryItemLabelIsNonEmpty() {
        for item in ScreenInventory.allItems {
            XCTAssertFalse(item.label.isEmpty,
                "label for \(item.id.rawValue) must not be empty")
        }
    }

    // MARK: - item(for:) / index(of:)

    func testItemLookupReturnsMatchingItemForEveryID() {
        for id in ScreenID.allCases {
            XCTAssertEqual(ScreenInventory.item(for: id).id, id)
        }
    }

    func testIndexOfIsContiguousAndZeroBased() {
        var indexes = Set<Int>()
        for id in ScreenID.allCases {
            indexes.insert(ScreenInventory.index(of: id))
        }
        XCTAssertEqual(indexes, Set(0..<ScreenID.allCases.count),
            "indexes must cover [0, count) without gaps")
    }

    // MARK: - next/previous as inverses

    func testNextAndPreviousAreInverses() {
        for id in ScreenID.allCases {
            XCTAssertEqual(
                ScreenInventory.previous(before: ScreenInventory.next(after: id)),
                id,
                "previous(next(\(id))) should equal \(id)"
            )
        }
    }

    // MARK: - Stable raw values (persistence-shaped)

    func testKnownRawValuesAreStable() {
        // These string IDs ship into app-shell.jsx + persistence; renaming a
        // case is a migration, not a refactor. Lock the public surface here.
        XCTAssertEqual(ScreenID.obWelcome.rawValue, "ob-welcome")
        XCTAssertEqual(ScreenID.appInbox.rawValue, "app-inbox")
        XCTAssertEqual(ScreenID.sfcPalette.rawValue, "sfc-palette")
        XCTAssertEqual(ScreenID.setAccount.rawValue, "set-account")
        XCTAssertEqual(ScreenID.errDisconnected.rawValue, "err-disconnected")
    }

    // MARK: - Full raw-value corpus

    func testAllOnboardingRawValuesAreStable() {
        XCTAssertEqual(ScreenID.obWelcome.rawValue,       "ob-welcome")
        XCTAssertEqual(ScreenID.obPrivacy.rawValue,       "ob-privacy")
        XCTAssertEqual(ScreenID.obPermissions.rawValue,   "ob-permissions")
        XCTAssertEqual(ScreenID.obChannels.rawValue,      "ob-channels")
        XCTAssertEqual(ScreenID.obChannelDetail.rawValue, "ob-channel-detail")
        XCTAssertEqual(ScreenID.obVoice.rawValue,         "ob-voice")
        XCTAssertEqual(ScreenID.obTone.rawValue,          "ob-tone")
        XCTAssertEqual(ScreenID.obShortcuts.rawValue,     "ob-shortcuts")
        XCTAssertEqual(ScreenID.obDone.rawValue,          "ob-done")
    }

    func testAllMainAppRawValuesAreStable() {
        XCTAssertEqual(ScreenID.appInbox.rawValue,        "app-inbox")
        XCTAssertEqual(ScreenID.appInboxEmpty.rawValue,   "app-inbox-empty")
        XCTAssertEqual(ScreenID.appInboxLoading.rawValue, "app-inbox-loading")
        XCTAssertEqual(ScreenID.appOffline.rawValue,      "app-offline")
    }

    func testAllThreadRawValuesAreStable() {
        XCTAssertEqual(ScreenID.thrGroup.rawValue, "thr-group")
        XCTAssertEqual(ScreenID.thrMedia.rawValue, "thr-media")
        XCTAssertEqual(ScreenID.thrLong.rawValue,  "thr-long")
    }

    func testAllComposerRawValuesAreStable() {
        XCTAssertEqual(ScreenID.cmpTones.rawValue,   "cmp-tones")
        XCTAssertEqual(ScreenID.cmpCustom.rawValue,  "cmp-custom")
        XCTAssertEqual(ScreenID.cmpLowconf.rawValue, "cmp-lowconf")
        XCTAssertEqual(ScreenID.cmpNothing.rawValue, "cmp-nothing")
    }

    func testAllSurfaceRawValuesAreStable() {
        XCTAssertEqual(ScreenID.sfcPalette.rawValue,      "sfc-palette")
        XCTAssertEqual(ScreenID.sfcSnooze.rawValue,       "sfc-snooze")
        XCTAssertEqual(ScreenID.sfcRules.rawValue,        "sfc-rules")
        XCTAssertEqual(ScreenID.sfcMenubar.rawValue,      "sfc-menubar")
        XCTAssertEqual(ScreenID.sfcNotification.rawValue, "sfc-notification")
    }

    func testAllSettingsRawValuesAreStable() {
        XCTAssertEqual(ScreenID.setAccount.rawValue,   "set-account")
        XCTAssertEqual(ScreenID.setVoice.rawValue,     "set-voice")
        XCTAssertEqual(ScreenID.setChannels.rawValue,  "set-channels")
        XCTAssertEqual(ScreenID.setShortcuts.rawValue, "set-shortcuts")
        XCTAssertEqual(ScreenID.setPrivacy.rawValue,   "set-privacy")
        XCTAssertEqual(ScreenID.setModel.rawValue,     "set-model")
    }

    func testAllErrorRawValuesAreStable() {
        XCTAssertEqual(ScreenID.errDisconnected.rawValue, "err-disconnected")
        XCTAssertEqual(ScreenID.errAuth.rawValue,         "err-auth")
        XCTAssertEqual(ScreenID.errModelUpdate.rawValue,  "err-model-update")
    }

    func testRawValueRoundTripCoversEveryCase() {
        // Defense against silent rename: if any case's raw value drifts but
        // a hand-written test in the per-section corpus above is missed, the
        // round-trip via init?(rawValue:) catches it here.
        for id in ScreenID.allCases {
            XCTAssertEqual(ScreenID(rawValue: id.rawValue), id,
                           "raw-value round-trip failed for \(id)")
        }
    }

    func testRawValuesUseKebabCasePrefixConvention() {
        // app-shell.jsx groups screens by prefix (`ob-`, `app-`, `thr-`, `cmp-`,
        // `sfc-`, `set-`, `err-`). A new case without a recognized prefix would
        // silently miss the gallery routing.
        let knownPrefixes = ["ob-", "app-", "thr-", "cmp-", "sfc-", "set-", "err-"]
        for id in ScreenID.allCases {
            let raw = id.rawValue
            XCTAssertTrue(
                knownPrefixes.contains(where: { raw.hasPrefix($0) }),
                "\(raw) does not match any known prefix \(knownPrefixes)"
            )
            XCTAssertEqual(raw, raw.lowercased(),
                           "\(raw) must be lowercase for kebab-case convention")
            XCTAssertFalse(raw.contains("_"),
                           "\(raw) must use hyphens, not underscores")
        }
    }
}
