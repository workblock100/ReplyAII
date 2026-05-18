import Foundation

/// Extracts plain text from iMessage's `attributedBody` column.
///
/// The column holds a typedstream-encoded NSAttributedString — Apple's pre-KeyedArchive
/// binary format (deprecated ~2008 but still written by Messages.app). A full typedstream
/// parser is complex, but we only need the text payload:
///
///   1. Verify the "streamtyped" magic header.
///   2. Scan for typedstream's primitive-string type tag `+` (0x2B).
///   3. Read the variable-length int that follows, then the UTF-8 bytes.
///
/// Class-name C strings (NSString, NSObject, …) use a *different* encoding in
/// typedstream — they appear as raw length+bytes without the 0x2B prefix — so the
/// first 0x2B in the body is reliably the NSString (or NSMutableString) text payload.
///
/// Length encoding (all little-endian):
///   byte ≤ 0x7F         → length = byte
///   0x81 lo hi          → length = UInt16(lo | hi << 8)
///   0x82 b0 b1 b2 b3    → length = UInt32(b0 | b1<<8 | b2<<16 | b3<<24)
enum AttributedBodyDecoder {

    // MARK: - typedstream binary-format constants

    /// typedstream's primitive-string type tag. The first 0x2B in the
    /// archive body is reliably the NSString (or NSMutableString) text
    /// payload — class-name C strings use a different encoding without
    /// this prefix. Hoisted from the inline `bytes[cursor] == 0x2B`
    /// checks at TWO sites (`extractText`'s scan loop + the
    /// `readPrimitiveString` doc-comment reference) so a future
    /// typedstream-format change can be reasoned about as a single
    /// constant edit. Pinned by `AttributedBodyDecoderTests`'
    /// `*PrimitiveStringTypeTag*` cluster.
    static let primitiveStringTypeTag: UInt8 = 0x2B

    /// typedstream variable-length integer markers. `0x7F` is the
    /// boundary below which a single byte encodes the length directly;
    /// `0x81` introduces a 2-byte little-endian length; `0x82` introduces
    /// a 4-byte little-endian length. Drift on any one silently changes
    /// how a length-prefixed string is parsed — strings beyond the
    /// 7-bit boundary either get parsed at a wrong offset (truncated /
    /// embedded length-byte appears in the text payload) or get
    /// rejected as malformed when they shouldn't.
    static let lengthFormatShortBoundary: UInt8 = 0x7F
    static let lengthFormat16BitMarker:   UInt8 = 0x81
    static let lengthFormat32BitMarker:   UInt8 = 0x82

    /// Sanity cap on a primitive-string length. iMessage attributedBody
    /// payloads are bounded by message-size limits well below this; any
    /// length declaration above this bound indicates a malformed blob
    /// (or a hostile one). Drift up wastes memory on bogus inputs;
    /// drift down rejects legitimate long messages. Pinned by the
    /// existing `testThirtyTwoBitLengthDecodes` and behavioral tests.
    static let primitiveStringMaxLength: Int = 65_535

    /// "streamtyped" magic header byte sequence — Apple's typedstream
    /// signature. The header lives at the start of every typedstream
    /// archive; without these bytes the blob isn't a typedstream and
    /// `extractText` should bail. Drift here (e.g. someone capitalising
    /// the magic to "Streamtyped") would silently classify every real
    /// attributedBody as non-typedstream and return nil for every
    /// message.
    static let streamtypedMagicString: String = "streamtyped"

    // MARK: - Public

    /// Returns the plain-text content of a typedstream NSAttributedString blob,
    /// or `nil` if the blob is absent, too short, not a typedstream, or contains
    /// no recoverable UTF-8 text.
    static func extractText(from data: Data) -> String? {
        guard data.count > 14 else { return nil }
        let bytes = [UInt8](data)
        guard let bodyStart = streamtypedBodyStart(bytes) else { return nil }

        // Collect all primitive-string (+) values found after the header.
        // Real messages are one NSString; nested NSMutableAttributedString blobs
        // may carry additional runs. Concatenating them gives the full plain text.
        var parts: [String] = []
        var cursor = bodyStart

        while cursor < bytes.count {
            if bytes[cursor] == Self.primitiveStringTypeTag {
                if let (text, next) = readPrimitiveString(bytes: bytes, at: cursor + 1) {
                    parts.append(text)
                    cursor = next
                    continue
                }
            }
            cursor += 1
        }

        guard !parts.isEmpty else { return nil }
        // Deduplicate consecutive identical parts (some encoders repeat the string
        // for NSMutableAttributedString and its NSMutableString ivar).
        var deduped: [String] = []
        for part in parts where part != deduped.last {
            deduped.append(part)
        }
        return deduped.joined()
    }

    // MARK: - Header

    /// Finds the "streamtyped" magic within the first 20 bytes and returns the
    /// index of the first byte of the archive body (past magic + version byte).
    static func streamtypedBodyStart(_ bytes: [UInt8]) -> Int? {
        let magic: [UInt8] = Array(Self.streamtypedMagicString.utf8)   // 11 bytes
        let limit = min(20 + magic.count, bytes.count)
        guard let pos = findBytes(magic, in: bytes, from: 0, limit: limit) else { return nil }
        let after = pos + magic.count + 1                 // +1 skips the version byte
        return after < bytes.count ? after : nil
    }

    // MARK: - String reading

    /// Reads a primitive string starting at `index` (immediately after the 0x2B tag).
    /// Returns (decoded string, index past the last content byte) or nil on failure.
    static func readPrimitiveString(bytes: [UInt8], at index: Int) -> (String, Int)? {
        guard let (length, start) = readLength(bytes: bytes, at: index) else { return nil }
        let end = start + length
        guard length > 0, length <= Self.primitiveStringMaxLength, end <= bytes.count else { return nil }
        guard let text = String(bytes: bytes[start..<end], encoding: .utf8) else { return nil }
        return (text, end)
    }

    // MARK: - Byte utilities

    /// Variable-length integer decoder (little-endian, 1/3/5 byte forms).
    static func readLength(bytes: [UInt8], at index: Int) -> (length: Int, next: Int)? {
        guard index < bytes.count else { return nil }
        let b = bytes[index]
        if b <= Self.lengthFormatShortBoundary { return (Int(b), index + 1) }
        if b == Self.lengthFormat16BitMarker {
            guard index + 2 < bytes.count else { return nil }
            let lo = UInt16(bytes[index + 1])
            let hi = UInt16(bytes[index + 2]) << 8
            return (Int(lo | hi), index + 3)
        }
        if b == Self.lengthFormat32BitMarker {
            guard index + 4 < bytes.count else { return nil }
            var len: UInt32 = 0
            for k in 0..<4 { len |= UInt32(bytes[index + 1 + k]) << (8 * k) }
            return (Int(len), index + 5)
        }
        return nil
    }

    private static func findBytes(
        _ needle: [UInt8], in bytes: [UInt8], from: Int, limit: Int
    ) -> Int? {
        guard bytes.count >= needle.count else { return nil }
        let end = min(limit, bytes.count) - needle.count
        guard from <= end else { return nil }
        outer: for i in from...end {
            for j in 0..<needle.count where bytes[i + j] != needle[j] { continue outer }
            return i
        }
        return nil
    }
}
