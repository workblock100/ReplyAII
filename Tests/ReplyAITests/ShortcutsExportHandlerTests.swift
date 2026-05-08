import XCTest
@testable import ReplyAI

/// REP-262 — pivot-aligned alternative iMessage source via Shortcuts.app
/// URL callbacks. Tests cover the parser-only happy path, the structural
/// failure modes, and the empty-messages edge case so a Shortcut that
/// returns zero messages still produces a valid thread shell instead of
/// throwing.
final class ShortcutsExportHandlerTests: XCTestCase {

    // MARK: - Happy path

    func testValidJSONPayloadParsesThreads() throws {
        let json = """
        [
          {
            "id": "iMessage;-;+15555550100",
            "displayName": "Maya Lee",
            "preview": "see you at 3?",
            "channel": "imessage",
            "messages": [
              { "from": "them", "text": "see you at 3?", "time": "2:14 PM" },
              { "from": "me",   "text": "yep",          "time": "2:15 PM" }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 1)
        let export = exports[0]
        XCTAssertEqual(export.thread.id, "iMessage;-;+15555550100")
        XCTAssertEqual(export.thread.name, "Maya Lee")
        XCTAssertEqual(export.thread.channel, .imessage)
        XCTAssertEqual(export.thread.preview, "see you at 3?")
        XCTAssertEqual(export.thread.chatGUID, "iMessage;-;+15555550100")
        XCTAssertEqual(export.messages.count, 2)
        XCTAssertEqual(export.messages[0].from, .them)
        XCTAssertEqual(export.messages[0].text, "see you at 3?")
        XCTAssertEqual(export.messages[1].from, .me)
        XCTAssertEqual(export.messages[1].text, "yep")
    }

    func testValidJSONPayloadParsesMultipleThreads() throws {
        let json = """
        [
          { "id": "a", "displayName": "Alice", "preview": "x", "channel": "imessage", "messages": [] },
          { "id": "b", "displayName": "Bob",   "preview": "y", "channel": "imessage", "messages": [] }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 2)
        XCTAssertEqual(exports[0].thread.name, "Alice")
        XCTAssertEqual(exports[1].thread.name, "Bob")
    }

    // MARK: - Failure modes

    func testMalformedJSONThrowsMalformedPayload() throws {
        let url = try makeURL(payload: "{not valid json")

        XCTAssertThrowsError(try ShortcutsExportHandler.parse(url: url)) { err in
            XCTAssertEqual(err as? ShortcutsExportError, .malformedPayload)
        }
    }

    func testMissingDataParamThrows() throws {
        let url = URL(string: "replyai://import-messages")!

        XCTAssertThrowsError(try ShortcutsExportHandler.parse(url: url)) { err in
            XCTAssertEqual(err as? ShortcutsExportError, .malformedPayload)
        }
    }

    func testEmptyDataParamThrows() throws {
        let url = URL(string: "replyai://import-messages?data=")!

        XCTAssertThrowsError(try ShortcutsExportHandler.parse(url: url)) { err in
            XCTAssertEqual(err as? ShortcutsExportError, .malformedPayload)
        }
    }

    func testMissingRequiredFieldThrows() throws {
        // No `id` field — Codable decoding fails, parser maps to .malformedPayload.
        let json = """
        [ { "displayName": "Maya", "messages": [] } ]
        """
        let url = try makeURL(payload: json)

        XCTAssertThrowsError(try ShortcutsExportHandler.parse(url: url)) { err in
            XCTAssertEqual(err as? ShortcutsExportError, .malformedPayload)
        }
    }

    // MARK: - Edge cases

    func testEmptyMessagesArrayProducesThreadWithNoMessages() throws {
        let json = """
        [
          {
            "id": "iMessage;-;+15555550101",
            "displayName": "Empty Inbox",
            "preview": "",
            "channel": "imessage",
            "messages": []
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 1)
        XCTAssertTrue(exports[0].messages.isEmpty,
                      "an empty messages array must produce a thread with zero messages, not an error")
        XCTAssertEqual(exports[0].thread.name, "Empty Inbox")
    }

    func testMissingMessagesFieldDefaultsToEmpty() throws {
        // Field absent entirely — should still parse as thread with no messages.
        let json = """
        [ { "id": "x", "displayName": "Solo", "channel": "imessage" } ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 1)
        XCTAssertTrue(exports[0].messages.isEmpty)
    }

    func testUnknownChannelFallsBackToIMessage() throws {
        // Defensive default so a Shortcut that mis-types the channel still
        // produces a usable thread instead of erroring out the whole batch.
        let json = """
        [ { "id": "x", "displayName": "Maya", "channel": "carrier-pigeon", "messages": [] } ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.channel, .imessage)
    }

    func testChannelRawValueIsLowercased() throws {
        // The Shortcut author may type "iMessage" or "IMESSAGE"; the parser
        // lowercases before mapping so casing differences don't cause every
        // such payload to fall back to the default.
        let json = #"[ { "id": "x", "displayName": "Maya", "channel": "IMESSAGE", "messages": [] } ]"#
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.channel, .imessage)
    }

    func testFromFieldIsCaseInsensitive() throws {
        // Mirrors the channel-field tolerance: "ME" or "Me" should resolve to
        // .me, not silently fall back to .them. Without this guard a
        // sender-side message authored on the iPhone would render as if it
        // came from the contact.
        let json = """
        [
          {
            "id": "x", "displayName": "Maya", "channel": "imessage",
            "messages": [
              { "from": "ME",   "text": "lowercase me" },
              { "from": "Me",   "text": "title-case me" },
              { "from": "them", "text": "lowercase them" }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].messages[0].from, .me)
        XCTAssertEqual(exports[0].messages[1].from, .me)
        XCTAssertEqual(exports[0].messages[2].from, .them)
    }

    func testThreadTimeFallsBackToLastMessageTime() throws {
        // Shortcuts' `messages` array has a `time` per row; the parser uses the
        // last row's time as the thread.time so the inbox row sorts correctly
        // even when the top-level payload omits a thread-level time field.
        let json = """
        [
          {
            "id": "x", "displayName": "Maya", "channel": "imessage",
            "messages": [
              { "from": "them", "text": "earlier", "time": "1:01 PM" },
              { "from": "me",   "text": "latest",  "time": "3:42 PM" }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.time, "3:42 PM")
    }

    func testAvatarUsesFirstCharOfDisplayName() throws {
        // Avatar initial is the first grapheme — pinned so a refactor that
        // accidentally drops the prefix(1) call (e.g. switching to the full
        // display name as avatar) doesn't ship without a test catching it.
        let json = #"[ { "id": "x", "displayName": "Maya Lee", "channel": "imessage", "messages": [] } ]"#
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.avatar, "M")
    }

    /// Pin two intentional divergences vs `IMessageChannel.avatarInitial(for:)`.
    /// The Shortcut export uses raw `String(displayName.prefix(1))`:
    ///
    /// 1. **No uppercasing.** A `displayName: "maya lee"` produces avatar
    ///    `"m"` (lowercase). `IMessageChannel.avatarInitial` would
    ///    uppercase it to `"M"`. Shortcut payloads are user-authored, so
    ///    the parser preserves the user's input casing without inferring
    ///    formatting intent.
    /// 2. **No phone-glyph fallback.** A `displayName: "+15551234567"`
    ///    produces avatar `"+"`. `IMessageChannel.avatarInitial` would
    ///    return the telephone glyph `"☎"` from
    ///    `IMessageChannel.phoneAvatarGlyph`.
    ///
    /// Drift class: a well-meaning audit that "aligns avatar logic across
    /// channels" by routing this path through `IMessageChannel.avatarInitial`
    /// would silently change every Shortcut-imported thread's sidebar
    /// glyph — a UX shift no test would otherwise catch. The empty-
    /// displayName divergence is already pinned by
    /// `testAvatarFromEmptyDisplayNameIsEmpty`; this fills the
    /// remaining two cases so the full divergence surface is locked.
    func testAvatarDivergesFromIMessageChannelAvatarInitialOnCaseAndPhone() throws {
        // Lowercase displayName: prefix(1) preserves the lowercase byte;
        // IMessageChannel.avatarInitial would uppercase to "M".
        let lowercaseJSON = #"[ { "id": "x", "displayName": "maya lee", "channel": "imessage", "messages": [] } ]"#
        let lowercaseURL = try makeURL(payload: lowercaseJSON)
        let lowercaseExport = try ShortcutsExportHandler.parse(url: lowercaseURL)
        XCTAssertEqual(lowercaseExport[0].thread.avatar, "m",
            "lowercase displayName must produce lowercase avatar — drift toward routing through IMessageChannel.avatarInitial would silently uppercase to 'M'")
        // Sanity: confirm IMessageChannel.avatarInitial would have produced
        // the divergent value, so the test fails meaningfully if either
        // side ever harmonizes.
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "maya lee"), "M",
            "control: IMessageChannel.avatarInitial uppercases — divergence sanity")

        // Phone-handle displayName: prefix(1) returns "+"; avatarInitial
        // would return the telephone glyph.
        let phoneJSON = #"[ { "id": "y", "displayName": "+15551234567", "channel": "imessage", "messages": [] } ]"#
        let phoneURL = try makeURL(payload: phoneJSON)
        let phoneExport = try ShortcutsExportHandler.parse(url: phoneURL)
        XCTAssertEqual(phoneExport[0].thread.avatar, "+",
            "phone-handle displayName must produce '+' avatar — drift toward routing through IMessageChannel.avatarInitial would replace it with the telephone glyph '☎' on every Shortcut-imported phone thread")
        XCTAssertEqual(IMessageChannel.avatarInitial(for: "+15551234567"),
                       IMessageChannel.phoneAvatarGlyph,
            "control: IMessageChannel.avatarInitial maps '+' prefix to the phone glyph — divergence sanity")
    }

    /// Pin the current behavior: empty `displayName` produces an empty
    /// avatar (`String(displayName.prefix(1))` yields ""), unlike
    /// `IMessageChannel.avatarInitial(for:)` which falls back to "?".
    /// Pinned so an audit-pass that aligns Shortcuts with the iMessage
    /// fallback is a deliberate change visible here, not a quiet drift.
    /// Note: an empty displayName isn't malformed per the schema (only
    /// `id` and `displayName` keys must be present; their values aren't
    /// validated for non-emptiness), so this case can realistically
    /// reach `toExport()`.
    func testAvatarFromEmptyDisplayNameIsEmpty() throws {
        let json = #"[ { "id": "x", "displayName": "", "channel": "imessage", "messages": [] } ]"#
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.avatar, "",
            "empty displayName produces empty avatar — no '?' fallback like IMessageChannel.avatarInitial")
        XCTAssertEqual(exports[0].thread.name, "",
            "thread.name is the raw displayName, also empty here")
    }

    /// Both `preview` AND `messages` missing — the parser cascades through
    /// `preview ?? messages?.last?.text ?? ""` and lands on the empty string
    /// rather than throwing. Justification: the JSON itself is structurally
    /// valid (no required field is absent) and the inbox can render an empty
    /// preview row, so failing the entire URL would be more surprising than
    /// passing an empty thread through. Pin the empty-preview path so a
    /// well-meaning future change ("threads without previews are useless,
    /// throw instead") doesn't drop user-triggered exports on the floor.
    func testEmptyPayloadWithNoPreviewAndNoMessagesProducesEmptyPreview() throws {
        let json = """
        [{ "id": "x", "displayName": "Maya", "channel": "imessage" }]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports[0].thread.preview, "",
                       "missing preview AND missing messages must cascade to empty string, not throw")
        XCTAssertEqual(exports[0].thread.time, "",
                       "thread.time must also fall through to empty when no messages are available to source it from")
        XCTAssertTrue(exports[0].messages.isEmpty)
    }

    /// `from` field that isn't "me" (any case) maps to `.them`. Specifically pin
    /// "system" / arbitrary strings / empty string — without this, a future
    /// schema change adding a "system" sender would silently land in `.them`
    /// and look like a contact bubble. The current parser's "anything-not-me
    /// is them" semantics are intentional (Shortcuts is single-author per
    /// pull) and we want it to surface in CI if it changes.
    func testFromFieldUnrecognizedValuesMapToThem() throws {
        let json = """
        [
          { "id": "x", "displayName": "Maya", "channel": "imessage",
            "messages": [
              { "from": "system",  "text": "auto-reply" },
              { "from": "",        "text": "blank from" },
              { "from": "contact", "text": "labeled contact" }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].messages.count, 3)
        for (i, m) in exports[0].messages.enumerated() {
            XCTAssertEqual(m.from, .them,
                           "unrecognized `from` value at index \(i) must default to .them, not silently appear as the user")
        }
    }

    func testPreviewFallsBackToLastMessageWhenMissing() throws {
        let json = """
        [
          {
            "id": "x",
            "displayName": "Maya",
            "channel": "imessage",
            "messages": [
              { "from": "them", "text": "first" },
              { "from": "me",   "text": "last"  }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.preview, "last",
                       "preview must fall back to the most recent message when the JSON omits it")
    }

    // MARK: - Empty-string passthrough (Some("") regressions — gotcha #243-style)

    /// `preview` set to the empty string (NOT missing) wins over the message
    /// fallback: the cascade is `preview ?? messages?.last?.text ?? ""`, and
    /// `Some("")` is non-nil, so `??` doesn't fall through. Pinned because the
    /// AGENTS.md "present-but-empty strings are a recurring bug class" gotcha
    /// covers exactly this shape — a future "treat blank previews as missing"
    /// refactor should surface as a deliberate change here, not silent drift.
    func testExplicitEmptyPreviewWinsOverMessageFallback() throws {
        let json = """
        [
          { "id": "x", "displayName": "Maya", "channel": "imessage",
            "preview": "",
            "messages": [
              { "from": "me", "text": "hi", "time": "1:00 PM" }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.preview, "",
            "Some(\"\") on the preview field is non-nil, so ?? does not fall through to the last message text")
    }

    /// `id` set to the empty string is structurally valid JSON (the schema
    /// only requires the keys to exist, not be non-empty). The parser passes
    /// it through verbatim — `MessageThread.id == ""` and `chatGUID == ""`.
    /// Pinned because downstream code should be able to assume the export is
    /// faithful to the JSON, not silently rewritten. If a future audit
    /// decides empty IDs are nonsense and should throw `.malformedPayload`,
    /// this test surfaces that as a deliberate change.
    func testEmptyIdStringPassesThroughVerbatim() throws {
        let json = #"[ { "id": "", "displayName": "Maya", "channel": "imessage", "messages": [] } ]"#
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports[0].thread.id, "")
        XCTAssertEqual(exports[0].thread.chatGUID, "",
            "chatGUID is mirrored from id, so an empty id produces an empty chatGUID — Some(\"\") again")
    }

    // MARK: - Whitespace handling

    /// `from` is matched by `dto.from.lowercased() == "me"` — exact equality,
    /// no trim. `" me "` and `"  me"` therefore both route to `.them`,
    /// because the literal comparison fails. Pinned so a future change that
    /// trims whitespace (well-meaning robustness) surfaces here rather than
    /// quietly flipping the sender on every Shortcuts payload that has stray
    /// whitespace from a user-authored shortcut.
    func testFromFieldWithLeadingTrailingWhitespaceMapsToThem() throws {
        // Use space-padded variants only — embedding literal control chars
        // (tab, newline) in JSON strings would be invalid JSON, and the
        // semantic we're pinning is "no trim happens", which spaces prove.
        let json = """
        [
          { "id": "x", "displayName": "Maya", "channel": "imessage",
            "messages": [
              { "from": " me ",   "text": "spaces around" },
              { "from": "  me",   "text": "leading spaces" },
              { "from": "me  ",   "text": "trailing spaces" }
            ]
          }
        ]
        """
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].messages.count, 3)
        for (i, m) in exports[0].messages.enumerated() {
            XCTAssertEqual(m.from, .them,
                "whitespace-padded `me` at index \(i) must NOT match the literal lowercased == \"me\" check; routing to .them is intentional, no trimming")
        }
    }

    /// Channel value with surrounding whitespace fails the
    /// `Channel(rawValue:)` lookup — `Channel.imessage` rawValue is
    /// `"imessage"` exactly. The `?? .imessage` fallback then catches it,
    /// so a whitespace-padded value still produces an iMessage thread.
    /// Pinned because the user-visible behavior (whitespace tolerated) is
    /// correct, but the *path* (rawValue miss → fallback) is fragile —
    /// switching to `.trimmingCharacters(in: .whitespaces)` upstream would
    /// make whitespace-padded "slack" produce a Slack thread instead, and
    /// that's a change that should be visible in tests.
    func testChannelValueWithSurroundingWhitespaceFallsBackToImessage() throws {
        let json = #"[ { "id": "x", "displayName": "Maya", "channel": "  slack  ", "messages": [] } ]"#
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.channel, .imessage,
            "current parser does NOT trim the channel string; `\"  slack  \"` misses the rawValue lookup and falls through to .imessage")
    }

    // MARK: - Multi-grapheme avatar

    /// Avatar uses `String(displayName.prefix(1))`, which is grapheme-aware
    /// — an emoji at the front is one `Character`, so the avatar is the
    /// full emoji rather than half a surrogate pair. Pinned because a
    /// well-meaning switch to `.unicodeScalars.prefix(1)` or to a byte-
    /// based slice would break this for any non-BMP first character.
    func testAvatarPreservesEmojiFirstGrapheme() throws {
        let json = #"[ { "id": "x", "displayName": "🦊 Fox Friend", "channel": "imessage", "messages": [] } ]"#
        let url = try makeURL(payload: json)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports[0].thread.avatar, "🦊",
            "first Character of \"🦊 Fox Friend\" is the fox emoji; prefix(1) on String returns a one-Character substring, not a half-surrogate")
    }

    // MARK: - Duplicate query parameter

    /// `URLComponents.queryItems.first(where: { $0.name == "data" })` returns
    /// the FIRST `data` parameter when more than one is present. A user
    /// mis-authoring a Shortcut to append `&data=…` twice will see the first
    /// payload imported and the second silently dropped. Pinned to make
    /// that semantic explicit — if a future change starts merging or
    /// rejecting duplicates, the new behavior should be deliberate.
    func testFirstDataQueryItemWinsWhenMultiplePresent() throws {
        let firstPayload = #"[ { "id": "first", "displayName": "First", "channel": "imessage", "messages": [] } ]"#
        let secondPayload = #"[ { "id": "second", "displayName": "Second", "channel": "imessage", "messages": [] } ]"#

        var comps = URLComponents()
        comps.scheme = "replyai"
        comps.host = "import-messages"
        comps.queryItems = [
            URLQueryItem(name: "data", value: firstPayload),
            URLQueryItem(name: "data", value: secondPayload),
        ]
        let url = try XCTUnwrap(comps.url)

        let exports = try ShortcutsExportHandler.parse(url: url)

        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports[0].thread.id, "first",
            "queryItems.first(where:) returns the first matching item; the second `data=…` is dropped")
    }

    // MARK: - Hoisted-constant pin
    //
    // The `data` query parameter name is the only contract between the
    // user-authored Shortcut and the parser. Drift is invisible to the
    // user — every export silently throws `malformedPayload` and the
    // inbox simply doesn't update. Pin freezes the literal.

    func testQueryParameterNameIsFrozen() {
        XCTAssertEqual(ShortcutsExportHandler.payloadQueryParameterName, "data",
            "drift in the wire-format query name silently fails every Shortcut export — the user sees nothing happen and gets no error to act on")
    }

    // MARK: - Default channel + outgoing marker pins (REP-hoist 2026-05-07)

    /// The default channel applied when the `channel` field is absent
    /// from the payload (or unrecognized). Drift to e.g. `.sms` would
    /// silently re-route every legacy Shortcut export through the SMS
    /// path — InboxViewModel would mis-render the chip + dot color.
    func testDefaultChannelIsImessage() {
        XCTAssertEqual(ShortcutsExportHandler.defaultChannel, .imessage,
            "defaultChannel drift silently re-routes every legacy Shortcut export through the wrong channel")
    }

    /// The outgoing-message wire-format marker. The same literal `me`
    /// is used by `PromptBuilder.Template.speakerSelf` and
    /// `SearchIndex.outgoingSenderLabel` — three modules sharing one
    /// convention. Pin both the literal AND the cross-module equality.
    func testOutgoingMarkerIsMe() {
        XCTAssertEqual(ShortcutsExportHandler.outgoingMessageMarker, "me",
            "outgoingMessageMarker drift silently flips authorship for every outgoing message in every imported thread")
    }

    func testOutgoingMarkerEqualsPromptBuilderSpeakerSelf() {
        XCTAssertEqual(ShortcutsExportHandler.outgoingMessageMarker,
                       PromptBuilder.Template.speakerSelf,
            "ShortcutsExportHandler.outgoingMessageMarker must equal PromptBuilder.Template.speakerSelf — three modules share this `me` convention")
    }

    func testOutgoingMarkerEqualsSearchIndexOutgoingSenderLabel() {
        XCTAssertEqual(ShortcutsExportHandler.outgoingMessageMarker,
                       SearchIndex.outgoingSenderLabel,
            "ShortcutsExportHandler.outgoingMessageMarker must equal SearchIndex.outgoingSenderLabel — drift desyncs imported-thread authorship from search")
    }

    /// Pin that the parsed thread's `chatGUID` is set verbatim to the
    /// payload's `id`. This is the route key `IMessageSender.chatGUID(for:)`
    /// uses to reach the send target — drift to e.g. `chatGUID: nil`
    /// or `chatGUID: "\(channel.rawValue):\(id)"` would silently break
    /// every send originating from a Shortcuts-imported thread (the
    /// sender's `chatGUID(for:)` would fall through to the synthesis
    /// path and emit a malformed `iMessage;-;<channel>:<id>` GUID that
    /// Messages.app rejects with `errOSAScriptError`). Pin both the
    /// equality and the negative case (chatGUID is non-nil).
    func testParsedThreadChatGUIDEqualsPayloadID() throws {
        let payload = """
        [{
            "id": "iMessage;-;+15555550100",
            "displayName": "Maya Lee",
            "preview": "p",
            "channel": "imessage",
            "messages": []
        }]
        """
        let url = try makeURL(payload: payload)
        let exports = try ShortcutsExportHandler.parse(url: url)
        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports[0].thread.chatGUID, "iMessage;-;+15555550100",
            "imported-thread chatGUID must equal payload `id` verbatim — IMessageSender.chatGUID(for:) routes through this; drift would break send for every Shortcuts-imported thread")
        XCTAssertEqual(exports[0].thread.id, exports[0].thread.chatGUID,
            "imported-thread id and chatGUID must be the same value — both come from payload `id` and IMessageSender's send path round-trips through chatGUID; pin so a future `chatGUID: id + suffix` refactor surfaces here")
    }

    /// Pin that the `channel` field in the wire format is INDEPENDENT
    /// of the `id` field's shape. A user-authored Shortcut could
    /// emit `id: "iMessage;-;+15..."` (iMessage-shaped GUID) but
    /// `channel: "slack"` (because the user repurposed an imessage
    /// payload for a Slack export); the parser must NOT auto-correct
    /// the channel based on the id format — the user's Shortcut owns
    /// the channel field. Drift toward "if id starts with `iMessage;`
    /// then force channel to .imessage" would silently override the
    /// Shortcut's intent for any cross-channel import.
    func testChannelFieldOverridesAnyInferenceFromIDShape() throws {
        let payload = """
        [{
            "id": "iMessage;-;+15555550100",
            "displayName": "Cross-channel",
            "preview": "p",
            "channel": "slack",
            "messages": []
        }]
        """
        let url = try makeURL(payload: payload)
        let exports = try ShortcutsExportHandler.parse(url: url)
        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports[0].thread.channel, .slack,
            "channel field must override any iMessage-shape inference from id — Shortcut authors own the channel; a future `if id.hasPrefix(\"iMessage;\")` heuristic would silently corrupt cross-channel intent")
        XCTAssertTrue(exports[0].thread.id.hasPrefix("iMessage;"),
            "control: the test relies on an iMessage-shaped id; pinning the prefix lets the assertion above be unambiguous about what's being overridden")
    }

    /// Pin the empty-string `channel` fallback. A payload with
    /// `"channel": ""` would `lowercased()` to `""`, then
    /// `Channel(rawValue: "")` is nil, so the chain falls through to
    /// `defaultChannel` (.imessage). Same shape as the
    /// "unknown-string falls to imessage" case but pins the
    /// present-but-empty leg specifically. Drift toward filtering empty
    /// before the lowercased-rawValue lookup (e.g. `channel?.isEmpty == false`)
    /// is a behavior-no-op today but pinning the present-but-empty
    /// shape catches a future refactor that accidentally treats `""`
    /// as "no field" and sends it through a different default route.
    func testEmptyChannelStringFallsBackToImessage() throws {
        let payload = """
        [{
            "id": "T1",
            "displayName": "Empty Channel",
            "preview": "p",
            "channel": "",
            "messages": []
        }]
        """
        let url = try makeURL(payload: payload)
        let exports = try ShortcutsExportHandler.parse(url: url)
        XCTAssertEqual(exports.count, 1)
        XCTAssertEqual(exports[0].thread.channel, ShortcutsExportHandler.defaultChannel,
            "present-but-empty channel string must route through defaultChannel — same as missing-field path. Drift here is invisible until a future `channel?.isEmpty == false` filter changes the fallback shape")
        XCTAssertEqual(exports[0].thread.channel, .imessage,
            "control: defaultChannel is .imessage at the time of writing; double-pinned via the constant + the literal so a defaultChannel rebrand and an empty-string filter both have to update tests")
    }

    // MARK: - Helpers

    private func makeURL(payload: String) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "replyai"
        comps.host = "import-messages"
        comps.queryItems = [URLQueryItem(name: ShortcutsExportHandler.payloadQueryParameterName, value: payload)]
        return try XCTUnwrap(comps.url)
    }
}
