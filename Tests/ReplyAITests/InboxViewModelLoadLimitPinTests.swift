import XCTest
@testable import ReplyAI

/// Static-only pin for `InboxViewModel.perThreadMessageLoadLimit`. The
/// full `InboxViewModelTests` suites are environmentally skipped under
/// the autopilot's three-skip workaround (see AGENTS.md gotcha #243),
/// so this class lives separately — name chosen so the
/// `--skip InboxViewModelTests` substring filter doesn't drop it.
@MainActor
final class InboxViewModelLoadLimitPinTests: XCTestCase {

    /// `InboxViewModel.perThreadMessageLoadLimit` was previously two
    /// duplicated `limit: 40` literals — once in `syncFromIMessage`'s
    /// focus-thread preload and once in `loadMessages(for:)`. Drift on
    /// either site changes the prompt builder's context window for
    /// every shipped user. Pin the constant so a refactor that bumps
    /// one site without the other surfaces in code review.
    func testPerThreadMessageLoadLimitIsPinnedToFourty() {
        XCTAssertEqual(InboxViewModel.perThreadMessageLoadLimit, 40,
            "perThreadMessageLoadLimit drift either truncates conversation context (down) or makes thread-detail switches slow on chatty threads (up)")
    }
}
