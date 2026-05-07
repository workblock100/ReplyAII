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

    /// 11-digit non-US number (no leading "1") must NOT be reformatted as
    /// "+1 (XXX) XXX-XXXX" — that would mangle a UK or AU number into a
    /// false North American format. The implementation matches `where
    /// digits.hasPrefix("1")` specifically; pin the non-1-prefix path so a
    /// future "all 11-digit numbers" generalization shows up here as a
    /// deliberate behavior change rather than a quiet user-data bug.
    func testPrettyPhone11DigitsWithoutLeadingOnePassesThrough() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("44207946001"),
                       "44207946001",
                       "UK-shaped 11-digit number must NOT be reformatted into US +1 layout")
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("61286010001"),
                       "61286010001",
                       "AU-shaped 11-digit number must NOT be reformatted into US +1 layout")
    }

    /// 12+ digit numbers (international with country code in `+` form, no
    /// `+` to strip) hit the default branch and pass through. Pin the
    /// behavior so adding a new case (e.g. 12-digit UK with full country
    /// code) is a deliberate edit visible in this test.
    func testPrettyPhone12PlusDigitsPassesThrough() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("442079460012"),
                       "442079460012")
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("9876543210123"),
                       "9876543210123")
    }

    /// Empty input is a degenerate case but must not crash — the digit
    /// filter produces an empty string with count 0, switch hits default,
    /// returns "" unchanged. Pin so a future `dropFirst(1)` on an empty
    /// digit string can't slip through and crash with a precondition.
    func testPrettyPhoneEmptyStringPassesThrough() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone(""), "")
    }

    /// Letters mixed with digits: digit count is right but the input has a
    /// `(`/space/`@` sentinel (or none of those — all letters/digits). The
    /// guard prefers passing through anything with `(` already in it; "abc"
    /// has no digits so digit count is 0, default branch, passes through.
    func testPrettyPhoneAlphanumericPassesThrough() {
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone("abc"), "abc",
            "non-numeric input falls to default branch and round-trips")
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

    // MARK: - Exact-copy pins
    //
    // These two strings ship verbatim to the inbox banner when the
    // AppleScript path fails. The keyword-contains tests above stay
    // resilient to small wording tweaks; pin the full literals here so
    // a designer-led rewrite surfaces in code review.

    func testScriptCreationFailedCopyExactLiteral() {
        XCTAssertEqual(
            AppleScriptReaderError.scriptCreationFailed.errorDescription,
            "Failed to compile AppleScript."
        )
    }

    func testExecutionErrorCopyExactPrefix() {
        let raw = "syntax error: unexpected end-of-file"
        XCTAssertEqual(
            AppleScriptReaderError.executionError(raw).errorDescription,
            "AppleScript failed: \(raw)"
        )
    }

    // MARK: - Edge cases on recentChats parsing

    /// `recentChats()` returns threads sorted by `name` using
    /// `localizedCaseInsensitiveCompare`. The sidebar relies on this for
    /// stable ordering across syncs — an unsorted output would shuffle
    /// rows on every refresh and look like a UI bug. Pin so a refactor
    /// that drops the sort or swaps to case-sensitive surfaces here.
    func testRecentChatsSortsByNameCaseInsensitively() throws {
        let raw = """
        zoe wong||iMessage;-;+15550000001
        Alice Smith||iMessage;-;+15550000002
        bob jones||iMessage;-;+15550000003
        """
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.map(\.name),
                       ["Alice Smith", "bob jones", "zoe wong"],
                       "rows must sort by name using case-insensitive compare — capital A precedes lowercase b precedes lowercase z")
    }

    /// `ContactsResolver.name(for:)` echoes the input handle back when access
    /// is granted but no contact matches — the AppleScript reader treats
    /// that echo as "no resolution" so the prettyPhone formatter still
    /// runs. Without this defense, a 1:1 chat with a saved-but-unmatched
    /// number would render the raw `+12014623980` form. Pin so a future
    /// resolver that drops the echo behavior surfaces here as a deliberate
    /// change to this callsite.
    func testRecentChatsTreatsNameForEchoAsNoMatch() throws {
        let raw = "missing value||iMessage;-;+12014623980"
        let reader = makeReader(returning: raw,
                                nameFor: { handle in handle })  // echo the input verbatim
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.first?.name, "+1 (201) 462-3980",
            "echo from nameFor must NOT win over prettyPhone — otherwise unmatched handles render unformatted")
    }

    /// Empty-string echo from `nameFor` is treated identically to nil: the
    /// reader falls through to the chatID suffix, then to prettyPhone.
    /// Pin so a future resolver that returns "" for "no match" doesn't
    /// silently zero out the sidebar's display name.
    func testRecentChatsTreatsNameForEmptyStringAsNoMatch() throws {
        let raw = "missing value||iMessage;-;+12014623980"
        let reader = makeReader(returning: raw,
                                nameFor: { _ in "" })  // empty-string match
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.first?.name, "+1 (201) 462-3980",
            "empty-string nameFor result must be treated as no match — otherwise the sidebar shows an empty name cell")
    }

    // MARK: - parseMessages — direction edge cases

    /// Pin that direction parsing is case-insensitive — AppleScript's
    /// `direction of message` is documented as returning `incoming` /
    /// `outgoing`, but a future macOS revision could uppercase the value
    /// (e.g. `OUTGOING`) without warning. The implementation already
    /// lowercases the comparison; pin so a regression that drops the
    /// lowercasing surfaces here.
    func testMessagesForChatDirectionIsCaseInsensitive() throws {
        let raw = """
        cap||OUTGOING
        title||Outgoing
        mixed||OuTgOiNg
        normal||outgoing
        """
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 10)
        XCTAssertEqual(msgs.count, 4)
        XCTAssertTrue(msgs.allSatisfy { $0.from == .me },
            "every casing of `outgoing` must map to .me — got: \(msgs.map(\.from))")
    }

    /// Pin that any direction value other than (case-insensitive) `outgoing`
    /// maps to `.them`. Without this default, an AppleScript that returns
    /// e.g. an empty string or a localized form like `entrant` would silently
    /// flip messages to `.me` and the LLM would misattribute the user's own
    /// voice. The implementation chooses `.them` as the safe default.
    func testMessagesForChatUnknownDirectionMapsToThem() throws {
        let raw = """
        a||incoming
        b||sideways
        c||
        d||outgoing
        """
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 10)
        XCTAssertEqual(msgs.count, 4)
        XCTAssertEqual(msgs[0].from, .them, "incoming → .them")
        XCTAssertEqual(msgs[1].from, .them, "unknown direction (`sideways`) must default to .them, not .me")
        XCTAssertEqual(msgs[2].from, .them, "empty direction defaults to .them via the parts.count<=1 fallback")
        XCTAssertEqual(msgs[3].from, .me,   "outgoing → .me (sanity check)")
    }

    /// Pin that the limit cap is enforced post-parse, not just inside
    /// AppleScript. The script-side `repeat … to msgCount` could leak
    /// extra rows if a future Messages.app revision adds tapbacks or
    /// system rows that bypass the index math. Parse-side enforcement
    /// is the safety net so the inbox never sees more than `limit`
    /// messages per call.
    func testMessagesForChatParseSideLimitCap() throws {
        let raw = """
        a||outgoing
        b||outgoing
        c||outgoing
        d||outgoing
        e||outgoing
        """
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 3)
        XCTAssertEqual(msgs.count, 3,
            "parser must cap at limit=3 even when executor returns 5 rows — otherwise a misbehaving executor breaks the contract")
        XCTAssertEqual(msgs.map(\.text), ["a", "b", "c"],
            "rows must be returned in arrival order with the tail dropped, not the head")
    }

    // MARK: - parse() edge cases (recentChats)

    /// A row with `name||id||preview||extra` must keep `parts[2]` as the
    /// preview and silently drop trailing fields. Pin so a future schema
    /// expansion (e.g. adding a sender field) doesn't accidentally shift
    /// preview parsing onto the wrong column.
    func testRecentChatsIgnoresTrailingPipeFieldsAfterPreview() throws {
        let raw = "Alice Smith||iMessage;-;+12014623980||hello there||EXTRA||MORE"
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].preview, "hello there",
            "preview must come from parts[2] only — trailing fields are dropped, not concatenated")
    }

    /// When the row leads with empty name (`||id||preview`), the parser
    /// must fall back to deriving a name from the chatID rather than
    /// emitting a thread with an empty `name` (which would render as a
    /// blank sidebar row). Pin the fallback path.
    func testRecentChatsBlankNameFallsBackToChatIDDerivedName() throws {
        let raw = "||iMessage;-;+12014623980||hello"
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.count, 1,
            "a row with blank name but a usable chatID must still yield exactly one thread")
        XCTAssertFalse(threads[0].name.isEmpty,
            "fallback derivation must produce a non-empty name so the sidebar row is readable")
    }

    /// Group-chat synthetic IDs (`chat1234567890`) without any participant
    /// name should surface as the literal "Group chat" label, NOT the raw
    /// chat key. Pin since the user-visible string was an explicit product
    /// call (`AppleScriptMessageReader.formatHandleFromChatID`).
    func testRecentChatsBlankNameAndGroupChatIDLabelsAsGroupChat() throws {
        let raw = "||iMessage;+;chat1234567890||hello"
        let reader = makeReader(returning: raw)
        let threads = try reader.recentChats()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].name, "Group chat",
            "synthetic chat IDs (`chat...`) must label as `Group chat`, not the raw key")
    }

    /// `parse()` runs `localizedCaseInsensitiveCompare` so totally empty
    /// executor output (whitespace-only or empty) must yield zero threads
    /// without crashing on the sort. Pin the empty-input path.
    func testRecentChatsEmptyExecutorOutputYieldsNoThreads() throws {
        let reader = makeReader(returning: "")
        let threads = try reader.recentChats()
        XCTAssertTrue(threads.isEmpty,
            "no rows in → no threads out; the sort path must accept an empty array")
    }

    func testRecentChatsWhitespaceOnlyExecutorOutputYieldsNoThreads() throws {
        let reader = makeReader(returning: "   \n\t \n  ")
        let threads = try reader.recentChats()
        XCTAssertTrue(threads.isEmpty,
            "rows that trim to empty must drop without producing phantom threads")
    }

    // MARK: - parseMessages() edge cases (messagesForChat)

    /// A message body that itself contains the `||` separator (e.g. a user
    /// literally typed `a||b`) loses everything after the first `||` to
    /// the direction column. This is a known parser limitation rather
    /// than a bug — pin it so a "fix" that breaks the existing direction
    /// parsing surfaces here. Fixing the lossy split would require a
    /// different inter-field separator, which is an AppleScript-side
    /// schema change, not a parser-side one.
    func testMessagesForChatBodyContainingDoublePipeIsLossy() throws {
        // `a||b||outgoing` — parts = ["a", "b", "outgoing"]. body = "a",
        // dir = "b" (not a known direction → defaults to .them).
        let raw = "a||b||outgoing"
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 5)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].text, "a",
            "body keeps everything before the first `||` only — schema-level limitation, pinned for visibility")
        XCTAssertEqual(msgs[0].from, .them,
            "an unknown direction string (here `b`) must default to .them rather than silently flip to .me")
    }

    /// A row with a body but no `||` separator (e.g. AppleScript emitted
    /// only the body) must default direction to `incoming` → `.them`.
    /// Pin so a future refactor that lets the missing column collapse to
    /// an empty string doesn't accidentally route messages to `.me`.
    func testMessagesForChatRowWithNoSeparatorDefaultsToThem() throws {
        let raw = "hello with no direction column"
        let reader = makeReader(returning: raw)
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 5)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].text, "hello with no direction column",
            "the entire line becomes the body when no `||` is present")
        XCTAssertEqual(msgs[0].from, .them,
            "missing direction column defaults to .them so received messages aren't misattributed to the user")
    }

    /// Empty executor output for `messagesForChat` must yield zero
    /// messages without crashing the parser. Pin the empty-input path.
    func testMessagesForChatEmptyExecutorOutputYieldsNoMessages() throws {
        let reader = makeReader(returning: "")
        let msgs = try reader.messagesForChat(chatGUID: "iMessage;-;+12014623980", limit: 5)
        XCTAssertTrue(msgs.isEmpty,
            "no rows in → no messages out; the parser must accept an empty AppleScript result")
    }

    // MARK: - AppleScript template invariants

    /// Pin the AppleScript source emitted by `recentChats()`. The script
    /// runs against Messages.app and must keep the `tell application
    /// "Messages"` opener, the `every chat` enumeration, and the
    /// `||`-delimited output line — drift on any of these breaks the
    /// FDA-free fallback path silently. Companion to
    /// `IMessageSenderAppleScriptTemplateTests` which pins the send-side
    /// template.
    func testRecentChatsScriptStructureIsStable() throws {
        final class Captured: @unchecked Sendable { var source: String = "" }
        let captured = Captured()
        let reader = AppleScriptMessageReader(
            executor: { script in captured.source = script; return "" },
            nameFor: { _ in nil }
        )
        _ = try reader.recentChats()

        let src = captured.source
        XCTAssertTrue(src.contains("tell application \"Messages\""),
            "recentChats script must address Messages.app via `tell application \"Messages\"` — got: \(src)")
        XCTAssertTrue(src.contains("every chat"),
            "recentChats script must enumerate `every chat` — got: \(src)")
        XCTAssertTrue(src.contains("\"||\""),
            "recentChats script must emit `||`-delimited rows — the parser is hard-coded to that delimiter; got: \(src)")
        XCTAssertTrue(src.contains("end tell"),
            "recentChats script must close the tell block — got: \(src)")
    }

    /// Pin the AppleScript source emitted by `messagesForChat(chatGUID:limit:)`.
    /// Drift in the `first chat whose id is "..."` selector or the
    /// `text messages of theChat` enumeration would break the per-thread
    /// load path the inbox falls back to when chat.db isn't readable.
    func testMessagesForChatScriptStructureIsStable() throws {
        final class Captured: @unchecked Sendable { var source: String = "" }
        let captured = Captured()
        let reader = AppleScriptMessageReader(
            executor: { script in captured.source = script; return "" },
            nameFor: { _ in nil }
        )
        _ = try reader.messagesForChat(chatGUID: "iMessage;-;+15551234567", limit: 25)

        let src = captured.source
        XCTAssertTrue(src.contains("tell application \"Messages\""),
            "messagesForChat script must address Messages.app via `tell application \"Messages\"`")
        XCTAssertTrue(src.contains("first chat whose id is"),
            "messagesForChat script must select the chat by id — got: \(src)")
        XCTAssertTrue(src.contains("text messages of theChat"),
            "messagesForChat script must enumerate `text messages of theChat` — got: \(src)")
        XCTAssertTrue(src.contains("\"iMessage;-;+15551234567\""),
            "messagesForChat script must embed the GUID inside double quotes — got: \(src)")
    }
}
