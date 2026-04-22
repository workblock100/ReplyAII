# Planner log — 2026-04-22 (run 2)

status: OK

## Context

Second planner run on 2026-04-22. Previous run (`planner-2026-04-22.md`) left 43 open tasks. Since that run, the worker shipped 7 more tasks: REP-022, REP-023, REP-024, REP-025, REP-026, REP-049, REP-051. Additionally, a code audit found that REP-027 (SearchIndex multi-word AND) was already implemented in commit 687c5a3 (REP-015) but never had a separate task close. With 8 items done and 35 open, the pipeline was near the 30-task floor and needed topping up.

## Halt-condition check

- Last commit on main: `9717756` ("extract PromptBuilder + test coverage (REP-026)") — not a revert ✓
- Test count: `grep -r "func test" Tests/ReplyAITests/ | wc -l` = **179** (up from 158 at last planner run; worker added 21 tests across REP-022–026, REP-049, REP-051)
- Test count vs. 7 days ago: 60 → 179 (growth, not shrinkage) ✓
- wip/ branches: 8 open, all from 2026-04-21 — none older than 7 days ✓
- No binary blobs, no repo size anomaly ✓
- swift test: not runnable in this sandbox; test count audited via grep ✓

No halt. Proceeding.

## Archive verification

Items marked `status: done` in active sections but not yet in Done/archived:
- REP-022 → done (worker-2026-04-21-025439, concurrent sync guard) ✓
- REP-023 → done (worker-2026-04-22-043231, rule re-evaluation) ✓
- REP-024 → done (worker-2026-04-21-025439, malformed rule skipping) ✓
- REP-025 → done (worker-2026-04-22-013926, AppleScript timeout) ✓
- REP-026 → done (worker-2026-04-22-055650, PromptBuilder extract) ✓
- REP-049 → done (worker-2026-04-22-011918, concurrent prime guard) ✓
- REP-051 → done (worker-2026-04-22-011918, databaseError result code) ✓

Code audit finding (new this run):
- REP-027 (SearchIndex multi-word AND): `SearchIndex.ftsQuery` in commit 687c5a3 splits on whitespace and joins with space (FTS5 implicit AND), strips special chars, appends `*` for prefix. Tests `testIndexMultiTokenAND`, `testFTSQueryAppendsPrefix`, `testFTSQueryHandlesEmpty` all cover the success criteria. REP-027 is done — archived with note attributing to worker-2026-04-21-182615.

Code audit finding (partially done):
- REP-033 (SearchIndex BM25 ranking): `ORDER BY rank` is already in the FTS5 search SQL (commit 5f2a746, original FTS5 implementation). The success criteria tests (`testExactMatchRanksAbovePartialMatch`, `testResultsOrderedByRelevance`) are NOT yet written. Updated REP-033: changed scope to "tests only" since the implementation is done, changed effort M→S.

All 8 items moved to Done/archived.

## BACKLOG.md changes

### Archived (8 tasks)
- REP-022 (done, concurrent sync guard, worker-2026-04-21-025439)
- REP-023 (done, rule re-evaluation, worker-2026-04-22-043231)
- REP-024 (done, malformed rule skipping, worker-2026-04-21-025439)
- REP-025 (done, AppleScript timeout, worker-2026-04-22-013926)
- REP-026 (done, PromptBuilder extract, worker-2026-04-22-055650)
- REP-027 (done, SearchIndex AND/prefix — implemented in REP-015, worker-2026-04-21-182615)
- REP-049 (done, concurrent prime guard, worker-2026-04-22-011918)
- REP-051 (done, databaseError result code, worker-2026-04-22-011918)

### Updated (2 tasks)
- REP-033: scope changed to "add ranking tests only" (ORDER BY rank already in SQL); effort M→S
- REP-042: updated test count reference from 158 → 179; removed "after wip merges" prerequisite; expanded scope to include commits through REP-026

### Added (9 new tasks: REP-063 through REP-071)

**P1 — 3 tasks (all S effort, non-ui, auto-merge eligible):**
- REP-063 (S, P1): SearchIndex — `delete(threadID:)` for archived thread cleanup. Archived threads currently remain searchable — `InboxViewModel.archive` should call `index.delete(threadID:)`. Direct fix for a silent correctness gap.
- REP-065 (S, P1): RuleEvaluator — `senderIs` case-insensitive matching. Currently exact-case comparison; contact resolution can produce "Alice Smith" while the rule stores "alice smith". Cheap fix, real-world correctness impact.
- REP-068 (S, P1): IMessageChannel — map `message.cache_has_attachments` to `Message.hasAttachment: Bool`. Makes the `hasAttachment` rule predicate data-driven rather than sentinel-string-based. High value: data correct > heuristic.

**P2 — 6 tasks (mix of S/M, non-ui, auto-merge eligible):**
- REP-064 (S, P2): IMessageSender — max 4096-char message guard. Prevents silent truncation on very long sends.
- REP-066 (M, P2): DraftEngine — persist draft text to disk between launches. Quality-of-life: user edits survive app relaunch.
- REP-067 (M, P2): SearchIndex — snippet extraction for search results. FTS5 `snippet()` returns match excerpt; enables richer palette display.
- REP-069 (S, P2): RulesStore — 100-rule cap with graceful rejection. Prevents unbounded O(n) rule evaluation growth.
- REP-070 (S, P2): Stats — per-channel messages-indexed counter. Enables channel-specific observability in automation logs.
- REP-071 (S, P2): InboxViewModel — thread selection model tests. Covers `selectThread`, `prime`, `evict` call pattern via `MockDraftEngine`. Depends on REP-034 (evict).

## Open task count after changes

**45 open tasks total:**
- P1: REP-016 (human), REP-017 (human), REP-028, REP-048 (human), REP-050, REP-052, REP-063, REP-065, REP-068 = 9
- P2: REP-009, REP-010, REP-029–REP-047 (16, excluding already-archived ones), REP-053–REP-062 (9), REP-064, REP-066, REP-067, REP-069, REP-070, REP-071 = 36

**Worker auto-merge eligible (non-ui, non-human-claimed):**
- P1: REP-028, REP-050, REP-052, REP-063, REP-065, REP-068 = 6
- P2 (non-ui, non-human): REP-029, 030, 031, 032, 033, 034, 035, 036, 037, 038, 039, 040, 041, 042, 053, 054, 055, 056, 057, 058, 059, 061, 064, 066, 067, 069, 070, 071 = 28
- **Total auto-merge eligible: 34 / 45 = 76%** ✓ (above 60% floor)

**Effort distribution (all open):**
- S: 31 tasks (~69%)
- M: 13 tasks (~29%)
- L: 1 task (REP-010, Slack OAuth, ui_sensitive) (~2%)

Good mix for worker's 13-min budget. ✓

## Worker activity since last planner run

| Run ID | Tasks shipped | Test delta |
|---|---|---|
| worker-2026-04-21-025439 | REP-022, REP-024 (concurrent sync guard, malformed rule skip) | 158 → 165 (+7) |
| worker-2026-04-22-043231 | REP-023 (rule re-evaluation) | 165 → 169 (+4) |
| worker-2026-04-22-011918 | REP-049, REP-051 (prime guard, databaseError code) | 169 → 173 (+4) |
| worker-2026-04-22-013926 | REP-025 (AppleScript timeout) | 173 → 175 (+2) |
| worker-2026-04-22-055650 | REP-026 (PromptBuilder extract) | 175 → 179 (+6, but starting count was 173) |

Note: worker log for REP-026 states "Before: 173, After: 179" — cross-check shows test count jumped from 173 to 179 across those sessions (+6 in PromptBuilderTests). Total gain this cycle: 179 - 158 = **+21 tests** across 7 tasks shipped.

## Notes for the reviewer

1. **Human queue at 3 items**: REP-016 (senderKnown bug fix, correctness — highest priority), REP-017 (wip consolidation), REP-048 (DraftEngine test branch). All wip branches are <24h old. Human should action before the 7-day alarm window opens.
2. **REP-027 silently done**: SearchIndex AND semantics were implemented in commit 687c5a3 (REP-015) without a separate task claim. This is fine — the feature shipped — but the planner log notes it for the reviewer's audit trail. No worker run is needed.
3. **REP-033 scope reduced**: ORDER BY rank was present from the original FTS5 commit. Only the ranking tests remain. Effort M→S.
4. **REP-063 (SearchIndex delete)** is P1 because archived threads being searchable is a silent user-facing bug, not a nice-to-have. Worker should pick this up in the next P1 sweep.
5. **REP-068 (Message.hasAttachment)** removes the sentinel-string dependency from the `hasAttachment` rule predicate. REP-062 (human: product-copy pass on sentinels) notes this: after REP-068 lands, the sentinel string is only used for display (IMessagePreview), not for rule logic. The human copy decision becomes lower stakes.
6. **Test trajectory**: 60 → 145 → 158 → 179 over ~30 hours. Excellent pace. The 9 new tasks should push main toward 220+ once merged.
7. **Next planner focus**: If worker draws queue below 35 by next run (likely given 8 tasks/2h pace), add coverage tasks for the newly added P2 features (REP-066 persistence, REP-067 snippets) once they land.
