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

### REP-072 — InboxViewModel: consume pending UNNotification inline reply
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/NotificationCoordinator.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-028 registered the `UNTextInputNotificationAction` ("REPLY" category) and wired `NotificationCoordinator` to set `InboxViewModel.pendingNotificationReply`. The consumption side is still stubbed: `InboxViewModel` must observe `pendingNotificationReply`, look up the thread by ID, call `send(text:toChatGUID:)` via `IMessageSender`, then clear the pending reply. Handle the case where the thread is not in the loaded list (log and discard). Tests use a mock sender and verify the round-trip: set `pendingNotificationReply`, trigger observation, assert `IMessageSender.lastSent` received the correct text and GUID.
- success_criteria:
  - `InboxViewModel` observes `pendingNotificationReply` (or equivalent callback) and calls send
  - Sent GUID matches the thread's `chat.guid` (not synthesized)
  - `pendingNotificationReply` is cleared after consumption
  - Unknown threadID is logged and discarded without crash
  - `testNotificationReplyConsumedAndSent`, `testNotificationReplyUnknownThreadDiscarded`
- test_plan: Extend `InboxViewModelTests.swift` with 2 cases using `MockIMessageSender`.

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

### REP-030 — Preferences: pref.inbox.threadLimit setting
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Add `pref.inbox.threadLimit` key to `Preferences` with default value 50 (exposed via `PreferenceDefaults`). `InboxViewModel.syncFromIMessage()` reads this value and passes it to `recentThreads(limit:)` (REP-021 already ships the limit param). For now, just add the key + default + `@AppStorage` binding + a test verifying the default value and wipe behavior.
- success_criteria:
  - `Preferences.inboxThreadLimit: Int` (`@AppStorage`) with default 50
  - `PreferenceDefaults.inboxThreadLimit` constant
  - `wipeReplyAIDefaults` removes the key
  - Test: default is 50, wipe removes it, re-register restores 50
- test_plan: Extend `PreferencesTests.swift` with 2 new cases using suiteName-isolated UserDefaults.

### REP-031 — SmartRule: textMatchesRegex pattern validation at creation time
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulePredicate.textMatchesRegex(String)` silently returns false at evaluation time if the pattern is invalid. A user who typos their regex gets no feedback. Add `SmartRule.validateRegex(_ pattern: String) throws` (internal, testable) that attempts `try NSRegularExpression(pattern: pattern)` and rethrows with a human-readable description. Wire it in `RulesStore.add(_:)` — if the rule has a `.textMatchesRegex` predicate with an invalid pattern, throw before storing. Tests: valid pattern passes, invalid pattern (`[unclosed`) throws, error message includes the pattern, valid rules are unaffected.
- success_criteria:
  - `SmartRule.validateRegex` is internal and tested
  - `RulesStore.add` throws `RuleValidationError.invalidRegex(pattern:reason:)` for bad patterns
  - Valid rules unaffected
  - `testValidRegexPasses`, `testInvalidRegexThrows`, `testErrorMessageContainsPattern`
- test_plan: Extend `RulesTests.swift` with 3 cases.

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
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Add `pref.drafts.autoPrime: Bool` (default `true`) to `Preferences`. In `InboxViewModel.selectThread(_:)`, guard the `engine.prime(...)` call behind this preference. When false, the user's first draft is generated only on explicit `⌘J`. This gives power users a way to avoid triggering the LLM on every thread open. Tests: default is true (existing behavior unchanged), false skips prime call.
- success_criteria:
  - `Preferences.autoPrime: Bool` with `@AppStorage` and default true
  - `InboxViewModel` respects the flag
  - `testAutoPrimeTrueCallsPrime`, `testAutoPrimeFalseSkipsPrime`
- test_plan: Extend `PreferencesTests.swift` with default-check; extend InboxViewModelTests with a mock DraftEngine to verify prime call or no-op.

### REP-040 — IMessageSender: dry-run mode for test harness
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: `IMessageSender.send(text:toChatGUID:)` currently always executes an `NSAppleScript`. Add an injectable `isDryRun: Bool` property (default false). When true, skip the AppleScript call and return immediately with success. This prevents accidental message sends during development and lets integration tests verify the send path without messaging someone. Wire as a test-only convenience — not a user-visible setting. Tests: dry-run returns without error, real path (currently mocked via script interception) still works.
- success_criteria:
  - `isDryRun: Bool` on `IMessageSender`
  - `testDryRunReturnsSuccessWithoutScript`
  - Existing IMessageSenderTests unaffected
- test_plan: Extend `IMessageSenderTests.swift` with 1 new case.

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
- scope: After REP-016, REP-017, and REP-048 land (wip branch merges), the `What's done` section in AGENTS.md will again be stale: test count will have grown past 218, and new commits will not be listed. Update: (1) prepend the merged commits to the `What's done` list; (2) update the `N XCTest cases, all green` line; (3) remove any `What's still stubbed` bullets resolved by merged work. Docs-only commit — no code changes. NOTE: planner updated test count to 218 and prepended commits 90e21f6–a7204d2 on 2026-04-22; this task handles the post-wip-merge pass only.
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

### REP-059 — IMessageSender: retry once on errOSAScriptError (-1708)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: `errOSAScriptError (-1708)` is `errAEEventNotHandled` — Messages.app accepted the send but couldn't dispatch the Apple Event, typically during app startup or iCloud sync. It's transient and distinct from SQLITE_BUSY. Add a single retry: if `NSAppleScript.executeAndReturnError` returns an error with code `-1708`, wait 500ms and retry once. If the retry also fails, surface the original error. Non-retriable error codes fail immediately without retry. Depends on REP-025 (sendTimeout injection) for testability — use a short injected timeout when testing retry path.
- success_criteria:
  - Single retry on error code -1708 only
  - Non-retriable errors fail immediately
  - `testRetriableErrorSucceedsOnSecondAttempt`, `testNonRetriableErrorFailsImmediately`
- test_plan: Extend `IMessageSenderTests.swift` with 2 new mock-based cases.

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

### REP-064 — IMessageSender: 4096-char message length guard
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: AppleScript `tell application "Messages" to send "text"` may fail silently or truncate for very long message strings. Add a pre-flight guard: if the message text exceeds 4096 characters, return `ChannelError.sendFailed("message too long (\(text.count) chars, max 4096)")` before executing the AppleScript. This ensures the user sees a clear error rather than a silent truncation or AppleScript hang. Tests: a 4097-char message returns `sendFailed`; a 4096-char message proceeds to the AppleScript path (or dry-run if REP-040 landed).
- success_criteria:
  - Messages > 4096 chars return `ChannelError.sendFailed` without executing AppleScript
  - Messages ≤ 4096 chars proceed normally
  - `testTooLongMessageReturnsError`, `testExactLimitMessageProceeds`
  - Existing IMessageSenderTests unaffected
- test_plan: Extend `IMessageSenderTests.swift` with 2 new cases; use `isDryRun: true` for the proceed case.

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

### REP-069 — RulesStore: 100-rule hard cap with graceful rejection
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/RulesStore.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore.add()` has no upper bound. With many rules, `RuleEvaluator` scans all rules on every thread select (O(n) per thread × per thread in inbox). Add a 100-rule hard cap: if `rules.count >= maxRules`, `add()` throws `RuleValidationError.tooManyRules`. Expose as `static let maxRules = 100`. This prevents unbounded O(n) growth from programmatic imports (REP-035). Tests: add 100 rules succeeds; adding the 101st throws; `maxRules` constant is 100.
- success_criteria:
  - `RulesStore.maxRules = 100` constant
  - `add()` throws `RuleValidationError.tooManyRules` when at cap
  - `testAddUpToCapSucceeds`, `testAddBeyondCapThrows`
  - Existing RulesTests remain green
- test_plan: Extend `RulesTests.swift` with 2 new cases.

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
- status: open
- claimed_by: null
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

### REP-076 — InboxViewModel: mark thread as read on selection
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `Message.isRead` is now projected from `chat.db` (REP-036). `MessageThread.unread` count is computed from actual `is_read` values. When `InboxViewModel.selectThread(_:)` is called, optimistically mark the selected thread's `unread` count as 0 in the local model — the real `is_read` flip happens in Messages.app when the user reads it; this is UI-only local state. No DB write needed. Tests: select a thread with `unread > 0`, verify the local model shows `unread == 0`; a different thread's unread count is unaffected.
- success_criteria:
  - `selectThread(_:)` sets the selected thread's `unread` to 0 in the local model
  - Other threads' unread counts are unaffected
  - `testSelectMarkThreadRead`, `testSelectDoesNotAffectOtherThreads`
  - Existing InboxViewModelTests remain green
- test_plan: Extend `InboxViewModelTests.swift` with 2 new cases.

### REP-077 — IMessageChannel: SQLITE_NOTADB graceful error for corrupted chat.db
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `SQLITE_NOTADB (26)` is returned by `sqlite3_open_v2` when the file exists but is not a valid SQLite database (rare but possible after a macOS crash during iCloud sync). Currently this falls through as a generic `ChannelError.databaseError`. Add explicit detection: if the result code is `SQLITE_NOTADB`, surface `ChannelError.databaseCorrupted` (a new enum case). This gives `InboxScreen` a hook for a "database corrupted — re-sync from iCloud" recovery path. Tests: mock opener returning `SQLITE_NOTADB` → `databaseCorrupted` error; mock opener returning any other error code → generic `databaseError`.
- success_criteria:
  - `ChannelError.databaseCorrupted` case added
  - `SQLITE_NOTADB` from `dbOpener` produces `.databaseCorrupted`
  - Other error codes produce `.databaseError`
  - `testNotADBProducesDatabaseCorrupted`, `testOtherErrorProducesDatabaseError`
  - Existing IMessageChannelTests remain green
- test_plan: Extend `IMessageChannelTests.swift` with 2 new cases using injectable `dbOpener`.

### REP-078 — NotificationCoordinator: test coverage for handleNotificationResponse
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/NotificationCoordinatorTests.swift` (new)
- scope: REP-028 shipped `NotificationCoordinator` with `UNTextInputNotificationAction` registration, but test coverage is limited to category registration. The `handleNotificationResponse` path — extracting `threadID` from the notification `userInfo`, pulling the reply text from `UNTextInputNotificationResponse.userText`, and setting `InboxViewModel.pendingNotificationReply` — has no tests. Add `NotificationCoordinatorTests.swift`: mock a `UNNotificationResponse` subclass with controlled `userInfo` and text; verify `pendingNotificationReply` is set with the expected `(threadID, text)` tuple; verify an unknown threadID or missing `userInfo` keys result in a no-op (no crash).
- success_criteria:
  - `testHandleResponseSetsPendingReply`
  - `testHandleResponseMissingThreadIDIsNoOp`
  - `testHandleResponseMissingUserTextIsNoOp`
  - New test file `NotificationCoordinatorTests.swift` under `Tests/ReplyAITests/`
- test_plan: Mock `UNNotificationResponse` subclass with synthetic `userInfo`; no real notification infrastructure needed.

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
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Rules currently fire on every `syncFromIMessage()` call. Power users who perform an initial large sync (hundreds of threads) may not want rules auto-applied during that bulk import. Add `pref.rules.autoApplyOnSync: Bool` (default `true`). In `InboxViewModel.syncFromIMessage()`, guard the `RuleEvaluator` call behind this preference. When `false`, rules are only applied when the user manually selects a thread (`selectThread(_:)` path is unaffected). Tests: default is true (existing behavior unchanged); false skips the rules call during sync but not on thread select.
- success_criteria:
  - `Preferences.autoApplyRulesOnSync: Bool` with `@AppStorage` and default true
  - `syncFromIMessage()` respects the flag
  - `testAutoApplyRulesOnSyncDefaultTrue`, `testAutoApplyRulesFalseSkipsRulesOnSync`
  - Existing PreferencesTests remain green
- test_plan: Extend `PreferencesTests.swift` with default-check; extend `InboxViewModelTests.swift` with 2 mock-based cases.

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

### REP-063 — SearchIndex: delete(threadID:) for archived thread cleanup
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

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
