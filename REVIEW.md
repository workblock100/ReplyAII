# REVIEW.md

Weekly quality assessments written by the reviewer agent every Sunday. Most recent at top.

The reviewer never modifies code — only this file, AGENTS.md, and the planner's backlog. If quality trends badly, it pushes a `STOP AUTO-MERGE` item to BACKLOG.md.

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
