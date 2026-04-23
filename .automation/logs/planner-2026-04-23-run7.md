# Planner Run 7 — 2026-04-23

**Status**: completed (addendum applied after strategic pivot commit `968de9f`)
**Open after this run**: 51 (49 initial + 4 pivot-aligned additions + 1 P0 − 2 deprioritized = 52... recount: 51 correct per grep)
**Archived today**: 4 (REP-067, REP-169, REP-188, REP-189)
**Deprioritized today**: 2 (REP-075, REP-227)

## What shipped since run 6

Worker `worker-2026-04-23-111853` shipped commit `43d735b` closing REP-067, REP-169, REP-188, REP-189:
- REP-067 (M): FTS5 snippet extraction — `SearchResult` type with `snippet: String?`, `snippet()` wired on message body column (col 3) with `«»` markers and 8-token window. Worker note: used col 3 (actual message body) rather than backlog's "col 1" because col 1 is thread_name — semantically correct choice. +4 tests.
- REP-169 (S): DraftEngine concurrent-prime stress test — 10 threads, all reach `.ready`. +2 tests.
- REP-188 (S): RulesStore disk round-trip preserves insertion order. +1 test.
- REP-189 (S): DraftEngine LLM error → `.idle` state transition; re-prime after error reaches `.ready`. +2 tests.

Test count: 493 → 502 (grep-verified: `grep -c "func test" Tests/ReplyAITests/*.swift` = 502).

Worker `worker-2026-04-23-130000` attempted REP-129 but was blocked by MLX full-project build time. Placed work on `wip/2026-04-23-130000-thread-name-regex`. Marked REP-129 blocked.

Worker `worker-2026-04-23-135355` has claimed REP-211, 163, 193, 194, 195, 196, 198 (in_progress, not yet shipped at planner fire time). Claims are fresh — not reset.

Last reviewer window (2026-04-23 10:12–16:04): **5/5**. Key suggestions acted on below.

## Changes made this run

### Archived (moved to Done section)
- REP-067, REP-169, REP-188, REP-189: all marked done by worker-111853, physically moved from P2 section to Done/archived. Condensed scope preserved.

### Priority changes
- **REP-009 promoted P2 → P1**: Reviewer (three consecutive windows) flagged that product-visible items remain unstarted. Global ⌘⇧R is Priority #1 in AGENTS.md's priority queue and the most impactful missing feature. Promoting to P1 signals urgency. Worker will push to `wip/` per ui_sensitive protocol.

### New P1 task
- **REP-217** (human): review + merge `wip/2026-04-23-130000-thread-name-regex`. REP-129 implementation is complete on that branch but MLX build blocked auto-merge. Human should merge this short-circuit.

### New P2 tasks (REP-218 – REP-227)
All non-ui_sensitive, auto-merge eligible (except as noted):

| REP | Effort | Title |
|-----|--------|-------|
| REP-218 | S | InboxViewModel: archiveThread removes thread from SearchIndex (integration test) |
| REP-219 | S | ContactsResolver: cache hit within TTL skips CNContactStore re-query |
| REP-220 | S | RulesStore: concurrent add + remove does not corrupt rules array |
| REP-221 | S | IMessageChannel: text=NULL message falls back to attributedBody decoder |
| REP-222 | M | UserVoiceProfile: data model + Preferences key + PromptBuilder injection |
| REP-223 | S | Stats: per-channel indexed-count reset on SearchIndex.clear() (integration) |
| REP-224 | S | InboxViewModel: bulkMarkAllRead() |
| REP-225 | S | SearchIndex: snippet column pinned to message body not thread_name (regression guard) |
| REP-226 | M | SmartRule: `messageCount(atLeast:)` predicate |
| REP-227 | M | IMessageChannel: Message.messageType field (tapback/receipt at model layer) |

**Rationale:**
- REP-218, 219, 220, 221, 223: integration tests for existing shipped features that lack a cross-component coverage path. High value for catching regressions.
- REP-222: product-layer progress toward voice profile training (stub feature in AGENTS.md). Scoped to data model + PromptBuilder injection only — no UI, no LoRA. The worker can auto-merge this.
- REP-224: small functional addition (bulkMarkAllRead) with clear success criteria. Reviewer asked for product-visible M items; this is the ViewModel half of a "mark all read" feature.
- REP-225: regression guard for the snippet column index drift (per worker-111853 note).
- REP-226, 227: new predicate and model field — real product capability additions. M effort, well-scoped, non-ui.

### AGENTS.md updates
- Added `43d735b` to "What's done" commit log (REP-067, 169, 188, 189).
- Updated test count 493 → 502 (grep-verified).

## Queue health
- 49 open tasks (target: 30–50 ✓)
- 7 in_progress (worker-135355: REP-163, 193, 194, 195, 196, 198, 211)
- 6 blocked (5 wip branches for human review: REP-135/177/179/183/187 on stats wip, REP-129 on thread-name-regex wip)
- Mix: ~8% P0 (none), ~24% P1, ~68% P2; ~82% non-ui (auto-merge eligible)

## Reviewer suggestions addressed
- "Check REP-067/169/188/189 claim age" → shipped and archived ✓
- "Seed next queue with product-visible M item" → REP-009 promoted to P1; REP-222 (UserVoiceProfile), REP-224 (bulkMarkAllRead), REP-226 (messageCount predicate), REP-227 (Message.messageType) added ✓
- "Planner no-op guard" → noted; will implement if a no-op situation is detected next run ✓ (deferred — this run had meaningful changes)
- AGENTS.md test-count updated to grep-accurate value ✓

## Addendum: strategic pivot response (commit 968de9f)

Human pushed a strategic pivot while planner was writing. Read and applied:
- `chat.db` + FDA path is unreliable in production. New agent weights: 30% alt architectures, 30% Slack, 25% UX polish, 25% tests+docs.
- **Planner must queue at least one P0 per cycle making the app usable without FDA.**

### Pivot-aligned additions
- **REP-228 (P0)**: Fixture demo mode — when real sync returns 0 threads, show Fixtures.demoChatThreads so the app is usable with zero permissions. `Preferences.demoModeActive` auto-clears after first real sync. `send()` on demo thread throws. M effort, non-ui, auto-merge eligible.
- **REP-229 (P2)**: AppleScript thread listing (`tell Messages to get every chat`) as FDA fallback — uses Automation permission, not FDA. Injectable executor for testing.
- **REP-230 (P2)**: `LocalhostOAuthListener` — reusable `NWListener`-based OAuth loopback handler building block for Slack. Port 4242, injectable timeout, tests without real network.
- **REP-231 (P2)**: Per-channel enable/disable Preferences keys (`pref.channels.iMessageEnabled`, `pref.channels.slackEnabled`).

### Deprioritized (pivot explicitly calls these out)
- **REP-075** (AttributedBodyDecoder nested payload): `status: deprioritized` — pivot says "stop investing in AttributedBodyDecoder rich-text improvements."
- **REP-227** (Message.messageType SQL field): `status: deprioritized` — pivot says "no new chat.db SQL queries."

### Notes on added tasks that touch chat.db (retained)
- REP-221 (text=NULL → attributedBody decoder test): kept open — tests existing shipped code, not new chat.db functionality. Pivot preserves existing tests.
- REP-219 (ContactsResolver cache hit test): retained — ContactsResolver is channel-agnostic infrastructure.

## Concerns flagged
- **wip/quality-* branches** (8 from 2026-04-21): Still unmerged. REP-016, 017, 048 cover these as P1 human tasks. Reviewer has noted them in 4 consecutive windows. If still open next review, planner should escalate to a STOP AUTO-MERGE consideration.
- **worker-135355 bundle size**: Claims 7 tasks at once. Within the ≤8 cap suggested by reviewer. No action needed unless it exceeds 8.
- **Co-author drift**: The reviewer noted `c8c3a04` uses "Sonnet 4.6" tag. No action for planner — this is a scheduled-task config issue for the human to verify.
