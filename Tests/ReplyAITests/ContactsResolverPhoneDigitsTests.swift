import XCTest
@testable import ReplyAI

/// Tests for the pure static `CNContactStoreBackedStoring.phoneDigits(_:)` normalizer.
/// Lives in a separate XCTestCase class (not `ContactsResolverTests`) so it
/// runs in headless environments where the wider suite is `XCTSkipIf`'d due
/// to missing Contacts permission. `phoneDigits` is pure string math — no
/// CNContactStore touch — so it is safe to exercise everywhere.
///
/// The normalizer is the join key for sender-name resolution: messages
/// store handles in many shapes (`+1...`, `1-...`, `(...)`, raw 10 digits)
/// and ContactsResolver's cache keys depend on every shape collapsing to
/// the same bare 10-digit string. Drift here would silently break sender
/// name resolution for thousands of contacts.
final class ContactsResolverPhoneDigitsTests: XCTestCase {

    func testStripsFormattingCharacters() {
        // Common visual format from the iOS Contacts app.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("(631) 848-6282"), "6318486282")
    }

    func testStripsHyphens() {
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("631-848-6282"), "6318486282")
    }

    func testStripsLeadingPlusOne() {
        // E.164 form coming back from chat.db handles.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("+16318486282"), "6318486282")
    }

    func testStripsLeadingOneDigit() {
        // 11-digit US form ("16318486282") drops the leading 1.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("16318486282"), "6318486282")
    }

    func testTenDigitInputUnchanged() {
        // Already canonical — no transformation needed.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("6318486282"), "6318486282")
    }

    func testKeepsLeadingOneOnNonElevenDigit() {
        // The "drop leading 1" rule is gated on length == 11. A 7-digit
        // legacy local number that happens to start with 1 must not be
        // truncated, or it would silently key under the wrong contact.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("1234567"), "1234567")
    }

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits(""), "")
    }

    func testNonNumericInputReturnsEmpty() {
        // Email-shaped handle (Slack/iMessage email addresses) — no digits
        // means no match rather than a misleading partial.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("user@example.com"), "")
    }

    func testInternationalNumberKeepsAllDigits() {
        // UK +44 7700 900123 → 12 digits total. The "drop leading 1" rule
        // only applies when length == 11 AND starts with 1, so the +44
        // number passes through with its country code intact.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("+44 7700 900123"), "447700900123")
    }

    func testLetterMixedInputIgnoresLetters() {
        // Vanity numbers like "1-800-FLOWERS" — letters are dropped, the
        // surviving digits get the standard treatment.
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits("1-800-FLOW"), "1800")
    }

    func testAllShapesProduceIdenticalKey() {
        // The whole point of normalization: chat.db, the user's Contact
        // card, and a manually-typed handle all collapse to one cache key.
        let canonical = "6318486282"
        let shapes = [
            "+16318486282",
            "1-631-848-6282",
            "(631) 848-6282",
            "631.848.6282",
            "6318486282",
        ]
        for shape in shapes {
            XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits(shape), canonical,
                "shape '\(shape)' must normalize to canonical key — got: \(CNContactStoreBackedStoring.phoneDigits(shape))")
        }
    }

    /// Cross-file invariant pin (REP-hoist 2026-05-07): the
    /// group-chat-identifier guard inside
    /// `ContactsResolver.normalizedHandle` skips phone-normalization
    /// for any handle starting with `RuleEvaluator.groupChatIdentifierPrefix`.
    /// Drift between this guard and `.isGroupChat`'s prefix would
    /// silently mis-classify some handles — group identifiers might
    /// get phone-normalized (or vice versa). Synthetic pin: build a
    /// handle from the prefix and assert it passes through unchanged
    /// (no normalization applied).
    func testGroupChatHandlePassesThroughNormalizationUnchanged() {
        let resolver = ContactsResolver()
        let groupHandle = "\(RuleEvaluator.groupChatIdentifierPrefix)42-abc"
        XCTAssertEqual(resolver.normalizedHandle(groupHandle), groupHandle,
            "any handle prefixed with `\(RuleEvaluator.groupChatIdentifierPrefix)` must pass through normalizedHandle unchanged — drift between this guard and .isGroupChat's prefix is silent")
    }

    // MARK: - USPhoneNormalization constants freeze + cross-call-site pin

    /// Pin the two US-country-code constants. Drift in either breaks
    /// phone-handle deduplication: a contact stored as `+14155551234`
    /// would no longer match an iMessage handle of `4155551234` and
    /// contact-name resolution would silently fall back to the raw
    /// handle.
    func testUSCountryCodeNormalizationConstantsAreFrozen() {
        XCTAssertEqual(ContactsResolver.USPhoneNormalization.prefixedLength, 11,
            "US E.164 prefixed length must be 11 — drift breaks the drop-leading-1 path")
        XCTAssertEqual(ContactsResolver.USPhoneNormalization.countryCode, "1",
            "US country code must be string \"1\" — drift to `+1` would miss every digit-only input")
    }

    /// Cross-call-site invariant: every site that drops the country-
    /// code prefix must produce identical output for identical input.
    /// The three call sites are `ContactsResolver.normalizedHandle`,
    /// `CNContactStoreBackedStoring.phoneDigits`, and
    /// `AppleScriptMessageReader.prettyPhone`. The first two produce
    /// the bare 10-digit form; `prettyPhone` produces a formatted
    /// `+1 (NPA) NXX-XXXX` — different surface, same drop-1 rule. We
    /// pin the rule by exercising all three on the same 11-digit US
    /// input.
    func testElevenDigitUSInputIsHandledIdenticallyAcrossCallSites() {
        let raw = "16318486282"
        // Site 1: normalizedHandle → bare 10-digit
        let resolver = ContactsResolver()
        XCTAssertEqual(resolver.normalizedHandle(raw), "6318486282")
        // Site 2: phoneDigits → bare 10-digit
        XCTAssertEqual(CNContactStoreBackedStoring.phoneDigits(raw), "6318486282")
        // Site 3: prettyPhone → +1 (NPA) NXX-XXXX
        XCTAssertEqual(AppleScriptMessageReader.prettyPhone(raw), "+1 (631) 848-6282")
    }
}
