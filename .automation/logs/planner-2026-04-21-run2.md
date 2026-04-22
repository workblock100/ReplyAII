# Planner log — 2026-04-21 (third run, backlog replenishment)

status: OK

## Context

This is the third planner run today (second automated planner run, first was `62e23ba`, second was `plan: 2026-04-21` at ~18:00). Between runs, the worker shipped all 13 open non-ui-sensitive backlog tasks (REP-003 through REP-015) in a single burst, generating 85 new tests (60 → 145). The reviewer filed a 5/5 assessment. When the backlog ran dry, the worker correctly entered quality-pass mode and shipped 7 wip/ branches with additional test coverage — but this produced 5+ overlapping branches targeting the same subsystems (RuleContext.from, DraftEngine gap coverage).

**Main concern this run:** the backlog had only 2 open tasks remaining (REP-009, REP-010 — both ui_sensitive), leaving the worker with nothing auto-mergeable to pick up. Primary goal: replenish to 30–50 tasks.

## Halt-condition check

- Last commit on main: `55c7901` (review: window 2026-04-21 17:43, 5/5 — NOT a revert) ✓
- Test count: 145 on main. No shrinkage (all wip branches add tests). ✓
- wip/ branches: 7 open, all from 2026-04-21 — none older than 7 days ✓
- No binary blobs, no repo size anomaly ✓
- No swift test run available in this sandbox; last known state confirmed green by reviewer ✓

No halt. Proceeding.

## Archive verification

All done tasks are correctly in the `## Done / archived` section. Cleaned up three issues in the active sections:
- **REP-003**: was duplicated in P0 active section AND in Done/archived. Removed from active P0 — now only in Done/archived.
- **REP-004, REP-006, REP-012**: marked `status: done` in the P1 active section but NOT in Done/archived. Moved to Done/archived. These were claimed by `worker-2026-04-21-181128` per the worker log.

## wip/ branch assessment

7 open wip/ branches, all today:

| Branch | Commit | Content | Action |
|---|---|---|---|
| wip/quality-2026-04-21-184250 | e114b33 | RuleContext.from test coverage (documents email-quirk as bug) | → superseded by fix branch; human should close |
| wip/quality-2026-04-21-191222 | bcc8dd7 | Log-only commit (no code) | → trivial; human should close |
| wip/quality-2026-04-21-193800-senderknown-fix | d672ab4 | **Real bug fix**: operator-precedence in senderKnown, `.senderUnknown` never fired correctly | → **MERGE FIRST** (REP-016) |
| wip/quality-2026-04-21-211100 | 1bb9e41 | DraftEngine: 5 untested paths, 145→150 tests | → consolidate into main (REP-017) |
| wip/quality-2026-04-21-212529 | 75eb773 | senderIs, senderUnknown, .or, RuleContext.from, 145→156 tests | → best candidate for RuleEvaluator coverage merge |
| wip/quality-2026-04-21-213914 | 6a00fb3 | DraftEngine gap coverage (overlaps with 211100) | → pick one; drop duplicate |
| wip/quality-2026-04-21-215030 | f4e961b | RuleContext.from + senderIs/senderUnknown/or, 145→153 | → overlaps with 212529; pick best, drop other |

Queued REP-016 (P1, human) and REP-017 (P1, human) to surface this to the human owner.

## BACKLOG.md changes

### Archived this run
- REP-004 (done, silentlyIgnore parity)
- REP-006 (done, IMessageSender escape tests)
- REP-012 (done, RulesStore test coverage)
- Removed duplicate REP-003 from active P0 section

### Added (32 new tasks: REP-016 through REP-047)

**P1 — 13 tasks:**
- REP-016 (human, S): review + merge senderKnown operator-precedence bug fix — correctness bug, affects .senderUnknown predicate
- REP-017 (human, S): consolidate overlapping wip quality branches
- REP-018 (S, non-ui): SmartRule — isGroupChat + hasAttachment predicates
- REP-019 (S, non-ui): ContactsResolver — E.164 phone normalization before cache lookup
- REP-020 (S, non-ui): IMessageChannel — filter reaction + delivery-status message rows
- REP-021 (M, non-ui): IMessageChannel — configurable thread-list pagination (limit param)
- REP-022 (S, non-ui): InboxViewModel — concurrent sync guard
- REP-023 (M, non-ui): InboxViewModel — rule re-evaluation on RulesStore mutation
- REP-024 (S, non-ui): RulesStore — validate + skip malformed rules on load
- REP-025 (M, non-ui): IMessageSender — AppleScript execution timeout
- REP-026 (M, non-ui): DraftEngine — extract + test prompt template construction (PromptBuilder)
- REP-027 (M, non-ui): SearchIndex — multi-word AND query support
- REP-028 (M, non-ui): UNNotification — register inline reply action via UNUserNotificationCenter

**P2 — 19 tasks:**
- REP-029 (S, non-ui): IMessageChannel — SQLITE_BUSY graceful retry
- REP-030 (S, non-ui): Preferences — pref.inbox.threadLimit setting
- REP-031 (S, non-ui): SmartRule — textMatchesRegex pattern validation at creation
- REP-032 (M, non-ui): Stats — draft acceptance rate per tone
- REP-033 (M, non-ui): SearchIndex — FTS5 BM25 relevance ranking
- REP-034 (S, non-ui): DraftEngine — draft cache eviction for idle entries
- REP-035 (M, non-ui): RulesStore — export/import rules via JSON file URL
- REP-036 (S, non-ui): IMessageChannel — Message.isRead from is_read column
- REP-037 (M, non-ui): ContactsResolver — batch resolution helper for initial sync
- REP-038 (S, non-ui): MLXDraftService — mocked cancellation + load-progress test coverage
- REP-039 (S, non-ui): Preferences — pref.drafts.autoPrime toggle
- REP-040 (S, non-ui): IMessageSender — dry-run mode for test harness
- REP-041 (M, non-ui): SearchIndex — persist FTS5 index to disk between launches
- REP-042 (S, docs): AGENTS.md — update commit log + test count post-wip-merge
- REP-043 (M, ui): InboxViewModel — sync error state + FDABanner integration → wip/ required
- REP-044 (S, ui): MenuBarContent — unread-thread count badge → wip/ required
- REP-045 (M, ui): Stats — surface counters in set-privacy screen → wip/ required
- REP-046 (S, ui): InboxViewModel — optimistic send UI state → wip/ required
- REP-047 (S, ui): Sidebar — relative-time chip auto-tick every 10s → wip/ required

### Open task count after changes

34 open tasks total:
- 2 human-review (REP-016, REP-017) — worker skips these
- 13 non-ui-sensitive P1 tasks (REP-018 through REP-028) — worker auto-merges
- 2 non-ui-sensitive P2 + 7 non-ui-sensitive P2 = 17 non-ui-sensitive P2 tasks
- REP-009, REP-010, REP-043–047: 7 ui-sensitive (worker → wip/ branch)

Worker-auto-merge eligible (non-ui, non-human): 25/34 = 74% — above the 60% floor.
Effort distribution: 17 S-tasks, 13 M-tasks, 2 L-tasks (REP-009, REP-010). Good mix.

### Tasks considered but not added

- **Voice profile / LoRA training**: L effort, requires ML infrastructure (HuggingFace dataset, training loop). Out of scope for autonomous worker.
- **Slack Socket Mode** (follow-up to REP-010): blocked on REP-010 first.
- **AttributedBodyDecoder nested payloads**: marked in AGENTS.md "Priority queue #4" as "port python-typedstream". Effort is L+ and REP-003 already improved this substantially. Deferred — too risky for unattended worker.
- **UNNotificationServiceExtension** (process-extension for background reply sending): requires new bundle target + entitlement changes. Hard ban on Package.swift/project.yml changes.

## Distribution check

60% backend/logic/tests: 25 auto-merge tasks / 34 total = 74% ✓
30% test coverage specifically: ~10 of the 25 auto-merge tasks are test-only or test-primary (REP-019, REP-022, REP-024, REP-029, REP-030, REP-034, REP-038, REP-039, REP-040, REP-042) = 29% ✓ (close enough)
10% docs/tooling: REP-042 (AGENTS.md) = 3% — slightly under, acceptable given backlog depth needed

## Notes for the reviewer

1. **senderKnown bug (REP-016)** is the highest-priority item. It's a correctness bug that has existed since initial shipping. The operator-precedence issue means `.senderUnknown` rules never fire on email-handle senders and may misclassify digit-only phone numbers. Merge the fix before the quality coverage branches so tests are validated against correct behavior.

2. **Worker quality-pass** produced 5 overlapping wip/ branches. This is expected behavior when the backlog runs dry — the worker correctly entered quality mode. However, the duplication (especially 184250 vs 212529 vs 215030, and 211100 vs 213914) means human consolidation is needed before merge. The worker cannot close wip/ branches — only the human can do that.

3. **Test count on main** remains 145. Wip branches collectively add ~25+ tests. After REP-016 + REP-017, expect 170+ tests on main. This is a healthy trajectory.

4. **New task selection rationale**: focused on areas the reviewer called out (UNNotification, relative-time chip, sidebar copy), plus concrete gaps in testability (PromptBuilder, InboxViewModel concurrent guard, FTS5 ranking) and correctness improvements (reaction message filtering, phone normalization, SQLITE_BUSY handling). Avoided speculative features with unclear scoping.

5. **wip/ branch count**: currently 7. After human consolidation (REP-017), should drop to 0–1. No alarm needed.
