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

### REP-001 — persist `lastSeenRowID` across app launches
- priority: P0
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: `lastSeenRowID: [String: Int64]` currently lives in memory. Every relaunch zeros it, which causes every rule action to re-fire against the entire chat.db the next time the watcher triggers sync. Persist via `UserDefaults` under `pref.inbox.lastSeenRowID` as a JSON-encoded `[String: Int64]`, same pattern as `archivedThreadIDs`.
- success_criteria:
  - `InboxViewModel.init` hydrates `lastSeenRowID` from UserDefaults
  - `didSet` on the field writes through
  - New test: mutate watermarks → create a second `InboxViewModel` → watermarks survive
  - All existing tests stay green
- test_plan: add `testLastSeenRowIDPersistsAcrossInstances` mirroring `testArchivedIDsPersistAcrossInstances` exactly.

### REP-002 — SmartRule priority + conflict resolution
- priority: P0
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`, AGENTS.md
- scope: When multiple rules match the same thread+tone, today the first-added wins. AGENTS.md flags this as a TODO. Add an `Int` `priority` field to `SmartRule` (default 0, higher wins), teach `RuleEvaluator.matching` to sort matches by priority DESC before returning, and update `defaultTone(for:in:)` to obey. Keep JSON round-trip compatible — missing `priority` decodes as 0.
- success_criteria:
  - `SmartRule` gains `priority: Int` with default 0 and Codable-compatible handling for existing `rules.json`
  - `RuleEvaluator.matching` returns results sorted by priority DESC, then original order as tiebreaker
  - `defaultTone(for:in:)` picks the highest-priority match's tone
  - New tests: two-rule conflict, explicit priority wins; tiebreaker preserves insertion order; existing rules.json without priority still loads
- test_plan: add `testHigherPrioritySetDefaultToneWins`, `testPriorityFieldMissingDefaultsToZero`, `testPriorityRoundTripsThroughJSON`.

### REP-003 — better AttributedBodyDecoder (real typedstream parser)
- priority: P0
- effort: L
- ui_sensitive: false
- status: open
- claimed_by: null
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
- status: open
- claimed_by: null
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
- status: open
- claimed_by: null
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
- status: open
- claimed_by: null
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
- status: open
- claimed_by: null
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

---

## Done / archived

(Planner moves finished items here each day. Worker never modifies this section.)
