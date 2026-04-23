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

### REP-105 — Stats: persist lifetime counters to disk across app launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.shared` resets all in-memory counters to zero on every app launch. Persist cumulative counters to `~/Library/Application Support/ReplyAI/stats-lifetime.json` (separate from the per-session weekly file REP-056 produces). On `Stats.init`, read the JSON file and seed the in-memory counters from it. On each `increment*` call, schedule an atomic write of the updated totals (debounced 2s to avoid write-per-increment overhead). Use an injectable `statsFileURL: URL?` (nil = skip persistence, for tests). Tests: `testLifetimeCountersSeedFromDisk` — init with pre-written JSON, verify counters start at correct value; `testLifetimeCountersAccumulateAcrossInits` — write to disk in first instance, init second instance, verify accumulation; `testNilURLSkipsPersistence` — ensure tests using nil URL never read/write files.
- success_criteria:
  - `Stats(statsFileURL:)` initializer accepting injectable URL
  - In-memory counters seeded from disk on init
  - Atomic write on increment (debounced 2s)
  - `testLifetimeCountersSeedFromDisk`, `testLifetimeCountersAccumulateAcrossInits`, `testNilURLSkipsPersistence`
  - Existing StatsTests remain green (use `nil` URL)
- test_plan: New test cases in `StatsTests.swift` using temp-file URL injection; tear down in `tearDownWithError`.


### REP-111 — InboxViewModel: snooze thread action + resumption
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Models/MessageThread.swift` (or equivalent), `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: The gallery has a `sfc-snooze` screen with a snooze-duration picker. Add the underlying ViewModel action: `snooze(thread: MessageThread, until: Date)`. This sets `thread.snoozedUntil = until`, adds the thread ID to a `snoozedThreadIDs: Set<String>` persisted in Preferences (`pref.inbox.snoozedThreadIDs`), and removes the thread from the `threads` display array. A `Task.sleep(until: date, clock: .continuous)` is started that re-inserts the thread when it wakes. UI that triggers this (the snooze picker view) is ui_sensitive and handled separately. Tests: `testSnoozedThreadHiddenFromList` — snooze a thread, assert it's absent from `threads`; `testSnoozedThreadResurfacesAfterExpiry` — use a mock clock (pass `wakeDate` in the near past) to verify re-insertion; `testSnoozeSetPersistedAcrossInit` — verify `pref.inbox.snoozedThreadIDs` is written.
- success_criteria:
  - `InboxViewModel.snooze(thread:until:)` implemented
  - Snoozed threads hidden from `threads` array
  - Resumption timer re-inserts thread
  - `pref.inbox.snoozedThreadIDs` Preferences key for persistence
  - `testSnoozedThreadHiddenFromList`, `testSnoozedThreadResurfacesAfterExpiry`, `testSnoozeSetPersistedAcrossInit`
- test_plan: Extend `InboxViewModelTests.swift` with 3 new cases; use injected `Date` for deterministic timer tests.




### REP-129 — SmartRule: `threadNameMatchesRegex(pattern:)` predicate
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Screens/Surfaces/SfcRulesView.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: The predicate DSL has `textMatchesRegex(pattern:)` for message body, but no way to match against the thread's display name or sender handle. Add `case threadNameMatchesRegex(pattern: String)` to `RulePredicate`. `RuleContext` gains `threadDisplayName: String` (from `MessageThread.displayName` or equivalent). `RuleEvaluator` evaluates using `NSRegularExpression` with the same validation path as `textMatchesRegex`. `SfcRulesView.humanize(predicate:)` switch gets a new case string. Codable discriminator: `"threadNameMatchesRegex"`. Tests: pattern matching display name matches; non-matching display name doesn't; invalid regex throws at creation time; Codable round-trip preserves pattern.
- success_criteria:
  - `RulePredicate.threadNameMatchesRegex(pattern:)` case added and Codable
  - `RuleContext.threadDisplayName` field populated from thread
  - `RuleEvaluator` evaluates via NSRegularExpression
  - `SfcRulesView` exhaustive switch updated
  - `testThreadNameMatchesRegexWhenMatching`, `testThreadNameMatchesRegexWhenNotMatching`, `testThreadNameInvalidRegexThrows`, `testThreadNameMatchesRegexCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift` in a `ThreadNameMatchesRegexTests` class.


### REP-135 — Stats: sessionStartedAt timestamp and sessionDuration computed field
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: Add `sessionStartedAt: Date` (set in `Stats.init` to `Date()`) and a computed `sessionDuration: TimeInterval` (= `Date().timeIntervalSince(sessionStartedAt)`). Include `sessionDuration` in the weekly log JSON written by `writeWeeklyLog()` alongside existing counters. No disk persistence for this field (it resets per session by design). Injectable `nowProvider: () -> Date` (default `{ Date() }`) for deterministic tests. Tests: `testSessionStartedAtApproximatelyNow` — initialized within 1s of `Date()`; `testSessionDurationIsNonNegative` — computed field ≥ 0; `testSessionDurationIncludesInWeeklyLog` — JSON from `writeWeeklyLog()` contains `"sessionDuration"` key.
- success_criteria:
  - `Stats.sessionStartedAt: Date` set on init
  - `Stats.sessionDuration: TimeInterval` computed property
  - `sessionDuration` included in weekly log JSON
  - `testSessionStartedAtApproximatelyNow`, `testSessionDurationIsNonNegative`, `testSessionDurationIncludesInWeeklyLog`
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using isolated `Stats` instance (nil URL).



### REP-139 — Stats: flushNow() for clean-shutdown counter persistence
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Sources/ReplyAI/App/ReplyAIApp.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: The debounced write added by REP-105 may not fire if the app terminates before the 2s debounce window expires, causing the last session's increments to be lost. Add `Stats.flushNow()` that cancels the pending debounce task and writes current counters to disk synchronously. Wire it to `ReplyAIApp.applicationWillTerminate` (or equivalent scene lifecycle). Tests using injectable URL: increment counter + call `flushNow()` + re-init Stats from same URL → counter reflects all increments; calling `flushNow()` twice is idempotent; `flushNow()` on nil-URL Stats is a no-op.
- success_criteria:
  - `Stats.flushNow()` cancels debounce and writes synchronously
  - Called from app lifecycle shutdown hook
  - `testFlushNowPersistsBeforeDebounce` — re-init reads correct value after flush
  - `testFlushNowIsIdempotent` — two consecutive flushes don't corrupt state
  - `testFlushNowWithNilURLIsNoop` — no crash when URL is nil
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using temp-file URL injection; `tearDownWithError` cleans up.



### REP-142 — InboxViewModel: watcher-driven sync updates existing thread previewText
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: When `ChatDBWatcher` fires, `syncFromIMessage` fetches fresh threads and merges them into `threads`. For a thread already in the inbox, if a new message arrived, its `previewText` and `lastMessageDate` should update in place. Add a test using a mutable mock channel: initially returns thread A with preview "hello"; after sync, mutate the channel to return thread A with "world" as preview; sync again. Assert `threads.first?.previewText == "world"` and thread count is unchanged. Guards the upsert/merge behavior.
- success_criteria:
  - `testSyncUpdatesExistingThreadPreviewText` — re-sync with new preview updates thread in place
  - `testSyncPreservesUnchangedThreadCount` — count does not grow on re-sync of same thread IDs
  - No production code changes expected
- test_plan: 2 new tests in `InboxViewModelTests.swift`; extend the mock channel to support per-call result mutation.




### REP-146 — IMessageChannel: per-thread message cap applied independently across threads
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `IMessageChannel.recentThreads` fetches thread headers, then fetches messages per thread with a per-thread cap. Verify the cap is per-thread, not global: fixture DB with thread A (100 messages), thread B (3 messages), thread C (50 messages), per-thread cap 20. Assert: thread A returns 20, thread B returns 3 (uncapped), thread C returns 20. Total is 43, not 60. Uses the in-memory SQLite fixture pattern.
- success_criteria:
  - `testPerThreadMessageCapAppliedIndependently` — each thread capped at limit; under-limit thread returns full count
  - `testTotalMessageCountRespectsCappedSum` — sum equals min(count, cap) per thread, not a global cap
  - No production code changes expected
- test_plan: 2 new tests in `IMessageChannelTests.swift` using multi-thread in-memory SQLite fixture.


### REP-148 — RuleEvaluator: `apply()` output contract tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RuleEvaluator.apply(rules:to:)` returns `[(ruleID: UUID, action: RuleAction)]` for all matching rules — it's the entry point used by `InboxViewModel` to execute rule side-effects. The `matching()` and `defaultTone()` functions have heavy test coverage, but `apply()` itself is untested. Add 4 test cases using isolated `RuleEvaluator` calls: no matching rules returns empty array; two matching rules return two pairs; pairs are ordered priority-descending; inactive rule excluded from apply output. No production code changes.
- success_criteria:
  - `testApplyReturnsEmptyWhenNoRulesMatch` — no match → empty array
  - `testApplyIncludesAllMatchingRuleIDsAndActions` — 2 matching rules → 2 result pairs
  - `testApplyOrderFollowsPriorityDescending` — higher-priority rule's pair appears first
  - `testApplySkipsInactiveRules` — inactive rule excluded even if predicate matches
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift`; fabricate `SmartRule` + `RuleContext` inline, no `RulesStore` needed.

### REP-149 — Stats: `acceptanceRate(for:)` nil-vs-zero distinction
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.acceptanceRate(for tone:)` returns `nil` when no drafts have been generated for that tone (no data), `0.0` when drafts were generated but none accepted, and a real ratio when both generated and sent. This nil-vs-zero distinction is a product contract — nil means "no stats yet" vs 0% acceptance, and a UI should display these differently. Pin the three states: nil (fresh Stats, no casual drafts); 0.0 (1 casual generated, 0 sent); 0.5 (2 casual generated, 1 sent). No production code changes expected.
- success_criteria:
  - `testAcceptanceRateNilWhenNoDataForTone` — fresh Stats, `acceptanceRate(for: .casual)` is nil
  - `testAcceptanceRateZeroWhenGeneratedButNotSent` — 1 generated, 0 sent → 0.0
  - `testAcceptanceRateRatioWhenPartialAcceptance` — 2 generated, 1 sent → 0.5
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using isolated `Stats` instances (nil URL).

### REP-150 — SearchIndex: `Result` struct fields populated correctly from upsert data
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex.Result` contains `threadID`, `threadName`, `senderName?`, `text`, and `time`. No existing test verifies that each field is populated from the data supplied to `upsert(thread:messages:)` — tests only check `threadID` presence in results. Add tests: upsert a thread with a known name; search for it; assert `Result.threadName == thread.name`. Also pin `senderName` nil when the thread has no contact name. Multiple-thread search returns all matching threads without omissions.
- success_criteria:
  - `testSearchResultThreadNameMatchesUpsertedThread` — `result.threadName` equals the inserted thread name
  - `testSearchResultSenderNameNilWhenNoContact` — `result.senderName` is nil for a thread with no resolved contact
  - `testSearchReturnsAllMatchingThreadIDs` — 3 threads indexed, query matching 2 returns exactly 2 results
  - Existing SearchIndexTests remain green
- test_plan: 3 new tests in `SearchIndexTests.swift` using in-memory `SearchIndex`.

### REP-151 — IMessageChannel: `secondsSinceReferenceDate` autodetect at exact magnitude boundary
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `IMessageChannel.secondsSinceReferenceDate(appleDate:)` autodetects nanoseconds vs seconds by magnitude: if the value exceeds 1_000_000_000_000_000 (1e15), it divides by 1e9; otherwise treats as seconds. Test the boundary: value exactly 1e15 → treated as nanoseconds (1 million seconds → year ~2032); value 999_999_999_999_999 (one below) → treated as seconds (~year 33,000 which is wrong but defines the contract); value 0 → year 2001; value 1 billion → year ~2032 as seconds. Documents the implicit contract so a future magnitude-threshold change is caught.
- success_criteria:
  - `testNanosecondValueAboveBoundaryDividedByBillion` — input > 1e15 produces date ~year 2032
  - `testSecondValueBelowBoundaryPassesThrough` — input < 1e15 treated as seconds
  - `testZeroDateIsReferenceDate` — appleDate=0 → Jan 1 2001
  - Existing IMessageChannelTests remain green
- test_plan: 3 new tests in `IMessageChannelTests.swift`; compare `Date` against known reference epochs using `timeIntervalSince1970`.

### REP-152 — PromptBuilder: all-messages-from-same-sender produces valid prompt
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder.buildPrompt(messages:tone:)` formats each message with a sender role prefix. Edge case: if every message has `from: .me` (user replying to themselves) or every message has `from: .them`, the prompt should still be valid and non-empty — no crash, no assertion failure. Tests: all-`.me` messages → non-empty string; all-`.them` messages → non-empty string. A secondary test pins that the output changes between all-`.me` and all-`.them` inputs (i.e. the author label is actually different in the formatted output).
- success_criteria:
  - `testAllMessagesFromMeProducesValidPrompt` — all `.me` messages → non-empty string, no crash
  - `testAllMessagesFromThemProducesValidPrompt` — all `.them` messages → non-empty string, no crash
  - `testAuthorLabelDiffersBetweenMeAndThem` — prompt differs between all-`.me` and all-`.them` inputs
  - Existing PromptBuilderTests remain green
- test_plan: 3 new tests in `PromptBuilderTests.swift`; fabricate `Message` arrays with fixed `from` values.

### REP-153 — DraftEngine: `invalidate()` on uncached thread is idempotent
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine.invalidate(threadID:)` is called when the watcher fires new messages for a thread — it evicts any in-flight draft so the next prime generates fresh context. If `invalidate` is called for a thread that was never primed (no cache entry), it should be a no-op: no crash, state remains `.idle`, and other cached threads are unaffected. Tests: `invalidate` on a thread with no prior prime → no crash, state `.idle`; `invalidate` on thread A does not affect thread B's `.ready` state. No production code changes expected.
- success_criteria:
  - `testInvalidateUnknownThreadIsNoop` — no crash, state `.idle` for never-primed thread
  - `testInvalidateDoesNotAffectOtherCachedThread` — thread B's `.ready` state unchanged after invalidating thread A
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; use `StubLLMService` to prime thread B to `.ready` before calling `invalidate(threadID: threadA)`.

### REP-154 — RulesStore: `update()` with unknown UUID is a no-op
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore.update(rule:)` patches an existing rule by UUID. Calling it with a UUID not in the store should be a no-op: no crash, no change to rule count, no spurious write to disk. Existing test `testRemoveNonExistentUUIDIsNoOp` covers the `remove` path; the `update` path is unprotected by an equivalent. Tests: store contains 2 rules; call `update()` with a freshly-generated UUID → count stays 2, no crash; call `update()` on an existing rule UUID → rule's fields changed, count stays 2. Validates both the happy path and the guard.
- success_criteria:
  - `testUpdateUnknownUUIDIsNoop` — update unknown UUID → count unchanged, no crash
  - `testUpdateKnownUUIDChangesFields` — update known UUID → rule fields reflect new values
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift`; use isolated `RulesStore` with suiteName-based `UserDefaults`.

### REP-155 — InboxViewModel: re-selecting same thread does not double-prime
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModel.selectThread(_:)` primes a draft via the injected `primeHandler`. Calling it twice with the same thread should invoke the prime handler exactly once, not twice — the second call is a no-op when the thread is already selected. This guards against duplicate draft requests on tap-heavy UI interactions. Tests: set up `InboxViewModel` with a call-counting `primeHandler`; call `selectThread(thread)` twice; assert prime count == 1. Also verify `selectedThread` reflects the correct thread.
- success_criteria:
  - `testReselectSameThreadDoesNotDoublePrime` — prime handler invoked once on double-select
  - `testSelectedThreadIsCorrectAfterDoubleSelect` — `selectedThread` reflects the thread
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; use the existing `StaticMockChannel` + call-counting closure.

### REP-156 — ContactsResolver: `name(for:)` fallback to raw handle when store returns nil
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: `ContactsResolver.name(for handle:)` resolves a contact name; when the underlying store returns nil (handle not in address book), it falls back to the raw handle string as the display name. Pin this fallback contract: given a handle not in the mock store, `name(for:)` returns the handle itself (not nil, not empty). Also test the success path: when the mock store returns "Alice Smith" for "alice@example.com", `name(for:)` returns "Alice Smith". This is the display-name contract the inbox relies on.
- success_criteria:
  - `testNameForHandleFallsBackToHandleWhenNotInStore` — unresolved handle → returns handle string
  - `testNameForHandleReturnsContactNameWhenFound` — resolved handle → returns contact name
  - Existing ContactsResolverTests remain green
- test_plan: 2 new tests in `ContactsResolverTests.swift`; use the existing `MockContactsStore` pattern.

### REP-157 — SmartRule: empty `and([])` evaluates to vacuous true
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulePredicate.or([])` (empty disjunction) already has a test pinning it to `false` (`testOrEmptyArrayReturnsFalse`). The dual case, `RulePredicate.and([])` (empty conjunction), should evaluate to `true` by vacuous truth — no sub-predicates, none can fail. This is mathematically correct and guards against a future refactor that accidentally returns `false` for both empty composites. Also test `not(and([]))` which should be `false`. No production code changes expected.
- success_criteria:
  - `testAndEmptyArrayReturnsTrue` — `and([])` evaluates to `true` regardless of context
  - `testNotAndEmptyReturnsFalse` — `not(and([]))` evaluates to `false`
  - Codable round-trip for `and([])` preserves empty array
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift`; use any `RuleContext`.

### REP-158 — IMessageSender: `chatGUID(for:)` format for 1:1 vs group thread
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: `IMessageSender.chatGUID(for thread:)` returns `thread.chatGUID` verbatim for group chats (where chatGUID is already set by the SQL query), and synthesizes `"iMessage;-;<chatIdentifier>"` for 1:1 threads. This GUID selection is load-bearing — a wrong GUID routes a message to the wrong recipient in AppleScript. Add tests using mock `MessageThread` values: 1:1 thread with `chatGUID: nil`, `id: "alice@example.com"` → `"iMessage;-;alice@example.com"`; group thread with `chatGUID: "iMessage;+;chat123"` → returns GUID verbatim; thread with group-style `chatGUID` → not synthesized. No production code changes.
- success_criteria:
  - `testChatGUIDForOneToOneThreadSynthesized` — nil chatGUID → synthesized `iMessage;-;<id>`
  - `testChatGUIDForGroupThreadUsedVerbatim` — non-nil chatGUID → returned unchanged
  - Existing IMessageSenderTests remain green
- test_plan: 2 new tests in `IMessageSenderTests.swift`; construct `MessageThread` fixtures with controlled `chatGUID` values.

### REP-159 — IMessageChannel: `MessageThread.hasAttachment` from message-level SQL field
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `MessageThread.hasAttachment` is derived from `cache_has_attachments` in the message SQL query. No test verifies the thread-level aggregation: a thread with at least one message where `cache_has_attachments=1` should produce `MessageThread.hasAttachment == true`; a thread with no such messages should produce `false`. Uses the in-memory SQLite fixture pattern. Two tests: one thread with attachment → `hasAttachment: true`; one thread without → `hasAttachment: false`.
- success_criteria:
  - `testThreadHasAttachmentTrueWhenMessageHasAttachment` — at least one attachment message → thread `hasAttachment: true`
  - `testThreadHasAttachmentFalseWhenNoMessages HaveAttachment` — no attachment messages → thread `hasAttachment: false`
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests in `IMessageChannelTests.swift`; use the existing in-memory SQLite fixture helper.

### REP-160 — Stats: concurrent mixed-counter stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: REP-097 added a concurrent `recordDraftGenerated` stress test. A mixed-counter concurrent test is missing: `recordRuleFired`, `recordMessagesIndexed`, and `incrementIndexed` called simultaneously from multiple threads. Using `DispatchQueue.concurrentPerform(iterations: 100)`, fire a mix of all three in each iteration. Assert: no crash; `snapshot().rulesMatchedCount` is ≥ 100 (every iteration increments it once via `recordRuleFired + incrementRulesMatched`); total indexed ≥ 100. Guards the `Locked<T>` coverage across all three counter paths simultaneously.
- success_criteria:
  - `testConcurrentMixedCounterNoCrash` — 100 concurrent mixed calls complete without crash
  - `testConcurrentMixedCountersReachExpectedFloor` — each counter ≥ 100 after completion
  - Existing StatsTests remain green
- test_plan: 2 new tests in `StatsTests.swift`; use isolated `Stats(statsFileURL: nil)`.

### REP-161 — SmartRule: `textMatchesRegex` with anchored patterns (^ and $)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RuleEvaluator` uses `NSRegularExpression` for `textMatchesRegex`. Anchored patterns rely on the evaluator calling `.range(of:options:range:)` (which respects `^` and `$`) rather than `.contains`, which would ignore anchors. Tests: pattern `"^Hello"` matches "Hello world" and does not match "Say Hello"; pattern `"world$"` matches "Hello world" and does not match "world is big". Guards against a future refactor that replaces NSRegularExpression with a `.contains`-style shortcut and silently breaks user rules.
- success_criteria:
  - `testRegexStartAnchorMatchesPrefix` — `"^Hello"` matches "Hello world"
  - `testRegexStartAnchorRejectsNonPrefix` — `"^Hello"` does not match "Say Hello"
  - `testRegexEndAnchorMatchesSuffix` — `"world$"` matches "Hello world"
  - `testRegexEndAnchorRejectsNonSuffix` — `"world$"` does not match "world is big"
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift`; fabricate `RuleContext` with controlled `messageText`.

### REP-162 — IMessageSender: extract GUID validation to per-channel protocol method
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/ChannelService.swift`, `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: `IMessageSender.isValidChatGUID(_:)` is currently iMessage-only (validates the `iMessage;[+-];...` prefix). Reviewer noted this guard will need to widen when SMS or other channels add write capability. Refactor: move `isValidChatGUID` to a `static func validateChatGUID(_ guid: String, for channel: Channel) throws` on `IMessageSender`, and add a comment documenting the extension point for future channels. The iMessage validation logic is unchanged — same regex, same `SenderError.invalidChatGUID` throw. SMS path validates that the GUID matches `SMS;[+-];...` format (not yet enforced since SMS send is not wired, but the structure is ready). Tests: existing `isValidChatGUID` tests migrate to `validateChatGUID(for: .iMessage)`; new test `testSMSGUIDFormatRecognized` verifies the SMS branch doesn't throw for a well-formed SMS GUID; `testWrongChannelGUIDThrows` confirms an iMessage GUID passed with `.slack` channel throws. No behavior change for the iMessage path.
- success_criteria:
  - `IMessageSender.validateChatGUID(_:for:)` replaces `isValidChatGUID(_:)` (existing callers updated)
  - iMessage path: identical validation to prior behavior
  - SMS path: `SMS;[+-];...` passes, everything else throws
  - `testSMSGUIDFormatRecognized` — well-formed SMS GUID passes SMS validation
  - `testWrongChannelGUIDThrows` — iMessage GUID on non-iMessage channel throws
  - All existing `IMessageSenderTests` remain green
- test_plan: Migrate existing chatGUID validation tests to new API; add 2 new cross-channel tests.

### REP-163 — DraftStore: `listStoredDraftIDs()` method + orphan detection test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/DraftStore.swift`, `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: Add `listStoredDraftIDs() -> [String]` to `DraftStore`. It reads the drafts directory and returns the stem of every `.md` file (each stem is a thread ID). Useful for future "your drafts" UI and detecting orphaned entries whose threads have been deleted. Tests: empty store returns `[]`; after saving 3 drafts returns all 3 IDs; after deleting one draft, that ID is absent from the list; listing is order-independent.
- success_criteria:
  - `DraftStore.listStoredDraftIDs() -> [String]` implemented
  - `testListStoredDraftIDsEmpty` — empty store returns `[]`
  - `testListStoredDraftIDsAfterSave` — 3 saved drafts → 3 IDs returned
  - `testListStoredDraftIDsAfterDelete` — deleted draft ID absent from list
  - Existing DraftStoreTests remain green
- test_plan: 3 new tests in `DraftStoreTests.swift` using temp directory URL injection.

### REP-164 — IMessageChannel: per-thread message pagination with `before:` rowID cursor
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `messages(forThreadID:limit:)` currently fetches the N most-recent messages. Add an overload `messages(forThreadID:limit:before:)` where `before: Int64?` is an optional SQLite ROWID cursor. When non-nil the SQL WHERE clause includes `message.ROWID < before`, enabling "load older" pagination. The existing overload delegates to `before: nil` for backward compatibility. Tests: messages returned all have `ROWID < before`; `before: nil` matches current behavior; fewer than limit available returns all; `before` equal to minimum ROWID in DB returns empty.
- success_criteria:
  - `messages(forThreadID:limit:before:)` overload added
  - Existing overload delegates to `before: nil`
  - `testMessagesBeforeCursorFiltersCorrectly` — returned messages have rowID < before
  - `testMessagesPaginationNilCursorMatchesCurrent` — nil cursor identical to legacy call
  - `testMessagesPaginationReturnsAllWhenUnderLimit` — fewer than limit → all returned
  - `testMessagesPaginationAtMinRowIDReturnsEmpty` — before=minROWID → empty
  - Existing IMessageChannelTests remain green
- test_plan: 4 new tests in `IMessageChannelTests.swift` using multi-message in-memory SQLite fixture.

### REP-165 — SearchIndex: `clear()` method to wipe and rebuild
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Add `clear()` to `SearchIndex` that executes `DELETE FROM thread_search` and resets the per-channel indexed-message counter in `Stats` to zero (so the counter reflects actual indexed content after a rebuild). Called when the user wipes preferences or when a schema migration forces a full rebuild. Tests: upsert 3 threads, call `clear()`, search returns empty; upsert again after clear → searchable; concurrent `clear()` + `upsert()` does not crash.
- success_criteria:
  - `SearchIndex.clear()` executes `DELETE FROM thread_search` and resets Stats counter
  - `testClearWipesAllIndexedThreads` — no results after clear
  - `testClearThenUpsertIsSearchable` — re-indexed after clear is findable
  - `testConcurrentClearAndUpsertNoCrash` — concurrent calls complete without crash
  - Existing SearchIndexTests remain green
- test_plan: 3 new tests in `SearchIndexTests.swift` using in-memory `SearchIndex`.

### REP-166 — RuleEvaluator: empty-rules-array edge cases (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: No test covers `RuleEvaluator` with an empty rules array, the trivial boundary case. `matching(rules: [], context:)` should return `[]`; `defaultTone(rules: [], context:)` should return nil; `apply(rules: [], to:)` should return `[]`. All are safe no-ops. No production code changes expected.
- success_criteria:
  - `testMatchingEmptyRulesReturnsEmpty` — `matching([])` → `[]`
  - `testDefaultToneEmptyRulesReturnsNil` — `defaultTone([])` → nil
  - `testApplyEmptyRulesReturnsEmpty` — `apply([], to:)` → `[]`
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift`; fabricate any `RuleContext`.

### REP-167 — Preferences: all AppStorage key strings are distinct (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Duplicate `UserDefaults` key strings silently shadow each other — a future typo (e.g. reusing `"replyai.inbox.threadLimit"` for a new pref) would cause silent data loss. Add a test that explicitly lists all string keys defined in `Preferences` and asserts their uniqueness. The test should enumerate the constants via a hand-maintained array (not reflection) so adding a new key forces the engineer to add it here too. No production code changes.
- success_criteria:
  - `testAllPreferenceKeysAreUnique` — no duplicate key strings in the known-keys array
  - If a new key is added to `Preferences` without updating the test, the test fails at review
  - Existing PreferencesTests remain green
- test_plan: 1 new test in `PreferencesTests.swift`; maintain the key array alongside `Preferences.swift`.

### REP-168 — InboxViewModel: `isSyncing` flag transitions during syncFromIMessage
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModel.syncFromIMessage()` has no observable loading state — the UI has no way to know a sync is in progress (useful for showing a spinner or disabling the sync button). Add `isSyncing: Bool` (default false) that is set to true at the top of `syncFromIMessage` and reset to false in the defer block. Tests: `isSyncing` is true while sync is in progress; `isSyncing` is false after success; `isSyncing` is false after a channel throw.
- success_criteria:
  - `InboxViewModel.isSyncing: Bool` added
  - Set true at sync start, false in defer
  - `testIsSyncingTrueWhileSyncing` — flag is true during a slow sync
  - `testIsSyncingFalseAfterSuccess` — flag reset after normal completion
  - `testIsSyncingFalseAfterError` — flag reset after channel throws
  - Existing InboxViewModelTests remain green
- test_plan: 3 new tests in `InboxViewModelTests.swift`; use a slow-completion mock channel to observe the in-progress state.

### REP-169 — DraftEngine: N-concurrent-thread primes don't leak in-flight tasks (stress test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Prime 10 different thread IDs concurrently from a `DispatchQueue.concurrentPerform` loop using `StubLLMService`. After all primes complete (wait using `waitUntil`), verify that every thread is `.ready` and none are stuck in `.priming`. Guards against a task-leak where a concurrent invalidate+prime race leaves an orphaned `Task` whose completion updates are silently discarded, starving the state machine.
- success_criteria:
  - `testConcurrentPrimesOnDistinctThreadsAllReachReady` — 10 threads, all `.ready` after concurrent prime
  - `testNoPrimingStateLeaksAfterConcurrentPrimes` — no thread stuck in `.priming` after completion
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; use `StubLLMService` with configurable stream delay; `waitUntil` helper.

### REP-170 — SmartRule: `contactGroupMatchesName(groupName:)` predicate
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Channels/ContactsResolver.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Add `case contactGroupMatchesName(groupName: String)` to `RulePredicate`. `RuleContext` gains `contactGroupNames: [String]` (contact group names for the sender's handle, resolved via `CNContactStore.groups(matching:)` in `ContactsResolver`). `RuleEvaluator` evaluates using `context.contactGroupNames.contains { $0.localizedCaseInsensitiveContains(groupName) }`. Codable discriminator: `"contactGroupMatchesName"`. `SfcRulesView.humanize` gets a new case string. Tests: matching group name matches; non-matching group name doesn't; case-insensitive match; Codable round-trip preserves groupName; empty contactGroupNames returns false.
- success_criteria:
  - `RulePredicate.contactGroupMatchesName(groupName:)` case added and Codable
  - `RuleContext.contactGroupNames: [String]` field
  - `RuleEvaluator` case-insensitive contains check
  - `SfcRulesView.humanize` updated
  - `testContactGroupMatchesWhenGroupPresent`, `testContactGroupNoMatchWhenGroupAbsent`, `testContactGroupCaseInsensitive`, `testContactGroupMatchesCodableRoundTrip`, `testContactGroupEmptyGroupsReturnsFalse`
  - Existing RulesTests remain green
- test_plan: 5 new tests in `RulesTests.swift`; mock `contactGroupNames` in `RuleContext` directly without CNContactStore.

### REP-171 — Stats: `snapshot()` dictionary contains all expected counter keys (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.snapshot()` returns a `[String: Any]` summary dictionary used by `writeWeeklyLog()`. No test pins which keys are present. A future rename could silently drop a key and break the weekly log format without a test failure. Add a test asserting that a freshly-initialized Stats instance's snapshot contains all expected top-level keys. Maintain a `knownKeys` array in the test that matches the keys actually written by `snapshot()`.
- success_criteria:
  - `testSnapshotContainsAllExpectedKeys` — snapshot dict has all known key strings
  - If a key is renamed, this test fails; engineer updates both Stats and the test
  - Existing StatsTests remain green
- test_plan: 1 new test in `StatsTests.swift`; use isolated `Stats(statsFileURL: nil)`.

### REP-172 — AttributedBodyDecoder: zero-length and all-zero blobs return nil (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/AttributedBodyDecoderTests.swift`
- scope: `AttributedBodyDecoder.extractText(_:)` returns nil when no 0x2B tag is present. Pin the nil-on-no-tag contract for the two most common edge inputs: empty `Data()` and a 32-byte all-zero blob (a common null/empty DB entry). Both should return nil (not crash, not return empty string). Also test that a 1-byte blob containing only `0x2B` (the tag byte with no following length) returns nil without crashing — malformed minimal input.
- success_criteria:
  - `testEmptyDataReturnsNil` — `extractText(Data())` → nil
  - `testAllZeroBlobReturnsNil` — 32-byte zero blob → nil
  - `testSingleTagByteWithNoPayloadReturnsNil` — `Data([0x2B])` → nil, no crash
  - Existing AttributedBodyDecoderTests remain green
- test_plan: 3 new tests in `AttributedBodyDecoderTests.swift`; fabricate minimal `Data` values inline.

### REP-173 — ChatDBWatcher: repeated stop→reinit cycles complete without crash (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/ChatDBWatcherTests.swift`
- scope: Restart path: deallocate a `ChatDBWatcher`, create a new instance on the same source path, start, stop. Repeat 5 times. Guards against `DispatchSource` retain-cycle accumulation, handle reuse, or double-cancel from the prior watcher's `deinit`. After 5 cycles, the final watcher should fire callbacks correctly (write a test-file timestamp and verify the callback triggers). Uses a temp file URL as the watched path (no real chat.db needed).
- success_criteria:
  - `testFiveStopReinitCyclesNoCrash` — 5 reinit cycles complete without crash or trap
  - `testFinalWatcherAfterCyclesFiresCallback` — 6th instance fires its onChange callback on file touch
  - Existing ChatDBWatcherTests remain green
- test_plan: 2 new tests in `ChatDBWatcherTests.swift`; use `FileManager.default.temporaryDirectory` for the watched path; `tearDownWithError` removes temp file.

### REP-174 — IMessageSender: special-character escaping in AppleScript string construction
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: The AppleScript template embeds the message text inside a quoted string: `send "<text>" to <target>`. If `<text>` contains `"` (unescaped), the AppleScript is syntactically broken; a `
` inside the string may produce a multi-line literal that confuses the `tell` block. Add an `escapeForAppleScript(_:)` helper that escapes `\` → `\`, `"` → `"`, and newlines → `
` (the two-char literal). Apply it to `text` before insertion. Tests (dry-run mode): message with `"hello"` (quotes) produces script containing `"hello"`; message with embedded newline produces `
` literal in script; message with backslash doubles it; emoji string passes unchanged.
- success_criteria:
  - `IMessageSender.escapeForAppleScript(_:) -> String` helper added (internal)
  - Applied to `text` before building the AppleScript string
  - `testDoubleQuoteEscapedInAppleScript` — `"` → `"`
  - `testNewlineEscapedInAppleScript` — newline → `
` literal
  - `testBackslashEscapedInAppleScript` — `\` → `\`
  - `testEmojiPassesThroughUnchanged` — 🐢 emoji in message is not altered
  - Existing IMessageSenderTests remain green
- test_plan: 4 new tests in `IMessageSenderTests.swift`; inspect the generated `scriptSource` string in dry-run mode.

### REP-175 — RulesStore: `import()` merge-not-replace semantics (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-035's `import(from:)` has UUID-keyed merge semantics (update existing UUIDs, append new UUIDs, skip malformed). The existing test `testImportMergesRules` may not cover all three merge outcomes simultaneously. Ensure full coverage: (1) store contains rule A and B; import file contains updated rule A (same UUID, new action) and new rule C (fresh UUID) → result has 3 rules, A's action updated, B unchanged, C appended; (2) import of a file with no new UUIDs and no updated UUIDs produces identical store; (3) import of empty rules array is a no-op. No production code changes.
- success_criteria:
  - `testImportUpdatesExistingAndAppendsNew` — 2-rule store + import with 1 update + 1 new → 3 rules, updated action correct
  - `testImportWithNoChangesIsNoop` — import matching existing UUIDs and actions → store unchanged
  - `testImportEmptyArrayIsNoop` — import `[]` → store count unchanged
  - All import-related RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift`; use suiteName-isolated `RulesStore` and temp URL for export.


---

## Done / archived

### REP-079 — SmartRule: timeOfDay(start:end:) predicate for hour-range matching
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-000050
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: The current predicate DSL has 8 primitive kinds (senderIs, senderUnknown, hasAttachment, isGroupChat, textMatchesRegex, messageAgeOlderThan, hasUnread, and/or/not). Add `case timeOfDay(startHour: Int, endHour: Int)` (0–23, inclusive range, wrap-around for overnight e.g. 22–06). `RuleEvaluator` evaluates against `Calendar.current.component(.hour, from: Date())`. Inject a `DateProvider: () -> Date` for testability (same pattern as `messageAgeOlderThan`). Tests: current hour within range matches; current hour outside range doesn't; wrap-around overnight range (22–06) works correctly; Codable round-trip preserves startHour/endHour.
- success_criteria:
  - `RulePredicate.timeOfDay(startHour:endHour:)` case added and Codable
  - `RuleEvaluator` evaluates with injectable `DateProvider`
  - `testTimeOfDayWithinRangeMatches`, `testTimeOfDayOutsideRangeMismatches`, `testOvernightWrapAround`, `testTimeOfDayCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: Extend `RulesTests.swift` with 4 new cases using an injectable date closure.


### REP-133 — RulesStore: export round-trip covers all currently-shipped predicate kinds
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-000050
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-035 added export/import; REP-110 adds a version wrapper. Neither test exercises the full predicate set — existing tests use a small subset of predicates. Build one `SmartRule` for each currently-shipped predicate kind: `senderIs`, `senderUnknown`, `hasAttachment`, `isGroupChat`, `textMatchesRegex`, `messageAgeOlderThan`, `hasUnread`, plus composite `and`, `or`, `not` wrappers. Export all to a temp JSON URL, import back, assert every rule round-trips with an identical predicate (equality check). This is a Codable regression test: any new predicate kind that breaks the discriminated-union encoder/decoder will fail here.
- success_criteria:
  - `testExportImportRoundTripAllPredicateKinds` — all 8+ predicate kinds survive export/import unmodified
  - Test uses a temp URL; `tearDownWithError` cleans up
  - No production code touched
- test_plan: 1 new test in `RulesTests.swift`; extend if new predicate kinds land (REP-079, REP-129) by adding their cases.



### REP-136 — AGENTS.md: consolidate duplicate test-count lines
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `AGENTS.md`
- scope: AGENTS.md currently has the test count in two places: the repo-layout code fence header (`Tests/ReplyAITests/ NNN tests`) and the Testing expectations section ("NNN XCTest cases, all green."). The reviewer flagged this duplication in the 2026-04-22 22:10 review. Remove the hard-coded number from the Testing expectations section and replace with the live-count instruction: `Run \`grep -r "func test" Tests/ | wc -l\` for the current count`. Update the repo-layout header to the current count (349). Docs-only change — no Swift source touches.
- success_criteria:
  - Repo-layout header updated to current count (349)
  - Testing expectations section uses grep instruction instead of hard-coded number
  - No source files touched
  - Reviewer no longer flags dual test-count lines
- test_plan: N/A (docs-only).


### REP-126 — SearchIndex: file-backed persistence round-trip smoke test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-041 added on-disk FTS5 persistence via `SearchIndex(databaseURL:)`, but the file-backed path only exercises the in-memory path under `swift test`. Add a round-trip test: create a `SearchIndex` with a temp file URL, index 3 threads, destroy the instance, create a new `SearchIndex` from the same URL, verify all 3 threads are still searchable. Use `tearDownWithError` to delete the temp file. Catches schema migration regressions if the FTS5 schema ever changes without a matching migration. No production code changes.
- success_criteria:
  - `testDiskBackedIndexSurvivesReinit` — threads indexed in instance A are findable after instance B opens same URL
  - `testDiskBackedEmptyReinitDoesNotCrash` — opening an existing empty db URL without prior indexing is safe
  - No production code touched
- test_plan: 2 new tests in `SearchIndexTests.swift` using `FileManager.default.temporaryDirectory` for URL injection; `tearDownWithError` removes temp file.

### REP-128 — IMessageSender: chatGUID format pre-flight validation
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: Malformed `chatGUID` values (empty string, wrong service prefix, missing separator) produce opaque `errOSAScriptError` from AppleScript with no useful diagnostic. Add a pre-flight validation in `IMessageSender.send(text:toChatGUID:)` before constructing the AppleScript string: chatGUID must match the pattern `^iMessage;[+-];.+$`. Throw a new `SenderError.invalidChatGUID(String)` if the pattern fails. Tests use the dry-run/injectable `executeHook` seam so no AppleScript is invoked. Tests: valid 1:1 GUID passes; valid group GUID passes; empty string throws `invalidChatGUID`; wrong prefix (e.g. `"SMS;-;4155551234"`) throws; missing separator throws.
- success_criteria:
  - `SenderError.invalidChatGUID(String)` case added to `SenderError`
  - Validation runs before AppleScript construction
  - `testValidOneToOneGUIDPasses`, `testValidGroupGUIDPasses`, `testEmptyGUIDThrowsInvalid`, `testWrongPrefixThrowsInvalid`, `testMissingSeparatorThrowsInvalid`
  - Existing IMessageSenderTests remain green
- test_plan: 5 new tests in `IMessageSenderTests.swift`; no production AppleScript invocations (dry-run mode).

### REP-130 — Preferences: `pref.app.firstLaunchDate` set-once key
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/App/ReplyAIApp.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Companion to `launchCount` (REP-115). Add `pref.app.firstLaunchDate: Date?` (nil = not yet set) to `Preferences`. In `ReplyAIApp.init()`, if `firstLaunchDate == nil`, set it to `Date()` — only ever written once. Key is NOT wiped by `wipe()`. Useful for upgrade banners ("You've been using ReplyAI since…"), feature gating after N days, or analytics. Tests: `testFirstLaunchDateSetOnFirstInit` — nil before first write, then non-nil; `testFirstLaunchDateNotOverwrittenOnSubsequentInit` — calling init again doesn't update the date; `testFirstLaunchDateSurvivesWipe` — date persists after `wipe()`.
- success_criteria:
  - `pref.app.firstLaunchDate: Date?` in `Preferences`
  - Set-once guard in `ReplyAIApp.init()`
  - Key excluded from `wipe()` sweep
  - `testFirstLaunchDateSetOnFirstInit`, `testFirstLaunchDateNotOverwrittenOnSubsequentInit`, `testFirstLaunchDateSurvivesWipe`
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated UserDefaults; use a fresh suite per test to avoid cross-test date pollution.

### REP-134 — InboxViewModel: archive removes thread from SearchIndex (integration test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-063 wired `SearchIndex.delete(threadID:)` through `InboxViewModel.archive(_:)`. There is no integration test that verifies the end-to-end path: archive a thread via the ViewModel, then confirm it is no longer searchable. Add a test using the existing `StaticMockChannel` + an in-memory `SearchIndex`. Index the thread before sync, run `archive(thread:)`, assert `searchIndex.search(query: someKnownTerm)` returns empty. Guards against future refactors accidentally removing the `delete` call.
- success_criteria:
  - `testArchiveRemovesThreadFromSearchIndex` — thread not findable after archive
  - Uses in-memory `SearchIndex` (not a mock) for realistic FTS5 behavior
  - No production code changes
- test_plan: 1 new test in `InboxViewModelTests.swift`; inject `SearchIndex(databaseURL: nil)` into the ViewModel under test.

### REP-137 — PromptBuilder: oversized system instruction guard
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder` enforces a 2000-char message budget by dropping oldest messages first. However, if the tone system instruction itself exceeds the budget (e.g. a user pastes a 3000-char voice description), the current code may produce a prompt that overshoots the budget or silently drops all messages. Add a guard: if the system instruction length ≥ budget, truncate the instruction to `budget - 200` chars (leaving 200 chars minimum for at least the most-recent message). Tests: `testOversizedSystemInstructionTruncatedToFit` — 3000-char instruction + 1 short message produces a prompt ≤ total budget; `testOversizedSystemInstructionPreservesAtLeastOneMessage` — most-recent message still appears in output despite instruction truncation.
- success_criteria:
  - Guard added in `PromptBuilder` for system instruction overflow
  - `testOversizedSystemInstructionTruncatedToFit` — prompt within budget
  - `testOversizedSystemInstructionPreservesAtLeastOneMessage` — at least one message in output
  - Existing PromptBuilderTests remain green (short instructions unaffected)
- test_plan: 2 new tests in `PromptBuilderTests.swift` using a 3000-char fabricated tone instruction.

### REP-138 — DraftEngine: dismiss() deletes corresponding DraftStore entry
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftStore` (REP-066) persists draft text to disk when the engine reaches `.ready`. If the user explicitly dismisses a draft (⌘. → `DraftEngine.dismiss(threadID:tone:)`), the stored file should be deleted so the stale draft does not reappear on the next launch. Add `store?.delete(threadID:)` in the dismiss path (transition to `.idle`). Tests: after prime→ready→dismiss, `DraftStore.read(threadID:)` returns nil; dismiss on a thread with no stored draft is a no-op (no crash); re-prime after dismiss generates a fresh draft and writes a new store entry.
- success_criteria:
  - `DraftEngine.dismiss()` calls `store?.delete(threadID:)` on transition to `.idle`
  - `testDismissClearsStoredDraft` — `DraftStore.read` returns nil after dismiss
  - `testDismissWithNoStoredDraftIsNoop` — no crash when dismissing a thread with no stored draft
  - `testReprimingAfterDismissWritesNewEntry` — fresh draft written after dismiss+prime cycle
  - Existing DraftEngineTests remain green
- test_plan: 3 new tests in `DraftEngineTests.swift` using `DraftStore` with injected temp directory.

### REP-140 — SearchIndex: concurrent upsert+delete interleaving does not corrupt FTS5 state
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-057 added a concurrent search+upsert stress test. A concurrent upsert+delete race for the same `threadID` is not covered. Using `DispatchQueue.concurrentPerform(iterations:)`, fire 10 upserts and 10 deletes of the same thread ID concurrently. After completion, assert: no crash; the index is in a consistent state (thread findable or not — no partial row corruption); `search(query:)` returns `[threadID]` or `[]`, never throws. No production code changes expected (SQLite WAL serialization should handle this).
- success_criteria:
  - `testConcurrentUpsertDeleteNoCrash` — 10 upserts + 10 deletes of same thread complete without crash
  - `testConcurrentUpsertDeleteConsistentState` — post-race search returns array or empty, never throws
  - No production code touched
- test_plan: 2 new tests in `SearchIndexTests.swift`; use in-memory FTS5 (`SearchIndex(databaseURL: nil)`).

### REP-141 — ContactsResolver: batchResolve result has one entry per input handle, including nil
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: `batchResolve([String])` (REP-037) resolves handles via cache then store. Pin the mixed-case result contract: given handles `["alice@example.com", "bob@example.com", "charlie@example.com"]` where alice and charlie are resolvable and bob is not, the result dict must have exactly 3 keys — alice: non-nil, bob: nil, charlie: non-nil. Also verify that cached handles do NOT cause a second store lookup (store call count ≤ number of uncached handles). Catches any result-keyset bugs or extra store hits.
- success_criteria:
  - `testBatchResolveResultKeySetMatchesInputHandles` — result has one key per input handle
  - `testBatchResolveUnresolvableHandleMapsToNil` — unresolvable handle present as nil, not absent
  - `testBatchResolveCacheHitsDoNotInvokeStore` — cached handles bypass store lookup
  - Existing ContactsResolverTests remain green
- test_plan: 3 new tests in `ContactsResolverTests.swift` using mock `ContactsStoring` with call-count tracking.

### REP-143 — RulesStore: `rules` backing array preserves insertion order independent of priority
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore.rules` is the insertion-order backing array. `RuleEvaluator.matching` sorts by priority at evaluation time and must not affect `rules` order. Pin this invariant: adding rule A (priority 0) then rule B (priority 5) results in `rules = [A, B]`, not `[B, A]`. The UI relies on `rules` for creation-order display. Tests: rules appended not inserted by priority; persist+reload preserves file order; `update()` changes fields without reordering.
- success_criteria:
  - `testRulesArrayPreservesInsertionOrder` — lower-priority rule added first stays at `rules[0]`
  - `testLoadFromJSONPreservesFileOrder` — persist+reload order matches original
  - `testUpdateDoesNotReorderRules` — updating a rule's priority does not move it in the array
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift` using isolated `RulesStore` with injectable `UserDefaults`.

### REP-144 — SmartRule: unknown RuleAction `kind` decoded gracefully without crash
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RuleAction` uses a `kind` discriminator. If a future version introduces a new action and an older decoder encounters it, the app should not crash. REP-024 covers malformed-rule skipping at the `RulesStore` level; this task tests the Codable layer directly: decode JSON with `"kind": "unknown_future_action"`, assert a `DecodingError` is thrown (not a trap), and verify `RulesStore.load()` with such a JSON skips the offending rule and loads all remaining rules cleanly. Documents the forward-compatibility contract.
- success_criteria:
  - `testUnknownRuleActionKindThrowsDecodingError` — unknown kind throws `DecodingError`, not crash
  - `testRulesStoreSkipsRuleWithUnknownAction` — load with unknown-action JSON skips that rule, loads rest
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift` using hand-crafted JSON fixtures.

### REP-145 — PromptBuilder: empty message list produces non-empty valid prompt
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder.buildPrompt(messages:tone:)` is always called with at least one message in production, but a newly-created thread or a thread whose messages all failed to load could pass an empty array. Verify: empty messages + a tone → no crash, non-empty prompt string containing the tone instruction. Also pin: single-message input → prompt contains that message body. No production code changes expected.
- success_criteria:
  - `testEmptyMessagesProducesNonEmptyPrompt` — non-empty string returned, no crash
  - `testEmptyMessagesPromptContainsToneInstruction` — returned prompt includes tone text
  - `testSingleMessagePromptContainsMessageText` — single message body appears in output
  - Existing PromptBuilderTests remain green
- test_plan: 3 new tests in `PromptBuilderTests.swift` using fabricated tone and empty/single-element message arrays.

### REP-147 — DraftStore: concurrent write+read for same threadID is race-free
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: `DraftStore.write` and `read` operate on files in a shared directory. Concurrent calls from async `DraftEngine` operations could race. Using `DispatchQueue.concurrentPerform`, fire 10 concurrent writes of different text values and 10 concurrent reads for the same `threadID`. Assert: no crash; after all operations complete, `read(threadID:)` returns a valid non-empty String; the file is not corrupted. No production code changes expected if APFS `write(to:atomically:)` is used.
- success_criteria:
  - `testConcurrentWriteReadNoCrash` — 10 concurrent writes + 10 reads complete without crash
  - `testConcurrentWriteResultIsValid` — post-race read returns a valid string, not nil or garbled
  - No production code touched
- test_plan: 2 new tests in `DraftStoreTests.swift`; injected temp directory; `tearDownWithError` cleans up.


### REP-132 — DraftEngine: rapid regenerate() calls do not spawn parallel LLM streams
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: The concurrent prime guard (REP-049) prevents two simultaneous `prime()` calls. `regenerate()` should exhibit the same serialization: if called while a draft is `.loading`, the second call should cancel the first and start fresh (or be dropped), not run two streams in parallel. Using a `StubLLMService` with a configurable delay, call `regenerate()` for the same `(threadID, tone)` twice in quick succession. Assert the engine reaches exactly one `.ready` state (not two), and the draft counter increments by 1, not 2. Tests the invariant without timing dependencies by using a slow stub.
- success_criteria:
  - `testRapidRegenerateProducesOneDraftState` — final state is `.ready` exactly once
  - `testRapidRegenerateDoesNotDoubleDraftCount` — draft acceptance count not doubled
  - No production code changes if the guard already exists (test confirms invariant); add guard if not
- test_plan: 2 new tests in `DraftEngineTests.swift` using a slow `StubLLMService` with `Task.sleep` before yielding.


### REP-131 — ChatDBWatcher: stop() idempotency test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `Tests/ReplyAITests/ChatDBWatcherTests.swift`
- scope: `ChatDBWatcher.stop()` cancels the DispatchSource. If called twice (e.g. from a `deinit` race with an explicit stop), the second cancel on an already-cancelled source must not crash. Add a test: start a watcher, call `stop()` twice in succession, assert no crash (no `preconditionFailure` or `EXC_BAD_ACCESS`). Additionally, verify the watcher's callback is NOT invoked after the first `stop()` — a spurious callback after cancellation would indicate the source was not cancelled correctly. No production code changes expected.
- success_criteria:
  - `testDoubleStopDoesNotCrash` — calling stop() twice never traps
  - `testCallbackNotFiredAfterStop` — watcher callback is silent after stop()
  - No production code touched
- test_plan: 2 new tests in `ChatDBWatcherTests.swift`; use a temp file as the watched path (existing pattern in that test file).


### REP-127 — DraftEngine: trim leading/trailing whitespace from accumulated LLM stream output
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: LLMs commonly emit drafts with leading newlines (`"\n\nHello"`) or trailing whitespace (`"Hello   \n"`). When the stream accumulator transitions from `.loading` to `.ready(text:)`, apply `.trimmingCharacters(in: .whitespacesAndNewlines)` to the accumulated text before storing. Tests: `StubLLMService` configured to return a draft with leading newlines → state is `.ready("Hello")` not `.ready("\n\nHello")`; trailing whitespace draft → trimmed; whitespace-only draft → `.ready("")` without crash.
- success_criteria:
  - `DraftEngine` trims accumulated text before `.ready` transition
  - `testDraftLeadingNewlinesTrimmed` — leading whitespace removed
  - `testDraftTrailingWhitespaceTrimmed` — trailing whitespace removed
  - `testWhitespaceOnlyDraftReturnsEmptyString` — all-whitespace input yields empty `.ready` without crash
  - Existing DraftEngineTests remain green
- test_plan: 3 new tests in `DraftEngineTests.swift`; extend `StubLLMService` fixture with configurable draft text or add a second stub variant.


*(Planner moves finished items here each day. Worker never modifies this section.)*

### REP-066 — DraftEngine: persist draft edits to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-202900

### REP-115 — Preferences: `pref.app.launchCount` key + increment on startup
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-110 — RulesStore: export format version field for schema evolution
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-108 — ContactsResolver: flush cache on CNContactStoreDidChange notification
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-117 — IMessageChannel: graceful handling of deleted/unsupported messages (NULL text + NULL attributedBody)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-125 — SearchIndex: upsert replaces preview text for existing thread (no ghost terms)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-119 — SearchIndex: `search(query:limit:)` cap to prevent unbounded result sets
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-118 — DraftEngine: evict draft cache entry on thread archive
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-116 — SmartRule: `hasUnread` predicate for unread-thread matching
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-124 — InboxViewModel: pinned threads sort above unpinned threads after sync
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-123 — Stats: rulesMatchedCount ≤ rulesEvaluated invariant test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-122 — IMessageChannel: date autodetect boundary test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-121 — PromptBuilder: truncation preserves most-recent message with large payload
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-120 — RulesStore: concurrent add stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-114 — DraftEngine: LLM error path surfaces in DraftState
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-109 — SearchIndex: channel-filter integration test with two-channel data
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-104 — Preferences: graceful handling of unrecognized UserDefaults keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-103 — InboxViewModel: thread list sorted by recency after sync
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-101 — AGENTS.md: fix stale test-count line in Testing expectations
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-099 — SearchIndex: delete then re-insert round-trip (FTS5 tombstone check)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-098 — DraftEngine: per-(threadID,tone) cache isolation test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-074 — ContactsResolver: per-handle cache TTL (30 min) for post-launch contact changes
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-095 — IMessageChannel: per-thread message-history cap
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-096 — InboxViewModel: send() success/failure state transition tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-097 — Stats: concurrent increment stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-100 — SmartRule: `not` predicate evaluation + double-negation tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-102 — SearchIndex: empty-query returns empty list
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-106 — SmartRule: `messageAgeOlderThan(hours:)` predicate
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-107 — DraftEngine: explicit dismiss() state-transition tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-112 — PromptBuilder: tone system instruction distinctness test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-113 — SmartRule: `or` predicate with 3+ branches evaluation
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-041 — SearchIndex: persist FTS5 index to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-144200

### REP-073 — PromptBuilder: most-recent-message invariant + short-thread passthrough test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-144200

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
