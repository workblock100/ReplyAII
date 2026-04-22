import XCTest
@testable import ReplyAI

/// Tests for AttributedBodyDecoder against hand-crafted typedstream blobs.
///
/// Each fixture is assembled from the known typedstream structure:
///   [04 0B "streamtyped" 04] [class-definition bytes] [2B <len> <UTF-8>]
/// Only real user data ever belongs in chat.db; these blobs are synthetic.
final class AttributedBodyDecoderTests: XCTestCase {

    // MARK: - Blob builder

    /// Build a minimal typedstream blob with a single primitive-string payload.
    /// `filler` simulates the class-definition / object-header bytes between
    /// the streamtyped header and the 0x2B string marker.
    private func blob(
        text: String,
        filler: [UInt8] = [0x40, 0x84, 0x84, 0x87],
        lengthEncoding: LengthEncoding = .auto
    ) -> Data {
        var bytes: [UInt8] = [0x04, 0x0B]
        bytes += Array("streamtyped".utf8)
        bytes += [0x04]           // version
        bytes += filler
        bytes += [0x2B]           // primitive-string type tag
        let textBytes = Array(text.utf8)
        bytes += encodeLength(textBytes.count, as: lengthEncoding)
        bytes += textBytes
        return Data(bytes)
    }

    enum LengthEncoding { case auto, bits16, bits32 }

    private func encodeLength(_ n: Int, as mode: LengthEncoding) -> [UInt8] {
        switch mode {
        case .auto:
            if n <= 0x7F { return [UInt8(n)] }
            fallthrough
        case .bits16:
            return [0x81, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF)]
        case .bits32:
            return [0x82,
                    UInt8(n & 0xFF),
                    UInt8((n >> 8) & 0xFF),
                    UInt8((n >> 16) & 0xFF),
                    UInt8((n >> 24) & 0xFF)]
        }
    }

    // MARK: - Fixture 1: simple string

    func testSimpleStringDecodes() {
        let data = blob(text: "Hello")
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: data), "Hello")
    }

    // MARK: - Fixture 2: escaped / control characters

    func testEscapedCharsDecodes() {
        let text = "Hello\nWorld\t!"
        let data = blob(text: text)
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: data), text)
    }

    // MARK: - Fixture 3: multi-run attributed string

    /// A bold-on-part-of-text NSAttributedString stores the FULL text as one
    /// NSString; attribute ranges are carried separately (not as extra 0x2B strings).
    /// Validate we decode the whole text, not just the first visible run.
    func testMultiRunAttributedStringDecodes() {
        // Simulate the iMessage body "Buy milk and eggs" with two attribute spans.
        // The text is still one NSString in the typedstream.
        let data = blob(text: "Buy milk and eggs", filler: [
            // NSMutableAttributedString class intro bytes (real format excerpt)
            0x40, 0x84, 0x84, 0x87,
            0x17,  // length of "NSMutableAttributedString" = 25... let's use placeholder
            0x01, 0x84, 0x86,
        ])
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: data), "Buy milk and eggs")
    }

    // MARK: - Fixture 4: UTF-8 with emoji

    func testUTF8WithEmojiDecodes() {
        let text = "Hey 👋🏽 what's up?"
        let data = blob(text: text)
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: data), text)
    }

    // MARK: - Fixture 5: empty body

    func testEmptyDataReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.extractText(from: Data()))
    }

    func testTooShortDataReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.extractText(from: Data([0x04, 0x0B, 0x73])))
    }

    // MARK: - Fixture 6: malformed blob (no streamtyped header)

    func testMalformedBlobReturnsNil() {
        // Contains a valid-looking 0x2B string but no "streamtyped" magic.
        let bytes: [UInt8] = [0x84, 0x87, 0x2B, 0x05] + Array("Hello".utf8)
        XCTAssertNil(AttributedBodyDecoder.extractText(from: Data(bytes)))
    }

    func testNonTypestreamBlobDoesNotCrash() {
        // Random garbage — must not crash, must return nil.
        let bytes: [UInt8] = (0..<64).map { _ in UInt8.random(in: 0...255) }
        // We don't assert a specific value — just that it doesn't throw/crash.
        _ = AttributedBodyDecoder.extractText(from: Data(bytes))
    }

    // MARK: - Length encoding: 16-bit prefix

    func testSixteenBitLengthDecodes() {
        // Build a string of 200 'a' characters — longer than 127, needs 0x81 prefix.
        let longText = String(repeating: "a", count: 200)
        let data = blob(text: longText, lengthEncoding: .bits16)
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: data), longText)
    }

    // MARK: - Length encoding: 32-bit prefix

    func testThirtyTwoBitLengthDecodes() {
        let longText = String(repeating: "x", count: 300)
        let data = blob(text: longText, lengthEncoding: .bits32)
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: data), longText)
    }

    // MARK: - NSMutableString class hierarchy (nested NSMutableAttributedString)

    /// NSMutableAttributedString stores its text in an NSMutableString ivar.
    /// The 0x2B marker follows the NSMutableString class definition, not NSString.
    /// Verify we find the string regardless of what class-definition bytes precede it.
    func testNestedMutableAttributedStringDecodes() {
        var bytes: [UInt8] = [0x04, 0x0B]
        bytes += Array("streamtyped".utf8)
        bytes += [0x04]  // version

        // Simulate NSMutableAttributedString → NSMutableString class chain
        let nsMutableAttr = Array("NSMutableAttributedString".utf8)
        let nsMutableStr  = Array("NSMutableString".utf8)
        let nsStr         = Array("NSString".utf8)
        let nsObj         = Array("NSObject".utf8)

        bytes += [0x40, 0x84, 0x84, 0x87]
        bytes += [UInt8(nsMutableAttr.count + 1)] + nsMutableAttr + [0x00]
        bytes += [UInt8(nsMutableStr.count + 1)]  + nsMutableStr  + [0x00]
        bytes += [UInt8(nsStr.count + 1)]         + nsStr         + [0x00]
        bytes += [UInt8(nsObj.count + 1)]         + nsObj         + [0x00]
        bytes += [0x01, 0x01, 0x01, 0x01]  // versions
        bytes += [0x84, 0x86]              // class chain end

        let text = "Meeting at 3pm today"
        let textBytes = Array(text.utf8)
        bytes += [0x2B, UInt8(textBytes.count)] + textBytes

        XCTAssertEqual(AttributedBodyDecoder.extractText(from: Data(bytes)), text)
    }

    // MARK: - Streamtyped header location

    func testStreamtypedHeaderDetectedBeyondByteZero() {
        // Some blobs have a small prefix before the streamtyped magic.
        var bytes: [UInt8] = [0x04]  // leading byte
        bytes += [0x04, 0x0B]
        bytes += Array("streamtyped".utf8)
        bytes += [0x04, 0x2B, 0x06]
        bytes += Array("Hi mom".utf8)
        // Our header scanner looks in the first 20+ bytes, so this should decode.
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: Data(bytes)), "Hi mom")
    }

    // MARK: - Deduplication

    func testDuplicateStringsAreDeduped() {
        // Some encoders repeat the same NSString for NSMutableAttributedString + NSMutableString.
        // We should return the text once, not twice.
        var bytes: [UInt8] = [0x04, 0x0B]
        bytes += Array("streamtyped".utf8)
        bytes += [0x04, 0x40]
        let textBytes = Array("Dedupe me".utf8)
        // First occurrence
        bytes += [0x2B, UInt8(textBytes.count)] + textBytes
        // Immediate repeat (same bytes)
        bytes += [0x2B, UInt8(textBytes.count)] + textBytes
        XCTAssertEqual(AttributedBodyDecoder.extractText(from: Data(bytes)), "Dedupe me")
    }

    // MARK: - readLength unit tests

    func testReadLengthShortForm() {
        let bytes: [UInt8] = [0x05, 0x00]
        let result = AttributedBodyDecoder.readLength(bytes: bytes, at: 0)
        XCTAssertEqual(result?.length, 5)
        XCTAssertEqual(result?.next, 1)
    }

    func testReadLength16BitForm() {
        // 0x81 0xC8 0x00 → length = 0x00C8 = 200
        let bytes: [UInt8] = [0x81, 0xC8, 0x00]
        let result = AttributedBodyDecoder.readLength(bytes: bytes, at: 0)
        XCTAssertEqual(result?.length, 200)
        XCTAssertEqual(result?.next, 3)
    }

    func testReadLength32BitForm() {
        // 0x82 0x2C 0x01 0x00 0x00 → length = 0x0000012C = 300
        let bytes: [UInt8] = [0x82, 0x2C, 0x01, 0x00, 0x00]
        let result = AttributedBodyDecoder.readLength(bytes: bytes, at: 0)
        XCTAssertEqual(result?.length, 300)
        XCTAssertEqual(result?.next, 5)
    }

    func testReadLengthTruncatedReturnsNil() {
        // 0x81 with only one following byte — not enough for 16-bit
        let bytes: [UInt8] = [0x81, 0xFF]
        XCTAssertNil(AttributedBodyDecoder.readLength(bytes: bytes, at: 0))
    }

    // MARK: - Fuzz: random blob resilience (REP-061)

    func testFuzzRandomBlobsNeverCrash() {
        // Verify that no randomly-constructed blob causes a trap, assertion
        // failure, or invalid UTF-8 in the returned string. Uses the default
        // Swift PRNG so results are not reproducible across runs by design —
        // this is a crash-coverage test, not a deterministic fixture.
        var rng = SystemRandomNumberGenerator()
        let iterations = 10_000
        for _ in 0 ..< iterations {
            let length = Int.random(in: 0 ... 4096, using: &rng)
            var bytes = [UInt8](repeating: 0, count: length)
            for i in 0 ..< length {
                bytes[i] = UInt8.random(in: 0 ... 255, using: &rng)
            }
            let data = Data(bytes)
            // Must return without crashing; nil is an acceptable result.
            guard let text = AttributedBodyDecoder.extractText(from: data) else { continue }
            // Any returned string must be valid UTF-8 (String is always UTF-8 in Swift,
            // but verify the roundtrip to catch any internal encoding anomaly).
            XCTAssertNotNil(text.data(using: .utf8),
                            "extractText returned a String that is not valid UTF-8")
        }
    }
}
