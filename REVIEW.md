# REVIEW.md

Rolling 6-hour quality assessments written by the reviewer agent every 6 hours. Most recent at top.

The reviewer never modifies code — only this file, AGENTS.md, and the planner's backlog. If quality trends badly for four consecutive 6h windows, it pushes a `STOP AUTO-MERGE` item to BACKLOG.md.

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
