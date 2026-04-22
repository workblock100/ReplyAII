# BACKLOG.md

Prioritized, scoped task list maintained by the planner agent. The hourly worker picks the highest-priority open, non-ui-sensitive task and ships it.

**Format per task:**

```
### REP-NNN — <title>
- priority: P0 | P1 | P2
- effort:   S | M | L
- ui_sensitive: true | false
- status:   open | in_progress | blocked | done
- claimed_by: null | <run-id> | human
- files_to_touch: [list of primary paths]
- scope: 2-4 sentences of what "done" means
- success_criteria:
  - ...
- test_plan: ...
```

---

## P0 — ship-blocking or bug-fix

*(No open P0 items — all resolved. Last P0 closed: REP-003, worker-2026-04-21-173600.)*

---

## P1 — significant value, not urgent

### REP-016 — human: review + merge wip/quality-senderknown-fix
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Branch `wip/quality-2026-04-21-193800-senderknown-fix` (commit d672ab4) contains a real bug fix: operator-precedence in `RuleContext.from(thread:)` caused `&&` to bind tighter than `||`, so emails and digit-only phone numbers were misclassified as known contacts. The consequence is that the `.senderUnknown` rule predicate silently misfired since initial shipping. This is a correctness bug affecting any user who has set up `.senderUnknown` rules. Human should review the fix (it changes production logic), merge if correct, then check whether sibling wip branches' tests still pass with the corrected logic.
- success_criteria:
  - `senderKnown` correctly returns false for raw email addresses (e.g. "user@example.com")
  - `senderKnown` correctly returns false for digit-only phone strings (e.g. "4155551234")
  - `senderKnown` correctly returns true for display names (e.g. "Alice Smith")
  - Existing test suite remains green after merge
- test_plan: The wip branch includes tests covering these cases; human verifies they pass after merge.

### REP-017 — human: consolidate overlapping wip quality branches
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Seven wip/ branches contain overlapping quality-pass test additions. Human should cherry-pick the cleanest, non-duplicating tests into main (or merge the best single branch per subsystem). Priority order: (1) wip/quality-2026-04-21-193800-senderknown-fix (REP-016, do first); (2) best of wip/quality-2026-04-21-212529 or wip/quality-2026-04-21-215030 for RuleContext.from + senderIs/senderUnknown/or coverage; (3) best of wip/quality-2026-04-21-211100 or wip/quality-2026-04-21-213914 for DraftEngine gap coverage. Drop wip/quality-2026-04-21-184250 (superseded by the bug fix branch) and wip/quality-2026-04-21-191222 (log-only commit). REP-048 covers wip/quality-2026-04-21-221100 separately. Close all branches after merge.
- success_criteria:
  - All 6 wip/ branches from this group closed after review (wip/quality-2026-04-21-221100 handled by REP-048)
  - Test count on main increases from 218 (minimum: +8 from RuleContext/RuleEvaluator coverage, +5 from DraftEngine coverage = 231+)
  - No duplicate test functions in merged result
- test_plan: Human runs `grep -r "func test" Tests/ReplyAITests/ | wc -l` before and after to confirm net gain.

### REP-048 — human: review + merge wip/quality-2026-04-21-221100
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Branch `wip/quality-2026-04-21-221100` (commit db4a329) adds DraftEngine test coverage for the error path, stats integration, and `modelLoadStatus` transitions — 115 new test lines. This branch does not overlap with the REP-017 consolidation group (those target RuleEvaluator and early DraftEngine gap coverage). Human should review the test additions, confirm no duplicate function names with any branches merged via REP-017, then merge if clean. Close the branch after merge.
- success_criteria:
  - Branch merged and closed after review
  - Test count on main grows by the number of new `func test` declarations in this branch
  - No duplicate test function names after merge
  - `swift test` all green after merge
- test_plan: Human runs `swift test` after merge to confirm all green.

---

## P2 — stretch / backlog depth

### REP-009 — Global `⌘⇧R` hotkey (needs Accessibility)
- priority: P2
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/GlobalHotkey.swift` (new), `Sources/ReplyAI/App/ReplyAIApp.swift`, `Sources/ReplyAI/Resources/Info.plist`
- scope: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` to catch `⌘⇧R` from anywhere. On match, `openWindow(id: "inbox")`. Needs `NSAccessibilityUsageDescription`. If Accessibility not granted, show a small banner in the inbox with a deep-link to System Settings. UI-sensitive (new banner surface) → branch-only, human merges.
- success_criteria: code lands on `wip/...` branch; human reviews banner copy + placement before merge.
- test_plan: unit-test the key-matching logic (NSEvent parsing of modifier+key tuples).

### REP-010 — Slack OAuth loopback (first non-iMessage channel)
- priority: P2
- effort: L
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/SlackChannel.swift` (new), `Sources/ReplyAI/Channels/Keychain.swift` (new), AGENTS.md
- scope: Build the `SlackChannel: ChannelService` impl. OAuth flow spins up a local `NWListener` on `:4242` during auth only, opens the Slack authorize URL via `NSWorkspace.shared.open`, captures the `code`, exchanges for token via `oauth.v2.access`, stores in Keychain under `ReplyAI-Slack-<workspace>`. `recentThreads` hits `conversations.list` + `conversations.history` with `prefer_socket_events=true`. Socket Mode for real-time comes in a follow-up.
- success_criteria: `wip/` branch — human reviews scope creep, merges when ready.
- test_plan: mock Slack API responses in tests; no real HTTP in CI.

### REP-041 — SearchIndex: persist FTS5 index to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status:   done
- claimed_by: worker-2026-04-22-144200
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex` uses an in-memory SQLite FTS5 database. Every app launch rebuilds it from `IMessageChannel`. For large inboxes, this rebuild is slow and blocks the first search. Persist the FTS5 database to `~/Library/Application Support/ReplyAI/search.db`. On launch, open the persisted file instead of `:memory:`. Rebuild is still triggered on first launch (if file missing) or explicit settings wipe. Add a `SearchIndex(databaseURL: URL?)` initializer: nil = in-memory (tests), non-nil = file-backed (production). Tests: create an index, insert threads, close, reopen with same URL, verify threads are still searchable.
- success_criteria:
  - `SearchIndex(databaseURL: URL?)` initializer
  - File-backed mode survives close + reopen
  - `testPersistenceAcrossReopens`
  - Existing in-memory tests use `SearchIndex(databaseURL: nil)` — no regressions
- test_plan: Use a temp-file URL in persistence test; tear down in `tearDownWithError`.

### REP-043 — InboxViewModel: sync error state + inline error surface
- priority: P2
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Inbox/InboxScreen.swift`, `Sources/ReplyAI/Inbox/FDABanner.swift`
- scope: `syncFromIMessage()` currently swallows errors silently. If FDA is revoked mid-session or chat.db is inaccessible, the thread list silently stops updating. Expose `syncError: Error?` on `InboxViewModel`. In `InboxScreen`, render the existing `FDABanner` when the error is `ChannelError.authorizationDenied`, and a generic "sync paused — tap to retry" banner for other errors. Auto-clear `syncError` on the next successful sync. UI-sensitive → worker pushes to `wip/` branch. Human reviews banner copy + placement.
- success_criteria: `wip/` branch; human reviews error copy before merge.
- test_plan: `testSyncErrorExposedOnViewModel` (non-ui, auto-merge eligible if extracted).

### REP-044 — MenuBarContent: unread-thread count badge on menu-bar icon
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/MenuBar/MenuBarContent.swift`, `Sources/ReplyAI/App/ReplyAIApp.swift`
- scope: The `MenuBarExtra` currently shows just the `R` label. Add an unread-thread count badge (e.g. `Text("R (\(unread))")` or a `ZStack` overlay with a `Circle` + count label). Count comes from `InboxViewModel.threads.filter { $0.unread > 0 }.count`. Hide badge when count is 0. UI-sensitive → worker pushes to `wip/`. Human reviews icon treatment before merge.
- success_criteria: `wip/` branch; human reviews badge design.
- test_plan: N/A (view-only); human verifies dark-mode rendering.

### REP-045 — Stats: surface counters in set-privacy screen
- priority: P2
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Screens/Settings/SetPrivacyView.swift` (or equivalent), `Sources/ReplyAI/Services/Stats.swift`
- scope: The set-privacy screen (sfc-privacy gallery screen) is currently a stub. Wire `Stats.shared` counters into a real view: rules fired (total + by action), drafts generated vs sent, messages indexed. Rows styled to match the existing Settings screen design (plain list, `SectionLabel` headers, `KbdChip` for counts). UI-sensitive → worker pushes to `wip/`. Human reviews copy and layout before merge.
- success_criteria: `wip/` branch; human reviews stats layout.
- test_plan: N/A (view-only with live Stats data).

### REP-046 — InboxViewModel: optimistic send UI state
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Inbox/Composer/ComposerView.swift`
- scope: After `send(thread:)` returns, the composer continues showing the draft until the watcher fires (up to 600ms). Add an optimistic clear: on send success, immediately clear the draft in `InboxViewModel` and show a brief "Sent ✓" state in the composer before the next sync. Use `Task.sleep(for: .seconds(1.5))` then reset to idle. UI-sensitive → `wip/`. Human reviews the "Sent ✓" microcopy and animation timing.
- success_criteria: `wip/` branch; human reviews copy + timing.
- test_plan: Non-ui logic (clear on success, reset after delay) extractable for unit test in InboxViewModelTests.

### REP-047 — Sidebar: relative-time chip auto-tick every 10s
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/Sidebar/SidebarView.swift` (or `ThreadRow.swift`)
- scope: The "live · 12s ago" relative-time chip in the sidebar renders once on thread-select and doesn't update. Add a `Timer.publish(every: 10, on: .main, in: .common).autoconnect()` in the thread row view (or sidebar view model) so the time string refreshes every 10 seconds. Use `@Environment(\.date)` or a published `Date` to drive re-rendering. UI-sensitive → `wip/`. Human reviews the tick frequency and whether it causes observable CPU overhead.
- success_criteria: `wip/` branch; human reviews before merge.
- test_plan: N/A (view timer); human verifies chip auto-updates without scroll jitter.

### REP-062 — human: product-copy pass on IMessagePreview sidebar sentinel strings
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Channels/IMessagePreview.swift`
- scope: When REP-008 shipped the link + attachment preview feature, the worker chose `🔗 <host>` and `📎 Attachment` as the sentinel strings for link and attachment previews in `IMessagePreview`. These glyphs were explicitly flagged by the worker for human review (not asserted as final copy). Human should decide: (1) whether `🔗` and `📎` are the right glyphs vs alternatives (`↗`, `⊞`, `📸`, plain text); (2) whether `"Attachment"` is the right noun vs `"Media"` / `"Photo"` / `"File"`; (3) whether the space before the host name in `🔗 example.com` should be an en-space for visual rhythm. Note: after REP-068 lands, the `📎` sentinel no longer drives rule logic — only display. This is a product-copy decision, not a code question — update the two sentinel constants in `IMessagePreview.swift` once decided.
- success_criteria:
  - `linkPreviewSentinel` and `attachmentPreviewSentinel` constants reflect the decided copy
  - Existing tests updated if the sentinel strings change
  - Reviewer no longer flags this as an open human-review item
- test_plan: Human updates the constants; worker updates the 3 test assertions in `IMessageChannelPreviewTests.swift` that match against the sentinel strings.

### REP-066 — DraftEngine: persist draft edits to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/DraftStore.swift` (new), `Sources/ReplyAI/Services/DraftEngine.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/DraftStoreTests.swift` (new)
- scope: When the user edits a draft but doesn't send, the edited text is discarded on app quit — the next launch regenerates from the LLM. Add a `DraftStore` that writes the draft text to `~/Library/Application Support/ReplyAI/drafts/<threadID>.md` whenever `DraftEngine` transitions to `.ready(text:)`. On next launch, `InboxViewModel.selectThread` pre-populates the composer from `DraftStore` before kicking off the LLM prime. `DraftStore` prunes files older than 7 days on startup. Tests: write a draft, re-init DraftStore, read back the same text; verify 7-day prune removes stale files; verify unknown threadID returns nil.
- success_criteria:
  - `DraftStore.write(threadID:text:)` and `DraftStore.read(threadID:) -> String?` implemented
  - DraftEngine calls write on `.ready` transition
  - InboxViewModel reads store before prime
  - `testDraftPersistsAcrossReinit`, `testStaleDraftsArePruned`, `testUnknownThreadReturnsNil`
- test_plan: `Tests/ReplyAITests/DraftStoreTests.swift` using temp-directory URL injection.

### REP-067 — SearchIndex: FTS5 snippet extraction for search results
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: FTS5's `snippet()` auxiliary function returns a short excerpt of the matching text with terms marked. Currently `SearchIndex.search(query:)` returns `[String]` (thread IDs). Change the return type to `[SearchResult]` where `SearchResult: Equatable { threadID: String, snippet: String? }`. The snippet SQL: `snippet(thread_search, 1, '«', '»', '…', 8)` (column 1 = preview text, 8 token context window). snippet is nil when the query is empty. ⌘K palette can display the snippet as a secondary row under the thread name. Tests: snippet is non-empty for matching query; snippet contains the matched term; empty query returns empty snippets.
- success_criteria:
  - `SearchResult` type with `threadID` and `snippet` fields
  - `search(query:)` returns `[SearchResult]`
  - FTS5 `snippet()` wired with `«»` markers and 8-token window
  - `testSnippetContainsMatchedTerm`, `testSnippetNilOnEmptyQuery`, `testResultTypeIsSearchResult`
  - Existing SearchIndex callers updated (PalettePopover)
- test_plan: Extend `SearchIndexTests.swift` with 3 new cases using in-memory FTS5.

### REP-073 — PromptBuilder: verify most-recent-message invariant + short-thread passthrough test
- priority: P2
- effort: S
- ui_sensitive: false
- status:   done
- claimed_by: worker-2026-04-22-144200
- files_to_touch: `Sources/ReplyAI/Services/PromptBuilder.swift` (access-level change only), `Tests/ReplyAITests/PromptBuilderTests.swift` (extend)
- scope: REP-026 (commit 9717756) already implemented `PromptBuilder.truncate` (private) with a `historyCharBudget = 2_000` constant and shipped `testLongHistoryIsTruncatedToCharBudget`. Two invariants are untested: (1) a short history (well under budget) passes through unchanged — no messages are dropped; (2) when truncation does occur, the most-recent message (last in the array) is always retained, never the first. Change `truncate` visibility from `private` to `internal` so tests can call it directly with a custom budget. Add `testShortHistoryPassesThroughUnchanged` and `testMostRecentMessageAlwaysRetained`. No structural code changes — access-level bump + 2 test cases.
- success_criteria:
  - `PromptBuilder.truncate` is `internal` (not `private`)
  - `testShortHistoryPassesThroughUnchanged` — short history unchanged after truncate
  - `testMostRecentMessageAlwaysRetained` — last message present in any truncated output
  - Existing `testLongHistoryIsTruncatedToCharBudget` still passes
- test_plan: Extend `PromptBuilderTests.swift` with 2 cases using a custom low budget value.

### REP-074 — ContactsResolver: per-handle cache TTL (30 min) for post-launch contact changes
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-150000
- files_to_touch: `Sources/ReplyAI/Channels/ContactsResolver.swift`, `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: The in-memory cache in `ContactsResolver` is never invalidated during an app session. If the user adds a new contact after launch, that handle remains unresolved (displayed as the raw phone number) until the next relaunch. Add a `cachedAt: Date` field alongside each cached resolved name (stored in the existing `Locked<T>` dict). On a cache hit, check if the entry is older than `ttl` (default 30 minutes); if so, treat as a miss and re-query `ContactsStoring`. Expose `ttl: TimeInterval` as an injectable parameter (default `1800`). Tests: a fresh entry is returned from cache without re-query; an entry older than TTL triggers a re-query; TTL=0 always re-queries.
- success_criteria:
  - `ContactsResolver(store:ttl:)` initializer accepting injectable TTL
  - Fresh cache entry skips store; stale entry triggers re-query
  - `testFreshCacheHitSkipsStore`, `testStaleEntryTriggersFetch`, `testZeroTTLAlwaysFetches`
  - Existing ContactsResolverTests remain green
- test_plan: Extend `ContactsResolverTests.swift` with 3 new cases using a mock clock or `Date` injection.

### REP-075 — AttributedBodyDecoder: nested NSMutableAttributedString payload handling
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/AttributedBodyDecoder.swift`, `Tests/ReplyAITests/AttributedBodyDecoderTests.swift`
- scope: AGENTS.md "Better AttributedBodyDecoder" (priority queue item #4) notes that the current 0x2B tag scanner misses nested `NSMutableAttributedString` payloads — common for link previews, app clips, and collaborative iMessage features added in iOS 16+. A nested payload wraps the primary `NSAttributedString` inside another attributed string object graph. Extend the scanner to recognise the class-ref sequence for `NSMutableAttributedString` (byte signature differs from `NSAttributedString`) and recurse into the inner blob's UTF-8 extraction. Add hand-crafted hex fixtures representing the nested case (synthesize a minimal valid typedstream; document the byte layout). Tests: nested payload returns correct inner text; previously-passing single-level payloads remain correct; malformed nested blob returns nil.
- success_criteria:
  - Nested `NSMutableAttributedString` payload decoded correctly
  - `testNestedPayloadExtractsInnerText`
  - `testSingleLevelPayloadUnchanged`
  - `testMalformedNestedPayloadReturnsNil`
  - All existing AttributedBodyDecoderTests remain green
- test_plan: Extend `AttributedBodyDecoderTests.swift` with 3 new hex-fixture cases.

### REP-079 — SmartRule: timeOfDay(start:end:) predicate for hour-range matching
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: The current predicate DSL has 7 primitive kinds (senderIs, senderUnknown, hasAttachment, isGroupChat, textMatchesRegex, and/or/not). Add `case timeOfDay(startHour: Int, endHour: Int)` (0–23, inclusive range, wrap-around for overnight e.g. 22–06). `RuleEvaluator` evaluates against `Calendar.current.component(.hour, from: Date())`. Inject a `DateProvider: () -> Date` for testability. Tests: current hour within range matches; current hour outside range doesn't; wrap-around overnight range (22–06) works correctly; Codable round-trip preserves startHour/endHour.
- success_criteria:
  - `RulePredicate.timeOfDay(startHour:endHour:)` case added and Codable
  - `RuleEvaluator` evaluates with injectable `DateProvider`
  - `testTimeOfDayWithinRangeMatches`, `testTimeOfDayOutsideRangeMismatches`, `testOvernightWrapAround`, `testTimeOfDayCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: Extend `RulesTests.swift` with 4 new cases using an injectable date closure.


### REP-082 — ThreadRow: selection highlight bar animation with matchedGeometryEffect
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/ThreadList/ThreadRow.swift`, `Sources/ReplyAI/Inbox/ThreadList/ThreadListView.swift`
- scope: From AGENTS.md priority queue #2: animate the selected-row accent `Rectangle().fill(isSelected ? accent : .clear)` using `withAnimation(Theme.Motion.std)` and `matchedGeometryEffect` so the highlight slides between rows rather than snapping. The `Namespace` lives in `ThreadListView`; the matched ID is the thread `id`. `ThreadRow` receives `isSelected: Bool` and `animationNamespace: Namespace.ID`. Reduced-motion guard: `ThreadListView` reads `@Environment(\.accessibilityReduceMotion)` and passes a flag to skip the `.matchedGeometryEffect` and use `.animation(nil)` instead. UI-sensitive → worker pushes to `wip/`. Human reviews animation timing and reduced-motion skip before merge.
- success_criteria: `wip/` branch; human reviews animation feel and reduced-motion skip.
- test_plan: N/A (animation, view-only); human verifies no jitter on fast row changes.

### REP-083 — ComposerView + PillToggle: respect accessibilityReduceMotion
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/Composer/ComposerView.swift`, `Sources/ReplyAI/Components/PillToggle.swift`
- scope: From AGENTS.md priority queue #2: read `@Environment(\.accessibilityReduceMotion)` in `ComposerView` and skip the `withAnimation` crossfade on `editableDraft` appear/disappear when true. Read the same in `PillToggle` (used for tone pills) and skip the spring animation on selection change when true. No logic changes — only the animation modifier is conditionalised. UI-sensitive → worker pushes to `wip/`. Human verifies under System Preferences > Accessibility > Reduce Motion.
- success_criteria: `wip/` branch; human verifies animations skip cleanly under Reduce Motion.
- test_plan: N/A (view-only environment flag); no unit test needed.

### REP-095 — IMessageChannel: per-thread message-history cap
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-150000
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `IMessageChannel.recentThreads` fetches all messages for each thread with no upper limit. For threads with hundreds of messages, this burns unnecessary memory and slows the initial sync. Add a `messageLimit: Int = 20` parameter (injectable for tests) to the inner SQL query (`ORDER BY message.date DESC LIMIT :limit`). Return the most recent N messages per thread. Tests: a thread with >20 messages in the fixture returns exactly 20; a thread with <20 messages returns all of them; the returned messages are the most recent (sorted DESC, then reversed to chronological order for display).
- success_criteria:
  - `messageLimit` parameter on the relevant SQL query defaulting to 20
  - `testMessageLimitCapsResults`, `testMessageLimitDoesNotDropShortThreads`, `testMessageLimitPreservesMostRecent`
  - Existing IMessageChannelTests remain green
- test_plan: Extend `IMessageChannelTests.swift` using in-memory SQLite with >20-row fixtures.

### REP-096 — InboxViewModel: send() success/failure state transition tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-150000
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModel.send(thread:)` calls `IMessageSender.send(text:toChatGUID:)` and on success clears the draft via `DraftEngine`. Two critical state transitions are untested: (1) on success, the composer draft is cleared (DraftState → .idle); (2) on failure, the draft text is preserved so the user can retry. Use the injectable `executeHook` on `IMessageSender` (REP-093 pattern) and the mock DraftEngine from existing tests. Tests: `testSendSuccessClearsDraft`, `testSendFailurePreservesDraft`.
- success_criteria:
  - `testSendSuccessClearsDraft` — DraftState is .idle after successful send
  - `testSendFailurePreservesDraft` — draft text unchanged after failed send
  - No production code touched
- test_plan: Extend `InboxViewModelTests.swift` with 2 new cases; use mock channel + dryRunHook pattern.

### REP-097 — Stats: concurrent increment stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats` uses `NSLock` (via `Locked<T>`) to protect all counter mutations. The lock has been correct in review but was never stressed with concurrent callers. Add a test that spawns 200 concurrent Swift `Task`s, each calling `Stats.incrementRulesFired()` once. After all tasks complete (via `TaskGroup`), assert `stats.rulesEvaluated == 200`. If any increment is lost, the count will be under 200. This is a data-race detector test — run with `-sanitize=thread` in CI.
- success_criteria:
  - `testConcurrentIncrementNeverLosesUpdates` asserts final count == 200
  - Test passes with Thread Sanitizer enabled
  - No production code touched
- test_plan: Single test function using `withTaskGroup` in `StatsTests.swift`.

### REP-098 — DraftEngine: per-(threadID,tone) cache isolation test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine` caches drafts keyed by `(threadID, tone)`. The isolation invariant — that priming thread A does not affect thread B, and that tone X does not affect tone Y — is implicit but untested. Add a test that primes two different `(threadID, tone)` pairs with distinct draft texts, then verifies each pair retrieves its own text and the other pair's state is unaffected. Use the existing `StubLLMService` fixture.
- success_criteria:
  - `testCacheIsolationAcrossThreadIDs` — different threadIDs have independent cache entries
  - `testCacheIsolationAcrossTones` — same threadID, different tones have independent entries
  - No production code touched
- test_plan: Extend `DraftEngineTests.swift` with 2 new cases.

### REP-099 — SearchIndex: delete then re-insert round-trip (FTS5 tombstone check)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: FTS5 deletes leave "tombstone" entries that are cleaned up by `optimize` or `rebuild`. If `SearchIndex.delete(threadID:)` is followed by an `upsert` for the same threadID, the re-inserted thread should be fully searchable (no phantom tombstone interference). Add a test: insert thread, verify searchable, delete thread, verify not searchable, re-insert with same threadID but different preview text, verify the new preview text is searchable and the old text is not. Tests the full delete-reinsert lifecycle.
- success_criteria:
  - `testDeleteThenReinsertIsSearchable` — re-inserted thread is found by new preview text
  - `testDeleteThenReinsertOldTextGone` — old preview text no longer returns results
  - No production code touched
- test_plan: Extend `SearchIndexTests.swift` with 2 new cases using in-memory FTS5.

### REP-100 — SmartRule: `not` predicate evaluation + double-negation tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulePredicate.not(inner:)` was added in the DSL but its evaluation path in `RuleEvaluator` is only implicitly tested via the wip branch tests (not yet on main). Add explicit `RuleEvaluator` unit tests: (1) `not(senderIs("Alice"))` returns false when sender is Alice, true otherwise; (2) `not(not(senderIs("Alice")))` double-negation returns the same result as `senderIs("Alice")` — verifying the evaluator doesn't short-circuit; (3) `not` combined with `or` via De Morgan's law equivalence. Tests live in `RulesTests.swift` alongside existing predicate tests.
- success_criteria:
  - `testNotPredicateNegatesMatch`
  - `testDoubleNegationEquivalentToOriginal`
  - `testNotOrDeMorganEquivalence`
  - Existing RulesTests remain green
- test_plan: Extend `RulesTests.swift` with 3 new cases; no production code changes.

### REP-101 — AGENTS.md: fix stale test-count line in Testing expectations
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `AGENTS.md`
- scope: AGENTS.md Testing expectations section still reads "60 tests today. swift test from repo root." — a line that has been stale since the first automation run (now at 290 tests). Replace with the grep command so future readers can get the live count. Also verify the repo-layout header test count is current. Docs-only — no Swift source changes.
- success_criteria:
  - Stale "60 tests today" line replaced with `grep -r "func test" Tests/ | wc -l` instruction
  - Repo-layout header count matches current `grep` output
  - No source files touched
- test_plan: N/A (docs-only).

### REP-102 — SearchIndex: empty-query returns empty list
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-150000
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex.search(query:)` behavior for empty string is unspecified and untested. An empty FTS5 query either returns all rows or raises a SQLite error depending on dialect. Add a test: insert 3 threads, call `search(query: "")`, assert result is empty (not all-rows, not a crash). If the current implementation returns all rows on empty query, update `SearchIndex.search` to guard against it with an early return. The test drives the correct contract.
- success_criteria:
  - `testEmptyQueryReturnsEmptyList` — `search("")` returns `[]`
  - If implementation change required, guard added before the SQLite query
  - Existing search tests remain green
- test_plan: Single test function in `SearchIndexTests.swift`; may require a 1-line guard in `SearchIndex.swift`.

### REP-103 — InboxViewModel: thread list sorted by recency after sync
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModel.threads` should be sorted by most-recent message date (newest first) after a sync. The sort is done inside `syncFromIMessage`, but no test verifies the order. Using the mock channel from existing `InboxViewModelTests`, return 3 threads with different `lastMessageDate` values in non-sorted order, trigger a sync, and assert `viewModel.threads` is sorted newest-first. This catches any regression where the sort is accidentally dropped.
- success_criteria:
  - `testThreadsAreSortedByRecencyAfterSync` passes
  - No production code changes expected (sort should already exist; test confirms it)
- test_plan: Extend `InboxViewModelTests.swift` with 1 new case using mock channel with 3 out-of-order threads.

### REP-104 — Preferences: graceful handling of unrecognized UserDefaults keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift`
- scope: `Preferences.register(defaults:)` writes known keys, and `wipe()` removes them. If a future Preferences version removes a key that was persisted by an older app version, the stale value will sit in UserDefaults indefinitely. Add a test that manually writes an unrecognized key directly to the injectable `UserDefaults` suite, then calls `Preferences.wipe()` and verifies the unrecognized key is NOT removed (wipe is key-specific, not a full reset). Also verify that reading any known Preferences key after wipe returns the registered default, not the stale unrecognized value. Confirms the wipe scope is bounded and doesn't clobber unrelated keys.
- success_criteria:
  - `testWipeDoesNotRemoveUnrecognizedKeys` — unrecognized key survives wipe
  - `testKnownKeyFallsBackToDefaultAfterWipe` — known key returns default after wipe
  - Existing PreferencesTests remain green
- test_plan: Extend `PreferencesTests.swift` with 2 new cases using suiteName-isolated UserDefaults.

---

## Done / archived

*(Planner moves finished items here each day. Worker never modifies this section.)*

### REP-032 — Stats: draft acceptance rate per tone
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120935

### REP-035 — RulesStore: export + import rules via JSON file URL
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-142600

### REP-037 — ContactsResolver: batch resolution helper for initial sync
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-141222

### REP-038 — MLXDraftService: mocked cancellation + load-progress test coverage
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120200

### REP-042 — AGENTS.md: update What's done commit log + test count post-wip-merge
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-142600

### REP-053 — InboxViewModel: archive + unarchive thread round-trip tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-054 — DraftEngine: invalidate stale draft when watcher fires new messages
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-141222

### REP-058 — RulesStore: lastFiredActions observable for debug surface
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120200

### REP-061 — AttributedBodyDecoder: fuzz test with randomized malformed blobs
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-070 — Stats: per-channel messages-indexed counter
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120200

### REP-084 — IMessageChannel: test coverage for NULL message.text + attributedBody fallback path
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-093 — IMessageSender: consolidate isDryRun into executeHook pattern
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-094 — Stats: rulesMatchedCount counter (distinct from rulesEvaluated)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-080 — SearchIndex: channel TEXT column in FTS5 for per-channel filtered search
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-122448

### REP-085 — SearchIndex: prefix-match query support for ⌘K partial-word search
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-122448

### REP-092 — SearchIndex: sanitize FTS5 special-character input
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-122448

### REP-001 — persist `lastSeenRowID` across app launches
- priority: P0
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-172426

### REP-002 — SmartRule priority + conflict resolution
- priority: P0
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-172426

### REP-003 — better AttributedBodyDecoder (real typedstream parser)
- priority: P0
- effort: L
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-173600

### REP-004 — thread-list filter for `silentlyIgnore` action parity
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128

### REP-005 — observability: counters in `.automation/stats.json`
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181957

### REP-006 — IMessageSender: test AppleScript escaping against weird inputs
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128

### REP-007 — ChatDBWatcher test coverage (debounce + cancel)
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182346

### REP-008 — contextual preview: link + attachment detection
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-183617

### REP-011 — ContactsResolver: cache + access-state unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-183251

### REP-012 — RulesStore: remove / update / resetToSeeds test coverage
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128

### REP-013 — Preferences: factory-reset + defaults round-trip tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-183849

### REP-014 — IMessageChannel: SQL query + date-autodetect unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182949

### REP-015 — SearchIndex: incremental upsert path for watcher events
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182615

### REP-018 — SmartRule: isGroupChat + hasAttachment predicates
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-222600

### REP-019 — ContactsResolver: E.164 phone number normalization before cache lookup
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-222600

### REP-020 — IMessageChannel: filter reaction + delivery-status rows from thread preview
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-222600

### REP-021 — IMessageChannel: configurable thread-list pagination
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-223700

### REP-022 — InboxViewModel: concurrent sync guard
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-025439

### REP-023 — InboxViewModel: rule re-evaluation when RulesStore changes
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-043231

### REP-024 — RulesStore: validate + skip malformed rules on load
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-025439

### REP-025 — IMessageSender: AppleScript execution timeout
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-013926

### REP-026 — DraftEngine: extract + test prompt template construction
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055650

### REP-027 — SearchIndex: multi-word AND query support
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-020653

### REP-028 — UNNotification: register inline reply action on launch
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-032627

### REP-029 — IMessageChannel: SQLITE_BUSY graceful retry
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-030 — Preferences: pref.inbox.threadLimit setting
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633

### REP-031 — SmartRule: textMatchesRegex pattern validation at creation time
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633

### REP-033 — SearchIndex: add BM25 ranking tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-034 — DraftEngine: draft cache eviction for idle entries
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-042232

### REP-036 — IMessageChannel: Message.isRead from chat.db is_read column
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-039 — Preferences: pref.drafts.autoPrime toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-111201

### REP-040 — IMessageSender: dry-run mode for test harness
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633

### REP-049 — DraftEngine: concurrent prime guard
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-011918

### REP-050 — Extract `Locked<T>` generic wrapper to consolidate NSLock pattern
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-040356

### REP-051 — IMessageChannel: preserve sqlite3 result code in ChannelError
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-011918

### REP-052 — ChatDBWatcher: FSEvents error recovery with restart backoff
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-041448

### REP-055 — IMessageChannel: map message.date_delivered to Message.deliveredAt
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-056 — Stats: weekly aggregate file writer
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-042232

### REP-057 — SearchIndex: concurrent search + upsert stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-042232

### REP-059 — IMessageSender: retry once on errOSAScriptError (-1708)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-063 — SearchIndex: delete(threadID:) for archived thread cleanup
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

### REP-064 — IMessageSender: 4096-char message length guard
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-065 — RuleEvaluator: senderIs case-insensitive matching
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

### REP-068 — IMessageChannel: project cache_has_attachments to Message.hasAttachment
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

### REP-069 — RulesStore: 100-rule hard cap with graceful rejection
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-071 — InboxViewModel: thread selection model tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-111201

### REP-072 — InboxViewModel: consume pending UNNotification inline reply
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-064413

### REP-076 — InboxViewModel: mark thread as read on selection
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-077 — IMessageChannel: SQLITE_NOTADB graceful error for corrupted chat.db
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-078 — NotificationCoordinator: test coverage for handleNotificationResponse
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-081 — Preferences: pref.rules.autoApplyOnSync toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-111201
