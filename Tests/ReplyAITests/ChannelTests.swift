import XCTest
@testable import ReplyAI

final class ChannelTests: XCTestCase {

    func testCaseIterableCount() {
        // Pins allCases against accidental omission when new channels are added.
        XCTAssertEqual(Channel.allCases.count, 6)
    }

    func testAllCasesDecodable() throws {
        for channel in Channel.allCases {
            let encoded = try JSONEncoder().encode(channel)
            let decoded = try JSONDecoder().decode(Channel.self, from: encoded)
            XCTAssertEqual(decoded, channel, "\(channel.rawValue) failed Codable round-trip")
        }
    }

    func testDisplayNameNonEmpty() {
        for channel in Channel.allCases {
            XCTAssertFalse(channel.displayName.isEmpty, "\(channel.rawValue) has empty displayName")
        }
    }

    func testIconNameNonEmpty() {
        for channel in Channel.allCases {
            XCTAssertFalse(channel.iconName.isEmpty, "\(channel.rawValue) has empty iconName")
        }
    }

    func testRawValuesArePersistenceContract() {
        // Channel raw values land in rules.json, the search index, per-channel
        // Preferences keys, and the chat-list cache. Renaming a case orphans
        // every persisted reference. Pin the strings so a typo or autocomplete
        // accident here trips the test before it ships.
        XCTAssertEqual(Channel.imessage.rawValue, "imessage")
        XCTAssertEqual(Channel.whatsapp.rawValue, "whatsapp")
        XCTAssertEqual(Channel.slack.rawValue,    "slack")
        XCTAssertEqual(Channel.teams.rawValue,    "teams")
        XCTAssertEqual(Channel.sms.rawValue,      "sms")
        XCTAssertEqual(Channel.telegram.rawValue, "telegram")
    }

    func testAllCasesShape() {
        // Order drives the per-channel filter UI and the sidebar legend; if
        // a case were inserted in the middle the rendered icons would shift
        // without anyone noticing.
        XCTAssertEqual(Channel.allCases,
                       [.imessage, .whatsapp, .slack, .teams, .sms, .telegram],
                       "channel enumeration order must remain stable for layout + persistence")
    }

    func testIDMatchesRawValue() {
        // SwiftUI ForEach keys lists by .id; if id ever drifts from rawValue
        // the per-channel filter selection silently breaks.
        for channel in Channel.allCases {
            XCTAssertEqual(channel.id, channel.rawValue)
        }
    }

    func testLabelAndDisplayNameMatch() {
        // displayName is documented as a UI alias for label — pin them so a
        // future tweak to one doesn't silently leave the other stale.
        for channel in Channel.allCases {
            XCTAssertEqual(channel.displayName, channel.label,
                           "\(channel.rawValue): displayName must mirror label")
        }
    }

    func testLabelLiteralsArePinned() {
        // Labels appear verbatim in onboarding ("Connect WhatsApp"),
        // Settings → Channels rows, and the per-channel filter UI.
        // A spell-correction edit (e.g. "iMessage" → "iMessages") would
        // silently rewrite three surfaces. Pin literally so the diff
        // surfaces in code review.
        XCTAssertEqual(Channel.imessage.label, "iMessage")
        XCTAssertEqual(Channel.whatsapp.label, "WhatsApp")
        XCTAssertEqual(Channel.slack.label,    "Slack")
        XCTAssertEqual(Channel.teams.label,    "Teams")
        XCTAssertEqual(Channel.sms.label,      "SMS")
        XCTAssertEqual(Channel.telegram.label, "Telegram")
    }

    func testIconNameLiteralsArePinned() {
        // SF Symbol names are runtime-resolved strings — a typo prints
        // a placeholder square in production but compiles silently. Pin
        // the exact symbol per channel so a refactor that swaps icons
        // shows up as a code-review diff, not a visual regression.
        XCTAssertEqual(Channel.imessage.iconName, "message.fill")
        XCTAssertEqual(Channel.whatsapp.iconName, "phone.bubble.fill")
        XCTAssertEqual(Channel.slack.iconName,    "number.square.fill")
        XCTAssertEqual(Channel.teams.iconName,    "person.3.fill")
        XCTAssertEqual(Channel.sms.iconName,      "bubble.left.fill")
        XCTAssertEqual(Channel.telegram.iconName, "paperplane.fill")
    }

    func testIconNamesAreUnique() {
        // Two channels sharing an SF Symbol makes the channel indicator
        // ambiguous in the inbox sidebar. Distinct names, distinct icons.
        let names = Channel.allCases.map(\.iconName)
        XCTAssertEqual(Set(names).count, names.count,
                       "channel SF Symbols must be unique; got duplicates: \(names)")
    }

    func testDotColorMatchesThemeChannelToken() {
        // dotColor wires the channel into the Theme palette. If a future
        // refactor swaps a channel's dotColor to a different token (or
        // worse, a literal Color), the channel-agnostic UX direction
        // breaks: per-channel theming would no longer derive from a
        // single source of truth.
        XCTAssertEqual(
            String(describing: Channel.imessage.dotColor),
            String(describing: Theme.Color.channelIMessage)
        )
        XCTAssertEqual(
            String(describing: Channel.whatsapp.dotColor),
            String(describing: Theme.Color.channelWhatsApp)
        )
        XCTAssertEqual(
            String(describing: Channel.slack.dotColor),
            String(describing: Theme.Color.channelSlack)
        )
        XCTAssertEqual(
            String(describing: Channel.teams.dotColor),
            String(describing: Theme.Color.channelTeams)
        )
        XCTAssertEqual(
            String(describing: Channel.sms.dotColor),
            String(describing: Theme.Color.channelSMS)
        )
        XCTAssertEqual(
            String(describing: Channel.telegram.dotColor),
            String(describing: Theme.Color.channelTelegram)
        )
    }

    func testDotColorsAreDistinctAcrossChannels() {
        // Sidebar channel dots and the per-channel filter pills depend on
        // visually distinguishing channels at a glance. Two channels sharing
        // the same Theme color makes the inbox ambiguous — a Slack thread
        // and a Teams thread lit by the same dot is a UX regression that
        // would silently slip past the per-token mapping test above.
        let descriptors = Channel.allCases.map { String(describing: $0.dotColor) }
        XCTAssertEqual(
            Set(descriptors).count, descriptors.count,
            "channel dotColor must be unique per channel; got duplicates in \(descriptors)"
        )
    }

    func testDisplayNameMatchesLabelForEveryCase() {
        // displayName is the public alias UI code reaches for; label is the
        // legacy name. Keeping them aligned is the one-line invariant that
        // prevents drift if a future refactor edits one without the other.
        for channel in Channel.allCases {
            XCTAssertEqual(channel.displayName, channel.label,
                "displayName must equal label for \(channel)")
        }
    }

    func testInitFromUnknownRawValueReturnsNil() {
        // Defensive: rules.json on disk could carry a stale channel string
        // after a downgrade, and Codable falls back to this initializer.
        // It must reject unknown values cleanly so the rule is skipped
        // rather than crashing decode.
        XCTAssertNil(Channel(rawValue: ""))
        XCTAssertNil(Channel(rawValue: "iMessage"),  "case-sensitive: rawValues are lowercase")
        XCTAssertNil(Channel(rawValue: "discord"),   "channels not in the enum must not decode")
        XCTAssertNil(Channel(rawValue: "imessage "), "trailing whitespace must not decode")
    }
}

// MARK: - ChannelError.errorDescription

/// Pins the user-facing copy on every ChannelError case. These strings appear
/// in toasts and banners; if a case ever returns nil we silently ship a blank
/// message ("Sent" / "Error" with no detail). The catch-all `for case` loop
/// also fails compilation if a new case is added without being tested here.
final class ChannelErrorDescriptionTests: XCTestCase {

    func testPermissionDeniedSurfacesProvidedHint() {
        let err: ChannelError = .permissionDenied(hint: "Grant Full Disk Access")
        XCTAssertEqual(err.errorDescription, "Grant Full Disk Access",
                       "permissionDenied must surface the caller-provided hint verbatim")
    }

    func testAuthorizationDeniedHasActionableCopy() {
        let err: ChannelError = .authorizationDenied
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Settings"),
                      "authorizationDenied copy should point the user at Settings")
        XCTAssertFalse(desc.isEmpty)
    }

    func testUnavailablePassesMessageThrough() {
        let err: ChannelError = .unavailable("Slack workspace temporarily offline")
        XCTAssertEqual(err.errorDescription, "Slack workspace temporarily offline")
    }

    func testQueryPassesMessageThrough() {
        let err: ChannelError = .query("malformed FTS5 token")
        XCTAssertEqual(err.errorDescription, "malformed FTS5 token")
    }

    func testDatabaseErrorSurfacesMessageNotCode() {
        // The numeric code is preserved on the value for callers that want to
        // distinguish SQLITE_BUSY from auth failures, but the user-facing
        // string is the message — the code is debug surface.
        let err: ChannelError = .databaseError(code: 5, message: "database is locked")
        XCTAssertEqual(err.errorDescription, "database is locked")
    }

    func testDatabaseCorruptedHasRecoveryHint() {
        let desc = ChannelError.databaseCorrupted.errorDescription ?? ""
        XCTAssertTrue(desc.contains("iCloud"),
                      "databaseCorrupted copy should mention iCloud (the recovery path)")
        XCTAssertFalse(desc.isEmpty)
    }

    func testNetworkErrorPassesMessageThrough() {
        let err: ChannelError = .networkError("HTTP 503 Service Unavailable")
        XCTAssertEqual(err.errorDescription, "HTTP 503 Service Unavailable")
    }
}

// MARK: - ChannelService default extension overloads

/// Minimal stub that records its received `limit` so the convenience overloads
/// can be verified without standing up a real channel. Overrides exactly one of
/// the three protocol methods; the others fall through to the protocol
/// extension defaults.
private actor RecordingChannel: ChannelService {
    var lastRecentThreadsLimit: Int?
    var lastMessagesLimit: Int?

    func recentThreads(limit: Int) async throws -> [MessageThread] {
        lastRecentThreadsLimit = limit
        return []
    }

    func messages(forThreadID id: String, limit: Int) async throws -> [Message] {
        lastMessagesLimit = limit
        return []
    }
}

final class ChannelServiceDefaultsTests: XCTestCase {

    func testRecentThreadsDefaultLimitIsFifty() async throws {
        let ch = RecordingChannel()
        _ = try await ch.recentThreads()
        let captured = await ch.lastRecentThreadsLimit
        XCTAssertEqual(captured, 50,
                       "the no-arg recentThreads convenience must request the documented page size of 50")
    }

    func testMessagesForThreadDefaultLimitIsTwenty() async throws {
        let ch = RecordingChannel()
        _ = try await ch.messages(forThreadID: "t-1")
        let captured = await ch.lastMessagesLimit
        XCTAssertEqual(captured, 20,
                       "the no-limit messages overload must request the documented per-thread cap of 20")
    }

    func testNewIncomingMessagesDefaultReturnsEmpty() async throws {
        // RecordingChannel doesn't override newIncomingMessages, so the call
        // resolves to the protocol-extension default — which exists so older
        // mocks/stubs don't have to implement the incremental fetch until they
        // care about rule actions.
        let ch = RecordingChannel()
        let result = try await ch.newIncomingMessages(forThreadID: "t-1", sinceRowID: 0)
        XCTAssertEqual(result.count, 0,
                       "default newIncomingMessages must return [] until the channel chooses to override")
    }
}
