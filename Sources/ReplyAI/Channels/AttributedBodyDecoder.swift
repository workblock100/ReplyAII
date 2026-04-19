import Foundation

/// Best-effort reader for iMessage's `attributedBody` column — a
/// serialized NSAttributedString stored in Apple's typedstream format
/// (the predecessor to NSKeyedArchiver, deprecated since ~2008).
///
/// Rather than implement a full typedstream parser, we scan for the
/// well-known marker sequence `\x01 NSString + ` (`0x01`, class-ref
/// marker, class name, length-prefix, UTF-8 bytes). This catches the
/// plain-text body of nearly every real iMessage; rich attributes,
/// mentions, and formatting are discarded. Callers should treat the
/// result as plain text preview quality, not lossless roundtrip.
enum AttributedBodyDecoder {
    /// Returns the first decoded NSString in the blob, or nil if no
    /// recognizable text was found.
    static func extractText(from data: Data) -> String? {
        guard data.count > 20 else { return nil }

        // The blob usually starts with a "streamtyped" header; not
        // strictly required for our scan, so we don't gate on it.
        let bytes = [UInt8](data)
        // Look for an "NSString" class-name declaration. The byte layout
        // after it is:
        //   0x84 0x01 0x01  (object ref + newClass + version-1 signature)
        //   then the length of the string as a variable-length int,
        //   then UTF-8 bytes.
        // The length encoding:
        //   if firstByte < 0x80, length = firstByte
        //   if firstByte == 0x81, length = next 2 LE bytes
        //   if firstByte == 0x82, length = next 4 LE bytes
        guard let nsStringStart = findNSStringMarker(in: bytes) else { return nil }

        var cursor = nsStringStart
        // Skip class-name trailer up to the next `+` (short-literal) or
        // length byte. The text field is length-prefixed.
        while cursor < bytes.count, !isPlausibleLengthMarker(bytes[cursor]) { cursor += 1 }
        guard cursor < bytes.count else { return nil }

        guard let (length, next) = readLength(bytes: bytes, at: cursor) else { return nil }
        let end = next + length
        guard end <= bytes.count, length > 0, length < 16_384 else { return nil }

        let slice = bytes[next ..< end]
        return String(bytes: slice, encoding: .utf8)
    }

    // MARK: - Helpers

    /// Find the byte range "NSString" in the blob, returning the index
    /// just past the last 'g' (the trailing byte is usually followed by
    /// the length of the string we want).
    private static func findNSStringMarker(in bytes: [UInt8]) -> Int? {
        let needle: [UInt8] = [0x4E, 0x53, 0x53, 0x74, 0x72, 0x69, 0x6E, 0x67]  // "NSString"
        guard bytes.count >= needle.count else { return nil }
        outer: for i in 0 ... (bytes.count - needle.count) {
            for j in 0 ..< needle.count where bytes[i + j] != needle[j] {
                continue outer
            }
            return i + needle.count
        }
        return nil
    }

    private static func isPlausibleLengthMarker(_ b: UInt8) -> Bool {
        // Plain UTF-8 short literal marker (`+`), or the length prefixes
        // 0x81 / 0x82 used for medium / large strings.
        b == 0x2B || b == 0x81 || b == 0x82 || b <= 0x7F
    }

    private static func readLength(bytes: [UInt8], at index: Int) -> (length: Int, next: Int)? {
        guard index < bytes.count else { return nil }
        let marker = bytes[index]
        if marker == 0x2B, index + 1 < bytes.count {
            // The `+` marker is followed by the length byte, then bytes.
            return readLength(bytes: bytes, at: index + 1)
        }
        if marker <= 0x7F {
            return (Int(marker), index + 1)
        }
        if marker == 0x81, index + 2 < bytes.count {
            let lo = UInt16(bytes[index + 1])
            let hi = UInt16(bytes[index + 2]) << 8
            return (Int(lo | hi), index + 3)
        }
        if marker == 0x82, index + 4 < bytes.count {
            var len: UInt32 = 0
            for k in 0 ..< 4 {
                len |= UInt32(bytes[index + 1 + k]) << (8 * k)
            }
            return (Int(len), index + 5)
        }
        return nil
    }
}
