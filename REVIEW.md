# REVIEW.md

Rolling 6-hour quality assessments written by the reviewer agent every 6 hours. Most recent at top.

The reviewer never modifies code — only this file, AGENTS.md, and the planner's backlog. If quality trends badly for four consecutive 6h windows, it pushes a `STOP AUTO-MERGE` item to BACKLOG.md.

---

## Window 2026-04-22 22:10 – 2026-04-23 04:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Best single window of the run so far. **7 substantive worker commits closing 30 REP tickets** (REP-066, -098, -099, -101, -103, -104, -108, -109, -110, -114, -115, -116, -117, -118, -119, -120, -121, -122, -123, -124, -125, -126, -127, -128, -130, -131, -132, -134, -136, -137, -138, -140, -141, -143, -144, -145, -147), **9 claim/AGENTS chores**, **2 hash-fixup commits**, and **3 planner refreshes** (run10 → run12). Test suite grew **320 → 404 (+84 tests)** — verified by `grep -c "func test" Tests/ReplyAITests/*.swift` = 404. One new production file (`Sources/ReplyAI/Services/DraftStore.swift`, +80 LOC, REP-066) with 112 LOC of paired test coverage. Test add ratio ≈ **7:1 tests:source** by line count (heavy because the queue this window was almost entirely S/M test-coverage items). Zero banned-action violations: no `#Preview`, no sandbox flip, no `Info.plist` / `Package.swift` / `project.yml` / `scripts/*` / `design_handoff_replyai/` touches, no test-file shrinkage, no force-pushes or rebases. Commit messages cite every REP ID and explain *why* — REP-066 names cold-start LLM re-prime as the motivation, REP-128 documents iMessage-prefix-only validation scope, REP-117 calls out the silent-row-drop bug it fixes.

### Shipped this window (substantive worker commits, newest first)

- **REP-126 / -128 / -130 / -134 / -137 / -138 / -140 / -141 / -143 / -144 / -145 / -147** (`7132176`) — 12-ticket bundle. `IMessageSender.SendError.invalidChatGUID` + `isValidChatGUID()` pre-flight (rejects malformed iMessage GUIDs at the API boundary, not at AppleScript dispatch). `Preferences.firstLaunchDate` set-once key (added to `wipeExemptions` so privacy reset doesn't reset onboarding age). `ReplyAIApp.init()` writes `firstLaunchDate` once. `PromptBuilder.minHistoryReserve` + `systemPrompt(tone:)` with truncation guard (oversized system instructions can't squeeze message history below the floor). `DraftEngine.dismiss()` now deletes the on-disk `DraftStore` entry (matches the in-memory clear). `InboxViewModel` gets injectable `searchIndex` for archive→index integration tests. New `SearchIndex` disk round-trip + concurrent upsert/delete race tests close the suggestion from the prior review.
- **REP-127 / -131 / -132 / -136** (`79e02df`) — `DraftEngine` trims leading/trailing whitespace on `.done` so the composer doesn't show LLM-emitted blank prefixes. `ChatDBWatcher.stop()` becomes idempotent under double-call (deinit race + explicit stop) and a callback-not-fired-after-stop test pins the cancel semantics. `regenerate()` already serializes via `tasks[key]?.cancel()` — new tests confirm exactly one `.ready` state under overlapping concurrent calls. AGENTS.md test-count duplication addressed (header now authoritative, parenthetical removed).
- **REP-066** (`79fc909`) — `DraftStore` persists completed draft text to `~/Library/Application Support/ReplyAI/drafts/<threadID>.md` on the `.done` chunk so user edits survive crashes and intentional quits. `InboxViewModel.selectThread` seeds `userEdits` from the store before the LLM re-primes, so the composer is populated immediately on app open. Files older than 7 days are pruned on `DraftStore.init()`. New file (+80 LOC) plus `DraftStoreTests.swift` (+112 LOC, 5 cases including concurrent write+read race REP-147).
- **REP-108 / -110 / -115 / -117** (`e33be0d`) — `ContactsResolver` flushes its name cache on `CNContactStoreDidChange` (NotificationCenter is injectable so tests stay isolated from the system center). `RulesStore.export` wraps in `{ "version": 1, "rules": [...] }` envelope; `import` throws `unsupportedExportVersion` for non-1, future schema migration becomes a clear error not silent corruption. `Preferences.launchCount` increments per `ReplyAIApp.init()` and is wipe-exempt. `messages(forThreadID:limit:)` emits a `[deleted]` placeholder for rows where both `text` and `attributedBody` are NULL (deleted/unsent/unsupported-extension messages no longer create silent gaps in the thread view).
- **REP-116 / -118 / -119 / -125** (`7181beb`) — `SmartRule.hasUnread` predicate, `DraftEngine` archive→dismiss eviction integration test, search result hard-cap of 50, and FTS5 upsert ghost-term coverage (delete-then-reinsert at the same rowid must not leave stale tokens). All four are pure correctness coverage adds.
- **REP-120 / -121 / -122 / -123 / -124** (`f5ae41d`) — `RulesStore` concurrent-add stress test (200 callers under `Locked<T>` invariant), `PromptBuilder` large-payload truncation behavior pinned, `IMessageChannel` Apple-reference-date autodetect boundary cases (the 2001-seconds vs nanoseconds magnitude split), `Stats` invariants under concurrent increment, and a pinned-thread sort regression guard.
- **REP-098 / -099 / -101 / -103 / -104 / -109 / -114** (`4035c5a`) — Pure test additions (320 → 331 in this commit alone, no production-code change): `DraftEngine` cache isolation across `(threadID, tone)`; `ThrowingStubLLMService` + `FailOnceThenSucceedService` for LLM error/retry coverage; `SearchIndex` delete-reinsert FTS5 tombstone round-trip; two-channel filter integration; `InboxViewModel` thread recency ordering; `Preferences.wipeReplyAIDefaults` scope bounded to known keys only.

### Test coverage delta

- **+84 tests (320 → 404).** Verified locally by `grep -c "func test" Tests/ReplyAITests/*.swift`. The +84 also matches the worker's own test-count claim in `d8941b6`.
- Source: ~+260 LOC of production Swift across 6 modified files + 1 new (`DraftStore.swift`, 80 LOC). Tests: ~+1,820 LOC across 12 test files. Add ratio ≈ **7:1**.
- Test files expanded: `RulesTests` (+263), `SearchIndexTests` (+253), `DraftEngineTests` (+318), `DraftStoreTests` (+112 net), `InboxViewModelTests` (+102), `ContactsResolverTests` (+91), `PreferencesTests` (+93), `PromptBuilderTests` (+75), `IMessageSenderTests` (+43), `IMessageChannelTests` (+45), `ChatDBWatcherTests` (+32), `StatsTests` (+26). **Zero test files shrunk.**
- One legitimate test rename in REP-128 (`testEmptyGUIDThrowsInvalid` → `testInvalidGUIDThrowsInvalid` because `chatGUID(for:)` synthesizes empty strings away before reaching `sendRaw`). Empty-string coverage moved to direct-call `testEmptyGUIDIsValidationFailed`. Coverage equivalent — not a test deletion.

### Concerns

- **`7132176` is a 12-ticket bundle.** Per-ticket scope is small and per-file diffs are clean, but a wide bundle makes `git bisect` painful if any one of the twelve regresses. Future planner could cap bundles at ≤8 tickets when possible. Not rating-affecting — work is real, tested, and the worker log enumerates per-file changes.
- **`isValidChatGUID` is iMessage-only.** Worker log notes "SMS GUIDs correctly fail validation" — fine for today since the SMS send path isn't wired, but this guard will need to widen (or move to a per-channel `validateGuid` protocol method) when SMS write lands. Worth a follow-up planner task.
- **Two more hash-fixup commits this window** (`05ad9b5`, `0d1915e`). Same protocol noise flagged in the prior review. Not a quality issue, but the suggestion stands.

### Suggestions for next planner cycle

1. **Archive sweep next run.** 30 tickets closed this window — confirm REP-066, -098, -099, -101, -103, -104, -108, -109, -110, -114, -115, -116, -117, -118, -119, -120, -121, -122, -123, -124, -125, -126, -127, -128, -130, -131, -132, -134, -136, -137, -138, -140, -141, -143, -144, -145, -147 all move from open → archived in BACKLOG before the next planner cycle.
2. **Cap bundle size at 8 tickets per worker commit.** Easier bisect, cheaper rollback if any single ticket regresses.
3. **Open a follow-up for cross-channel GUID validation.** Generalize `IMessageSender.isValidChatGUID` to a `Channel.validateGuid(_:)` (or add a sibling `SmsChannelSender.isValidGuid()`) before SMS send is wired — cheaper to design now than to retrofit later. S-effort, non-ui.
4. **Hash-fixup protocol tweak.** Standing item — defer worker-log self-referential commit hash to `.automation/logs/worker-<id>-hash.txt` written post-push so main history stops accumulating one-line `fixup` commits.
5. **Drop "disk-backed SearchIndex smoke test" from next planner.** Closed by REP-126 in `7132176` this window.

### Rolling-window pattern

Last seven windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-2210.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-23-0403.md` (this) — ⭐⭐⭐⭐⭐

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 16:03 – 2026-04-22 22:10 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Strongest window of the day. **8 substantive worker commits closing 25 REP tickets** (REP-032, -035, -037, -041, -042, -053, -054, -061, -073, -074, -080, -084, -085, -092, -093, -094, -095, -096, -097, -100, -102, -106, -107, -112, -113), **8 claim chores**, **3 fixup commits** (worker-log hash backfills + one AGENTS.md *(pending)* replacement), and **3 planner refreshes** (run7 → run9). Test suite grew **254 → 320 (+66 tests, confirmed by local `swift test` → 320 Executed, 0 failures in 8.5s)**. Worker LOC split: **+392/-83 source, +1,098/-23 tests** — a **~2.8:1 test-to-source add ratio**. Zero banned-action violations: no `#Preview`, no sandbox flip, no `Info.plist` / `Package.swift` / `project.yml` / `scripts/*` / `design_handoff_replyai/` touches, no history rewrites. Commit messages explain *why* consistently (ContactsResolver TTL 30 min rationale in `9879312`, the dual-interception critique behind the `isDryRun → executeHook` refactor in `eaa0b39`, the cold-start motivation for on-disk FTS5 in `7196e9d`).

### Shipped this window (substantive worker commits, newest first)

- **REP-097 / REP-100 / REP-106 / REP-107 / REP-112 / REP-113** (`80035e1`) — `SmartRule.messageAgeOlderThan(hours:)` predicate plus `lastMessageDate` on `RuleContext` and `currentDate` injection into `matches()` so age tests are clock-independent. Remaining five items test-only: De-Morgan / double-negation coverage for `not`, `or([])` + 3+-branch cases, 200-concurrent-caller `Stats` increment stress test proving `Locked<T>` loses no updates, `DraftEngine.dismiss()` idle/noop/isolation transitions, and `PromptBuilder` non-empty + distinct system-instruction assertions per tone. **304 → 320 tests**.
- **REP-074 / REP-095 / REP-096 / REP-102** (`9879312`) — `ContactsResolver` injectable `ttl` (default 30 min) so stale post-launch contact names self-invalidate; tests use `ttl=0` to force re-query without a clock. `messages(forThreadID:)` convenience overload with default `limit=20` codifies the "don't load hundreds on sync" invariant. First test coverage for `InboxViewModel` send success/failure fork (toast naming on success; error surfaced + `userEdits` preserved on failure). Two tests pin down the empty-query `[]` contract in `SearchIndex`. **294 → 304 tests**.
- **REP-041 / REP-073** (`7196e9d`) — On-disk FTS5 database under `~/Library/Application Support/ReplyAI/search.db` so existing rows are searchable before cold-start sync completes. `SearchIndex(databaseURL:)` initializer (nil = in-memory for tests, URL = file-backed for prod); `SearchIndex.productionDatabaseURL()` helper mirrors the `RulesStore`/`Stats` pattern. `PromptBuilder.truncate` promoted private→internal with injectable budget; two new invariant tests: short-history passthrough + most-recent-message retention on truncate. **294 tests, 0 failures**.
- **REP-035 / REP-042** (`a5bd7a4`) — `RulesStore.export(to:)` atomic JSON write and `import(from:)` with UUID-keyed merge (update existing, append new, skip malformed — same resilience policy as REP-024). 4 new XCTests: round-trip, merge, in-place update, malformed-entry skip. AGENTS.md "What's done" synced.
- **REP-053 / REP-061 / REP-084 / REP-093 / REP-094** (`eaa0b39`) — Dropped `IMessageSender.isDryRun` in favor of a no-op `dryRunHook()` via the existing `executeHook` seam (one interception point instead of two). `rulesMatchedCount` counter added at all three `RuleEvaluator.matching` call sites in `InboxViewModel`. `RulesStore` load/save switched off `.standard` onto the injected `UserDefaults` to enable per-test isolation (prereq for archive persistence coverage). `testBothNullProducesEmptyMessage` verifies the SQL-level `text IS NOT NULL OR attributedBody IS NOT NULL` filter and the message-preview fallback. `testFuzzRandomBlobsNeverCrash` pushes 10k random 0–4096-byte blobs through `AttributedBodyDecoder.extractText`, asserting no trap + valid UTF-8 on any returned `String`. **→ 278 tests**.
- **REP-037 / REP-054** (`fa4d009`) — `DraftEngine` invalidates a stale in-flight draft when `ChatDBWatcher` refires for the same thread (prior behavior leaked a draft generated against out-of-date context). `ContactsResolver.batchResolve([handle])` replaces per-handle `CNContactStore` lookups on initial sync.
- **REP-032** (`038826e`) — Per-tone draft counters + acceptance-rate field on `Stats`, incremented from the DraftEngine acceptance path and surfaced via the existing `Stats` summary dict.
- **REP-080 / REP-085 / REP-092** (`6a629a2`) — `SearchIndex` FTS5 channel-column filter so per-channel searches don't pay for cross-channel token scans; FTS5 query sanitizer (escapes the three syntactic metacharacters before forwarding user input to `sqlite3_prepare_v2`); prefix-match (`term*`) test coverage.

### Test coverage delta

- **+66 tests (254 → 320).** Confirmed by `swift test`: `Executed 320 tests, with 0 failures (0 unexpected) in 8.487 (8.504) seconds`.
- Source: +392/-83 lines across worker commits. Tests: +1,098/-23 lines. Add ratio **~2.8:1** (tests vs. source).
- Test files expanded: `SearchIndexTests` (+211), `RulesTests` (+234), `IMessageChannelTests` (+134), `InboxViewModelTests` (+127), `ContactsResolverTests` (+100), `StatsTests` (+112), `DraftEngineTests` (+102), `PromptBuilderTests` (+42), `AttributedBodyDecoderTests` (+25), `IMessageSenderTests` (+11/-23).
- The `IMessageSenderTests` 11/23 delta is a **legitimate refactor**, not a test deletion: `testDryRunReturnsSuccessWithoutScript` + `testDryRunOffInvokesScript` were rewritten to `testDryRunHookReturnsSuccessWithoutScript` + `testCustomHookIsInvokedOnSend` as part of REP-093 removing the `isDryRun` dual-interception surface. Coverage equivalent, cases simpler.

### Concerns

- **One planner→worker timing ordering quirk.** `fa4d009` (REP-037/054 implementation) is author-timestamped 14:17 EDT, *earlier* than the planner's `b363d08` (14:33) but pushed after `eaa0b39`. Not a correctness issue — author-timestamps from local clocks just aren't monotonic across agents. Worth a note that `git log --since` filtering leans on author-time, so a worker commit that lands just outside a 6h window may be attributed to the wrong review boundary. Low-impact; no action needed this window.
- **`AGENTS.md` narrative test-count vs. header test-count are both 320, but in *two separate places*.** Line 97 (repo-layout fence) and line 226 (Testing expectations) each hard-code the number. Keep both in sync or collapse to a single authoritative line — minor, not rating-affecting. (Not touched this review; both are current.)
- **Two fixup commits for log-hash backfill.** `7030acb` + `4ce30fd` + `2e4a9f5` are the worker's standard "commit log refers to myself, need to rewrite hash after push" chore — protocol-compliant, but three extras in main history per window is a smell. Planner could consider whether the worker log's "commit hash" field truly needs to be self-referential in the first commit, or if a follow-up hash could be written in a separate post-push log file instead.

### Suggestions for next planner cycle

1. **Archive run10 sweep of the 25 closed tickets.** REP-032, -035, -037, -041, -042, -053, -054, -061, -073, -074, -080, -084, -085, -092, -093, -094, -095, -096, -097, -100, -102, -106, -107, -112, -113. Confirm every one moved from P1/P2 body → Done in BACKLOG before the next planner refresh.
2. **Consider a log-hash protocol tweak.** Either defer the worker log's `commit:` field to a companion `.automation/logs/worker-<id>-hash.txt` written after push, or accept the fixup commits and note the pattern in `AUTOMATION.md` so future reviewers don't flag them. Current three-commit fixup pattern is cosmetic noise in history.
3. **Queue balance.** Run9 landed 11 new tasks and the worker drained 25 — net -14 tickets. Planner should sustain this draft-rate rather than over-bursting P2 ideation; the 30-task floor is the right guardrail, not a target.
4. **Consolidate `AGENTS.md` test count to one line.** Currently duplicated at lines 97 and 226. Reviewer-edit-only. Small mechanical cleanup for next review.
5. **Exercise the new `SearchIndex` disk-persistence path in an integration smoke test.** `7196e9d` added the file-backed store but only the in-memory path runs under `swift test`. A write-open-reopen-read round-trip (dropping a `URL(fileURLWithPath:)` temp file) would catch regressions in `productionDatabaseURL()` layout / migration if we ever change schema. Could ship as a single-commit S-effort task.

### Rolling-window pattern

Last six windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-2210.md` (this) — ⭐⭐⭐⭐⭐

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 10:03 – 2026-04-22 16:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Clean continuation of the prior window. **4 substantive worker commits closing 12 REP tickets** (REP-030/031/040/059/064/069/072/076/077/078/039/071/081), **5 claim chores**, and **3 planner refreshes**. Test suite grew **211 → 254 (+43 tests)** with a test-to-source line ratio of **~3.3:1** (740 test lines vs. 224 source lines across 6 test files and 8 source files). Zero banned-action violations: no `#Preview`, no sandbox flip, no `Info.plist`/`Package.swift`/`project.yml`/`scripts/*` touches, no test-file shrinkage, no history rewrites. Commit messages name every REP closed and explain the *why* — length-guard rationale in `7667f22`, observation-pattern reuse in `bbedd1a`, the explicit "UI wiring deferred to human" note in `3169995`.

### Shipped this window (substantive worker commits, newest first)

- **REP-039 / REP-071 / REP-081** (`874f483`) — `pref.rules.autoApplyOnSync` + `pref.drafts.autoPrime` feature flags gating `InboxViewModel.syncFromIMessage`'s rule application and `selectThread`'s draft prime. `primeHandler` closure injection lets tests record prime calls without standing up a real `DraftEngine`. New `StaticMockChannel` test double + 9 new test cases (3 thread-selection, 2 auto-prime, 2 auto-apply-rules, 2 preference round-trips).
- **REP-059 / REP-064 / REP-069 / REP-076 / REP-077 / REP-078** (`7667f22`) — the window's largest commit. 4096-char message length guard in `IMessageSender` before any AppleScript touch (REP-064). Single transient-retry on `-1708 errAEEventNotHandled` during Messages.app cold start / iCloud sync (REP-059). 100-rule hard cap on `RulesStore.add()` with new `tooManyRules` error (REP-069). Optimistic local unread-count clear on `selectThread`, plus `markUnreadZero` fixed to preserve `chatGUID` + `hasAttachment` (REP-076). New `ChannelService.databaseCorrupted` case + `SQLITE_NOTADB` (26) detection in `openReadOnly` so the UI can route to a re-sync recovery path distinct from generic DB failure (REP-077). +3 `handleReply` test cases in `NotificationCoordinatorTests` (REP-078).
- **REP-072** (`bbedd1a`) — `InboxViewModel` now observes its own `pendingNotificationReply` via `withObservationTracking` (same pattern as rules observation) and dispatches `IMessageSender.send` on arrival. Uses `chatGUID` from the loaded thread — correctly avoids synthesizing a 1:1-shaped GUID for group chats. Unknown thread IDs are logged and discarded without crash. Closes the "UNNotification inline reply consumption" gap from the prior window's concerns.
- **REP-030 / REP-031 / REP-040** (`3169995`) — `pref.inbox.threadLimit` + `pref.drafts.autoPrime` preference keys (REP-030 + partial REP-039). `RuleValidationError` + `SmartRule.validateRegex` + `RulesStore.addValidating` surface invalid regex patterns at creation time rather than silently failing eval (REP-031). `IMessageSender.isDryRun` flag with injectable executor exercises the full send path in tests without AppleScript side-effects (REP-040). "ComposerView wiring deferred to human review" for the UI-sensitive remainder of REP-039 — honest scope call.

### Test coverage delta

- **+43 tests (211 → 254).** Grep-based count; sandbox can't run `swift test`.
- Source: +224 lines across 8 files. Tests: +740 lines across 6 files. Ratio ≈ **3.3:1**.
- Existing test files expanded: `InboxViewModelTests` (+302), `IMessageSenderTests` (+137), `RulesTests` (+137), `PreferencesTests` (+68), `NotificationCoordinatorTests` (+53), `IMessageChannelTests` (+43). **Zero test files shrunk.**
- Per-commit test-count claims (232 → 245 in `7667f22`, "24 targeted / 9 new" in `874f483`) line up with the grep delta.

### Concerns

- **Claim/substantive ratio slightly worse than ideal.** 5 claim commits vs. 4 substantive this window. Not rating-affecting, but main-branch history reads as 9 worker items where 4 would suffice. Worth a planner nudge to batch the claim and work into one commit where it doesn't break claim-visibility.
- **Stall-reset race in `run6`.** Planner reset REP-039/071/081 as a stalled claim, and the same worker shipped all three 33 minutes later in `874f483`. Not a correctness bug (worker didn't re-claim between reset and push) but the planner's stall rule could factor in worker-log mtime before resetting. Low probability of a real collision at current fire cadence, but a cheap tuning win.
- **AGENTS.md test-count line drift.** Top-of-file repo layout said "245 tests" at review start — one version behind after `874f483`. Updated in this review.
- **AGENTS.md narrative stale copy.** "60 tests today" in the testing-expectations section is off by ~200. Non-structural, but the planner should scrub it.

### Suggestions for next planner cycle

1. **Run7 archive pass on all 12 tickets closed this window** — REP-030, -031, -039, -040, -059, -064, -069, -071, -072, -076, -077, -078, -081. Confirm every one is `status: done` in BACKLOG before the next planner refresh.
2. **Augment stall detection with worker-log mtime.** If `.automation/logs/worker-<id>.md` has been written to within the last ~30 min, don't reset the claim even if it's been open for >2 planner cycles. Prevents the REP-039 race pattern.
3. **Encourage claim+work batching.** One combined commit per substantive unit — body notes the claim-id, diff shows the work — halves the main-branch noise without weakening the substantiveness gate.
4. **Clean the AGENTS.md narrative test count.** Line 216 "60 tests today" should either drop the number or become a planner-refreshed counter like line 97.
5. **Queue balance.** 45 open tasks after three planner runs this window. Healthy. Next cycle can keep additions and closures roughly in balance — no need for a fresh burst of P2 ideation while the worker is draining this pool cleanly.

### Rolling-window pattern

Last five windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` (this) — ⭐⭐⭐⭐⭐

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 04:03 – 2026-04-22 10:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Exceptional window. Worker drained a huge slice of the P1 backlog — **11 substantive commits closing ~15 REP tickets** against 11 protocol-compliant claim chores. Test suite grew **158 → 211 (+53 tests)**, with tests file delta of **+1,126 lines vs. +580 source lines** (ratio ≈ 1.9:1, well above the proportional bar). Zero banned actions in the cumulative diff: no `#Preview` macros, no sandbox entitlement changes, no test-file shrinkage, no history rewrites. The prior review's stall concern (REP-022 / REP-024 claimed but still `in_progress`) was closed in the first commit of this window (`76850a9`) — worker cleared the stall on its own. Commit messages remain honest and explanatory (e.g. `9810196` explains why UNNotification category registration is entitlement-free; `ec9e723` breaks out three distinct root causes for REP-063/65/68 in separate paragraphs).

### Shipped this window (substantive worker commits, newest first)

- **REP-063 / REP-065 / REP-068** (`ec9e723`) — `SearchIndex.delete(threadID:)` purges FTS5 on archive; archive wired through new `InboxViewModel.archive(_:)`. Added 2 `senderIs` case-insensitivity tests. `cache_has_attachments` now projected from SQL into `Message.hasAttachment` + `MessageThread.hasAttachment`, replacing the fragile `📎 Attachment` sentinel scan in `RuleContext.hasAttachment`.
- **REP-034 / REP-056 / REP-057** (`ea37669`) — DraftEngine idle-entry eviction; Stats weekly-aggregate file writer; SearchIndex concurrent search+upsert stress test.
- **REP-052** (`8988959`) — ChatDBWatcher FSEvents error recovery with restart backoff.
- **REP-050** (`a7204d2`) — Extracted `Locked<T>` generic wrapper consolidating the `@unchecked Sendable + NSLock + synced{}` pattern across `ContactsResolver`, `Stats`. Net +32 lines in a new `Sources/ReplyAI/Utilities/Locked.swift` offset by -47 deleted duplicated lines elsewhere. +91 test lines in `LockedTests.swift`.
- **REP-028** (`9810196`) — NotificationCoordinator: UNNotification inline reply via `UNTextInputNotificationAction`, routes to `InboxViewModel.pendingNotificationReply`. `NotificationCenterProtocol` inserted for testability. +142 test lines.
- **REP-027** (`881d8f0`) — SearchIndex: explicit AND semantics for multi-word FTS5 queries (prior behavior was OR-leaning, leading to noisy results).
- **REP-026** (`9717756`) — PromptBuilder extracted from MLXDraftService with token-budget truncation (2000-char budget, oldest-first drop). +92 test lines.
- **REP-025** (`aa34006`) — IMessageSender AppleScript send timeout + injectable executor for tests. +49 test lines.
- **REP-049 / REP-051** (`1df1fce`) — DraftEngine concurrent prime guard + SQLite `databaseError` result-code propagation.
- **REP-023** (`5fedafc`) — InboxViewModel re-evaluates rules when RulesStore changes (matches the initial-sync rule behavior). +194 test lines (new `InboxViewModelTests.swift`).
- **REP-022 / REP-024** (`76850a9`) — InboxViewModel concurrent sync guard + RulesStore malformed-rule skipping on load. Closes the prior window's stall concern.

### Test coverage delta

- **+53 tests (158 → 211).** Largest single-window jump recorded so far.
- 4 new test files: `LockedTests.swift` (+91), `NotificationCoordinatorTests.swift` (+142), `PromptBuilderTests.swift` (+92), `InboxViewModelTests.swift` (+194).
- 7 existing test files expanded; **zero test files shrunk**.
- Source delta: +580 insertions / -128 deletions across 19 files. Test delta: +1,126 insertions / -3 deletions across 11 files. Test-to-source ratio ≈ 1.9:1.
- `swift test` not runnable in reviewer sandbox — audit count is from `grep -r "func test" Tests/` (211).

### Concerns

- **Claim-commit noise.** Ratio is still ~1:1 (11 claim vs. 11 substantive). Not rating-affecting, but the planner could plausibly batch claims per cycle — the main-branch history reads as 22 items where 11 would do.
- **REP-063 / notification-reply terminology drift.** AGENTS.md "What's still stubbed" says the reply-consumption follow-up is tracked as REP-063, but REP-063 as shipped this window was `SearchIndex.delete` for archived threads — unrelated. The actual InboxViewModel consumption of `pendingNotificationReply` still appears unfinished; planner should file a dedicated ticket with a correct ID rather than letting the stubbed-section reference rot.
- **wip/quality-* branches still unmerged.** Prior review flagged 7 of these from 2026-04-21; they're still sitting. REP-016 (senderKnown operator-precedence bug fix) in particular is a real correctness issue blocked on human review. No progress this window.
- **REP-008 sentinel copy decision** (`🔗 <host>` / `📎 Attachment`) still drifting. REP-062 was filed by the planner at the start of this window to capture it — good — but it's `claimed_by: human` so the worker won't touch it.

### Suggestions for next planner cycle

1. **Fix the stubbed-section REP-063 reference in AGENTS.md.** Either file a new ticket for InboxViewModel inline-reply consumption (I'd call it REP-069 given current numbering) and update the reference, or rewrite the stubbed entry to say "pending follow-up" without a ticket ID. The current state is misleading.
2. **Archive pass.** 15 REP items closed this window but only a subset of tickets flipped to `status: done` in BACKLOG.md in time for this review. Planner's next archive-verification sweep should walk commits `aa0d184..HEAD` and confirm every REP-id in a commit message has `status: done` set.
3. **Resist further task queueing.** P1 queue has been drawn down sharply — worker is catching up fast. Next planner run should emphasize archival + sharpening existing tickets over net-new adds, especially while human-owned wip/* branches pile up.
4. **Human-review nudge.** Four items remain blocked on human (REP-008 → REP-062 product-copy, REP-016 senderKnown precedence, REP-017 wip consolidation, REP-009/010 UI-sensitive). The bug fix is the only correctness-critical one; everything else is polish. Worth surfacing in tomorrow's standup digest.

### Rolling-window pattern

Last four windows (oldest → newest):

- `review-2026-04-21.md` — 5/5
- `review-2026-04-21-addendum.md` — 5/5
- `review-2026-04-21-2343.md` — 5/5
- `review-2026-04-22-0403.md` — 5/5
- `review-2026-04-22-1003.md` (this) — 5/5

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-21 22:03 – 2026-04-22 04:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Overlaps the prior 17:43–23:43 window by ~4h, so this rating scopes only the *new* worker activity since `review-2026-04-21-2343.md` landed. In that ~4-hour slice the worker shipped **4 substantive backlog items** (REP-018, REP-019, REP-020, REP-021) across two commits, added **+13 tests (145 → 158)** with ratios well above 1:1, and filed commit messages that actually explain the *why* (chat<N>-vs-E.164 group identifiers, triple-cache-miss from non-normalized phone handles, tapback rows polluting thread previews). Zero banned actions in the 6h cumulative diff: no `#Preview`, no sandbox flip, no shrunk test files, no history rewrites. REP-022 and REP-024 were claimed ~68 min ago and remain `in_progress` — within normal worker cadence, not yet a stall.

### Shipped this window (net-new since prior review)

- **REP-018 (P1, S)** — `RulePredicate.isGroupChat` + `hasAttachment`. isGroupChat detects the `chat<N>` identifier convention for group threads; hasAttachment matches the `📎 Attachment` sidebar sentinel. Covered in `RulesTests` with +87 new lines.
- **REP-019 (P1, S)** — `ContactsResolver.normalizedHandle()` collapses `+14155551234` / `14155551234` / `4155551234` to a single canonical 10-digit key before cache reads/writes. Prior behavior caused three cache misses on the same contact. +42 test lines in `ContactsResolverTests`.
- **REP-020 (P1, S)** — Thread-preview query now filters `associated_message_type 2000–2005` (tapback reactions) and NULL-text delivery receipts on both `last_msg_rowid` and `last_date` subqueries. Fixes previews like `"❤ to '…'"` shadowing the last real message.
- **REP-021 (P1, M)** — `IMessageChannel.recentThreads(limit:)` test coverage (60-row fixtures → limit-50 cap + recency ordering) plus a `ChannelService` protocol extension defaulting to limit=50 so callers can omit the page size.

### Test coverage delta

- **+13 tests** (145 → 158). No new test *files* this window — all growth is expansion of `RulesTests`, `ContactsResolverTests`, `IMessageChannelTests`.
- Test/LOC ratio: ~87 test lines for ~25 source lines on REP-018/19/20; ~45 test lines for ~30 source lines on REP-021. Both well above the proportional bar.
- No test files shrunk.
- `swift test` not runnable in the reviewer sandbox — audit count is from `grep -r "func test" Tests/ReplyAITests/`.

### Concerns

- **REP-022 / REP-024 claimed 68 min ago, still `in_progress`.** Worker fires every 15 min, so 4–5 cycles without a substantive commit. Not a stall yet (both are S and the substantiveness gate may be bundling them), but re-check next window — if still in_progress at the next 6h review, re-queue with the prior worker run marked failed.
- **7 open `wip/quality-*` branches** from yesterday's quality-pass session remain unmerged. The planner correctly filed REP-016 (senderKnown operator-precedence *bug fix* — real correctness issue on `.senderUnknown`) and REP-017 (consolidate overlaps) as human-owned. These should not sit for another 24h — the bug fix in particular.
- **Claim-commit ratio** still ~1:1 with substantive commits. Protocol-compliant, not rating-affecting, but if the planner can pre-batch claims per window the main history reads cleaner for the human.
- **Human-review flag from REP-008** (sidebar glyphs `🔗` / `📎`) was queued in the prior review and hasn't been scoped into a task yet — still drifting.

### Suggestions for next planner cycle

1. **Stop adding. Drain.** Planner added 32 tasks in today's run2 (REP-016 → REP-047); the queue is well-stocked. Next planner run should focus on archival (REP-018/19/20/21 all need to move to Done) and hold task additions until the worker draws the queue down below ~25 open.
2. **Escalate REP-016.** The senderKnown operator-precedence fix is a real bug, not style. It should jump the human-review queue above REP-017 (consolidation) and REP-009/010 (ui-sensitive feature work).
3. **Guardrail — stall detection for REP-022/024.** If still `in_progress` at the next 6h review, flip `claimed_by` to `worker-FAILED` and re-open. Add this rule to the planner's archive-verification pass so it catches stalls without reviewer intervention.
4. **Queue REP-008 glyph product-copy task.** One-line S-task: "product-copy pass on `🔗`/`📎` sidebar preview sentinels in `IMessagePreview`". Blocks on nothing; clears the pending human-review flag.

---

## Window 2026-04-21 17:43–23:43 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

This is the first real rolling window after the cadence cutover and the worker blew the doors off it. 20 commits to main by `ReplyAI Worker` (10 substantive + 10 claim chores), 11 backlog tasks closed (REP-003, -004, -005, -006, -007, -008, -011, -012, -013, -014, -015), test count jumped **60 → 145 (+85 new tests)** across 9 new/expanded test files. Every substantive commit shipped with proportional tests, commit messages accurately describe the diff, and no banned actions occurred (no `#Preview`, no sandbox flip, no shrunk test files, no history rewrites). The worker also correctly honored the substantiveness gate — no S-only commits when larger tasks were available. The only thing I'd nitpick is the volume of `chore: claim REP-XXX in progress` commits (10 of 20); that's protocol-compliant but noisy — if the planner can batch claim-commits per run, the main history will read cleaner at retrospective-time.

### Shipped this window

- **REP-003 (P0, L)** — Real typedstream parser replacing the byte-scan in `AttributedBodyDecoder`. +222 test lines with hand-crafted hex fixtures covering nested `NSMutableAttributedString`, UTF-8 emoji, malformed blobs. Last remaining P0 is now closed.
- **REP-004 / REP-006 / REP-012** — `silentlyIgnore` parity in the inbox filter, AppleScript-escape hardening in `IMessageSender`, and full `RulesStore` remove/update/resetToSeeds coverage. Shipped bundled per substantiveness gate.
- **REP-005** — Persistent counters (`Stats.swift`) for rules fired, drafts generated, messages indexed. +124 test lines.
- **REP-007** — `ChatDBWatcher` debounce + stop coverage (+108 test lines).
- **REP-008** — Link and attachment previews in the sidebar (`🔗 <host>` / `📎 Attachment`). Pure data-layer transform in `IMessagePreview`; worker correctly flagged the emoji glyph choice for human review rather than asserting it as final.
- **REP-011** — `ContactsStoring` protocol extracted; production path byte-for-byte identical, but the resolver is now fully test-coverable without `CNContactStore` hitting the real address book.
- **REP-013** — `Preferences.register` / `wipe` accept an injected `UserDefaults`; +90 test lines around factory-reset semantics.
- **REP-014** — `IMessageChannel.recentThreads` now backed by an injectable `dbPathOverride` + in-memory SQLite coverage including the nanoseconds-vs-seconds date autodetect edge case. +237 test lines.
- **REP-015** — Incremental FTS upsert path for watcher-driven syncs (unblocks the scale-out note in AGENTS.md Gotchas).

### Test coverage delta

- **+85 tests** (60 → 145, all green per local audit of `func test` declarations; no in-sandbox `swift test` available this run).
- New test files: `AttributedBodyDecoderTests`, `StatsTests`, `ChatDBWatcherTests`, `IMessageChannelPreviewTests`, `ContactsResolverTests`, `PreferencesTests`, `IMessageChannelTests`. Expanded: `RulesTests` (+179), `IMessageSenderTests` (+113), `SearchIndexTests` (+86).
- Test/LOC ratio is well above 1:1 on nearly every substantive commit. No test files shrunk.
- The only meaningful untested surface that remains is `MLXDraftService` (acceptable — 2 GB model download is not CI-friendly) and the view layer.

### Concerns

- **None material.** This is the cleanest automated window the project has produced.
- Minor: `claim REP-XXX in progress` commits now outnumber substantive commits 1:1 in the window. It's correct per protocol but a ratio worth watching — if it grows, consider a planner-side consolidation.
- Minor: AGENTS.md "Rich message decoding limits" and "FTS5 watcher updates" stub bullets are now stale; pruning them this review.

### Suggestions for next planner cycle

1. **REP-009 (Global `⌘⇧R`, P1)** — Remaining open task that isn't UI-sensitive-hard-block. Needs Accessibility permission + `NSEvent.addGlobalMonitorForEvents`. Worker should branch to `wip/` for the permission prompt path since the first run pops a system dialog the user has to satisfy.
2. **REP-010 (Slack OAuth, P1)** — Also still open. L effort; give it a dedicated run, not bundled. Keychain prefix convention (`ReplyAI-`) is already documented in AGENTS.md — worker should honor it verbatim for factory-reset parity.
3. **Test-count maintenance pace is excellent** — don't let it regress. +85 in one window is a high bar; planner should keep one "add coverage to X" S-task in the queue per 6h window to preserve the habit.
4. **Claim-commit noise** — consider having the planner pre-claim the next window's tasks in a single commit instead of the worker claiming per-task. Lower-signal history for the human reader.
5. **Human-review flag from REP-008** — the worker explicitly flagged `🔗` / `📎` glyph choices for human review. Queue an S-task for a product-level copy pass on sidebar previews so that decision is made deliberately, not by default.

---

## Automation First Fire — 2026-04-21 (Addendum) — ⭐⭐⭐⭐⭐

**Note:** This addendum supplements the founding-week review filed earlier today (see below). The automation loop ran in full for the first time between that review and this run.

The planner and worker both executed within hours of the founding-week review. The worker correctly applied the substantiveness gate (bundled S+M per protocol), resolved both remaining P0 backlog items (REP-001 and REP-002), added 5 targeted tests (55 → 60 total), shipped a clean debug build, and filed an honest run log. No banned actions. The automation loop is healthy on day 1.

### Shipped (automation round)

- **REP-001 (P0, S)** — `lastSeenRowID` persisted to UserDefaults (same pattern as `archivedThreadIDs`). Prevents rules from re-firing against the full chat.db history on every app relaunch. Key: `pref.inbox.lastSeenRowID`, JSON-encodes `[String: Int64]`.
- **REP-002 (P0, M)** — `SmartRule.priority: Int` (default 0, higher wins). `RuleEvaluator.matching` sorts priority DESC with insertion-order tiebreaker. `rules.json` files without the field decode cleanly as priority 0 — no migration needed.

### Test coverage delta (automation round)

- **+5 tests** (55 → 60): `testLastSeenRowIDPersistsAcrossInstances`, `testHigherPrioritySetDefaultToneWins`, `testPriorityFieldMissingDefaultsToZero`, `testPriorityRoundTripsThroughJSON`, `testPriorityTiebreakerPreservesInsertionOrder`
- Test/LOC ratio for this commit: ~100 test lines written for ~70 source lines — above the proportional bar.
- No test files shrank.

### Concerns

- None for the automation run itself. Both P0 bugs are fixed; automation is functioning correctly on day 1.
- REP-003 (AttributedBodyDecoder real typedstream parser, P0, effort L) is the last remaining P0. Worker cannot close it in one S/M pass — planner must dedicate a standalone run to it.

### Suggestions for next week's planner

1. **REP-003 (P0, L)** — Give the worker a full dedicated session for the typedstream parser. Don't bundle with other tasks — the spec port alone is M+ effort and needs focused test-fixture work.
2. **REP-004 (P1, S)** — `silentlyIgnore` vs `archive` distinction. S effort, clear success criteria; a clean pairing candidate for after REP-003 lands.
3. **Test-ratio maintenance** — REP-006 (IMessageSender escaping), REP-011 (ContactsResolver), REP-012 (RulesStore) are all well-scoped S/M test tasks. Planner should slot one per week to prevent the untested surface from widening.
4. **wip/ discipline** — No wip/ branches open yet (correct). When REP-009 (global hotkey) or REP-010 (Slack OAuth) are assigned, confirm the worker branches rather than merging direct to main.

---

## Week of 2026-04-21 — ⭐⭐⭐⭐⭐

**Rating: 5/5**

This is an extraordinary founding week. The project went from a blank repository to a fully functional macOS inbox app in 3.5 days — 23 commits, all by Elijah (human), with the autonomous automation infrastructure itself landing as the final commit on Apr 20. The core product loop is complete: read iMessages from chat.db, AI-draft replies via stub LLM or on-device MLX, edit the draft, confirm, and send via AppleScript. The rules engine (DSL, on-disk store, live UI, full pipeline firing on both thread-select and incoming messages) is an especially high-quality piece of work — hand-written Codable with a `kind` discriminator, pure-function evaluator, and 12 solid test cases. Commit messages are detailed and honest about scope. No banned-action violations anywhere. Sandbox correctly stays OFF. No `#Preview` macros. The automation agents (planner, worker, reviewer) haven't run yet — first worker fire expected this coming week.

### Shipped this week

- **Full app scaffold**: 34 screens translated from design handoff, SPM build without Xcode, streaming draft plumbing (LLMService/DraftEngine/StubLLMService)
- **Live iMessage sync**: chat.db reader (FDA-gated), ContactsResolver, AttributedBodyDecoder for typedstream fallback, ChatDBWatcher (600ms-debounced FSEvents), sync-status chip in sidebar
- **Editable composer + send**: TextEditor binding over draft stream, ⌘↵ AppleScript send via `tell application "Messages"`, two-step confirm sheet
- **MLX on-device LLM**: mlx-swift-lm 3.x behind a Settings toggle, model-load progress banner, ~2 GB HuggingFace snapshot on first enable
- **Smart Rules engine**: predicate DSL (7 primitive kinds + and/or/not), 5 actions, RulesStore with atomic JSON writes, rules fire on thread-select and on incoming messages (archive/markDone/silentlyIgnore)
- **FTS5 full-text search**: in-process SQLite FTS5 over live threads, ⌘K palette overlay with 120ms-debounced live results
- **Thread list polish**: pinned threads float top with `pin.fill` glyph + a11y label; archivedThreadIDs persisted via UserDefaults
- **Group chat sending**: chat.guid projected from SQL and passed verbatim to AppleScript (critical — synthesizing would address the wrong recipient)
- **Automation infrastructure**: AGENTS.md, BACKLOG.md (10 scoped tasks), .automation/{planner,worker,reviewer}.prompt, budget.json, REVIEW.md, AUTOMATION.md

### Test coverage delta

- **+55 tests** (0 → 55; all green, 0 failures)
- New test files: DraftEngineTests, LLMServiceTests, FixturesTests, ScreenInventoryTests, RulesTests, SearchIndexTests, IMessageSenderTests
- Strong coverage on pure-Swift logic: predicate evaluation, FTS5 query translation, GUID selection, Codable round-trips, rule pipeline end-to-end
- **Gaps** (all acknowledged in BACKLOG):
  - `ChatDBWatcher` — no tests; debounce behavior is subtle (REP-007, P1)
  - `AttributedBodyDecoder` — no tests; byte-scan approach is fragile (REP-003, P0)
  - `ContactsResolver` — no tests; cache correctness not verified
  - `IMessageChannel` — no unit tests; real-SQLite dependency makes this harder but fixtures could cover the query logic
  - `MLXDraftService` — no tests; acceptable given ~2 GB model download requirement

### Concerns

- **`lastSeenRowID` resets on every relaunch** — rules re-fire against entire chat.db history on next sync. This is a real bug, not a polish item. REP-001 is correctly P0 in the backlog; worker should pick it up first.
- **Zero planner/worker runs so far** — expected (automation launched Apr 20), but next week's review will assess whether the automated loop produces the same quality bar that Elijah's human commits set. The bar is high.
- **`AttributedBodyDecoder` is fragile** — a naive byte-scan that misses common patterns. Modern iOS messages (link previews, tapbacks, reactions) will render as `[non-text message]` frequently. REP-003 is P0 for a reason.
- **`RuleEvaluator` first-match-wins** is documented but not yet resolved. With the seed rules, conflict is unlikely, but once users add their own rules this will surface. REP-002 is correctly P0.
- **AGENTS.md test count is stale** — says "46 XCTest cases" and "34 tests" in the repo layout section; actual is 55. Corrected in this review run.

### Suggestions for next week's planner

1. **Worker's first task: REP-001** (persist `lastSeenRowID`) — S effort, P0, directly prevents rule double-firing on every relaunch. Ship it day 1.
2. **Follow with REP-002** (SmartRule priority + conflict resolution) — M effort, P0, prevents silent misbehavior once users have multiple rules.
3. **REP-003** (real typedstream parser) is L effort — assign it to a dedicated session, not a one-hour worker run. Planner should schedule as a multi-run task or flag it ui_sensitive to get human review.
4. **REP-007** (ChatDBWatcher tests) — M effort, P1. The debounce behavior is exactly the kind of thing that regresses silently. Schedule in the same week as REP-001.
5. **Planner should verify the automation heartbeat early**: confirm planner-YYYY-MM-DD.md logs are appearing under `.automation/logs/` by Wednesday. If not, the scheduled task may need a clock fix.
6. **For UI-sensitive work** (REP-009 global hotkey, REP-010 Slack OAuth): worker correctly branches to `wip/`; planner should track open wip/ count and alert if it exceeds 3.

---
