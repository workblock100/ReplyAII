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
}
