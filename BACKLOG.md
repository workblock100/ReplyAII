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


### REP-003 — better AttributedBodyDecoder (real typedstream parser)
- priority: P0
- effort: L
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-173600
- files_to_touch: `Sources/ReplyAI/Channels/AttributedBodyDecoder.swift`, `Tests/ReplyAITests/AttributedBodyDecoderTests.swift` (new)
- scope: Current implementation is a naive byte-scan that misses common patterns (nested `NSMutableAttributedString`, multi-attribute-run strings, longer length prefixes). Replace with a proper typedstream reader covering enough of the format to extract all `NSString` and `NSMutableString` payloads from typical iMessage rich-text blobs. Reference spec: https://github.com/dgelessus/python-typedstream — port the relevant bits.
- success_criteria:
  - Parses: typedstream header, class references, object references, length-prefixed strings (short, 16-bit, 32-bit)
  - Handles nested `NSMutableAttributedString` containing `NSMutableString`
  - Returns concatenated plain text when multiple string runs exist
  - New test file with at least 6 hand-crafted blob fixtures covering: simple string, escaped chars, multi-run attributed string, UTF-8 with emoji, empty body, malformed blob (returns nil, no crash)
  - `[non-text message]` fallback frequency drops materially against a sample of real chat.db rows (qualitative — noted in commit message)
- test_plan: write fixtures as hex-encoded `Data` literals in the test file; no real-user data in the repo.

## P1 — significant value, not urgent

### REP-004 — thread-list filter for `silentlyIgnore` action parity
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Today `.archive` and `.silentlyIgnore` both add the thread to `archivedThreadIDs`. Semantically they should differ: `silentlyIgnore` should additionally suppress the menu-bar popover and any future notification. Add `silentlyIgnoredThreadIDs: Set<String>` persisted to UserDefaults, filter those out of `MenuBarContent.waitingThreads`, and make archive the visible-in-menu-bar case.
- success_criteria:
  - Two distinct persisted sets
  - `MenuBarContent` filters out silently-ignored threads (archived still show in menu bar count)
  - Tests confirm both sets persist independently and `silentlyIgnore` doesn't leak into archive
- test_plan: `testSilentlyIgnoreAndArchiveAreDistinct`, `testMenuBarHidesSilentlyIgnored`.

### REP-005 — observability: counters in `.automation/stats.json`
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181957
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift` (new), `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/StatsTests.swift` (new)
- scope: Add a lightweight `Stats` observable (in-memory, written to `~/Library/Application Support/ReplyAI/stats.json` on change). Counts: `rulesFiredByAction: [String: Int]`, `draftsGenerated: Int`, `draftsSent: Int`, `messagesIndexed: Int`. Hook counter increments at the points they happen (InboxViewModel for rules/archive/send, DraftEngine for drafts). No UI yet — just persist. Surfacing in set-privacy comes in a follow-up.
- success_criteria:
  - Thread-safe like `ContactsResolver` (NSLock-guarded)
  - JSON round-trip + reload on instantiate
  - Wired at the three primary increment sites
  - Tests for the counter math and persistence
- test_plan: `testCountersIncrement`, `testStatsRoundTripThroughJSON`, `testIncrementsFromMultipleThreadsAreSerialized`.

### REP-006 — IMessageSender: test AppleScript escaping against weird inputs
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: Current escape pair is `\\` and `\"`. Real messages can contain backticks, `$(...)`, newlines, null bytes, zero-width chars, Emoji ZWJ sequences. Add a `chatGUID` + text-escape helper that's explicitly tested against a fixture of adversarial inputs. No behavior change for normal strings — pure hardening.
- success_criteria:
  - New exposed `IMessageSender.escapeForAppleScriptLiteral(_:)` (internal but testable)
  - Test fixture of at least 10 weird inputs: quotes inside quotes, backticks, control chars, very long strings, mixed scripts
  - Each fixture round-trips to a script that would be safe to execute (we can't actually run AppleScript in the test; just verify the escape output never contains an unescaped `"` or ends with `\`)
- test_plan: property-style test — for each input, assert `countOccurrences(unescaped \") == 0` on the output.

### REP-007 — ChatDBWatcher test coverage (debounce + cancel)
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182346
- files_to_touch: `Tests/ReplyAITests/ChatDBWatcherTests.swift` (new), possibly `Sources/ReplyAI/Channels/ChatDBWatcher.swift` (inject DispatchQueue for testability)
- scope: `ChatDBWatcher` has no tests. The debounce behavior (coalesce burst writes into one fire) is subtle and easy to regress. Add a test suite that: triggers N simulated writes within the debounce window and asserts exactly one `onChange` callback fires; triggers writes across the window and asserts two fires; calls `stop()` and asserts no further fires. Mechanism: inject an NSRunLoop-driven expectation or use a subclass that exposes `scheduleFire()` directly.
- success_criteria:
  - Tests don't touch a real file system — refactor to accept an injected "change signal" for testability OR use a tempfile + touch to trigger real fsevents (slower but realer)
  - Minimum 4 cases: single fire, burst coalesces, across-window produces two, stop() halts
- test_plan: see above.

### REP-008 — contextual preview: link + attachment detection
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelPreviewTests.swift` (new)
- scope: Current thread preview is the last message's raw text or `[non-text message]`. When the body is a URL, show "🔗 <host>". When the body is empty but the decoder found an attachment marker, show "📎 Attachment" instead of `[non-text message]`. Pure display logic — no data changes. Add a small extractor + tests.
- success_criteria:
  - URL detection: single-URL message → "🔗 example.com" (scheme-stripped, host only)
  - Empty body + typedstream with attachment sentinel → "📎 Attachment"
  - Regular text unchanged
  - Tests for each case
- test_plan: call the new extractor directly from a test; no SQLite needed.

### REP-014 — IMessageChannel: SQL query + date-autodetect unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182949
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift` (new), `Sources/ReplyAI/Channels/IMessageChannel.swift` (expose `secondsSinceReferenceDate` as internal)
- scope: `IMessageChannel.recentThreads` builds an SQL query against chat.db and contains `secondsSinceReferenceDate(appleDate:)` magnitude autodetect — both are untested. Use an in-memory SQLite database (via the existing `sqlite3` C API) populated with hand-crafted rows to test: the query returns threads sorted by recency, the magnitude cutoff correctly identifies nanosecond vs. seconds timestamps, NULL `text` rows fall back to attributedBody decode, the `chat_identifier` projection is correct for 1:1 vs. group chats.
- success_criteria:
  - In-memory SQLite fixtures — no dependency on real `~/Library/Messages/chat.db`
  - `secondsSinceReferenceDate(appleDate:)` made `internal` (not `private`) so tests can call it directly
  - 5 tests: sort order, magnitude-detection-nanosecond, magnitude-detection-seconds, null-text-fallback, group-chat-guid-projection
  - All 60 existing tests remain green
- test_plan: `testThreadsSortedByRecency`, `testDateAutodetectNanoseconds`, `testDateAutodetectSeconds`, `testNullTextFallsBackToAttributedBody`, `testGroupChatGUIDProjection`.

### REP-015 — SearchIndex: incremental upsert path for watcher events
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182615
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Sources/ReplyAI/Channels/ChatDBWatcher.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: `SearchIndex.rebuild()` re-inserts every thread on every watcher fire. For large inboxes this becomes O(n) work for each incoming message. Add `upsert(thread: MessageThread)` that does a single FTS5 `INSERT OR REPLACE` keyed by `thread_id`. Wire it in `InboxViewModel`'s watcher callback for new/updated threads so the index gets incrementally updated. `rebuild()` stays for initial load. Tests verify upserted threads are searchable and that a second upsert with updated text replaces the prior entry.
- success_criteria:
  - `SearchIndex.upsert(thread:)` method added
  - `InboxViewModel.handleIncomingMessages(_:)` calls `upsert` for each new/updated thread instead of `rebuild`
  - `rebuild()` still called on initial sync only
  - 3 new tests: `testUpsertMakesThreadSearchable`, `testUpsertReplacesStaleEntry`, `testRebuildStillWorksAfterUpsert`
  - All existing SearchIndex tests remain green
- test_plan: extend existing `SearchIndexTests.swift` with the 3 new cases.

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

### REP-011 — ContactsResolver: cache + access-state unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift` (new), `Sources/ReplyAI/Channels/ContactsResolver.swift` (inject mock)
- scope: `ContactsResolver` has NSLock-guarded cache logic and an access-state machine (unknown/granted/denied) with no tests at all. Extract `CNContactStore` behind a narrow injectable protocol (`ContactsStoring`) so tests can provide deterministic responses. Test: cache hit skips store call; cache miss queries store + populates cache; two concurrent calls for the same handle both resolve without deadlock; access state transitions correctly from `.unknown` to `.granted` and `.denied`.
- success_criteria:
  - `ContactsResolver` accepts a `ContactsStoring` dependency (default: the real `CNContactStore`) without changing the public `name(for:)` API
  - 4 new tests: cache hit, cache miss + population, concurrent access (XCTestExpectation-based), access state transitions
  - All 55 existing tests remain green
- test_plan: `testCacheHitReturnsCachedName`, `testCacheMissQueriesStore`, `testConcurrentResolutionIsSafe`, `testAccessStateMachineTransitions`.

### REP-012 — RulesStore: remove / update / resetToSeeds test coverage
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore` has `remove`, `update`, and `resetToSeeds` methods called directly from the rules UI but none are tested. Extend `RulesTests.swift` (same temp-file pattern as `testStoreRoundTripsAddedRule`) with: rule removal persists (second instance doesn't find the removed rule), update mutates an existing rule and round-trips, resetToSeeds restores the canonical defaults, removing a non-existent UUID is a safe no-op.
- success_criteria:
  - 4 new test functions, all using temp-file injection to avoid touching production storage
  - `testRemoveRulePersistsToDisk`, `testUpdateRulePersists`, `testResetToSeedsRestoresDefaults`, `testRemoveNonExistentUUIDIsNoOp`
  - All existing tests stay green
- test_plan: mirror `testStoreRoundTripsAddedRule` setup (temp directory URL injected into `RulesStore(fileURL:)`).

### REP-013 — Preferences: factory-reset + defaults round-trip tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift` (new)
- scope: `registerReplyAIDefaults` and `wipeReplyAIDefaults` in `Preferences.swift` have no tests. Write a test suite using a suiteName-isolated `UserDefaults` (never `.standard`) so tests don't pollute the running app's preferences. Verify: `registerReplyAIDefaults` seeds all expected keys to their `PreferenceDefaults` values; `wipeReplyAIDefaults` removes every `pref.*` key; wipe does NOT remove non-`pref.*` keys; default values match the `PreferenceDefaults` enum constants.
- success_criteria:
  - 4 tests using `UserDefaults(suiteName: "test.ReplyAI.prefs")` — isolated, torn down in `tearDownWithError`
  - `testRegisterDefaultsSeedsCorrectValues`, `testWipeRemovesPrefKeys`, `testWipePreservesNonPrefKeys`, `testDefaultValueMatchesEnum`
  - All existing tests stay green
- test_plan: suite tearDown calls `UserDefaults.standard.removePersistentDomain(forName:)` on the test suite name.

---

## Done / archived

(Planner moves finished items here each day. Worker never modifies this section.)

### REP-003 — better AttributedBodyDecoder (real typedstream parser)
- priority: P0
- effort: L
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-173600

### REP-005 — observability: counters in `.automation/stats.json`
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181957

### REP-007 — ChatDBWatcher test coverage (debounce + cancel)
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182346

### REP-015 — SearchIndex: incremental upsert path for watcher events
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182615

### REP-014 — IMessageChannel: SQL query + date-autodetect unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182949

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
