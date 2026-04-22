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
  - Test count on main increases from 158 (minimum: +8 from RuleContext/RuleEvaluator coverage, +5 from DraftEngine coverage = 171+)
  - No duplicate test functions in merged result
- test_plan: Human runs `grep -r "func test" Tests/ReplyAITests/ | wc -l` before and after to confirm net gain.

### REP-022 — InboxViewModel: concurrent sync guard
- priority: P1
- effort: S
- ui_sensitive: false
- status:   done
- claimed_by: worker-2026-04-21-025439
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift` (new)
- scope: `InboxViewModel.syncFromIMessage()` is called from two sites: the `ChatDBWatcher` callback and a manual refresh. If both fire simultaneously (watcher fires while a slow initial sync is in progress), two concurrent sync tasks race and can produce duplicate threads or torn state. Add a `private var isSyncing = false` guard on `@MainActor`. If `isSyncing` is true when `syncFromIMessage()` is called, return early without launching a second task. Test with a mock `IMessageChannel` that blocks on the first call: verify a concurrent second call is a no-op.
- success_criteria:
  - `isSyncing` guard prevents overlapping sync tasks
  - Flag is reset to false in both the success and error paths
  - `testConcurrentSyncCallsDoNotOverlap`: two rapid calls result in exactly one `recentThreads` invocation
  - Existing behavior (single sync completes normally) unchanged
- test_plan: New `Tests/ReplyAITests/InboxViewModelTests.swift` with a blocking mock channel.

### REP-023 — InboxViewModel: rule re-evaluation when RulesStore changes
- priority: P1
- effort: M
- ui_sensitive: false
- status:   done
- claimed_by: worker-2026-04-22-043231
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift` (extend or new)
- scope: Rules currently fire on thread-select and on incoming watcher events. If the user adds/edits a rule while threads are visible, the change has no immediate effect — the user has to re-select a thread or wait for the watcher. Add a `withObservationTracking` or explicit subscription to `RulesStore.rules` in `InboxViewModel`. When the rule list changes, re-evaluate all currently loaded threads and apply any new rule actions (pin, archive, setDefaultTone). This is pure in-memory re-evaluation — no SQLite re-query needed. Test: add a rule after threads are loaded; verify the action fires on the existing thread list without a sync.
- success_criteria:
  - `InboxViewModel` observes `RulesStore.rules` changes
  - On change, `applyRules(to: threads)` re-fires for all loaded threads
  - New rule with `.pin` action immediately pins the matching thread
  - Test verifies the re-evaluation path with a mock RulesStore + thread fixture
- test_plan: `testRuleAdditionTriggersReEvaluation`, `testRuleChangeUpdatesPinnedThreads`.

### REP-024 — RulesStore: validate + skip malformed rules on load
- priority: P1
- effort: S
- ui_sensitive: false
- status:   done
- claimed_by: worker-2026-04-21-025439
- files_to_touch: `Sources/ReplyAI/Rules/RulesStore.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore.load()` currently does a single `JSONDecoder().decode([SmartRule].self, from: data)`. A single malformed rule entry in `rules.json` crashes the entire decode and leaves the user with no rules. Wrap each rule's decode in a try-catch using a `[DecodableSmartRule]` intermediate: decode the array as `[[String: AnyCodable]]`, then attempt `JSONDecoder().decode(SmartRule.self, ...)` per element, skip failures. Log the skip count to `Stats.shared.ruleLoadSkips` (add a new counter). Test: a rules.json with one valid + one malformed entry loads correctly with one rule and increments the skip counter.
- success_criteria:
  - Partial-failure decode: N valid + M malformed → N rules loaded, M logged to Stats
  - No crash on any malformed input (fuzz: empty object, wrong type for `kind`, missing `id`)
  - `testMalformedRuleIsSkipped`, `testPartiallyCorruptRulesFileLoadsValidRules`
  - Existing `RulesTests` remain green
- test_plan: Write malformed rule JSON as a fixture string; inject via temp-file URL.

### REP-025 — IMessageSender: AppleScript execution timeout
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-013926
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: `NSAppleScript.executeAndReturnError` is a synchronous blocking call. If Messages.app hangs (happens during iCloud sync), the call blocks the caller's thread indefinitely. Wrap in a `DispatchQueue.global().async` + `DispatchSemaphore` pattern with a 10-second timeout. If the semaphore wait times out, return a `ChannelError.sendFailed("AppleScript timed out")` error. Add an `IMessageSender.sendTimeout: TimeInterval` injectable property (default 10s) to make the timeout testable. Test with a mock that never signals the semaphore; verify timeout error within 1s (use a 0.1s injected timeout for speed).
- success_criteria:
  - Timeout path returns `ChannelError.sendFailed` (not a hang)
  - Normal path unaffected (signals semaphore before timeout)
  - `sendTimeout` is injectable for test speed
  - `testSendTimeoutReturnsError`, `testNormalSendCompletesBeforeTimeout`
- test_plan: Inject a 0.1s timeout + a mock that blocks; verify error returned within 0.5s.

### REP-026 — DraftEngine: extract + test prompt template construction
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Sources/ReplyAI/Services/PromptBuilder.swift` (new), `Tests/ReplyAITests/PromptBuilderTests.swift` (new)
- scope: The prompt template is currently assembled inline inside `DraftEngine`. Extracting it into a `PromptBuilder` struct makes it testable, easy to tune, and visible for review without wading through async streaming logic. `PromptBuilder.build(thread: MessageThread, tone: Tone) -> String` produces the full prompt string. Unit tests assert: thread context (sender, channel, recent messages) is included; tone label appears in the prompt; long message histories are truncated to fit a token budget (estimate at 1 char ≈ 0.25 tokens; cap at 2000 chars of history); the prompt never includes raw newlines that would break a single-line instruction format.
- success_criteria:
  - `PromptBuilder.build(thread:tone:)` extracted and tested in isolation
  - DraftEngine delegates to PromptBuilder — no behavior change
  - 5 tests: tone label present, thread context present, long-history truncation, empty-message fallback, non-iMessage channel label
- test_plan: `Tests/ReplyAITests/PromptBuilderTests.swift` — pure Swift, no async needed.

### REP-027 — SearchIndex: multi-word AND query support
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex.search(query:)` passes the raw query string to FTS5. A query like "hello world" is interpreted by FTS5 as a phrase (adjacent "hello world"), not an AND of the two terms. For an inbox search, AND semantics ("must contain both words anywhere in the thread") are more useful. Preprocess the query: split on whitespace, strip FTS5 special chars, rejoin with ` AND ` for 2+ tokens. Single-token queries pass through unchanged. Test with a thread containing "hello" but not adjacent to "world" — verify it matches "hello world" as an AND query but not a phrase query.
- success_criteria:
  - "hello world" → `hello AND world` in FTS5
  - Single word unchanged; empty query returns empty results (not a crash)
  - Multi-word query matches threads containing both words non-adjacently
  - `testMultiWordAndSemantics`, `testSingleWordUnchanged`, `testEmptyQueryReturnsEmpty`
  - Existing `SearchIndexTests` remain green
- test_plan: Extend `SearchIndexTests.swift` with 3 new cases using in-memory FTS5.

### REP-028 — UNNotification: register inline reply action on launch
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/App/ReplyAIApp.swift`, `Sources/ReplyAI/Services/NotificationCoordinator.swift` (new), `Tests/ReplyAITests/NotificationCoordinatorTests.swift` (new)
- scope: Register a `UNNotificationCategory` with a `UNTextInputNotificationAction` (identifier: "REPLY") so the system shows an inline reply field on ReplyAI notifications. Create `NotificationCoordinator` (`@Observable @MainActor`) that: requests UNAuthorizationOptions (.alert, .badge, .sound) on first launch, registers the "REPLY" category, implements `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` to extract the reply text and route to `InboxViewModel.pendingNotificationReply`. Wire into `ReplyAIApp.init()`. Tests use a mock `UNUserNotificationCenter` (protocol-extracted) to verify: category registered on launch, delegate callback extracts text correctly, authorization re-request is skipped if already granted.
- success_criteria:
  - `UNUserNotificationCenter` usage behind an injectable protocol for testability
  - Category registered with "REPLY" action identifier
  - `testCategoryRegisteredOnLaunch`, `testDelegateExtractsReplyText`, `testAuthorizationSkippedIfGranted`
  - No production entitlement changes required (UNNotification works without sandbox)
- test_plan: Mock `UNUserNotificationCenter` protocol; inject into `NotificationCoordinator` constructor.

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

### REP-049 — DraftEngine: concurrent prime guard
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-011918
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine.prime(for thread:tone:)` starts an async stream task. If called twice for the same `(threadID, tone)` before the first completes (e.g., rapid thread re-selection), two concurrent streams run and both try to update the same `DraftState`. Add a `private var primingTasks: [String: Task<Void, Never>]` (keyed by `"\(threadID):\(tone.rawValue)"`). Before starting a new prime, cancel any existing task for that key and replace it. This ensures at most one in-flight stream per (thread, tone) — the prior behavior silently accumulated dangling tasks. Tests: rapid double-prime cancels the first task before starting the second; state reflects the second prime's output.
- success_criteria:
  - At most one in-flight prime per (threadID, tone) at any time
  - Prior task is cancelled (not leaked) before a new one starts
  - `testDoublePrimeCancelsFirst`, `testDoublePrimeResultReflectsSecond`
  - Existing DraftEngine tests remain green
- test_plan: Extend `DraftEngineTests.swift` with 2 new cases using a slow mock `LLMService`.

### REP-050 — Extract `Locked<T>` generic wrapper to consolidate NSLock pattern
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Utilities/Locked.swift` (new), `Sources/ReplyAI/Channels/ContactsResolver.swift`, `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/LockedTests.swift` (new)
- scope: `ContactsResolver` and `Stats` both use the `@unchecked Sendable + NSLock` pattern with a private `synced { }` wrapper. AGENTS.md calls this a consolidation candidate when 3+ sites use it. Extract `struct Locked<T>: @unchecked Sendable` with `withLock<U>(_ block: (inout T) throws -> U) rethrows -> U`. Update `ContactsResolver.cache` and `Stats.counters` to use `Locked`. Scan the codebase for additional `@unchecked Sendable + NSLock` pairs and update those too. Behavior is identical — this is a pure refactor with tests verifying thread-safety semantics.
- success_criteria:
  - `Locked.swift` added to `Sources/ReplyAI/Utilities/`
  - `ContactsResolver` and `Stats` (and any other sites found) refactored to `Locked<T>` with no behavior change
  - `LockedTests.swift`: concurrent read + write stress test confirms no data races
  - All existing tests remain green after refactor
- test_plan: `testConcurrentReadWriteIsThreadSafe` (DispatchQueue.concurrentPerform), `testWithLockRethrows`, `testInitialValue`.

### REP-051 — IMessageChannel: preserve sqlite3 result code in ChannelError
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-011918
- files_to_touch: `Sources/ReplyAI/Channels/ChannelService.swift`, `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `ChannelError.databaseError(String)` discards the numeric sqlite3 result code (e.g., `SQLITE_BUSY = 5`, `SQLITE_LOCKED = 6`, `SQLITE_AUTH = 23`). Change to `ChannelError.databaseError(code: Int32, message: String)`. Update all `IMessageChannel` callsites that throw `databaseError` to pass `sqlite3_errmsg` plus the raw result code. This makes REP-029's SQLITE_BUSY retry cleaner — the caller checks `code == SQLITE_BUSY` rather than string-matching. Update the existing tests that pattern-match on `databaseError` to also assert the `code` field.
- success_criteria:
  - `ChannelError.databaseError(code: Int32, message: String)` replaces the single-String variant
  - All `IMessageChannel` throw sites updated
  - Existing tests updated to assert `code` field
  - `testDatabaseErrorPreservesCode`: inject a bad db path, verify SQLITE_CANTOPEN (14) is preserved
- test_plan: Extend `IMessageChannelTests.swift`; trigger a real `sqlite3_open` failure with a bad path.

### REP-052 — ChatDBWatcher: FSEvents error recovery with restart backoff
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/ChatDBWatcher.swift`, `Tests/ReplyAITests/ChatDBWatcherTests.swift`
- scope: `DispatchSource.makeFileSystemObjectSource` can be cancelled by the system (e.g., if `chat.db` is moved or the file descriptor becomes invalid). Currently the `cancel` handler is not set — the source silently stops delivering events and the sync chip freezes. Add a `cancel` handler that schedules a restart via `DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay)` where `restartDelay` starts at 5s and doubles on repeated cancellations (capped at 60s). Add a `stopWatching()` public method that cancels without restart (for clean shutdown). Expose `restartDelay: TimeInterval` as injectable for tests. Test: inject a mock source that fires the cancel handler; verify restart is scheduled; `stopWatching()` cancels without scheduling restart.
- success_criteria:
  - Cancel handler set in `startWatching`
  - Restart scheduled after cancellation with 5s initial backoff, capped at 60s
  - `stopWatching()` cancels without triggering restart
  - `testCancellationSchedulesRestart`, `testStopWatchingDoesNotRestart`
- test_plan: Extend `ChatDBWatcherTests.swift` with 2 new cases using injectable mock source.

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

### REP-029 — IMessageChannel: SQLITE_BUSY graceful retry
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `sqlite3_open` on `chat.db` can return `SQLITE_BUSY` when macOS Messages holds a write lock (common during iCloud sync). Currently we surface a generic error. Add a retry: on `SQLITE_BUSY`, sleep 100ms and retry once before failing. Open with `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` flags to prevent write-lock escalation. Test by intercepting the `sqlite3_open` call via a `ChatDBOpener` injectable closure that returns `SQLITE_BUSY` on the first call and `SQLITE_OK` on the second. Complements REP-051 (error code preservation makes SQLITE_BUSY detection cleaner).
- success_criteria:
  - Single retry on SQLITE_BUSY with 100ms delay
  - Open flags include `SQLITE_OPEN_READONLY`
  - `testSQLiteBusyRetriesOnce`, `testSQLiteBusyTwiceThrows`
- test_plan: Injectable `ChatDBOpener` closure in `IMessageChannel`; default uses real `sqlite3_open`.

### REP-030 — Preferences: pref.inbox.threadLimit setting
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
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
- status: open
- claimed_by: null
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

### REP-033 — SearchIndex: FTS5 BM25 relevance ranking
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: FTS5 supports `rank` (BM25 score, more negative = more relevant) via a special column. Currently results are returned in arbitrary order. Add `ORDER BY rank` to the FTS5 query so more relevant matches surface first. The `SearchResult` type (or whatever `search(query:)` returns) should optionally expose the rank score for future use. Tests: insert threads with varying match quality; verify exact-match thread ranks above a thread where the term appears only once in a long preview.
- success_criteria:
  - `ORDER BY rank` added to FTS5 query
  - Results array order reflects relevance (most relevant first)
  - `testExactMatchRanksAbovePartialMatch`, `testResultsOrderedByRelevance`
  - Existing SearchIndex tests remain green
- test_plan: Extend `SearchIndexTests.swift` with 2 new ranking cases.

### REP-034 — DraftEngine: draft cache eviction for idle entries
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine` stores one `DraftState` per `(threadID, tone)` pair in a dictionary. This grows unboundedly as the user browses threads. Add `evict(threadID: String)` (called when a thread is deselected in `InboxViewModel`) that removes all tone entries for that thread from the cache. Add a `cacheSize: Int` computed property for testability. Tests: prime a draft for thread A, evict A, verify cache is empty; prime drafts for threads A and B, evict A, verify B remains.
- success_criteria:
  - `evict(threadID:)` removes all tone entries for that thread
  - `cacheSize` computed property counts live entries
  - `InboxViewModel` calls `engine.evict(threadID:)` on thread deselection
  - `testEvictClearsSingleThread`, `testEvictLeavesOtherThreadsIntact`
- test_plan: Extend `DraftEngineTests.swift` with 2 new cases.

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

### REP-036 — IMessageChannel: Message.isRead from chat.db is_read column
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Models/Message.swift` (or `MessageThread.swift`), `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: The SQL query already reads `message.is_read`, but it's not surfaced on the `Message` model. Add `isRead: Bool` to `Message` and project it from the query result. Use it to compute an accurate `MessageThread.unread` count rather than the heuristic currently in place. Test with in-memory SQLite fixtures containing a mix of read and unread rows; verify the thread's `unread` count matches exactly.
- success_criteria:
  - `Message.isRead: Bool` field added
  - `MessageThread.unread` computed from actual `is_read` values, not a heuristic
  - `testUnreadCountFromIsReadColumn`, `testAllReadThreadHasZeroUnread`
  - Existing IMessageChannelTests remain green
- test_plan: Extend `IMessageChannelTests.swift` with 2 new in-memory SQLite cases.

### REP-037 — ContactsResolver: batch resolution helper for initial sync
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/ContactsResolver.swift`, `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: During initial sync, `InboxViewModel` calls `resolver.name(for:)` once per thread — each call acquires and releases the `NSLock` (or `Locked<T>` after REP-050) separately. For a 50-thread inbox that's 50 lock acquisitions. Add `resolveAll(handles: [String]) -> [String: String]` that acquires the lock once, resolves all cache hits in-lock, identifies misses, releases, then queries the store for misses, re-acquires to write results. Net: 2 lock acquisitions regardless of inbox size. Tests verify: the result matches serial resolution output, cache hits don't invoke the store, mixed cache-hit/miss scenarios are correct.
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
- status: open
- claimed_by: null
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
- scope: After REP-016, REP-017, and REP-048 land (wip branch merges), the `What's done` section in AGENTS.md will be stale: test count will have grown past 158, and new commits will not be listed. Update: (1) prepend the merged commits to the `What's done` list; (2) update the `N XCTest cases, all green` line in the repo layout and `Testing expectations` sections; (3) remove any `What's still stubbed` bullets that were resolved by merged work. This is a docs-only commit — no code changes.
- success_criteria:
  - `What's done` list is current with main branch commits
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
- scope: Once REP-022 lands and `InboxViewModelTests.swift` exists, extend it with archive/unarchive round-trip coverage. `InboxViewModel` stores `archivedThreadIDs` in `Preferences`. Test: archive a thread → `threads` list no longer contains it; unarchive → it reappears; persisted across a simulated relaunch (wipe + re-init of Preferences with suiteName-isolated UserDefaults). Requires the mock channel from REP-022.
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

### REP-055 — IMessageChannel: map message.date_delivered to Message.deliveredAt
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Models/Message.swift`, `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: The `message` table has a `date_delivered` column (same Apple reference-date epoch as `date`). Add `deliveredAt: Date?` to the `Message` model. Project it from the SQL query using the same `secondsSinceReferenceDate` conversion already used for `date`. `deliveredAt` is nil for messages with `date_delivered = 0`. Existing `MessageBubble` can use this field in a future UI pass for a "Delivered" tick mark. Tests: a row with `date_delivered > 0` produces a non-nil `deliveredAt`; a row with `date_delivered = 0` produces nil.
- success_criteria:
  - `Message.deliveredAt: Date?` field added and projected from SQL
  - `testDeliveredAtNonNilForDeliveredRow`, `testDeliveredAtNilForZeroValue`
  - Existing IMessageChannelTests remain green
- test_plan: Extend `IMessageChannelTests.swift` with 2 in-memory SQLite cases.

### REP-056 — Stats: weekly aggregate file writer
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: Add `Stats.writeWeeklyLog(to url: URL) throws` that serializes current counter values into a Markdown file formatted as `# Stats week of YYYY-MM-DD\n\n- rulesEvaluated: N\n- draftsSent: N\n...`. This method will be called by planner/reviewer scripts to produce `.automation/logs/stats-YYYY-WW.md` snapshots. Keep it simple: a point-in-time dump with no retention or rolling-window logic. Tests: output string contains all expected counter keys; zero-value counters are not omitted; method writes to the given file URL.
- success_criteria:
  - `Stats.writeWeeklyLog(to url: URL) throws` added
  - Output includes all current counter keys (including zero values)
  - `testWeeklyLogContainsAllCounters`, `testWeeklyLogWritesToFile`
- test_plan: Extend `StatsTests.swift` with 2 cases using temp-file URLs.

### REP-057 — SearchIndex: concurrent search + upsert stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex` wraps a SQLite FTS5 connection. Verify thread-safety by running 100 concurrent `upsert` + `search` calls via `DispatchQueue.concurrentPerform`. The test must not crash or corrupt the index. If `SearchIndex` is not currently thread-safe, add an `NSLock`-guarded wrapper around the sqlite handle as the fix (document why in a comment). Final search after all concurrent operations should return the expected result count.
- success_criteria:
  - `testConcurrentUpsertAndSearch` runs 100 concurrent operations without crash or corruption
  - Final result count is deterministic
  - If thread-safety fix needed, `NSLock` added and documented
- test_plan: Extend `SearchIndexTests.swift` with 1 stress test.

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
- scope: When REP-008 shipped the link + attachment preview feature, the worker chose `🔗 <host>` and `📎 Attachment` as the sentinel strings for link and attachment previews in `IMessagePreview`. These glyphs were explicitly flagged by the worker for human review (not asserted as final copy). Human should decide: (1) whether `🔗` and `📎` are the right glyphs vs alternatives (`↗`, `⊞`, `📸`, plain text); (2) whether `"Attachment"` is the right noun vs `"Media"` / `"Photo"` / `"File"`; (3) whether the space before the host name in `🔗 example.com` should be an en-space for visual rhythm. This is a product-copy decision, not a code question — update the two sentinel constants in `IMessagePreview.swift` once decided.
- success_criteria:
  - `linkPreviewSentinel` and `attachmentPreviewSentinel` constants reflect the decided copy
  - Existing tests updated if the sentinel strings change
  - Reviewer no longer flags this as an open human-review item
- test_plan: Human updates the constants; worker updates the 3 test assertions in `IMessageChannelPreviewTests.swift` that match against the sentinel strings.

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
