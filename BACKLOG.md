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

### REP-228 — InboxViewModel: fixture demo mode when no channel provides threads
- priority: P0
- effort: M
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-23-145504
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Fixtures/Fixtures.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: **Strategic pivot P0: app must be useful with zero permissions.** When `syncFromIMessage()` returns 0 threads AND no other channel provides threads, populate `viewModel.threads` from `Fixtures.demoChatThreads` (a new `static let` on `Fixtures`). Each demo thread carries `isDemoThread: Bool = true`. Demo threads are excluded from `send()` (throws `InboxError.demoModeNotSendable`). Rules do not auto-apply to demo threads. `Preferences.demoModeActive: Bool` (defaults `true`; auto-set to `false` after any real sync returns ≥1 thread; exempt from `wipe()`). Tests: demo threads appear when real sync returns empty; demo mode flag persists to Preferences; demo mode disables after successful real sync; `send()` on demo thread throws `demoModeNotSendable`.
- success_criteria:
  - `Fixtures.demoChatThreads: [MessageThread]` — 3–5 realistic seed threads (distinct from the gallery Fixtures.threads)
  - `InboxViewModel` populates from demo fixtures when threads empty after sync
  - `Preferences.demoModeActive` key set false after first real sync ≥1 thread
  - `MessageThread.isDemoThread: Bool` field
  - `testDemoThreadsAppearsWhenSyncReturnsEmpty`
  - `testDemoModeFlagClearsAfterRealSync`
  - `testSendOnDemoThreadThrows`
  - Existing InboxViewModelTests remain green
- test_plan: 3 new tests in `InboxViewModelTests.swift`; use `StaticMockChannel` returning empty threads for first test, non-empty threads for second.

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

### REP-200 — human: review and merge wip/2026-04-23-085959-stats-session-acceptance
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`, `Tests/ReplyAITests/RulesTests.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Worker-085959 implemented REP-135 (Stats.sessionStartedAt + sessionDuration), REP-177 (Stats.overallAcceptanceRate), REP-179 (RuleEvaluator equal-priority determinism), REP-183 (Preferences wipe-exempt regression guard), and REP-187 (Stats.snapshot() JSON validation) but was blocked by MLX full-project build time exceeding the 13-min worker budget. All 5 implementations are on branch `wip/2026-04-23-085959-stats-session-acceptance`. Human should: (1) review the wip branch diff; (2) run `swift test` on main for baseline; (3) cherry-pick or merge the branch; (4) run `swift test` to confirm new tests pass; (5) mark REP-135, REP-177, REP-179, REP-183, REP-187 as done in BACKLOG.
- success_criteria:
  - wip/2026-04-23-085959-stats-session-acceptance merged into main
  - REP-135, REP-177, REP-179, REP-183, REP-187 all marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` before and after merge to confirm baseline and pass.

### REP-217 — human: review + merge wip/2026-04-23-130000-thread-name-regex
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Screens/Surfaces/SfcRulesView.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Worker-2026-04-23-130000 implemented REP-129 (`threadNameMatchesRegex(pattern:)` predicate) but was blocked by MLX full-project build time exceeding the 13-min budget. Implementation is complete on branch `wip/2026-04-23-130000-thread-name-regex`. Human should: (1) review the wip branch diff; (2) run `swift test` on main for baseline; (3) cherry-pick or merge the branch; (4) run `swift test` to confirm new tests pass; (5) mark REP-129 as done in BACKLOG.
- success_criteria:
  - wip/2026-04-23-130000-thread-name-regex merged into main
  - REP-129 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` before and after merge to confirm baseline and pass.

---

## P2 — stretch / backlog depth

### REP-009 — Global `⌘⇧R` hotkey (needs Accessibility)
- priority: P1
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



### REP-075 — AttributedBodyDecoder: nested NSMutableAttributedString payload handling
- priority: P2
- effort: M
- ui_sensitive: false
- status: deprioritized
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
- status: blocked
- claimed_by: worker-2026-04-23-130000
- blocker: MLX full build on fresh clone exceeded time budget; implementation complete on wip/2026-04-23-130000-thread-name-regex; human should run `swift test` and merge if green
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
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; implementation on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: Add `sessionStartedAt: Date` (set in `Stats.init` to `Date()`) and a computed `sessionDuration: TimeInterval` (= `Date().timeIntervalSince(sessionStartedAt)`). Include `sessionDuration` in the weekly log JSON written by `writeWeeklyLog()` alongside existing counters. No disk persistence for this field (it resets per session by design). Injectable `nowProvider: () -> Date` (default `{ Date() }`) for deterministic tests. Tests: `testSessionStartedAtApproximatelyNow` — initialized within 1s of `Date()`; `testSessionDurationIsNonNegative` — computed field ≥ 0; `testSessionDurationIncludesInWeeklyLog` — JSON from `writeWeeklyLog()` contains `"sessionDuration"` key.
- success_criteria:
  - `Stats.sessionStartedAt: Date` set on init
  - `Stats.sessionDuration: TimeInterval` computed property
  - `sessionDuration` included in weekly log JSON
  - `testSessionStartedAtApproximatelyNow`, `testSessionDurationIsNonNegative`, `testSessionDurationIncludesInWeeklyLog`
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using isolated `Stats` instance (nil URL).








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
- status: blocked
- claimed_by: worker-2026-04-23-135355
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






### REP-177 — Stats: overallAcceptanceRate() aggregate across all tone keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; implementation on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.acceptanceRate(for tone:)` gives per-tone rates. A UI surface (e.g. set-privacy screen) may want an aggregate across all tones. Add `Stats.overallAcceptanceRate() -> Double?` that returns `nil` if no drafts generated across any tone, or `Double(totalSent) / Double(totalGenerated)` aggregating across all tone counters. Tests: fresh instance → nil; 3 generated across 2 tones, 1 sent → 0.333...; all generated but none sent → 0.0.
- success_criteria:
  - `Stats.overallAcceptanceRate() -> Double?` added
  - `testOverallAcceptanceRateNilWhenNoData` — nil on fresh instance
  - `testOverallAcceptanceRateAggregatesAcrossTones` — total sent / total generated
  - `testOverallAcceptanceRateZeroWhenGeneratedButNoneSent` — 0.0 not nil
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using isolated `Stats(statsFileURL: nil)`.

### REP-178 — InboxViewModel: pin state persists to Preferences across re-init
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModel.pinThread` sets a flag that causes the thread to sort above others. Verify the pin state persists through Preferences so it survives an app relaunch. Test: pin a thread in one ViewModel instance with an injectable `UserDefaults` suite; create a second ViewModel from the same defaults; assert the thread is still marked pinned and appears at the top of the sorted list. Also pin: unpinThread removes from `pinnedIDs` and thread drops from pinned position.
- success_criteria:
  - `testPinStatePersistsThroughReInit` — pinned thread still at top after ViewModel re-init from same UserDefaults
  - `testUnpinRemovesFromPinnedSet` — unpinned thread no longer pinned after reinit
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift` using suiteName-isolated `UserDefaults`.

### REP-179 — RuleEvaluator: equal-priority rules maintain deterministic evaluation order
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; tests on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RuleEvaluator.matching(rules:context:)` sorts by priority descending. When two rules have the same priority, the output order should be deterministic (insertion order preserved, not arbitrary). Test: two rules at priority 0, inserted A then B; matching returns `[A, B]` (insertion order). Also test with priority 5 and 5: same result. This guards against a future `sort` → `stableSort` rollback. No production code changes expected if insertion order is already preserved.
- success_criteria:
  - `testEqualPriorityRulesPreserveInsertionOrder` — two rules at same priority return in insertion order
  - `testEqualPriorityDeterministicOnMultipleCalls` — calling matching() twice returns identical order
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift`; fabricate two rules with identical priority and different UUIDs.


### REP-183 — Preferences: wipeReplyAIDefaults skips firstLaunchDate and launchCount (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; tests on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift`
- scope: REP-130 and REP-115 added `firstLaunchDate` and `launchCount` as wipe-exempt keys. Verify the exemption is enforced: call `wipe()` after setting both values; assert both survive. This pins the `wipeExemptions` set as a regression guard — if the exemption list is accidentally cleared, this test fails. Also test: non-exempt keys ARE wiped (e.g. `autoPrimeEnabled` returns default after wipe). No production code changes expected.
- success_criteria:
  - `testWipePreservesFirstLaunchDate` — `firstLaunchDate` non-nil after wipe
  - `testWipePreservesLaunchCount` — `launchCount` retains value after wipe
  - `testWipeClearsNonExemptKey` — a non-exempt preference key returns default after wipe
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated `UserDefaults`.


### REP-187 — Stats: snapshot() values are JSON-serializable without throwing
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; tests on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.snapshot()` returns `[String: Any]`. This dictionary is passed to `JSONSerialization.data(withJSONObject:)` by `writeWeeklyLog()`. If any value type is not JSON-serializable (e.g. a `Date` object, a struct), `writeWeeklyLog` will silently fail or crash at the `try?` call site. Pin the contract: `JSONSerialization.isValidJSONObject(snapshot())` returns `true` for a freshly-initialized Stats instance; also for one with non-zero counters. No production code changes expected if the snapshot already uses only numbers/strings.
- success_criteria:
  - `testSnapshotIsValidJSONObject` — `JSONSerialization.isValidJSONObject(snapshot())` returns true
  - `testSnapshotWithCountersIsValidJSON` — snapshot with non-zero counters also passes JSON validation
  - Existing StatsTests remain green
- test_plan: 2 new tests in `StatsTests.swift` using isolated `Stats(statsFileURL: nil)` with incremented counters.



### REP-190 — InboxViewModel: thread sort stability — same-timestamp threads don't swap order
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: When two threads share the same `lastMessageDate`, the sort should be stable (threads don't arbitrarily swap positions between syncs). Test: add threads A and B with identical timestamps; sync multiple times; assert A always appears before B (using thread IDs as tiebreaker or creation order). Unstable sort is user-visible as jumping rows in the thread list during live sync.
- success_criteria:
  - `testEqualTimestampThreadsSortStably` — threads with same timestamp don't reorder across syncs
  - `testEqualTimestampSortUsesIdAsSecondaryKey` — tiebreaker is thread ID (deterministic)
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; use `StaticMockChannel` with two threads sharing a timestamp.


### REP-191 — DraftStore: concurrent read+write does not corrupt draft file
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: `DraftStore` writes atomically via a temp-file rename, but a concurrent read during a write could theoretically return an empty or partial file. Test with `DispatchQueue.concurrentPerform(iterations: 20)` performing alternating writes and reads on the same thread ID using an injected temp directory. Assert: no empty string returned from `read()`; no crash; final `read()` after all concurrency returns the last-written draft text. No production code changes expected (atomic write should be sufficient).
- success_criteria:
  - `testConcurrentReadWriteNoCrash` — 20 concurrent read+write cycles complete without crash
  - `testConcurrentReadWriteNoEmptyResult` — `read()` never returns empty string mid-write
  - Existing DraftStoreTests remain green
- test_plan: 2 new tests in `DraftStoreTests.swift` using temp directory injection and `DispatchQueue.concurrentPerform`.

### REP-192 — RulesStore: 100-rule cap boundary — 100th add succeeds, 101st throws
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-069 added a 100-rule hard cap via `RulesStore.addValidating(_:)`. Pin the exact boundary: adding rule #100 succeeds (no throw); adding rule #101 throws `tooManyRules`. Also: the store count must remain at 100 after the failed add (no partial state). No production code changes expected.
- success_criteria:
  - `testHundredthRuleAddSucceeds` — rule #100 added without throwing
  - `testHundredAndFirstRuleThrowsTooManyRules` — rule #101 throws `tooManyRules`
  - `testStoreCountUnchangedAfterFailedAdd` — count stays at 100 after throw
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift` using isolated `RulesStore` with injected `UserDefaults`.

### REP-193 — IMessageSender: 4096-char boundary — 4096 succeeds, 4097 throws
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-064 added a 4096-char message length guard in `IMessageSender.send()`. Pin the boundary: a 4096-char ASCII message sends (no throw); a 4097-char message throws `SenderError.messageTooLong`. Also: a 4096-char message composed of multi-byte Unicode chars (emoji) uses Swift `String.count` (char count), not byte count — verify a 10-emoji string that is >4096 bytes but <4096 chars passes. Uses the injectable `executeHook` seam — no real AppleScript.
- success_criteria:
  - `testMessageAtExactLimitSucceeds` — 4096-char ASCII message sends without throw
  - `testMessageOverLimitThrows` — 4097-char message throws `messageTooLong`
  - `testMultiByteCharsUseCharCount` — 10-emoji string (>4096 bytes, <4096 chars) passes
  - Existing IMessageSenderTests remain green
- test_plan: 3 new tests in `IMessageSenderTests.swift` using dry-run hook.

### REP-194 — Preferences: threadLimit clamped to valid range [1, 200]
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: `pref.inbox.threadLimit` is used as a SQL LIMIT clause. If stored as 0, negative, or an unreasonably large value, the query produces no results or hangs on very large result sets. Add a computed getter that clamps the raw stored value to `max(1, min(200, rawValue))`. The setter writes the raw value as-is (clamping happens at read time). Tests: raw value -1 → getter returns 1; raw value 0 → getter returns 1; raw value 201 → getter returns 200; raw value 50 → getter returns 50; raw value 200 → getter returns 200.
- success_criteria:
  - `Preferences.threadLimit` getter clamps raw value to [1, 200]
  - `testThreadLimitClampsNegativeToOne` — -1 → 1
  - `testThreadLimitClampsZeroToOne` — 0 → 1
  - `testThreadLimitClampsOverMaxToMax` — 201 → 200
  - `testThreadLimitPassesThroughValidValue` — 50 → 50
  - Existing PreferencesTests remain green
- test_plan: 4 new tests in `PreferencesTests.swift` using injected `UserDefaults`.

### REP-195 — DraftEngine: dismiss on an unprimed thread is a silent no-op
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine.dismiss(threadID:tone:)` transitions a `.ready` draft to `.idle` and clears the `DraftStore` entry. If called on a `threadID` that was never primed (no cache entry at all), the call should silently return — no crash, no state change, no `DraftStore` delete attempted on a non-existent file. Tests: fresh engine, call `dismiss("never-primed-id", tone: .casual)`; assert no crash; assert state for that thread is `.idle`. Also test dismiss after prime → ready succeeds as usual.
- success_criteria:
  - `testDismissOnUnprimedThreadIsNoop` — no crash, state remains `.idle`
  - `testDismissAfterPrimeTransitionsToIdle` — normal dismiss path still works
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; first test requires no prior prime calls.

### REP-196 — SearchIndex: repeated search with unchanged index returns identical order
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: FTS5 BM25 ranking is deterministic for a fixed index state. Pin the contract: index 3 threads with different relevance levels for the query "hello"; search once → get order [A, B, C]; search again without any writes → get identical [A, B, C]. A third search after a no-op `upsert` of an unrelated thread also returns [A, B, C]. Unstable ordering would cause visible jump in ⌘K palette results.
- success_criteria:
  - `testRepeatedSearchReturnsSameOrder` — two identical searches on unchanged index return same order
  - `testSearchOrderStableAfterUnrelatedUpsert` — upsert of different thread doesn't reorder prior results
  - Existing SearchIndexTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift` using in-memory FTS5 with 3 seeded threads.

### REP-197 — PromptBuilder: each supported tone produces a distinct non-empty system instruction
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder.systemPrompt(tone:)` is called for each `Tone` case. Pin the distinctness contract: iterate all `Tone` cases via `CaseIterable`, collect the system strings, assert every string is non-empty, assert all strings are pairwise distinct (no two tones share identical instruction text). Guards against a future refactor that accidentally maps multiple tones to the same prompt.
- success_criteria:
  - `testAllTonesProduceNonEmptySystemInstruction` — every tone yields a non-empty string
  - `testToneSystemInstructionsAreDistinct` — no two tones share identical instruction text
  - Existing PromptBuilderTests remain green
- test_plan: 2 new tests in `PromptBuilderTests.swift`; `Tone.allCases` must be `CaseIterable`.

### REP-198 — IMessageChannel: threads with no messages are excluded from recentThreads
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `recentThreads(limit:)` joins `chat` and `message` tables. A chat with zero associated messages (draft group, invite pending) should not appear in the result. Test with in-memory SQLite fixture: one thread with 3 messages, one thread with 0 messages. Assert: only the thread with messages appears in the returned list. Also assert: the returned thread's `messageCount` equals 3 (not 0).
- success_criteria:
  - `testEmptyThreadExcludedFromRecentThreads` — thread with 0 messages not returned
  - `testThreadWithMessagesIncluded` — thread with messages returns with correct messageCount
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests in `IMessageChannelTests.swift` using in-memory SQLite fixture.

### REP-202 — SmartRule: decode unknown predicate discriminator produces graceful nil (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: Forward-compatibility guard: when `RulePredicate` decodes a JSON dict with `"kind": "unknownFutureFeature"`, the decode should either return nil or throw a `DecodingError.dataCorrupted` — never an unhandled crash. Build a test that JSON-decodes a `SmartRule` array containing one rule with an unknown predicate kind and one with a valid kind. Assert: the valid rule decodes correctly; decoding the unknown kind does not crash (may throw or be skipped depending on the implementation). Simulates a user downgrading from a newer app version that added a new predicate.
- success_criteria:
  - `testUnknownPredicateKindDoesNotCrash` — decode of unknown `"kind"` does not trap
  - `testKnownPredicateKindDecodesAdjacentToUnknown` — valid predicate in same array decodes correctly
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift`; craft a JSON literal with a `"kind": "xyzzy"` predicate alongside a `"kind": "senderIs"` predicate.

### REP-203 — DraftEngine: regenerate on different tone evicts original tone's cache entry (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Prime thread X with `.casual` → wait for `.ready`. Call `regenerate(threadID: X, tone: .formal)`. Assert: the engine no longer has a valid `.casual` cache entry for thread X (state returns to `.idle` or begins `.priming` for `.formal`); a second wait yields `.ready` with the `.formal` tone. Guards against tone-switch displaying a stale `.casual` draft while the new `.formal` prime runs in the background.
- success_criteria:
  - `testRegenerateOnToneChangeEvictsOldToneCache` — `.casual` state is gone after `regenerate(.formal)`
  - `testRegenerateOnToneChangeReachesReadyForNewTone` — engine reaches `.ready` for `.formal` after wait
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; use `StubLLMService` + `waitUntil` helper.

### REP-204 — IMessageChannel: recentThreads limit boundary (under-limit and over-limit)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: In-memory fixture with exactly 5 threads. `recentThreads(limit: 1)` → 1 thread; `recentThreads(limit: 3)` → 3 threads; `recentThreads(limit: 10)` → 5 threads (all available). Documents that `limit` is applied strictly (SQL LIMIT) and the query doesn't overshoot or error when fewer rows exist than the requested limit.
- success_criteria:
  - `testRecentThreadsLimitOneLimitsToOne` — limit 1 returns exactly 1 thread
  - `testRecentThreadsLimitExceedsAvailableReturnsAll` — limit 10 with 5 threads returns 5
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests in `IMessageChannelTests.swift` using in-memory SQLite with 5 seeded chat rows.

### REP-205 — SearchIndex: delete() removes thread from all subsequent queries (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Index threads A ("hello world"), B ("hello swift"), C ("goodbye world"). Call `delete(threadID: B)`. Run 3 queries: "hello" (previously returned A+B → should now return only A); "swift" (previously returned B → should return empty); "goodbye" (should still return C unchanged). Guards against FTS5 soft-delete / rowid-reuse scenarios where a deleted thread resurfaces.
- success_criteria:
  - `testDeleteRemovesThreadFromSingleTermSearch` — "swift" returns empty after deleting B
  - `testDeleteDoesNotAffectOtherMatchingThreads` — "hello" still returns A after deleting B
  - `testDeleteDoesNotAffectUnrelatedThread` — "goodbye" still returns C
  - Existing SearchIndexTests remain green
- test_plan: 3 new tests in `SearchIndexTests.swift` using in-memory FTS5; set up 3 threads with known content.

### REP-206 — PromptBuilder: oldest messages dropped first when budget exceeded (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: Build a list of 5 messages where combined length exceeds the 2000-char budget. Verify drop-oldest semantics: `message[0]` (oldest, first in array) must not appear in the built prompt; `message[4]` (newest) must appear. Also test: with exactly 2000 chars of messages (at budget boundary), all 5 messages survive. This pins the truncation direction so a future refactor can't accidentally flip to drop-newest.
- success_criteria:
  - `testOldestMessagesDroppedWhenOverBudget` — message[0] absent, message[4] present when over budget
  - `testAllMessagesPreservedAtExactBudget` — 2000-char total keeps all messages
  - Existing PromptBuilderTests remain green
- test_plan: 2 new tests in `PromptBuilderTests.swift`; fabricate messages with known lengths using String(repeating:).

### REP-207 — Preferences: autoPrime and autoApplyOnSync default to false in fresh suite (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Pin the safety defaults for `autoPrimeEnabled` and `autoApplyOnSync`. A fresh `Preferences` instance on an isolated `UserDefaults` suite (no prior writes) must return `false` for both. These flags control auto-send behavior: if they accidentally default to `true`, the app would auto-send replies to every incoming message without user confirmation. Regression guard against a config change that treats absence-as-true.
- success_criteria:
  - `testAutoPrimeDefaultsToFalse` — fresh suite → `autoPrimeEnabled == false`
  - `testAutoApplyOnSyncDefaultsToFalse` — fresh suite → `autoApplyOnSync == false`
  - Existing PreferencesTests remain green
- test_plan: 2 new tests in `PreferencesTests.swift` using suiteName-isolated `UserDefaults`; do not write any value before reading.

### REP-208 — SmartRule: double-negation `not(not(pred))` evaluates identically to pred (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: Verify predicate composition correctness: `not(not(senderIs("Alice")))` must match when `senderIs("Alice")` matches, and must not match when it doesn't. Test with two base predicates (a matching and a non-matching context). Also test: `not(not(not(pred)))` inverts correctly (equals `not(pred)`). Guards the `not` composition against a double-negation cancellation bug in the evaluator.
- success_criteria:
  - `testDoubleNegationMatchesWhenBaseMatches` — `not(not(senderIs("Alice")))` matches context with sender "Alice"
  - `testDoubleNegationMissesWhenBaseMisses` — same predicate misses context with sender "Bob"
  - `testTripleNegationInvertsBase` — `not(not(not(pred)))` equals `not(pred)` result
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift`; construct `RuleContext` directly with controlled sender field.

### REP-209 — InboxViewModel: unread count cleared to zero after selectThread (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-076 wired mark-as-read on thread select. Pin the unread-clear contract: start with a thread at `unread: 3`; call `viewModel.selectThread(thread)`; assert `thread.unread == 0`. Also assert: the thread's position in `viewModel.threads` is unchanged after the unread update (no re-sort triggered by the unread change alone). Uses `StaticMockChannel` with a seeded thread.
- success_criteria:
  - `testSelectThreadClearsUnreadCount` — `thread.unread == 0` after selectThread
  - `testSelectThreadDoesNotResortList` — thread index in `threads` unchanged after unread clear
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; seed a thread with `unread: 3` via the mock channel fixture.

### REP-211 — AGENTS.md: correct stale SHA `05e7035` → `4035c5a` in done-log (docs-only)
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `AGENTS.md`
- scope: Reviewer-2026-04-23-1012 flagged `05e7035` as a non-existent commit SHA in the "What's done" log — identified as pre-existing from the 2026-04-22-174500 worker run. The real SHA is `4035c5a` (covers REP-098/099/101/103/104/109/114). Planner has already corrected this in AGENTS.md during the 2026-04-23 run6 refresh; this task is a verification commit — worker must run `git cat-file -e 4035c5a` to confirm validity, verify the AGENTS.md entry now reads `4035c5a`, and commit a one-line confirmation with the validation result in the commit body.
- success_criteria:
  - `git cat-file -e 4035c5a` exits 0 (verified)
  - AGENTS.md done-log entry for worker-2026-04-22-174500 reads `4035c5a` (not `05e7035`)
  - No other AGENTS.md sections touched
- test_plan: N/A (docs-only). Worker validates SHA before committing.

### REP-212 — InboxViewModel: `selectThread` seeds `userEdits` from DraftStore when stored draft exists (integration test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-066 ships `DraftStore` and its scope explicitly states "InboxViewModel.selectThread seeds `userEdits` from the store before the LLM re-primes, so the composer is populated immediately on app open." There is no integration test pinning this end-to-end path. Test: write a draft string to an injected temp `DraftStore` for thread ID "T1"; construct an `InboxViewModel` with that DraftStore injected; call `selectThread` with a thread whose ID is "T1"; assert `viewModel.userEdits == <stored string>` before the LLM prime completes. Also: a thread with no stored draft leaves `userEdits` empty on select.
- success_criteria:
  - `testSelectThreadSeedsUserEditsFromDraftStore` — stored draft string appears in `userEdits` after selectThread
  - `testSelectThreadWithNoStoredDraftLeavesUserEditsEmpty` — no stored draft → empty userEdits
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; inject `DraftStore(directoryURL: tempDir)` into ViewModel; write draft before constructing ViewModel.

### REP-213 — Stats: `rulesMatchedCount` increments by matched-rule count, not once per evaluation call (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.rulesMatchedCount` is incremented in `InboxViewModel` at rule-evaluation time. Pin the per-match semantics: if 3 rules match a single thread evaluation, `rulesMatchedCount` must grow by 3 (not 1). If 0 rules match, the counter is unchanged. Uses `Stats(statsFileURL: nil)` with injected mock rule evaluator results. Guards against an implementation that calls `increment(.rulesMatchedCount)` once per `matching()` call regardless of match count.
- success_criteria:
  - `testRulesMatchedCountIncrementsPerMatchedRule` — 3 matching rules → count +3
  - `testRulesMatchedCountUnchangedOnZeroMatches` — 0 matching rules → count unchanged
  - Existing StatsTests remain green
- test_plan: 2 new tests in `StatsTests.swift`; use isolated `Stats` instance and direct counter manipulation.

### REP-214 — InboxViewModel: failed send preserves `userEdits` and surfaces `sendError` (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: The 2026-04-22-1603 review noted "error surfaced + `userEdits` preserved on failure" as shipped behavior for `InboxViewModel.send()`. Pin this with a regression test: use a throwing mock sender (via injectable `IMessageSender` seam) that always throws `SenderError.messageTooLong`. Call `send(thread:)`. Assert: (1) `viewModel.userEdits` retains its pre-send value; (2) a non-nil `sendError` is surfaced on the ViewModel. Also test the success path: successful send clears userEdits (optimistic clear, REP-046 scope). The throwing path is the regression guard.
- success_criteria:
  - `testFailedSendPreservesUserEdits` — `userEdits` unchanged after throwing send
  - `testFailedSendSurfacesSendError` — `sendError` non-nil after throwing send
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests using injectable `executeHook` seam that throws `messageTooLong`; no real AppleScript.

### REP-215 — SmartRule: `validateRegex` rejects invalid patterns and accepts valid ones (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-031 shipped `SmartRule.validateRegex(_:)` + `RulesStore.addValidating(_:)` + `RuleValidationError.invalidRegex`. These are correctness gates but coverage may be thin. Pin 4 boundary cases: (1) `"[invalid"` throws `.invalidRegex`; (2) `"^hello.*$"` is accepted (no throw); (3) `""` (empty pattern) is accepted — matches everything, which is intentional for "catch-all" rules; (4) `"(?P<name>x)"` (Python named group, unsupported in ICU) throws `.invalidRegex`. Guards the regex validation gate against silent bypass.
- success_criteria:
  - `testInvalidRegexThrowsAtCreation` — `"[invalid"` → `.invalidRegex` from `addValidating`
  - `testValidRegexAccepted` — `"^hello.*$"` → no throw
  - `testEmptyPatternAccepted` — `""` → no throw
  - `testUnsupportedRegexSyntaxThrows` — unsupported ICU syntax → `.invalidRegex`
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift` using isolated `RulesStore` with injected `UserDefaults`.

### REP-216 — DraftEngine: `regenerate(threadID:tone:)` for same tone reaches `.ready` again (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: REP-203 tests tone-change eviction on `regenerate`. This is the same-tone complement: prime thread X with `.casual` → wait for `.ready`. Call `regenerate(threadID: X, tone: .casual)`. Assert engine transitions back through `.priming` then reaches `.ready` again (new draft, same tone). A `StubLLMService` with a configurable second chunk set can verify the draft content differs from the first prime. Guards against a shortcut where `regenerate` no-ops when the tone hasn't changed.
- success_criteria:
  - `testRegenerateSameToneTransitionsThroughPriming` — engine enters `.priming` on regenerate call
  - `testRegenerateSameToneReachesReady` — engine reaches `.ready` after regenerate completes
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; configure `StubLLMService` with distinct first/second stream content; use `waitUntil` helper.

### REP-210 — IMessageSender: combined newline + backslash escaping in AppleScript literal (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-174 fixed `\n → \\n` escaping. Add a combined boundary test: a message containing `"line one\nline two\nbackslash: \\"` produces an AppleScript string literal where `\n` is escaped to `\\n` and `\\` is escaped to `\\\\`. Also: a message containing a tab character `\t` passes through unchanged (tabs are legal in AppleScript string literals). Uses the injectable `executeHook` seam to capture the constructed AppleScript string without executing it.
- success_criteria:
  - `testNewlineAndBackslashBothEscapedInAppleScript` — `\n` → `\\n`, `\\` → `\\\\` in AppleScript literal
  - `testTabCharacterPassesThroughUnescaped` — tab in message text passes unescaped
  - Existing IMessageSenderTests remain green
- test_plan: 2 new tests in `IMessageSenderTests.swift`; use `executeHook` seam to capture AppleScript string for assertion rather than executing.

### REP-229 — AppleScript thread listing: `tell Messages to get every chat` fallback when FDA unavailable
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift` (or new `Sources/ReplyAI/Channels/AppleScriptMessageReader.swift`), `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: **Pivot-aligned (alt message-source).** Add `AppleScriptMessageReader.recentChats() -> [MessageThread]` that executes `tell application "Messages" to get every chat` via `NSAppleScript`. Returns a `[MessageThread]` with display name, chat GUID, and a placeholder `previewText` (AppleScript can retrieve `every text chat` with `name` and `id` but not full message history — that's OK for the thread list). No FDA required — uses Automation permission. `IMessageChannel.recentThreads()` uses this as a fallback when `openReadOnly()` fails with `authorizationDenied`. Tests use injectable AppleScript executor (same seam as `IMessageSender`).
- success_criteria:
  - `AppleScriptMessageReader.recentChats() -> [MessageThread]` implemented with injectable executor
  - `IMessageChannel.recentThreads()` calls `AppleScriptMessageReader` when `openReadOnly()` returns `.authorizationDenied`
  - `testAppleScriptFallbackPopulatesThreadsWhenFDADenied` — mock channel returns `authorizationDenied`; fallback executor returns chat list; `recentThreads()` returns non-empty
  - `testAppleScriptFallbackExecutorIsInjectable` — custom executor captures AppleScript string for assertion
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests; injectable executor captures and asserts on the AppleScript source string without executing real AppleScript.

### REP-230 — LocalhostOAuthListener: injectable loopback handler for Slack OAuth
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/LocalhostOAuthListener.swift` (new), `Tests/ReplyAITests/LocalhostOAuthListenerTests.swift` (new)
- scope: **Pivot-aligned (Slack first).** Building block for REP-010 (Slack OAuth). Extract the loopback listener into a standalone `LocalhostOAuthListener` that: (1) binds an `NWListener` on `127.0.0.1:4242`; (2) resolves a `code` query parameter from the first incoming callback URL; (3) calls a completion handler with `code: String` and shuts down the listener. Injectable port and timeout (`default: 120s`). Tests verify: valid callback URL returns the `code`; timeout fires completion with `OAuthError.timeout`; double-start is a no-op. No Slack-specific logic here — just the reusable plumbing.
- success_criteria:
  - `LocalhostOAuthListener(port:timeout:)` type in new file
  - `start(completion: (Result<String, OAuthError>) -> Void)` and `stop()` methods
  - `testValidCallbackURLExtractsCode` — mock NW connection delivering `/?code=abc123`  → completion called with `"abc123"`
  - `testTimeoutFiresWithOAuthError` — no callback within timeout fires `.timeout`
  - `testDoubleStartIsNoop` — second `start()` while running is safe
  - Existing tests remain green
- test_plan: 3 new tests in `LocalhostOAuthListenerTests.swift`; use an injectable `NWListener` factory or connect a real listener to localhost in a test.

### REP-231 — Preferences: per-channel enable/disable keys (iMessage, Slack, demo)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: **Pivot-aligned (channel architecture).** Add three Preferences keys: `pref.channels.iMessageEnabled: Bool` (default `true`), `pref.channels.slackEnabled: Bool` (default `false`), `pref.channels.demoModeActive: Bool` (alias of `Preferences.demoModeActive` from REP-228, or consolidate here). These are the channel-level on/off switches that `InboxViewModel.syncFromIMessage` and future `SlackChannel.recentThreads` will check before attempting a sync. Tests: default values; round-trip through UserDefaults; wipe behavior (channels.* keys are NOT wipe-exempt — privacy reset clears channel tokens).
- success_criteria:
  - `pref.channels.iMessageEnabled`, `pref.channels.slackEnabled` Preferences keys
  - Default values correct (`iMessage=true`, `slack=false`)
  - Neither key is wipe-exempt (both cleared on `wipe()`)
  - `testIMessageEnabledDefaultsToTrue`, `testSlackEnabledDefaultsToFalse`, `testChannelKeysClearedOnWipe`
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated `UserDefaults`.

### REP-218 — InboxViewModel: archiveThread removes thread from SearchIndex (integration test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-063 shipped `SearchIndex.delete(threadID:)` and wired it in `InboxViewModel.archive(_:)`. Add an integration test verifying the full pipeline: seed a thread into an injectable `SearchIndex` and the ViewModel; call `archive(thread)`; assert `searchIndex.search("query matching thread")` returns empty. Also assert thread absent from `viewModel.threads` after archive. Guards against future refactors that break the archive→index-purge path.
- success_criteria:
  - `testArchiveThreadRemovesFromSearchIndex` — searching for archived thread returns no results
  - `testArchiveThreadRemovedFromViewModelThreads` — thread absent from `threads` after archive
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; inject temp-directory `SearchIndex` and `StaticMockChannel`.

### REP-219 — ContactsResolver: cache hit within TTL skips CNContactStore re-query
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: REP-074 added injectable `ttl`. Pin the positive cache-hit path: resolve a handle once (store query count = 1); call `name(for:)` again within the TTL window; assert store query count remains 1 (no second query). Complement to REP-185 which tests TTL expiry. Guards against a future change that accidentally bypasses the cache on every call.
- success_criteria:
  - `testCacheHitWithinTTLSkipsStoreQuery` — second call within TTL does not increment mock store call count
  - Existing ContactsResolverTests remain green
- test_plan: 1 new test in `ContactsResolverTests.swift` using `MockContactsStore` with call counter; `ttl=9999`.

### REP-220 — RulesStore: concurrent add + remove does not corrupt rules array
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore` uses `Locked<T>` for thread-safety. Pin correctness under concurrent writes: `DispatchQueue.concurrentPerform(iterations: 50)` alternately calls `add(_:)` and `remove(ruleID:)` on the same store. After completion, assert: no crash, `rules.count ≥ 0`, no duplicate IDs. Guards against a race where a `Locked<T>` scope is held across an add while a concurrent remove modifies a different index.
- success_criteria:
  - `testConcurrentAddRemoveNoCrash` — 50 concurrent add+remove operations complete without crash
  - `testConcurrentAddRemoveNoDuplicateIDs` — no duplicate UUIDs in `rules` after stress
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift` using isolated `RulesStore` with injected `UserDefaults` suite.

### REP-221 — IMessageChannel: text=NULL message falls back to attributedBody decoder
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: The SQL query selects both `message.text` and `message.attributedBody`. When `text` is NULL, `AttributedBodyDecoder.extractText` is called on the raw blob. Add an in-memory SQLite fixture: one message row with `text = NULL` and a hand-crafted minimal typedstream `attributedBody` blob; call `messages(forThreadID:limit:)`; assert the returned message body matches the decoded string (not nil, not "[deleted]"). Verifies the fallback path is exercised, not just the SQL filter.
- success_criteria:
  - `testNullTextFallsBackToAttributedBodyDecoder` — message with null text returns decoded attributedBody content
  - `testNullTextNullBlobProducesPlaceholder` — both null → "[deleted]" placeholder
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests using in-memory SQLite with attributedBody blob fixtures from `AttributedBodyDecoderTests`.

### REP-222 — UserVoiceProfile: data model + Preferences key + PromptBuilder injection
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: The `ob-voice` screen is a UI mock; full LoRA training is out of scope. Add the data layer: `pref.voice.exampleMessages: [String]` (UserDefaults key, defaults to `[]`, max 20 entries enforced at setter, each entry max 500 chars — truncated at setter). `PromptBuilder.buildPrompt(...)` gains optional `voiceExamples: [String]` parameter; when non-empty, inserts a "Style examples from the user's prior messages:" section above the conversation history. Tests: examples appear in built prompt; empty examples → no section header; >20 examples clamped to 20; entry >500 chars truncated at setter.
- success_criteria:
  - `pref.voice.exampleMessages` key with 20-entry cap and 500-char per-entry truncation
  - `PromptBuilder.buildPrompt` injects voice examples when non-empty
  - `testVoiceExamplesInjectedIntoPrompt` — examples appear between system and history in output
  - `testEmptyVoiceExamplesProduceNoHeader` — no section header when list is empty
  - `testVoiceExamplesCapEnforcedAtTwenty` — setter clamps list to 20 entries
  - `testVoiceExampleTruncatedAtFiveHundredChars` — long entry truncated at setter
- test_plan: 4 new tests in `PromptBuilderTests.swift` + 2 in `PreferencesTests.swift`.

### REP-223 — Stats: per-channel indexed-count reset on SearchIndex.clear() (integration)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-165 ships `SearchIndex.clear()` which calls `Stats.resetIndexedCounters()`. Add an integration test: seed an iMessage indexed count of 5 into a shared `Stats` instance via mock increments; call `searchIndex.clear()` (with the same `Stats` instance injected); assert `stats.indexedMessageCount(for: .iMessage) == 0`. Also assert non-index counters (rules fired, drafts generated) are unchanged by clear(). Guards the Stats→SearchIndex contract.
- success_criteria:
  - `testClearResetsStatsIndexedCount` — indexed count returns 0 after clear()
  - `testClearDoesNotAffectOtherStatsCounters` — rules/drafts counters unchanged by clear()
  - Existing SearchIndexTests and StatsTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift` using in-memory `SearchIndex` with injected `Stats` instance.

### REP-224 — InboxViewModel: bulkMarkAllRead() sets unread=0 for all loaded threads
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Add `bulkMarkAllRead()` to `InboxViewModel` that iterates `threads` and sets `unread = 0` for each. Useful for a "Mark all read" menu action (UI wiring is separate, human-reviewed). Tests: start with 3 threads each with `unread > 0`; call `bulkMarkAllRead()`; assert all three have `unread == 0`; thread count unchanged.
- success_criteria:
  - `InboxViewModel.bulkMarkAllRead()` implemented
  - `testBulkMarkAllReadClearsAllUnreadCounts` — all threads have `unread == 0` after call
  - `testBulkMarkAllReadPreservesThreadCount` — thread array count unchanged
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift` using `StaticMockChannel` seeded with 3 threads with `unread > 0`.

### REP-225 — SearchIndex: snippet column pinned to message body, not thread_name (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Worker-111853 notes `snippet(messages_fts, 3, '«', '»', '…', 8)` uses column 3 (message body text). Pin with a test: index a thread where the thread name contains the search term "alpha" but the message body does not; search "alpha"; assert snippet does NOT contain "alpha" (because snippet comes from the message body column, not thread_name). Then index a thread where the message body contains "beta"; search "beta"; assert snippet contains `«beta»`. Guards against schema migration that shifts column indices.
- success_criteria:
  - `testSnippetExtractsFromMessageBodyNotThreadName` — thread-name match does not produce snippet
  - `testSnippetContainsBoldMarkerAroundMatchedTerm` — body match produces `«term»` in snippet
  - Existing SearchIndexTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift` using in-memory FTS5 with distinct thread_name and body content.

### REP-226 — SmartRule: `messageCount(atLeast:)` predicate — match threads with ≥N messages
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Screens/Surfaces/SfcRulesView.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Add `case messageCount(atLeast: Int)` to `RulePredicate`. `RuleContext` gains `messageCount: Int` (from `MessageThread.messages.count`). `RuleEvaluator` evaluates: `context.messageCount >= atLeast`. Codable discriminator: `"messageCountAtLeast"`. `SfcRulesView.humanize` gets a new case string. Useful for rules like "if thread has ≥10 messages, use detailed tone". Tests: context.messageCount=5, predicate atLeast=3 → true; atLeast=5 → true; atLeast=6 → false; Codable round-trip preserves the threshold; atLeast=0 → vacuous-true (always matches).
- success_criteria:
  - `RulePredicate.messageCount(atLeast:)` case added and Codable
  - `RuleContext.messageCount: Int` field populated from thread
  - `RuleEvaluator` evaluates `context.messageCount >= atLeast`
  - `SfcRulesView.humanize` updated
  - `testMessageCountAtLeastMatchesWhenAboveThreshold`, `testMessageCountAtLeastMissesWhenBelowThreshold`, `testMessageCountAtLeastZeroIsVacuousTrue`, `testMessageCountAtLeastCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift`; construct `RuleContext` directly with controlled `messageCount`.

### REP-227 — IMessageChannel: Message.messageType field exposes tapback/receipt at model layer
- priority: P2
- effort: M
- ui_sensitive: false
- status: deprioritized
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Sources/ReplyAI/Models/MessageThread.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: Tapbacks (`associated_message_type 2000–2005`) and delivery receipts are currently filtered at the SQL level by the thread-preview query. Expose `messageType: MessageType` on `Message` where `MessageType` is an enum: `.standard`, `.tapback`, `.deliveryReceipt`, `.unknown(Int)`. The SQL query for `messages(forThreadID:)` adds the `associated_message_type` column. Tapbacks and receipts are still filtered from thread previews (existing behavior preserved) but are now available to callers who want to show reaction summaries or sync status. Tests: standard message has `.standard` type; a row with `associated_message_type = 2000` has `.tapback`; a row with `associated_message_type = 2002` (read receipt) has `.deliveryReceipt`.
- success_criteria:
  - `MessageType` enum with `.standard`, `.tapback`, `.deliveryReceipt`, `.unknown(Int)` cases
  - `Message.messageType` field populated from SQL
  - `testStandardMessageTypeIsStandard`, `testTapbackMessageTypeIsTapback`, `testDeliveryReceiptTypeIsDeliveryReceipt`, `testUnknownAssociatedTypeIsPreserved`
  - Existing IMessageChannelTests and thread-preview filter remain green
- test_plan: 4 new tests in `IMessageChannelTests.swift` using in-memory SQLite fixture with varied `associated_message_type` values.

## Done / archived

### REP-067 — SearchIndex: FTS5 snippet extraction for search results
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: `SearchResult` type with `threadID` and `snippet: String?` fields. `search(query:)` returns `[SearchResult]`. FTS5 `snippet()` wired on message body column (col 3) with `«»` markers and 8-token context window. Worker note: used col 3 (message body) rather than col 1 (thread_name) for semantic correctness. 4 tests in `SearchIndexSnippetTests`.

### REP-169 — DraftEngine: N-concurrent-thread primes don't leak in-flight tasks (stress test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: 2 tests in `DraftEngineTests`: `testConcurrentPrimesOnDistinctThreadsAllReachReady` and `testNoPrimingStateLeaksAfterConcurrentPrimes`. 10 threads primed concurrently via `DispatchQueue.concurrentPerform`; all reach `.ready`.

### REP-188 — RulesStore: rules persisted in insertion order, not sort order
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: 1 test `testDiskRoundTripPreservesInsertionOrder` in `RulesTests`: add A (priority 0) then B (priority 5), export+import, assert A before B.

### REP-189 — DraftEngine: LLM stream error transitions state to `.idle`, not stuck in `.priming`
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: 2 tests in `DraftEngineTests`: `testPrimeErrorLeavesEngineInIdleNotErrorState` and `testPrimeSucceedsAfterPreviousError`. Uses `ThrowingStubLLMService` then `StubLLMService` in sequence.

### REP-199 — InboxViewModelAutoPrimeTests: fix non-deterministic crashes under Swift 6 + macOS 26.3
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `BlockingMockChannel` mutable fields migrated to `Locked<T>` backing stores; `InboxViewModelAutoPrimeTests`, `InboxViewModelThreadSelectionTests`, `InboxViewModelReselectTests` gain isolated `RulesStore` + `SearchIndex` per test. Eliminates TOCTOU data race and cross-test SharedState interference under Swift 6 strict-concurrency.
- test_plan: Targeted test-class runs confirm 0 crashes; 493 tests total (grep-verified).

### REP-201 — AGENTS.md: correct stale commit SHA `904b0e7` → `7512321` in done-log
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326
- files_to_touch: `AGENTS.md`
- scope: SHA `904b0e7` (non-existent) replaced with `7512321` (verified valid) for worker-2026-04-23-020741 contract-tests batch. Test count updated 463 → 493 (grep-accurate).
- test_plan: N/A (docs-only).

### REP-165 — SearchIndex: `clear()` method to wipe and rebuild
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Add `clear()` to `SearchIndex` that executes `DELETE FROM thread_search` and resets the per-channel indexed-message counter in `Stats` to zero. Tests: upsert 3 threads, call `clear()`, search returns empty; upsert again after clear → searchable; concurrent `clear()` + `upsert()` does not crash.
- test_plan: 3 new tests in `SearchIndexTests.swift` using in-memory `SearchIndex`.

### REP-176 — DraftStore: 7-day prune threshold removes old files and preserves recent ones (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: `DraftStore.init()` prunes draft files older than 7 days. Tests: file aged 8 days deleted on init; file aged 6 days survives init.
- test_plan: 2 new tests in `DraftStoreTests.swift` using setAttributes modificationDate.

### REP-180 — PromptBuilder: system prompt precedes all conversation history in output
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: Pin contract: system instruction appears before first message line in buildPrompt output. Tests: `testSystemPromptPrecedesConversationHistory`, `testAllMessagesFollowSystemBlock`.
- test_plan: 2 new tests in `PromptBuilderTests.swift` using fabricated messages and `.casual` tone.

### REP-181 — IMessageSender: -1708 retry count capped, not infinite
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-064 added -1708 retry. Pin retry cap: all-failing hook throws after ≤ maxRetry+1 calls; one-failure hook succeeds after 2 calls.
- test_plan: 2 new tests using call-counting hook closures; no real AppleScript.

### REP-182 — DraftEngine: empty LLM stream produces `.idle` not stuck `.priming`
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Empty stream (zero chunks, normal completion) should transition to `.idle`, not stay in `.priming`. Tests: `testEmptyLLMStreamTransitionsToIdle`, `testEmptyLLMStreamDoesNotCrash`.
- test_plan: 2 new tests using `EmptyStubLLMService` that returns a zero-yield stream.

### REP-184 — SearchIndex: 3-word query requires all 3 terms (explicit AND semantics test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Extend AND-semantics coverage to 3-word queries. "quick lazy fox" returns empty (no thread has all 3). Guards FTS5 query from accidentally switching to OR.
- test_plan: 3 new tests in `SearchIndexTests.swift` with overlapping-term threads.

### REP-185 — ContactsResolver: TTL expiry forces re-query on next call (cache invalidation test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: ttl=0 forces store re-query on second call (count==2); ttl=9999 uses cache (count==1). Documents TTL contract.
- test_plan: 2 new tests using `MockContactsStore` with call counter.

### REP-186 — IMessageChannel: messages within a thread ordered newest-first
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: Pin sort order: first returned message has latest date regardless of DB insert order. Guards against SQL ORDER BY direction change.
- test_plan: 2 new tests using in-memory SQLite fixture.

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

### REP-148 — RuleEvaluator: `apply()` output contract tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-149 — Stats: `acceptanceRate(for:)` nil-vs-zero distinction
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-150 — SearchIndex: `Result` struct fields populated correctly from upsert data
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-151 — IMessageChannel: `secondsSinceReferenceDate` autodetect at exact magnitude boundary
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-152 — PromptBuilder: all-messages-from-same-sender produces valid prompt
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-153 — DraftEngine: `invalidate()` on uncached thread is idempotent
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-154 — RulesStore: `update()` with unknown UUID is a no-op
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-157 — SmartRule: empty `and([])` evaluates to vacuous true
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-158 — IMessageSender: `chatGUID(for:)` format for 1:1 vs group thread
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-160 — Stats: concurrent mixed-counter stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-161 — SmartRule: `textMatchesRegex` with anchored patterns (^ and $)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-166 — RuleEvaluator: empty-rules-array edge cases (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-172 — AttributedBodyDecoder: zero-length and all-zero blobs return nil (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-173 — ChatDBWatcher: repeated stop→reinit cycles complete without crash (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-174 — IMessageSender: special-character escaping in AppleScript string construction
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-175 — RulesStore: `import()` merge-not-replace semantics (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-105 — Stats: persist lifetime counters to disk across app launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-064432

### REP-139 — Stats: flushNow() for clean-shutdown counter persistence
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-064432

### REP-159 — IMessageChannel: `MessageThread.hasAttachment` from message-level SQL field
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-064432

### REP-146 — IMessageChannel: per-thread message cap applied independently across threads
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-055654

### REP-156 — ContactsResolver: `name(for:)` fallback to raw handle when store returns nil
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-055654

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

### REP-142 — InboxViewModel: watcher-driven sync updates existing thread previewText
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-155 — InboxViewModel: re-selecting same thread does not double-prime
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-167 — Preferences: all AppStorage key strings are distinct (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-168 — InboxViewModel: isSyncing flag transitions during syncFromIMessage
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-171 — Stats: snapshot() dictionary contains all expected counter keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-199 — InboxViewModelAutoPrimeTests: fix non-deterministic crashes under Swift 6 + macOS 26.3
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326

### REP-201 — AGENTS.md: correct stale test count 463 → 493 in header
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326
