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

    // MARK: - Helpers

    private func makeURL(payload: String) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "replyai"
        comps.host = "import-messages"
        comps.queryItems = [URLQueryItem(name: "data", value: payload)]
        return try XCTUnwrap(comps.url)
    }
}
