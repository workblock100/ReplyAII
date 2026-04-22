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
  - Test count on main increases from 245 (minimum: +8 from RuleContext/RuleEvaluator coverage, +5 from DraftEngine coverage = 258+)
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

### REP-032 — Stats: draft acceptance rate per tone
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Sources/ReplyAI/Services/DraftEngine.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats` tracks `draftsGenerated: Int` and `draftsSent: Int` as aggregate counts. Add `draftsGeneratedByTone: [String: Int]` and `draftsSentByTone: [String: Int]` (using `Tone.rawValue` as key). Increment `draftsGeneratedByTone[tone]` in `DraftEngine.generate(for:tone:)`. Increment `draftsSentByTone[tone]` in `InboxViewModel.send(thread:)` (the active tone at send time). Both must be thread-safe (existing NSLock covers) and JSON-round-trip. Add `acceptanceRate(for tone: Tone) -> Double?` convenience (nil if no drafts generated for that tone). Tests: counters increment correctly per tone, round-trip through JSON, acceptance rate calculation.
- success_criteria:
  - Two new `[String: Int]` fields on `Stats`, persisted to stats.json
  - Correct increment sites in DraftEngine and InboxViewModel
  - `testPerToneCountersIncrement`, `testPerToneCountersRoundTrip`, `testAcceptanceRateCalculation`
  - Existing StatsTests remain green
- test_plan: Extend `StatsTests.swift` with 3 new cases.

### REP-035 — RulesStore: export + import rules via JSON file URL
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/RulesStore.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Add `RulesStore.export(to url: URL) throws` that encodes `rules` as JSON and writes it to `url`. Add `RulesStore.import(from url: URL) throws` that reads + decodes rules from `url` and merges by UUID: existing rules with the same UUID are updated; new UUIDs are appended; nothing is deleted. Import is resilient to malformed entries (same skip logic as REP-024). Tests cover: export round-trips, import merges correctly, import skips malformed entries, import with duplicate UUID updates existing.
- success_criteria:
  - `export(to:)` + `import(from:)` methods on `RulesStore`
  - Merge semantics: update on UUID match, append on new UUID
  - Malformed entries during import are skipped (not thrown)
  - `testExportRoundTrips`, `testImportMergesNewRules`, `testImportUpdatesExistingRule`, `testImportSkipsMalformed`
- test_plan: Use temp-file URLs throughout; no production storage touched.

### REP-037 — ContactsResolver: batch resolution helper for initial sync
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/ContactsResolver.swift`, `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: During initial sync, `InboxViewModel` calls `resolver.name(for:)` once per thread — each call acquires and releases the `Locked<T>` separately. For a 50-thread inbox that's 50 lock acquisitions. Add `resolveAll(handles: [String]) -> [String: String]` that acquires the lock once, resolves all cache hits in-lock, identifies misses, releases, then queries the store for misses, re-acquires to write results. Net: 2 lock acquisitions regardless of inbox size. Tests verify: the result matches serial resolution output, cache hits don't invoke the store, mixed cache-hit/miss scenarios are correct.
- success_criteria:
  - `resolveAll` method on `ContactsResolver`
  - Batch result is identical to serial `name(for:)` calls
  - Store not called for cached handles
  - `testBatchResultMatchesSerial`, `testBatchCacheHitsSkipStore`, `testBatchMixedHitMiss`
- test_plan: Extend `ContactsResolverTests.swift` with 3 new cases.

### REP-038 — MLXDraftService: mocked cancellation + load-progress test coverage
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift` (extend)
- scope: `MLXDraftService` can't be tested with a real 2 GB model, but the stream-contract it adheres to (emit `.loadProgress` chunks before `.text` chunks, support cancellation mid-stream) can be tested by adding mock `LLMService` implementations in the test file. Add two test-only mocks: (1) `LoadProgressThenTextService` — emits N `.loadProgress` chunks then 1 `.text` chunk, then finishes; (2) `CancellableLongService` — emits text slowly (via `Task.sleep`). Tests: `DraftEngine` correctly transitions through `loading → streaming` states when given `LoadProgressThenTextService`; cancellation of a `CancellableLongService` stream transitions to `.idle` without crash. These mocks may already exist in wip branches — if those branches are merged, skip and mark done.
- success_criteria:
  - Both mock services implemented inline in test file (not in Sources/)
  - `testLoadProgressTransitionsState`, `testCancellationTransitionsToIdle`
  - No production code touched
- test_plan: Extend `DraftEngineTests.swift`; mark done if covered by merged wip branches.

### REP-039 — Preferences: pref.drafts.autoPrime toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-111201
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Add `pref.drafts.autoPrime: Bool` (default `true`) to `Preferences`. In `InboxViewModel.selectThread(_:)`, guard the `engine.prime(...)` call behind this preference. When false, the user's first draft is generated only on explicit `⌘J`. This gives power users a way to avoid triggering the LLM on every thread open. Tests: default is true (existing behavior unchanged), false skips prime call.
- success_criteria:
  - `Preferences.autoPrime: Bool` with `@AppStorage` and default true
  - `InboxViewModel` respects the flag
  - `testAutoPrimeTrueCallsPrime`, `testAutoPrimeFalseSkipsPrime`
- test_plan: Extend `PreferencesTests.swift` with default-check; extend InboxViewModelTests with a mock DraftEngine to verify prime call or no-op.

### REP-041 — SearchIndex: persist FTS5 index to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex` uses an in-memory SQLite FTS5 database. Every app launch rebuilds it from `IMessageChannel`. For large inboxes, this rebuild is slow and blocks the first search. Persist the FTS5 database to `~/Library/Application Support/ReplyAI/search.db`. On launch, open the persisted file instead of `:memory:`. Rebuild is still triggered on first launch (if file missing) or explicit settings wipe. Add a `SearchIndex(databaseURL: URL?)` initializer: nil = in-memory (tests), non-nil = file-backed (production). Tests: create an index, insert threads, close, reopen with same URL, verify threads are still searchable.
- success_criteria:
  - `SearchIndex(databaseURL: URL?)` initializer
  - File-backed mode survives close + reopen
  - `testPersistenceAcrossReopens`
  - Existing in-memory tests use `SearchIndex(databaseURL: nil)` — no regressions
- test_plan: Use a temp-file URL in persistence test; tear down in `tearDownWithError`.

### REP-042 — AGENTS.md: update What's done commit log + test count post-wip-merge
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `AGENTS.md`
- scope: After REP-016, REP-017, and REP-048 land (wip branch merges), the `What's done` section in AGENTS.md will again be stale: test count will have grown past 245, and new commits will not be listed. Update: (1) prepend the merged commits to the `What's done` list; (2) update the `N XCTest cases, all green` line; (3) remove any `What's still stubbed` bullets resolved by merged work. Docs-only commit — no code changes. NOTE: planner updated test count to 245 and prepended commits 7667f22–3169995 on 2026-04-22 run5; this task handles the post-wip-merge pass only.
- success_criteria:
  - `What's done` list is current with main branch commits after wip merges
  - Test count matches `grep -r "func test" Tests/ | wc -l` on main at time of commit
  - No stale struck-through stub entries
- test_plan: N/A (docs-only).

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

### REP-053 — InboxViewModel: archive + unarchive thread round-trip tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Once REP-022 landed and `InboxViewModelTests.swift` exists, extend it with archive/unarchive round-trip coverage. `InboxViewModel` stores `archivedThreadIDs` in `Preferences`. Test: archive a thread → `threads` list no longer contains it; unarchive → it reappears; persisted across a simulated relaunch (wipe + re-init of Preferences with suiteName-isolated UserDefaults). Requires the mock channel from REP-022.
- success_criteria:
  - Archive removes thread from visible list
  - Unarchive restores it
  - `archivedThreadIDs` persists in isolated UserDefaults
  - `testArchiveRemovesFromList`, `testUnarchiveRestoresThread`, `testArchivedIDsPersist`
- test_plan: Extend `InboxViewModelTests.swift`; use suiteName-isolated UserDefaults.

### REP-054 — DraftEngine: invalidate stale draft when watcher fires new messages
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: When `ChatDBWatcher` fires and `syncFromIMessage()` merges new incoming messages, any existing draft for the currently selected thread was composed without knowledge of those messages — it's stale context. Add `DraftEngine.invalidate(threadID:)` that sets the `DraftState` back to `.idle` without evicting the cache entry (keeping the entry means a follow-up re-prime can reuse the cache key). In `InboxViewModel.syncFromIMessage()`, after merging, call `engine.invalidate(threadID:)` for any thread that gained new messages AND matches `selectedThreadID`. Tests: new message on selected thread invalidates its draft; new message on non-selected thread does not.
- success_criteria:
  - `DraftEngine.invalidate(threadID:)` resets state to `.idle`
  - `InboxViewModel` calls it on sync for newly-messaged selected thread only
  - `testInvalidateResetsToIdle`, `testInvalidateSkipsNonSelectedThread`
- test_plan: Extend `DraftEngineTests.swift` with 2 new cases.

### REP-058 — RulesStore: lastFiredActions observable for debug surface
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/RulesStore.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: When rules fire, actions are applied silently. A user debugging their rules has no way to know which rules matched. Add `lastFiredActions: [(ruleID: UUID, action: RuleAction)]` to `RulesStore` (non-persisted, in-memory only). `RuleEvaluator.apply(rules:to:)` returns the fired actions; `RulesStore` captures them as `lastFiredActions`, reset to empty on each evaluation batch. The Rules screen can surface this in a future UI pass. Tests: after evaluation with a matching rule, `lastFiredActions` is non-empty with the correct ruleID and action; after a no-match evaluation, it's empty.
- success_criteria:
  - `RulesStore.lastFiredActions` reflects the most recent evaluation batch
  - Populated for matching rules; empty for no-match
  - `testLastFiredActionsPopulatedOnMatch`, `testLastFiredActionsEmptyOnNoMatch`
- test_plan: Extend `RulesTests.swift` with 2 new cases.

### REP-061 — AttributedBodyDecoder: fuzz test with randomized malformed blobs
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/AttributedBodyDecoderTests.swift`
- scope: REP-003 added hand-crafted hex fixtures. Add a property-based fuzz test: generate 10,000 random `Data` blobs of varying length (0 to 4096 bytes, uniform random content) and pass each to `AttributedBodyDecoder.decode`. Assertions: (a) `decode` never throws or traps — it must return nil or a String; (b) any returned String is valid UTF-8. This verifies malformed-input resilience against inputs not covered by hand-crafted fixtures. Use Swift's `SystemRandomNumberGenerator` for seeding.
- success_criteria:
  - 10,000 random blobs processed without crash or throw
  - No invalid UTF-8 in any returned String
  - Test runs in under 10 seconds
  - `testFuzzRandomBlobsNeverCrash`
- test_plan: Single test function in `AttributedBodyDecoderTests.swift`; no new source files needed.

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

### REP-070 — Stats: per-channel messages-indexed counter
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.messagesIndexed` is an aggregate count with no channel breakdown. Add `messagesIndexedByChannel: [String: Int]` (keyed by `Channel.rawValue`). `SearchIndex.upsert(thread:)` already receives the `MessageThread`; call `Stats.shared.incrementIndexed(channel: thread.channel)`. JSON-persisted alongside existing counters. Useful for automation logs to see which channel is driving index growth. Tests: index threads from two channels; verify per-channel counts; JSON round-trip.
- success_criteria:
  - `messagesIndexedByChannel: [String: Int]` on `Stats`, persisted to stats.json
  - `SearchIndex.upsert` calls `Stats.shared.incrementIndexed(channel:)`
  - `testPerChannelCountersIncrement`, `testPerChannelCountersRoundTrip`
  - Existing StatsTests remain green
- test_plan: Extend `StatsTests.swift` with 2 new cases.

### REP-071 — InboxViewModel: thread selection model tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-111201
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModelTests.swift` (added by REP-022) covers the sync guard and rule re-evaluation paths but not the thread selection flow. Add coverage for: `selectThread(_:)` sets `selectedThreadID`; `selectThread` calls `engine.prime(for:tone:)` when `autoPrime` is true; selecting the same thread twice calls prime once (idempotent). Uses a `MockDraftEngine` added inline. Optionally cover `evict` on deselect if REP-034 has landed.
- success_criteria:
  - `testSelectThreadUpdateSelectedID`
  - `testSelectThreadCallsPrime`
  - `testSelectSameThreadTwiceCallsPrimeOnce`
  - No new source files needed (all inline in test file)
- test_plan: Extend `InboxViewModelTests.swift` with 3 new cases using a `MockDraftEngine` stub.

### REP-073 — PromptBuilder: token-count guard to truncate long thread contexts
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder.build(thread:tone:)` concatenates all messages in the thread without any length guard. A thread with 100+ messages could produce a prompt that overflows the model's context window, causing silent truncation or LLM errors. Add `PromptBuilder.truncate(messages:toBudget:)` that trims the oldest messages first until the estimated token count (rough heuristic: `text.utf8.count / 4`) is under a configurable `tokenBudget` (default 2048). Wire it in `build(thread:tone:)`. Expose `tokenBudget: Int` as an injectable parameter for tests. Tests: a thread exceeding the budget is trimmed (oldest messages dropped first); a short thread passes through unchanged; the most-recent message is always preserved.
- success_criteria:
  - `PromptBuilder.truncate(messages:toBudget:)` internal method
  - Long thread prompt fits within budget; short thread is unmodified
  - Most-recent message always present in output
  - `testLongThreadIsTruncated`, `testShortThreadIsUnchanged`, `testMostRecentMessagePreserved`
  - Existing PromptBuilderTests remain green
- test_plan: Extend `PromptBuilderTests.swift` with 3 new cases.

### REP-074 — ContactsResolver: per-handle cache TTL (30 min) for post-launch contact changes
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
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

### REP-080 — SearchIndex: channel TEXT column in FTS5 for per-channel filtered search
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: The FTS5 table currently stores `thread_id TEXT, sender TEXT, preview TEXT`. Add a `channel TEXT` column storing `thread.channel.rawValue`. Update `upsert(thread:)` to include the channel value. Add a `search(query:channel:) -> [String]` overload that appends `AND channel = ?` to the FTS5 WHERE clause when `channel` is non-nil (default nil = no filter). Backwards compatible: the nil overload calls through to the existing unfiltered path. Tests: filter by channel returns only matching threads; nil channel returns all; upserted channel value survives re-query.
- success_criteria:
  - `channel TEXT` column in FTS5 schema
  - `search(query:channel:)` overload with per-channel filtering
  - `testChannelFilterReturnsOnlyMatchingChannel`, `testNilChannelReturnsAll`, `testUpsertedChannelIsPersisted`
  - Existing SearchIndexTests remain green
- test_plan: Extend `SearchIndexTests.swift` with 3 new cases using in-memory FTS5.

### REP-081 — Preferences: pref.rules.autoApplyOnSync toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-22-111201
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Rules currently fire on every `syncFromIMessage()` call. Power users who perform an initial large sync (hundreds of threads) may not want rules auto-applied during that bulk import. Add `pref.rules.autoApplyOnSync: Bool` (default `true`). In `InboxViewModel.syncFromIMessage()`, guard the `RuleEvaluator` call behind this preference. When `false`, rules are only applied when the user manually selects a thread (`selectThread(_:)` path is unaffected). Tests: default is true (existing behavior unchanged); false skips the rules call during sync but not on thread select.
- success_criteria:
  - `Preferences.autoApplyRulesOnSync: Bool` with `@AppStorage` and default true
  - `syncFromIMessage()` respects the flag
  - `testAutoApplyRulesOnSyncDefaultTrue`, `testAutoApplyRulesFalseSkipsRulesOnSync`
  - Existing PreferencesTests remain green
- test_plan: Extend `PreferencesTests.swift` with default-check; extend `InboxViewModelTests.swift` with 2 mock-based cases.

### REP-082 — SmartRule: isEnabled toggle for soft-disabling rules
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Rules/RulesStore.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Add `isEnabled: Bool` (default `true`) to `SmartRule`. `RuleEvaluator.matching(rules:context:)` filters out rules where `isEnabled == false` before evaluating predicates — disabled rules behave as if they don't exist. `RulesStore.toggle(id:)` flips `isEnabled` and persists. JSON-Codable: missing key on older rule files decodes as `true` for backwards compatibility (use `@DecodingDefault.True` or manual decode with fallback). Tests: disabled rule not applied even when predicate would match; enabled rule fires normally; toggle persists across reinit; Codable round-trip with missing key defaults to true.
- success_criteria:
  - `SmartRule.isEnabled: Bool` with backwards-compatible Codable (missing key → true)
  - `RuleEvaluator` skips disabled rules
  - `RulesStore.toggle(id:)` flips and persists
  - `testDisabledRuleNotApplied`, `testEnabledRuleApplied`, `testTogglePersists`, `testMissingKeyDefaultsToEnabled`
  - Existing RulesTests remain green
- test_plan: Extend `RulesTests.swift` with 4 new cases.

### REP-083 — DraftEngine: generation latency tracking in Stats
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats` tracks `draftsGenerated: Int` but has no latency data. Add `totalDraftLatencyMs: Double` to `Stats` (JSON-persisted). In `DraftEngine`, record a `startDate` when a prime/generate call begins streaming and call `Stats.shared.recordDraftLatency(ms:)` when the stream ends (including on error — use `defer`). Add a convenience `averageDraftLatencyMs: Double?` computed property on `Stats` (nil if `draftsGenerated == 0`). Tests: latency accumulates across calls; average is correct; JSON round-trips; error path still records latency via defer.
- success_criteria:
  - `totalDraftLatencyMs: Double` on `Stats`, persisted to stats.json
  - `DraftEngine` calls `recordDraftLatency(ms:)` on stream completion
  - `averageDraftLatencyMs` computed correctly
  - `testLatencyAccumulatesAcrossCalls`, `testAverageDraftLatency`, `testLatencyJSONRoundTrip`
  - Existing StatsTests remain green
- test_plan: Extend `StatsTests.swift` with 3 new cases; use `StubLLMService` with controlled stream duration.

### REP-084 — PromptBuilder: inject user display name from Preferences
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Add `pref.composer.userDisplayName: String?` (default nil) to `Preferences`. When non-nil, `PromptBuilder.build(thread:tone:)` includes `"You are replying as \(name)."` as the first line of the system prompt — giving the LLM voice context. When nil, the system prompt is unchanged. Tests: system prompt includes name when preference is set; prompt is unchanged when nil; Preferences key defaults to nil; wipe removes it.
- success_criteria:
  - `Preferences.userDisplayName: String?` with default nil
  - `PromptBuilder` injects the name when non-nil
  - `testSystemPromptIncludesName`, `testSystemPromptUnchangedWhenNil`
  - `testUserDisplayNameDefaultsNil`, `testUserDisplayNameWipeRemovesKey`
  - Existing PromptBuilderTests remain green
- test_plan: Extend `PromptBuilderTests.swift` and `PreferencesTests.swift` with 2 cases each.

### REP-085 — IMessageChannel: group thread participant list from handle table
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Sources/ReplyAI/Models/MessageThread.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `MessageThread` has no `participants: [String]` field. For group chats, the `chat_handle_join` + `handle` tables expose all participant phone numbers / email addresses. Add `participants: [String]` to `MessageThread` (empty for 1:1 chats is acceptable — contact is the `chatIdentifier`). Update `IMessageChannel.recentThreads` SQL to LEFT JOIN `chat_handle_join` and aggregate handle IDs with `GROUP_CONCAT`. `ContactsResolver.resolveAll` (REP-037, if shipped) can name-resolve them in bulk. Tests: in-memory fixture with 2-participant group → `participants.count == 2`; 1:1 thread → empty or single-element list; handles are raw (resolver called separately).
- success_criteria:
  - `MessageThread.participants: [String]` field added
  - SQL query aggregates participant handles via `GROUP_CONCAT`
  - `testGroupThreadHasParticipants`, `testOneOnOneThreadParticipantsEmpty`
  - Existing IMessageChannelTests remain green
- test_plan: Extend `IMessageChannelTests.swift` with 2 new fixture-based cases using in-memory SQLite.

### REP-086 — SearchIndex: search(query:limit:) overload with result cap
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex.search(query:)` currently returns all matching thread IDs with no cap. For a large inbox the palette could display dozens of results, most irrelevant. Add `search(query:limit: Int?) -> [String]` overload: when `limit` is non-nil, appends `LIMIT ?` to the FTS5 SQL. The existing `search(query:)` calls through with `limit: nil` (no change in behaviour). `PalettePopover` passes `limit: 20` for a snappy UX. Tests: limit=5 on a 10-result corpus returns 5; nil returns all 10; limit=0 returns empty; existing callers unaffected.
- success_criteria:
  - `search(query:limit:)` overload added to `SearchIndex`
  - FTS5 SQL appends `LIMIT ?` when non-nil
  - `testLimitCapsResults`, `testNilLimitReturnsAll`, `testLimitZeroReturnsEmpty`
  - Existing SearchIndexTests remain green
- test_plan: Extend `SearchIndexTests.swift` with 3 new cases.

### REP-087 — AttributedBodyDecoder: extract inline URLs from link attributes
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/AttributedBodyDecoder.swift`, `Tests/ReplyAITests/AttributedBodyDecoderTests.swift`
- scope: iOS iMessage link previews embed the link as an NSAttributedString `.link` attribute alongside the display text. The current typedstream scanner extracts the plain text but discards attribute dictionaries. Add `AttributedBodyDecoder.extractURLs(from data: Data) -> [URL]` that scans the typedstream for NSString keys matching the `NSLink` attribute key and parses adjacent URL string bytes. This complements `IMessagePreview`'s current heuristic `🔗 <host>` sentinel (REP-008) with ground-truth link data for richer previews and more accurate `hasAttachment` logic. Tests: blob with one embedded link → single URL returned; blob with two links → two URLs; blob with no link attributes → empty array; malformed blob → empty array (never nil).
- success_criteria:
  - `AttributedBodyDecoder.extractURLs(from:) -> [URL]` method added
  - Returns correct URLs from synthetic typedstream fixtures
  - Malformed input returns empty array, never crashes
  - `testSingleLinkExtracted`, `testMultipleLinksExtracted`, `testNoLinkAttributeReturnsEmpty`, `testMalformedBlobReturnsEmpty`
  - Existing AttributedBodyDecoderTests remain green
- test_plan: Extend `AttributedBodyDecoderTests.swift` with 4 new hex-fixture cases; document synthetic typedstream byte layout in comments.

### REP-088 — Preferences: pref.inbox.showUnreadOnly toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/PreferencesTests.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Add `pref.inbox.showUnreadOnly: Bool` (default `false`) to `Preferences`. In `InboxViewModel`, compute `visibleThreads` as a filtered view of `threads`: when `showUnreadOnly` is true, include only threads where `unread > 0`; when false, include all threads. Views bind to `visibleThreads` instead of `threads`. Tests: default false shows all threads; true shows only unread; preference persists across reinit; wipe restores false.
- success_criteria:
  - `Preferences.showUnreadOnly: Bool` with default false
  - `InboxViewModel.visibleThreads` respects the flag
  - `testShowUnreadOnlyFiltersThreads`, `testShowAllThreadsWhenFalse`
  - `testShowUnreadOnlyDefaultFalse`, `testShowUnreadOnlyWipeRestoresDefault`
  - Existing PreferencesTests + InboxViewModelTests remain green
- test_plan: Extend `PreferencesTests.swift` with 2 new cases; extend `InboxViewModelTests.swift` with 2 new cases using mock threads with varying unread counts.

### REP-089 — ThreadListView: animated thread-select highlight bar (ui_sensitive)
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/ThreadList/ThreadListView.swift`, `Sources/ReplyAI/Inbox/ThreadList/ThreadRow.swift`
- scope: AGENTS.md priority queue #2: the current selection indicator is a static `Rectangle().fill(isSelected ? accent : .clear)`. Replace with an animated bar using `withAnimation(Theme.Motion.std)` and `matchedGeometryEffect(id: "selection", in: namespace)` so the highlight slides between rows instead of jumping. Respect `@Environment(\.accessibilityReduceMotion)` — skip the crossfade when true, use instant fill change instead. UI-sensitive → worker pushes to `wip/` branch; human reviews animation feel + reduced-motion fallback.
- success_criteria: `wip/` branch with animation; human reviews before merge.
- test_plan: N/A (view animation); human verifies in app that the bar slides smoothly between rows.

### REP-090 — RulesTests: test coverage for or/not composite predicate evaluation
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: The `or([…])` and `not(…)` composite predicates in `RulePredicate` have no dedicated tests on main (the wip/quality-* branches covering these are blocked on human review via REP-017). Add direct test coverage without touching those wip branches: `or([.senderIs("A"), .senderIs("B")])` matches a thread from either sender; `or(…)` with all-false predicates returns false; `not(.senderIs("A"))` matches non-A; `not(.senderIs("A"))` does not match A; nested `or([not(.senderIs("A")), .isGroupChat])` evaluates correctly. No production code changes — tests only.
- success_criteria:
  - `testOrPredicateMatchesEither`
  - `testOrPredicateAllFalseReturnsFalse`
  - `testNotPredicateMatchesOpposite`
  - `testNotPredicateDoesNotMatchSelf`
  - `testNestedOrNotCombination`
  - No new source files; all inline in `RulesTests.swift`
- test_plan: Extend `RulesTests.swift` with 5 new cases; no production code touched.

### REP-091 — Stats: weeklyLog file writer test coverage
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: REP-056 shipped the weekly aggregate log writer in `Stats`, but test coverage targets counter increments rather than the file-writer path. Add tests for: (1) `writeWeeklyLog(to directory:)` creates a file named `stats-YYYY-Www.json` in the given directory; (2) the JSON content includes the expected counter fields (`draftsGenerated`, `draftsSent`, `rulesEvaluated`, `messagesIndexed`); (3) calling `writeWeeklyLog` twice in the same week overwrites rather than appends; (4) `writeWeeklyLog` on a non-existent directory creates it (or fails gracefully — verify current behavior and document). Uses temp-directory injection; no `Stats.shared` global touched.
- success_criteria:
  - `testWeeklyLogFileCreated`
  - `testWeeklyLogContainsExpectedFields`
  - `testWeeklyLogOverwritesSameWeek`
  - `testWeeklyLogHandlesNonExistentDirectory`
  - Existing StatsTests remain green
- test_plan: Extend `StatsTests.swift` with 4 new cases; use a `FileManager`-based temp directory.

---

## Done / archived

*(Planner moves finished items here each day. Worker never modifies this section.)*

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
