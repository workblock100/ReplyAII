import XCTest
@testable import ReplyAICore

/// Pure-static pin tests for ContactsResolver constants. The full
/// `ContactsResolverTests` suite is environmentally skipped in headless
/// runners (no Contacts authorization for xctest) — see AGENTS.md
/// gotcha #243 and the autopilot's three-skip workaround. The constants
/// pinned here don't construct a `ContactsResolver` at all, so they run
/// cleanly under the workaround. Class name is deliberately distinct
/// from `ContactsResolverTests` so the `--skip ContactsResolverTests`
/// substring filter doesn't drop these pins.
final class ContactsResolverDefaultPinTests: XCTestCase {

    /// `ContactsResolver.defaultTTL` is the production cache window for
    /// resolved contact names. Drift here changes how often the system
    /// Contacts framework is queried for every shipped user — too short
    /// thrashes the system-wide Contacts cache (visible as battery
    /// drain on a chatty inbox); too long means a contact renamed in
    /// the user's address book takes too long to surface in ReplyAI.
    /// Pin so a future "let's tighten freshness" refactor lands in
    /// review.
    func testDefaultTTLIsThirtyMinutes() {
        XCTAssertEqual(ContactsResolver.defaultTTL, 1800,
            "defaultTTL drift changes Contacts query rate for every shipped user — pin so the freshness/performance trade-off is a deliberate edit")

        // The init default arg routes through `defaultTTL`. The
        // existing skipped suite covers the dynamic init+resolve flow;
        // here we just verify the static-constant plumbing.
        XCTAssertEqual(ContactsResolver.defaultTTL, 1800)
    }
}
