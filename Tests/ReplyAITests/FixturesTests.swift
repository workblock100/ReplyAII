import XCTest
@testable import ReplyAI

final class FixturesTests: XCTestCase {
    func testEveryThreadHasStableID() {
        let ids = Fixtures.threads.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "thread IDs must be unique")
    }

    func testSeededDraftsExistForPrimaryThreads() {
        for tone in Tone.allCases {
            XCTAssertFalse(Fixtures.seedDraft(threadID: "t1", tone: tone).isEmpty)
            XCTAssertFalse(Fixtures.seedDraft(threadID: "t3", tone: tone).isEmpty)
        }
    }

    func testUnknownThreadReturnsGenericAcknowledgment() {
        // Live iMessage threads aren't in fixtures — the stub LLM must
        // return a neutral per-tone line instead of a canned Maya Chen
        // response that would read absurdly to anyone else.
        for tone in Tone.allCases {
            let fallback = Fixtures.seedDraft(threadID: "nonexistent-xyz", tone: tone)
            XCTAssertFalse(fallback.isEmpty)
            XCTAssertEqual(fallback, Fixtures.genericAcknowledgment(tone: tone))
            // Must NOT leak the t1 ("review the deck") copy.
            let t1 = Fixtures.seedDraft(threadID: "t1", tone: tone)
            XCTAssertNotEqual(fallback, t1)
        }
    }

    func testLowConfidenceThreadBelowThreshold() {
        // cmp-lowconf surfaces at confidence < 0.4. t4 (SMS verification code)
        // should fall in that bucket.
        let c = Fixtures.seedConfidence(threadID: "t4", tone: .warm)
        XCTAssertLessThan(c, 0.4)
    }

    func testHighContextThreadsAboveThreshold() {
        for id in ["t1", "t3"] {
            let c = Fixtures.seedConfidence(threadID: id, tone: .warm)
            XCTAssertGreaterThanOrEqual(c, 0.4)
        }
    }

    func testMessagesFallBackWhenNotSeeded() {
        let fallback = Fixtures.messages(forThread: "t2", fallback: "x", time: "1:00 PM")
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback[0].text, "x")
        XCTAssertEqual(fallback[0].from, .them)
    }

    func testChannelReplyCountsAreFinite() {
        for ch in Channel.allCases {
            XCTAssertGreaterThan(Fixtures.replyCount(for: ch), 0)
        }
    }

    // MARK: - demoChatThreads (REP-228 — first-launch demo mode)
    //
    // demoChatThreads is the user's first impression when iMessage,
    // Slack, and every other channel come up empty. The shape of this
    // array drives what the inbox renders before any real data exists,
    // so an accidental edit (empty list, only one channel, all unread = 0)
    // would silently degrade the new-user experience.

    func testDemoChatThreadsIsNonEmpty() {
        // A zero-thread demo would render an empty inbox on first launch
        // and look broken to users who haven't connected anything yet.
        XCTAssertFalse(Fixtures.demoChatThreads.isEmpty,
            "demoChatThreads must seed the empty inbox with something to render")
    }

    func testDemoChatThreadsHaveUniqueIDs() {
        let ids = Fixtures.demoChatThreads.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
            "demo thread IDs must be unique — duplicates collide in InboxViewModel selection state")
    }

    func testDemoChatThreadsAllUseDemoIDPrefix() {
        // The "demo-" prefix is the audit signal `InboxViewModel` uses to
        // distinguish demo rows from real ones (e.g. for `send()` guards).
        // Renaming the prefix is a migration; pin it here.
        for thread in Fixtures.demoChatThreads {
            XCTAssertTrue(thread.id.hasPrefix("demo-"),
                "demo thread \(thread.id) must use 'demo-' id prefix so InboxViewModel can detect demo rows")
        }
    }

    func testDemoChatThreadsCoverMultipleChannels() {
        // Showing only iMessage rows in demo mode misses the multi-channel
        // selling point. Pin coverage to ≥ 2 distinct channels.
        let channels = Set(Fixtures.demoChatThreads.map(\.channel))
        XCTAssertGreaterThanOrEqual(channels.count, 2,
            "demo threads should cover ≥ 2 channels to demonstrate the unified inbox")
    }

    func testAtLeastOneDemoThreadHasUnread() {
        // The unread badge is what pulls the user's eye to the inbox on
        // first launch. An all-read demo set would feel inert.
        let totalUnread = Fixtures.demoChatThreads.reduce(0) { $0 + $1.unread }
        XCTAssertGreaterThan(totalUnread, 0,
            "at least one demo thread must be unread — otherwise the inbox feels inert on first launch")
    }

    func testEveryDemoThreadHasNonEmptyPreview() {
        // Empty preview text would render a blank thread row.
        for thread in Fixtures.demoChatThreads {
            XCTAssertFalse(thread.preview.isEmpty,
                "demo thread \(thread.id) has empty preview — would render as a blank row")
            XCTAssertFalse(thread.name.isEmpty,
                "demo thread \(thread.id) has empty name — would render as a nameless row")
        }
    }

    func testEveryDemoThreadHasNonEmptyTimeLabel() {
        // The relative-time chip is part of the row's affordance hierarchy;
        // an empty time would render a misaligned row.
        for thread in Fixtures.demoChatThreads {
            XCTAssertFalse(thread.time.isEmpty,
                "demo thread \(thread.id) has empty time label — would render misaligned")
        }
    }

    // MARK: - Fixtures.contextSummary

    func testContextSummaryReturnsSeededValueForT1() {
        // ContextCard renders this string verbatim when the user opens the
        // gallery's t1 thread. Pin the seeded ID set so a refactor doesn't
        // silently drop these — the cards would render an empty body.
        XCTAssertNotNil(Fixtures.contextSummary(for: "t1"),
            "t1 must have a seeded contextSummary (rendered in gallery)")
    }

    func testContextSummaryReturnsSeededValueForT3() {
        XCTAssertNotNil(Fixtures.contextSummary(for: "t3"),
            "t3 must have a seeded contextSummary (rendered in gallery)")
    }

    func testContextSummaryReturnsNilForUnknownThread() {
        // Default branch — non-fixture threads (real iMessage syncs)
        // produce nil and ContextCard falls back to its empty state.
        XCTAssertNil(Fixtures.contextSummary(for: "unknown-real-thread-id"),
            "unknown thread must return nil — ContextCard relies on this for its empty state")
    }

    // MARK: - REP-XXX: Sidebar fixtures pin

    /// `Fixtures.folders` and `Fixtures.sidebarChannels` are the sidebar's
    /// empty-state when no real data has loaded — i.e. what every screenshot
    /// in the App Store listing and design handoff is built from. Drift in
    /// labels, order, or channel set silently changes those references.

    func testFoldersOrderMatchesFolderKindAllCases() {
        // Sidebar bucket order is defined by Folder.Kind.allCases; the
        // fixtures must list folders in that exact order or the gallery
        // and the live app render different sidebars.
        XCTAssertEqual(Fixtures.folders.map(\.id), Folder.Kind.allCases,
                       "fixture folder order must match Folder.Kind.allCases — gallery + live render the same sidebar")
    }

    func testFoldersLabelsArePinned() {
        // Labels render in the sidebar — drift would silently change the
        // copy users see on the empty/demo state.
        let labels = Fixtures.folders.reduce(into: [Folder.Kind: String]()) {
            $0[$1.id] = $1.label
        }
        XCTAssertEqual(labels[.all],      "Unified Inbox")
        XCTAssertEqual(labels[.priority], "Priority")
        XCTAssertEqual(labels[.awaiting], "Awaiting reply")
        XCTAssertEqual(labels[.snoozed],  "Snoozed")
        XCTAssertEqual(labels[.done],     "Replied")
    }

    func testFoldersCountsArePositiveOrZero() {
        // Sidebar badges don't render negative counts; pin the invariant
        // before any drift introduces one accidentally.
        for folder in Fixtures.folders {
            XCTAssertGreaterThanOrEqual(folder.count, 0,
                                        "folder counts must be ≥ 0 — sidebar badge can't render negatives")
        }
    }

    func testSidebarChannelsContentAndOrder() {
        // Order defines the icon row in the sidebar's channels group.
        XCTAssertEqual(Fixtures.sidebarChannels,
                       [.imessage, .whatsapp, .slack, .teams, .sms, .telegram],
                       "sidebar channel row order is part of the visual identity — pin verbatim")
    }

    func testSidebarChannelsAreUnique() {
        // A duplicate channel would render two adjacent icons at the same
        // tint — caught at render time but not until then.
        let unique = Set(Fixtures.sidebarChannels)
        XCTAssertEqual(unique.count, Fixtures.sidebarChannels.count,
                       "sidebar channels must be unique — duplicates would render redundant icons")
    }

    // MARK: - genericAcknowledgment per-tone copy pin

    /// `Fixtures.genericAcknowledgment(tone:)` is what the stub LLM returns
    /// for every real (non-fixture) thread. That means every user with iMessage
    /// connected and no MLX model loaded sees this exact copy in the composer.
    /// A silent edit changes the first impression across the entire user base
    /// — pin verbatim so product copy review is forced to acknowledge the change.

    func testGenericAcknowledgmentWarmCopyPinned() {
        XCTAssertEqual(
            Fixtures.genericAcknowledgment(tone: .warm),
            "Thanks for the heads up — I'll circle back on this shortly."
        )
    }

    func testGenericAcknowledgmentDirectCopyPinned() {
        XCTAssertEqual(
            Fixtures.genericAcknowledgment(tone: .direct),
            "got it. back to you in a bit."
        )
    }

    func testGenericAcknowledgmentPlayfulCopyPinned() {
        XCTAssertEqual(
            Fixtures.genericAcknowledgment(tone: .playful),
            "Consider it received. A thoughtful reply is compiling 🙃"
        )
    }

    func testGenericAcknowledgmentToneVoiceShape() {
        // Tone identity invariants — warm starts capitalized + ends with a
        // period; direct is all-lowercase + period; playful is capitalized
        // and includes the 🙃 emoji. Drift in those shapes would erode the
        // tone-distinctness the ⌘/ cycle is meant to communicate.
        let warm    = Fixtures.genericAcknowledgment(tone: .warm)
        let direct  = Fixtures.genericAcknowledgment(tone: .direct)
        let playful = Fixtures.genericAcknowledgment(tone: .playful)

        XCTAssertTrue(warm.first?.isUppercase ?? false,
                      "warm tone leads capitalized")
        XCTAssertTrue(direct.first?.isLowercase ?? false,
                      "direct tone is intentionally lowercase")
        XCTAssertTrue(playful.contains("🙃"),
                      "playful tone keeps the upside-down-smile signature emoji")
    }
}
