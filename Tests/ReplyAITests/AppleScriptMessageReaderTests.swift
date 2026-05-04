import XCTest
@testable import ReplyAI

/// Covers the pure-parsing surface of AppleScriptMessageReader so we can change
/// the AppleScript source without re-running it against a live Messages.app.
/// All paths use the injected executor closure to feed canned `||`-delimited
/// strings; no AppleScript is ever compiled here.
final class AppleScriptMessageReaderTests: XCTestCase {

    // MARK: - prettyPhone

    func testPrettyPhoneFormatsElevenDigitUS() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("+12014623980"),
                       "+1 (201) 462-3980")
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("12014623980"),
                       "+1 (201) 462-3980",
                       "no leading + on an 11-digit US number must still format")
    }

    func testPrettyPhoneFormatsTenDigitUS() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("2014623980"),
                       "(201) 462-3980")
    }

    func testPrettyPhonePassesThroughEmail() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("alice@example.com"),
                       "alice@example.com")
    }

    func testPrettyPhonePassesThroughChatKey() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("chat1234567890"),
                       "chat1234567890")
    }

    func testPrettyPhonePassesThroughAlreadyFormatted() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("+1 (201) 462-3980"),
                       "+1 (201) 462-3980",
                       "a string that already contains spaces or '(' must round-trip unchanged")
    }

    func testPrettyPhonePassesThroughHumanName() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("Alice Smith"),
                       "Alice Smith",
                       "a name with a space is not a phone — must round-trip")
    }

    func testPrettyPhonePassesThroughUnusualDigitCount() {
        // 9 digits — not 10 or 11-with-1, falls through to default branch
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("123456789"),
                       "123456789")
        // 7 digits — also falls through
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("5551212"),
                       "5551212")
    }

    // MARK: - recentChats parsing

    /// Canned-executor shorthand. `result` becomes the AppleScript stdout the
    /// reader parses; the script source is captured for any tests that want to
    /// assert escaping or interpolation.
    private func makeReader(returning result: String,
                            captureScript: @escaping @Sendable (String) -> Void = { _ in },
                            nameFor: @escaping @Sendable (String) -> String? = { _ in nil })
    -> AppleScriptMessageReader {
        AppleScriptMessageReader(
            executor: { script in captureScript(script); return result },
            nameFor: nameFor
        )
    }

    func testRecentChatsParsesWellFormedRows() throws {
        let raw = """
        Alice Smith||iMessage;-;+12014623980
        Group Brunch||iMessage;+;chat1234567890
        +12025550199||iMessage;-;+12025550199
        """
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()

        XCTAssertEqual(threads.count, 3,
                       "all three well-formed rows must produce a thread")
        // Sorted by name (case-insensitive). After prettyPhone the +1...0199
        // row sorts as "+1 (202) 555-0199" — the leading "+" sorts before
        // letters so it should land first.
        let names = threads.map(\.name)
        XCTAssertEqual(Set(names),
                       ["Alice Smith", "Group Brunch", "+1 (202) 555-0199"],
                       "names must be the three rows after prettyPhone")
        // chatGUID round-trips as the second column verbatim.
        XCTAssertEqual(threads.first(where: { $0.name == "Alice Smith" })?.chatGUID,
                       "iMessage;-;+12014623980")
        XCTAssertEqual(threads.first(where: { $0.name == "Group Brunch" })?.chatGUID,
                       "iMessage;+;chat1234567890")
    }

    func testRecentChatsDropsMissingValueWithoutChatID() throws {
        // First row has neither name nor chatID → must be skipped.
        // Second row has missing-value name but a usable chatID → name is
        // synthesized from the chatID suffix (a phone number).
        let raw = """
        missing value||
        missing value||iMessage;-;+12014623980
        """
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()

        XCTAssertEqual(threads.count, 1,
                       "row with no name and no chatID must be dropped, second row recoverable")
        // The synthesized name from chatID suffix gets prettyPhone applied.
        XCTAssertEqual(threads.first?.name, "+1 (201) 462-3980")
        XCTAssertEqual(threads.first?.chatGUID, "iMessage;-;+12014623980")
    }

    func testRecentChatsAppliesGroupChatLabelForSyntheticChatID() throws {
        // Empty name + group-style chat key → "Group chat" label fallback.
        let raw = "||iMessage;+;chat9999999999"
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads.first?.name, "Group chat")
    }

    func testRecentChatsResolvesContactNameViaNameFor() throws {
        // The lookup closure resolves the chatID's handle suffix to a
        // contact name; the row's raw "missing value" first column is
        // overridden by the resolution.
        let raw = "missing value||iMessage;-;+12014623980"
        let reader = makeReader(returning: raw,
                                nameFor: { handle in
                                    handle == "+12014623980" ? "Alice From Contacts" : nil
                                })
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.first?.name, "Alice From Contacts",
                       "nameFor closure must upgrade the synthesized name when it returns a real value")
    }

    func testRecentChatsFillsEmDashWhenPreviewMissing() throws {
        // Empty preview cell falls back to "—" so the row isn't visually
        // blank in the sidebar.
        let raw = "Alice||iMessage;-;+12014623980||"
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.first?.preview, "—",
                       "empty preview must fall back to em-dash placeholder")
    }

    func testRecentChatsTreatsMissingValuePreviewAsEmpty() throws {
        // AppleScript can leak the literal string "missing value" into the
        // preview cell — the parser treats it as empty and falls back to "—".
        let raw = "Alice||iMessage;-;+12014623980||missing value"
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.first?.preview, "—")
    }

    // MARK: - messagesForChat parsing

    func testMessagesForChatParsesDirection() throws {
        let raw = """
        hey||outgoing
        hello back||incoming
        sup||outgoing
        """
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 10)

        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[0].from, .me,    "outgoing must map to .me")
        XCTAssertEqual(msgs[1].from, .them,  "incoming must map to .them")
        XCTAssertEqual(msgs[2].from, .me)
        XCTAssertEqual(msgs.map(\.text), ["hey", "hello back", "sup"])
    }

    func testMessagesForChatDropsMissingValueAndEmptyBodies() throws {
        let raw = """
        missing value||incoming
        ||incoming
           ||outgoing
        real text||incoming
        """
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+1", limit: 10)
        XCTAssertEqual(msgs.count, 1, "only the row with a non-empty, non-missing body survives")
        XCTAssertEqual(msgs.first?.text, "real text")
    }

    func testMessagesForChatRespectsLimit() throws {
        // Six rows, limit 3 — caller-provided cap must clamp the output even
        // when the executor leaks more rows than requested (defensive parity
        // with the AppleScript-side `startIdx` clamp).
        let raw = (1...6).map { "msg-\($0)||incoming" }.joined(separator: "\n")
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "x", limit: 3)
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs.map(\.text), ["msg-1", "msg-2", "msg-3"])
    }

    func testMessagesForChatEscapesGUIDInScript() throws {
        // The GUID embeds inside a double-quoted AppleScript string literal,
        // so any backslash or quote in the GUID has to be escaped before
        // interpolation — a hostile or unusual GUID must not break the script.
        var capturedScript = ""
        let reader = AppleScriptMessageReader(
            executor: { script in capturedScript = script; return "" },
            nameFor: { _ in nil }
        )
        let nasty = #"weird"chat\guid"#
        _ = try reader.messagesForChat(chatGUID: nasty, limit: 1)

        // The script must contain the escaped form, not the raw.
        XCTAssertTrue(capturedScript.contains(#"\"chat\\guid"#),
                      "embedded quote and backslash must be escaped before AppleScript sees them")
    }

    func testMessagesForChatClampsZeroAndNegativeLimit() throws {
        // Limit ≤ 0 is nonsense; the reader must clamp to 1 so the AppleScript
        // doesn't compute a degenerate startIdx. We check the script contains
        // "+ 1 + 1" pattern and the parser still respects a 1-cap.
        var capturedScript = ""
        let raw = "msg-1||incoming\nmsg-2||incoming"
        let reader = AppleScriptMessageReader(
            executor: { script in capturedScript = script; return raw },
            nameFor: { _ in nil }
        )
        let msgs = try reader.messagesForChat(chatGUID: "x", limit: 0)

        XCTAssertEqual(msgs.count, 1, "limit 0 must clamp to 1, not return everything")
        XCTAssertTrue(capturedScript.contains("- 1 + 1"),
                      "AppleScript startIdx expression must reflect the clamped limit of 1")
    }

    // MARK: - AppleScriptReaderError.errorDescription

    func testScriptCreationFailedHasNonEmptyCopy() {
        // Surfaced when NSAppleScript(source:) returns nil. Must be
        // non-empty so the inbox banner doesn't render blank.
        let copy = AppleScriptReaderError.scriptCreationFailed.errorDescription ?? ""
        XCTAssertFalse(copy.isEmpty,
            "scriptCreationFailed must have user-visible copy")
        XCTAssertTrue(copy.contains("AppleScript"),
            "copy should reference AppleScript so the user knows which permission is implicated — got: \(copy)")
    }

    func testExecutionErrorInterpolatesUnderlyingMessage() {
        // The OSAErrorMessage from NSAppleScript carries the actual
        // failure cause; surfacing it verbatim is the only useful signal
        // for triage.
        let raw = "syntax error: Expected end of line but found identifier."
        let copy = AppleScriptReaderError.executionError(raw).errorDescription ?? ""
        XCTAssertTrue(copy.contains(raw),
            "executionError must include the underlying AppleScript message — got: \(copy)")
    }

    func testLocalizedErrorBridgeSurfacesOurCopy() {
        // SwiftUI `error.localizedDescription` should hit our text, not
        // the generic CFString fallback.
        let err: Error = AppleScriptReaderError.executionError("permission denied")
        XCTAssertTrue(err.localizedDescription.contains("permission denied"),
            "LocalizedError bridge must surface our copy — got: \(err.localizedDescription)")
    }
}
