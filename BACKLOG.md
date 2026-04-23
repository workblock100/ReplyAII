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

### REP-066 — DraftEngine: persist draft edits to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-202900
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
- scope: The current predicate DSL has 8 primitive kinds (senderIs, senderUnknown, hasAttachment, isGroupChat, textMatchesRegex, messageAgeOlderThan, hasUnread, and/or/not). Add `case timeOfDay(startHour: Int, endHour: Int)` (0–23, inclusive range, wrap-around for overnight e.g. 22–06). `RuleEvaluator` evaluates against `Calendar.current.component(.hour, from: Date())`. Inject a `DateProvider: () -> Date` for testability (same pattern as `messageAgeOlderThan`). Tests: current hour within range matches; current hour outside range doesn't; wrap-around overnight range (22–06) works correctly; Codable round-trip preserves startHour/endHour.
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


### REP-126 — SearchIndex: file-backed persistence round-trip smoke test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-041 added on-disk FTS5 persistence via `SearchIndex(databaseURL:)`, but the file-backed path only exercises the in-memory path under `swift test`. Add a round-trip test: create a `SearchIndex` with a temp file URL, index 3 threads, destroy the instance, create a new `SearchIndex` from the same URL, verify all 3 threads are still searchable. Use `tearDownWithError` to delete the temp file. Catches schema migration regressions if the FTS5 schema ever changes without a matching migration. No production code changes.
- success_criteria:
  - `testDiskBackedIndexSurvivesReinit` — threads indexed in instance A are findable after instance B opens same URL
  - `testDiskBackedEmptyReinitDoesNotCrash` — opening an existing empty db URL without prior indexing is safe
  - No production code touched
- test_plan: 2 new tests in `SearchIndexTests.swift` using `FileManager.default.temporaryDirectory` for URL injection; `tearDownWithError` removes temp file.

### REP-127 — DraftEngine: trim leading/trailing whitespace from accumulated LLM stream output
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: LLMs commonly emit drafts with leading newlines (`"\n\nHello"`) or trailing whitespace (`"Hello   \n"`). When the stream accumulator transitions from `.loading` to `.ready(text:)`, apply `.trimmingCharacters(in: .whitespacesAndNewlines)` to the accumulated text before storing. Tests: `StubLLMService` configured to return a draft with leading newlines → state is `.ready("Hello")` not `.ready("\n\nHello")`; trailing whitespace draft → trimmed; whitespace-only draft → `.ready("")` without crash.
- success_criteria:
  - `DraftEngine` trims accumulated text before `.ready` transition
  - `testDraftLeadingNewlinesTrimmed` — leading whitespace removed
  - `testDraftTrailingWhitespaceTrimmed` — trailing whitespace removed
  - `testWhitespaceOnlyDraftReturnsEmptyString` — all-whitespace input yields empty `.ready` without crash
  - Existing DraftEngineTests remain green
- test_plan: 3 new tests in `DraftEngineTests.swift`; extend `StubLLMService` fixture with configurable draft text or add a second stub variant.

### REP-128 — IMessageSender: chatGUID format pre-flight validation
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: Malformed `chatGUID` values (empty string, wrong service prefix, missing separator) produce opaque `errOSAScriptError` from AppleScript with no useful diagnostic. Add a pre-flight validation in `IMessageSender.send(text:toChatGUID:)` before constructing the AppleScript string: chatGUID must match the pattern `^iMessage;[+-];.+$`. Throw a new `SenderError.invalidChatGUID(String)` if the pattern fails. Tests use the dry-run/injectable `executeHook` seam so no AppleScript is invoked. Tests: valid 1:1 GUID passes; valid group GUID passes; empty string throws `invalidChatGUID`; wrong prefix (e.g. `"SMS;-;4155551234"`) throws; missing separator throws.
- success_criteria:
  - `SenderError.invalidChatGUID(String)` case added to `SenderError`
  - Validation runs before AppleScript construction
  - `testValidOneToOneGUIDPasses`, `testValidGroupGUIDPasses`, `testEmptyGUIDThrowsInvalid`, `testWrongPrefixThrowsInvalid`, `testMissingSeparatorThrowsInvalid`
  - Existing IMessageSenderTests remain green
- test_plan: 5 new tests in `IMessageSenderTests.swift`; no production AppleScript invocations (dry-run mode).

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

### REP-130 — Preferences: `pref.app.firstLaunchDate` set-once key
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/App/ReplyAIApp.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Companion to `launchCount` (REP-115). Add `pref.app.firstLaunchDate: Date?` (nil = not yet set) to `Preferences`. In `ReplyAIApp.init()`, if `firstLaunchDate == nil`, set it to `Date()` — only ever written once. Key is NOT wiped by `wipe()`. Useful for upgrade banners ("You've been using ReplyAI since…"), feature gating after N days, or analytics. Tests: `testFirstLaunchDateSetOnFirstInit` — nil before first write, then non-nil; `testFirstLaunchDateNotOverwrittenOnSubsequentInit` — calling init again doesn't update the date; `testFirstLaunchDateSurvivesWipe` — date persists after `wipe()`.
- success_criteria:
  - `pref.app.firstLaunchDate: Date?` in `Preferences`
  - Set-once guard in `ReplyAIApp.init()`
  - Key excluded from `wipe()` sweep
  - `testFirstLaunchDateSetOnFirstInit`, `testFirstLaunchDateNotOverwrittenOnSubsequentInit`, `testFirstLaunchDateSurvivesWipe`
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated UserDefaults; use a fresh suite per test to avoid cross-test date pollution.

### REP-131 — ChatDBWatcher: stop() idempotency test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/ChatDBWatcherTests.swift`
- scope: `ChatDBWatcher.stop()` cancels the DispatchSource. If called twice (e.g. from a `deinit` race with an explicit stop), the second cancel on an already-cancelled source must not crash. Add a test: start a watcher, call `stop()` twice in succession, assert no crash (no `preconditionFailure` or `EXC_BAD_ACCESS`). Additionally, verify the watcher's callback is NOT invoked after the first `stop()` — a spurious callback after cancellation would indicate the source was not cancelled correctly. No production code changes expected.
- success_criteria:
  - `testDoubleStopDoesNotCrash` — calling stop() twice never traps
  - `testCallbackNotFiredAfterStop` — watcher callback is silent after stop()
  - No production code touched
- test_plan: 2 new tests in `ChatDBWatcherTests.swift`; use a temp file as the watched path (existing pattern in that test file).

### REP-132 — DraftEngine: rapid regenerate() calls do not spawn parallel LLM streams
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: The concurrent prime guard (REP-049) prevents two simultaneous `prime()` calls. `regenerate()` should exhibit the same serialization: if called while a draft is `.loading`, the second call should cancel the first and start fresh (or be dropped), not run two streams in parallel. Using a `StubLLMService` with a configurable delay, call `regenerate()` for the same `(threadID, tone)` twice in quick succession. Assert the engine reaches exactly one `.ready` state (not two), and the draft counter increments by 1, not 2. Tests the invariant without timing dependencies by using a slow stub.
- success_criteria:
  - `testRapidRegenerateProducesOneDraftState` — final state is `.ready` exactly once
  - `testRapidRegenerateDoesNotDoubleDraftCount` — draft acceptance count not doubled
  - No production code changes if the guard already exists (test confirms invariant); add guard if not
- test_plan: 2 new tests in `DraftEngineTests.swift` using a slow `StubLLMService` with `Task.sleep` before yielding.

### REP-133 — RulesStore: export round-trip covers all currently-shipped predicate kinds
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-035 added export/import; REP-110 adds a version wrapper. Neither test exercises the full predicate set — existing tests use a small subset of predicates. Build one `SmartRule` for each currently-shipped predicate kind: `senderIs`, `senderUnknown`, `hasAttachment`, `isGroupChat`, `textMatchesRegex`, `messageAgeOlderThan`, `hasUnread`, plus composite `and`, `or`, `not` wrappers. Export all to a temp JSON URL, import back, assert every rule round-trips with an identical predicate (equality check). This is a Codable regression test: any new predicate kind that breaks the discriminated-union encoder/decoder will fail here.
- success_criteria:
  - `testExportImportRoundTripAllPredicateKinds` — all 8+ predicate kinds survive export/import unmodified
  - Test uses a temp URL; `tearDownWithError` cleans up
  - No production code touched
- test_plan: 1 new test in `RulesTests.swift`; extend if new predicate kinds land (REP-079, REP-129) by adding their cases.

### REP-134 — InboxViewModel: archive removes thread from SearchIndex (integration test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-063 wired `SearchIndex.delete(threadID:)` through `InboxViewModel.archive(_:)`. There is no integration test that verifies the end-to-end path: archive a thread via the ViewModel, then confirm it is no longer searchable. Add a test using the existing `StaticMockChannel` + an in-memory `SearchIndex`. Index the thread before sync, run `archive(thread:)`, assert `searchIndex.search(query: someKnownTerm)` returns empty. Guards against future refactors accidentally removing the `delete` call.
- success_criteria:
  - `testArchiveRemovesThreadFromSearchIndex` — thread not findable after archive
  - Uses in-memory `SearchIndex` (not a mock) for realistic FTS5 behavior
  - No production code changes
- test_plan: 1 new test in `InboxViewModelTests.swift`; inject `SearchIndex(databaseURL: nil)` into the ViewModel under test.

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

### REP-136 — AGENTS.md: consolidate duplicate test-count lines
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `AGENTS.md`
- scope: AGENTS.md currently has the test count in two places: the repo-layout code fence header (`Tests/ReplyAITests/ NNN tests`) and the Testing expectations section ("NNN XCTest cases, all green."). The reviewer flagged this duplication in the 2026-04-22 22:10 review. Remove the hard-coded number from the Testing expectations section and replace with the live-count instruction: `Run \`grep -r "func test" Tests/ | wc -l\` for the current count`. Update the repo-layout header to the current count (349). Docs-only change — no Swift source touches.
- success_criteria:
  - Repo-layout header updated to current count (349)
  - Testing expectations section uses grep instruction instead of hard-coded number
  - No source files touched
  - Reviewer no longer flags dual test-count lines
- test_plan: N/A (docs-only).

### REP-137 — PromptBuilder: oversized system instruction guard
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder` enforces a 2000-char message budget by dropping oldest messages first. However, if the tone system instruction itself exceeds the budget (e.g. a user pastes a 3000-char voice description), the current code may produce a prompt that overshoots the budget or silently drops all messages. Add a guard: if the system instruction length ≥ budget, truncate the instruction to `budget - 200` chars (leaving 200 chars minimum for at least the most-recent message). Tests: `testOversizedSystemInstructionTruncatedToFit` — 3000-char instruction + 1 short message produces a prompt ≤ total budget; `testOversizedSystemInstructionPreservesAtLeastOneMessage` — most-recent message still appears in output despite instruction truncation.
- success_criteria:
  - Guard added in `PromptBuilder` for system instruction overflow
  - `testOversizedSystemInstructionTruncatedToFit` — prompt within budget
  - `testOversizedSystemInstructionPreservesAtLeastOneMessage` — at least one message in output
  - Existing PromptBuilderTests remain green (short instructions unaffected)
- test_plan: 2 new tests in `PromptBuilderTests.swift` using a 3000-char fabricated tone instruction.

---

## Done / archived

*(Planner moves finished items here each day. Worker never modifies this section.)*

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
