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

    // MARK: - Sidebar fixtures pin

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

    /// `Fixtures.sidebarChannels` must enumerate every `Channel.allCases`
    /// case in the same order. The verbatim-array pin above catches edits
    /// to the literal, but it would silently pass if a new Channel case
    /// were added to the enum and someone forgot to update Fixtures —
    /// the new channel just wouldn't render in the sidebar. Pinning the
    /// equality with `Channel.allCases` forces the next channel addition
    /// to either update Fixtures.sidebarChannels or to deliberately edit
    /// this test (acknowledging the divergence).
    func testSidebarChannelsMatchesChannelAllCases() {
        XCTAssertEqual(
            Fixtures.sidebarChannels, Channel.allCases,
            "sidebarChannels must enumerate every Channel.allCases case in the same order — adding a Channel case requires updating Fixtures.sidebarChannels too"
        )
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

    // MARK: - Fixtures.replyCount per-channel pins

    /// Per-channel "Learned from N of your replies" counts surface in the
    /// onboarding voice screen and the privacy receipts. Pinning them keeps
    /// screenshots and copy reviews stable across iterations — a silent
    /// number drift would invalidate every comparison shot.
    func testReplyCountIMessagePinned() {
        XCTAssertEqual(Fixtures.replyCount(for: .imessage), 3_411)
    }

    func testReplyCountSlackPinned() {
        XCTAssertEqual(Fixtures.replyCount(for: .slack), 1_204)
    }

    func testReplyCountWhatsAppPinned() {
        XCTAssertEqual(Fixtures.replyCount(for: .whatsapp), 612)
    }

    func testReplyCountSMSPinned() {
        XCTAssertEqual(Fixtures.replyCount(for: .sms), 221)
    }

    func testReplyCountTeamsPinned() {
        XCTAssertEqual(Fixtures.replyCount(for: .teams), 184)
    }

    func testReplyCountTelegramPinned() {
        XCTAssertEqual(Fixtures.replyCount(for: .telegram), 54)
    }

    // MARK: - Fixtures.seedConfidence per-thread pins

    /// Confidence values gate the cmp-lowconf surface ( <0.4 ⇒ "refuse to
    /// guess" UI ). The exact thread-by-thread pins document the mapping
    /// the design depends on so a fixture refactor can't silently remove a
    /// design state from the gallery.
    func testSeedConfidenceT1PinnedHigh() {
        for tone in Tone.allCases {
            XCTAssertEqual(Fixtures.seedConfidence(threadID: "t1", tone: tone), 0.86, accuracy: 0.0001)
        }
    }

    func testSeedConfidenceT3PinnedHigh() {
        for tone in Tone.allCases {
            XCTAssertEqual(Fixtures.seedConfidence(threadID: "t3", tone: tone), 0.86, accuracy: 0.0001)
        }
    }

    func testSeedConfidenceT4PinnedLow() {
        // SMS verification-code thread — must stay below the 0.4 cmp-lowconf
        // threshold so the "refuse to guess" surface keeps a fixture trigger.
        for tone in Tone.allCases {
            let c = Fixtures.seedConfidence(threadID: "t4", tone: tone)
            XCTAssertEqual(c, 0.32, accuracy: 0.0001)
            XCTAssertLessThan(c, 0.4)
        }
    }

    func testSeedConfidenceUnknownThreadPinnedMid() {
        // Default fallback — between t4's "refuse" threshold and t1/t3's
        // "high context" threshold so the UI defaults to a normal draft.
        for tone in Tone.allCases {
            XCTAssertEqual(Fixtures.seedConfidence(threadID: "unknown-xyz", tone: tone), 0.62, accuracy: 0.0001)
        }
    }

    // MARK: - First-impression demo thread copy pins

    /// `demo-1` is the very first row a brand-new user sees (when no real
    /// channel has data yet). Its preview is the literal first impression
    /// of ReplyAI's keyboard-first promise — drift would silently weaken
    /// the most important onboarding moment.
    func testDemoOneIsReplyAIWelcomeWithKeyboardHint() {
        guard let row = Fixtures.demoChatThreads.first(where: { $0.id == "demo-1" }) else {
            XCTFail("demo-1 must exist as the welcome row"); return
        }
        XCTAssertEqual(row.name, "ReplyAI",
            "demo-1 row name is the brand greeting; pinned so a refactor doesn't accidentally rename it to a real contact")
        XCTAssertEqual(
            row.preview,
            "Welcome — try ⌘K to open the palette, ⌘↵ to send, ⌘J to regenerate.",
            "demo-1 preview is the literal first impression of ReplyAI's keyboard-first promise"
        )
        XCTAssertTrue(row.pinned,
            "demo-1 must be pinned to the top — the welcome row only works as a welcome if it appears first")
        XCTAssertGreaterThan(row.unread, 0,
            "demo-1 must show as unread — the badge is what pulls the eye to the welcome on first launch")
    }

    // MARK: - Curated draft copy pins

    /// `t1` is the gallery's flagship "design review" demo thread; the warm
    /// draft is the App Store screenshot's most-quoted line. Verbatim pins
    /// force product-copy review to acknowledge any rewrite.
    func testFlagshipT1DraftCopyPinned() {
        XCTAssertEqual(
            Fixtures.seedDraft(threadID: "t1", tone: .warm),
            "Yes! Looking at it now — I'll leave inline comments on 4–9 before the meeting."
        )
        XCTAssertEqual(
            Fixtures.seedDraft(threadID: "t1", tone: .direct),
            "On it. Comments incoming on 4–9 before 4."
        )
        XCTAssertEqual(
            Fixtures.seedDraft(threadID: "t1", tone: .playful),
            "Already in the deck pretending to be helpful 🫡 — comments landing soon."
        )
    }

    func testFlagshipT3DraftCopyPinned() {
        XCTAssertEqual(
            Fixtures.seedDraft(threadID: "t3", tone: .warm),
            "Huge — thanks for pushing this through. Loom when you get a sec 🙏"
        )
        XCTAssertEqual(
            Fixtures.seedDraft(threadID: "t3", tone: .direct),
            "Nice. Send the Loom whenever it's ready."
        )
        XCTAssertEqual(
            Fixtures.seedDraft(threadID: "t3", tone: .playful),
            "Billing flow, finally unshackled. Will stare at the Loom lovingly."
        )
    }
}
