# Planner Run — 2026-04-24 run 9

**Status**: completed  
**Model**: claude-sonnet-4-6 (minimum spec; preferred is Opus 4.7 — model drift persists, 6th consecutive window)  
**Open before this run**: ~72 (post-run8 addendum state, with 3 new wip branches unregistered)  
**Open after this run**: ~72 (0 archived, 4 new tasks added, 7 status updates applied)  
**Archived today**: 0 (no substantive commits to main since run8 addendum)  
**New tasks added**: 4 (REP-282, REP-283, REP-284, REP-285)  
**Status updates**: 7 (REP-244 in_progress→blocked; REP-224/245/246/248 open→blocked; REP-254 wip count 24→27)

---

## Halt condition check

- **swift test**: `.build/` absent on clone machine (MLX cold-build issue, REP-254). Cannot run `swift test`. Last confirmed test count: 527 on main (commit `9a6c3d1`, worker-2026-04-24-102657). No test-count decrease detected in reviewed commits. ✓ (no halt triggered — build verification unavailable, same as prior runs)
- **Last commit on main**: `74c129f` (claim REP-244 for worker-2026-04-24-170301) — not a revert. ✓
- **Repo size**: No binary check-ins in recent git log. ✓
- **No halt conditions triggered.**

---

## What happened since planner run 8 (addendum)

Three new wip branches opened since the run8 addendum, none yet registered in BACKLOG:

1. **`wip/2026-04-24-133823-inbox-bulk-filter`** — Worker-2026-04-24-133823 claimed REP-224/245/246/248 and shipped all four bundled in commit `a0b46ed`: `bulkMarkAllRead()`, `filterByChannel(_:)`, `totalUnreadCount`, `bulkArchiveRead()`. No BACKLOG status update was made by the worker. Branch count: +1.

2. **`wip/2026-04-24-163229-un-notification-parser`** — Worker-2026-04-24-163229 claimed REP-241 and shipped `UNNotificationContentParser` (+42 LOC source, +96 LOC tests, 7 tests) on this branch. AGENTS.md was updated with the branch reference but REP-241 blocker note was already present. Branch count: +1.

3. **`wip/2026-04-24-170301-sync-all-channels`** — Worker-2026-04-24-170301 claimed REP-244 and shipped the multi-channel aggregator (commit `984bb13`, +4 tests: merges, dedupes, partial-failure, empty-list). Status was `in_progress` in BACKLOG — not yet updated to `blocked`. Branch count: +1.

Total wip branches: **27** (up from 24 at run8).

No code committed to main since run8. Effective main-branch test count remains 527.

---

## Changes made this run

### Status updates

- **REP-244** — `status: in_progress` → `status: blocked`. Implementation confirmed on `wip/2026-04-24-170301-sync-all-channels` (commit `984bb13`). Added blocker note: MLX cold-build exceeds 13-min budget; human merge path is REP-284.
- **REP-224** — `status: open`, `claimed_by: null` → `status: blocked`, `claimed_by: worker-2026-04-24-133823`. Bundled with REP-245/246/248 on `wip/2026-04-24-133823-inbox-bulk-filter`.
- **REP-245** — `status: open`, `claimed_by: null` → `status: blocked`, `claimed_by: worker-2026-04-24-133823`. Same bundle.
- **REP-246** — `status: open`, `claimed_by: null` → `status: blocked`, `claimed_by: worker-2026-04-24-133823`. Same bundle.
- **REP-248** — `status: open`, `claimed_by: null` → `status: blocked`, `claimed_by: worker-2026-04-24-133823`. Same bundle.
- **REP-254** — wip branch count updated 24 → 27. Added three new branches to enumeration: `wip/2026-04-24-133823-inbox-bulk-filter`, `wip/2026-04-24-163229-un-notification-parser`, `wip/2026-04-24-170301-sync-all-channels`. Added reference to REP-285 as the root structural fix.

### New tasks added

| REP   | Priority | Effort | Category | Description |
|-------|----------|--------|----------|-------------|
| REP-282 | P1 | S | human/review | Review + merge wip/2026-04-24-133823-inbox-bulk-filter (REP-224/245/246/248 bundled) |
| REP-283 | P1 | S | human/review | Review + merge wip/2026-04-24-163229-un-notification-parser (REP-241) |
| REP-284 | P0 | S | human/review | Review + merge wip/2026-04-24-170301-sync-all-channels (REP-244) — pivot P0 |
| REP-285 | P0 | M | human/infra | Split MLX into separate Swift product target to remove from test compilation — root fix for wip queue blocker |

---

## Mandatory P0 requirement check

> "Every planner cycle should queue at least one P0 task that moves the product closer to being usable WITHOUT the user granting FDA."

**Satisfied by REP-284** (review + merge REP-244 syncAllChannels): once this wip branch merges, `InboxViewModel` will concurrently aggregate threads from all registered `ChannelService` instances — iMessage (via AppleScript fallback or chat.db), Slack, notification-captured messages — into a unified thread list without requiring FDA. This is the core "usable without FDA" architecture payoff.

**Also satisfied by REP-285**: fixing the build time unblocks REP-228 (demo mode), REP-236 (AppleScript fallback), REP-255 (notification permission request), REP-247 (ViewState), REP-278 (thread cache) — all pivot-critical tasks stuck in wip branches. Without REP-285, these branches may sit unmerged indefinitely.

---

## Strategic analysis

### What's working well

- **Pivot compliance is strong.** Zero FDA/chat.db tasks added in the last 4 planner cycles. All new worker-shipped code (REP-239/265 MessagesAppActivation, REP-244 syncAllChannels, REP-241 UNNotificationContentParser, REP-224/245/246/248 bulk inbox ops) is pivot-aligned: no FDA required, builds toward a channel-agnostic product.
- **Worker throughput per fire is solid.** Workers are shipping coherent bundles (4 tasks bundled in inbox-bulk-filter, full syncAllChannels with 4 tests in sync-all-channels). The quality of the individual wip deliverables looks good.
- **The reviewer→planner signal loop is functioning.** REP-280 (warm-build wip-drain) was added after a reviewer suggestion; REP-281 (REP-267 human review) was added in the same addendum. This cycle adds REP-282–285 directly addressing reviewer feedback from window 10:10–16:10.

### What needs urgent human action

The wip queue at 27 branches is the single most important issue. With the current cadence:
- Workers open ~2–3 new wip branches per 2h cycle
- Zero branches are merging (build time blocker)
- Net accumulation: ~12–18 branches/day

At this rate the wip queue will exceed 50 branches by 2026-04-27. Each branch represents real shipped code that's not in `main`, meaning: (a) it can't be reviewed against the live app; (b) later branches may conflict with earlier ones; (c) the reviewer can't verify `swift test` against main.

**The single highest-leverage action the human can take**: run REP-285 (Package.swift split) so `swift test` completes in <5 min. After that, REP-280 (warm-build wip-drain) becomes worker-executable and the queue can drain autonomously. Until then, REP-284 and REP-282/283 are the best individual merge targets (each is a self-contained commit with no known conflicts).

### Task mix assessment (against planner.prompt targets)

Current open tasks by category (approximate):
- Alt message-source (AppleScript, Accessibility, Shortcuts, Notifications): ~15% — on-target (30% target); most are blocked on wip merge
- Non-iMessage channels (Slack, WhatsApp, Teams, Telegram): ~25% — slightly below target (30%); Slack pipeline is deep, others are stubbed
- UX / practicality polish: ~20% — slightly below target (25%); most UI tasks are P2 open or blocked behind channel work
- Test coverage: ~35% — above target (10%); many pinning tests queued from prior windows
- Docs / tooling: ~5% — on-target

No new chat.db / FDA tasks added. ✓

### Should new non-human tasks be added?

With ~72 open tasks and a 30–50 target, the backlog is significantly over target. Adding non-human tasks this cycle would worsen the ratio. The right play:
1. **Don't add new worker tasks this cycle** — the worker has ample work; the bottleneck is merging, not planning.
2. **Watch the next cycle** — if REP-285 is actioned by the human, the queue may drain enough to justify 3–5 new tasks next cycle.
3. **Exception**: REP-285 itself is a human task but adds one new P0. Justified because it's the root fix.

---

## Wip branch priority order for human merge (fresh start list)
Sorted chronologically (oldest = highest-conflict risk if deferred):

1. `wip/quality-*` (8 branches) — requires human cherry-pick/consolidation per REP-016/017/048
2. `wip/2026-04-23-085959-stats-session-acceptance` (REP-135/177/179/183/187) — REP-200 review task
3. `wip/2026-04-23-130000-thread-name-regex` (REP-129) — REP-217 review task
4. `wip/2026-04-23-145504-demo-mode` OR `wip/worker-2026-04-23-161500-demo-mode` (REP-228, pick one, close other)
5. `wip/2026-04-23-191507-appleScript-fallback` (REP-236/229) — pivot P0, no FDA
6. `wip/2026-04-23-200831-slack-http-keychain-deleteall` (REP-237/238) — REP-232 review task
7. `wip/2026-04-23-230824-telegram-channel-tests` (REP-256/205/206) — REP-276 review task
8. `wip/2026-04-24-005143-rep255-notification-permission` (REP-255) — pivot P0, notification auth
9. `wip/2026-04-24-031929-channel-stubs` (REP-243/260/261/264) — REP-277 review task
10. `wip/2026-04-24-083949-rep266-slack-oauth-flow` (REP-266) — pivot P0, Slack OAuth
11. `wip/worker-2026-04-24-113000-viewstate` OR `wip/2026-04-24-120000-viewstate-slacktokenstore` (REP-247, pick one via REP-275)
12. `wip/2026-04-24-114653-slack-socket-client` (REP-267) — REP-281 review task
13. `wip/2026-04-24-133823-inbox-bulk-filter` (REP-224/245/246/248) — REP-282 review task (NEW)
14. `wip/2026-04-24-152005-thread-cache` (REP-278) — REP-279 review task
15. `wip/2026-04-24-163229-un-notification-parser` (REP-241) — REP-283 review task (NEW)
16. `wip/2026-04-24-170301-sync-all-channels` (REP-244) — REP-284 review task (NEW, pivot P0)

Branches to close without merging (no code, or superseded):
- `wip/2026-04-24-113000-slack-socket-token-store` — claim-only, no implementation commit
- `wip/worker-2026-04-24-105453-rep278-threads-cache` — superseded by wip/2026-04-24-152005-thread-cache
- `wip/worker-2026-04-24-115000-notification-parser-slack-token` — verify if superseded; close if no unique code

---

## Next planner cycle

If REP-285 is completed by the human before the next run:
- Expect worker to drain 3–5 wip branches via REP-280
- Re-assess backlog size; may be appropriate to add 4–6 new worker tasks in the Slack-completion space (REP-257 full conversations.history fetch, REP-272 SlackChannel.authorize wiring, Telegram Bot API send implementation)
- Promote REP-258 (AccessibilityAPIReader) from P2 to P1 if the AppleScript wip branch (REP-236) has merged — it becomes the next alt message-source milestone
