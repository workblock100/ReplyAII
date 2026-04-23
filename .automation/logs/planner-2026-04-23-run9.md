# Planner Run 9 — 2026-04-23

**Status**: completed
**Open after this run**: 50 worker-actionable (59 open + 13 blocked + 7 human = 79 total active)
**Archived today (this run)**: 0 (no new done items found in main since run 8)
**New tasks added**: 18 (REP-236 through REP-253)

## What shipped since run 8

No new substantive commits merged to main since run 8's `d9414e1` (plan commit). The most recent commit is `02dad4b` (claim REP-233 + REP-234 for worker-2026-04-23-171932).

**Stale claims discovered:**
- `worker-2026-04-23-171932` claimed REP-233 + REP-234 at ~17:19 EDT. Now ~18:14 EDT (~55 minutes later, well past the 13-min budget). No ship commit, no wip branch. Claims reset to `open` / `claimed_by: null` so the next worker can pick them up.

**New wip branch discovered:**
- `wip/worker-2026-04-23-161500-demo-mode` — a second complete implementation of REP-228 (demo fixture mode) by worker-161500. Worker log shows +207 LOC, 3 new tests, `swiftc -typecheck` clean, but `swift test` blocked on MLX full-project build time. This is separate from the original `wip/2026-04-23-145504-demo-mode` (worker-145504, +193 LOC, 3 tests). Updated REP-228's blocker field to highlight BOTH branches so human can pick the better implementation.

**Test count**: 502 (unchanged — no new merges). AGENTS.md header is accurate.

## Halt condition check

- `swift test` suite: last known state is 502 tests passing (worker-2026-04-23-111853, commit `43d735b`). No new code commits to main since then — no regression risk.
- Last commit on main: `02dad4b` (claim commit, not a revert). Clean.
- Repo size: normal. No binary runaway detected.
- Last 7-day test count trajectory: 404 → 463 → 493 → 502 — monotonically increasing. ✓
- **No halt conditions triggered.**

## Changes made this run

### Field updates to existing tasks

| REP | Change |
|-----|--------|
| REP-228 | `blocker` updated to reference BOTH wip/145504 and wip/161500 demo-mode implementations |
| REP-229 | `priority` promoted P2 → P1 (pivot-critical: only open AppleScript thread-list task) |
| REP-233 | `status` reset `in_progress` → `open`; `claimed_by` reset → `null` (stale worker-171932 claim) |
| REP-234 | `status` reset `in_progress` → `open`; `claimed_by` reset → `null` (stale worker-171932 claim) |

### New P0 task

**REP-236 (P0, M)**: Wire AppleScript fallback into `IMessageChannel.recentThreads()` when chat.db returns `authorizationDenied`. Implements `AppleScriptMessageReader` (absorbing REP-229 spec) and wires it as the iMessage channel's FDA fallback. This is the key task that makes the thread list work without FDA via Automation permission. 4 tests. **This satisfies the mandatory P0 "usable without FDA" requirement for this cycle.**

### New P1 tasks (2)

**REP-237 (P1, S)**: `SlackHTTPClient` — injectable URL session wrapper for Slack API calls. Bearer auth, correct URL construction, HTTP error mapping to `ChannelError`. 5 tests. Prereq for REP-242 (real Slack data fetch).

**REP-238 (P1, S)**: `KeychainHelper.deleteAll(prefix:)` for factory reset / channel de-auth. Extends REP-233. 3 tests.

### New P2 tasks (15)

**Alt message-source (30% target):**
- **REP-239 (P2, S)**: `MessagesAppActivationObserver` — `NSWorkspace` notification trigger when Messages.app becomes frontmost. 3 tests. Alt sync trigger without FDA.
- **REP-240 (P2, M)**: `AppleScriptMessageReader.messagesForChat(chatGUID:limit:)` — extend REP-236 to fetch messages for a specific chat via AppleScript. 4 tests.
- **REP-241 (P2, M)**: `UNNotificationContentParser` — dedicated parser for iMessage notification payloads. Extracts sender handle + preview + chatGUID. 4 tests. Prereq for REP-235.

**Non-iMessage channels (30% target):**
- **REP-242 (P2, M)**: `SlackChannel.recentThreads()` with real `conversations.list` API call. 4 tests. (Depends REP-234 + REP-237.)
- **REP-243 (P2, S)**: `Channel` enum add `.telegram`, `.whatsapp`, `.teams`, `.sms` cases + `CaseIterable` + `Codable`. 3 tests.
- **REP-244 (P2, M)**: `InboxViewModel.syncAllChannels()` — concurrent multi-channel merge with dedupe. 4 tests. Key for multi-channel UX.

**Channel-agnostic UX (25% target):**
- **REP-245 (P2, S)**: `InboxViewModel.filterByChannel(_:)` — view-level channel filter. 4 tests.
- **REP-246 (P2, S)**: `InboxViewModel.totalUnreadCount: Int`. 3 tests.
- **REP-247 (P2, M)**: `InboxViewModel.ViewState` enum — loading/populated/demo/error/empty. 4 tests. Replaces implicit thread-count checks.
- **REP-248 (P2, S)**: `InboxViewModel.bulkArchiveRead()` — archive all read threads. 3 tests.

**Test coverage (10% target):**
- **REP-249 (P2, S)**: `ContactsResolver` concurrent same-handle resolve returns consistent result. 2 tests.
- **REP-250 (P2, S)**: `DraftEngine.invalidate()` mid-prime transitions to idle (zombie-prime guard). 2 tests.
- **REP-251 (P2, S)**: `RulesStore` compound predicate export+import round-trip. 3 tests.
- **REP-252 (P2, S)**: `SearchIndex` BM25 ranking — higher-frequency term ranks first. 2 tests.

**Docs/tooling (5% target):**
- **REP-253 (P2, S)**: `AGENTS.md` "What's still stubbed" update — remove resolved UNNotification inline reply, add Slack/AppleScript status notes. Docs-only.

## P0 check ✓

**REP-236 (P0, M)** is a fresh, worker-actionable P0 that wires the AppleScript fallback for thread listing when FDA is unavailable. This is concrete, self-contained, and moves the product toward being usable without granting FDA. ✓

**REP-228 (P0, M)** remains blocked on human merge (2 complete wip implementations). Human should prioritize merging one of the two demo-mode branches today to close this out.

## Queue health after this run

- **50 worker-actionable open tasks** (open + non-human + non-ui-sensitive)
- **13 blocked** tasks (all waiting on human wip-branch merges)
- **7 human review** tasks (old quality branches + recent wip bundles + demo mode)
- Mix breakdown:
  - Alt message-source: REP-229, REP-236, REP-239, REP-240, REP-241 = 5 tasks (~10% of total)
  - Non-iMessage channels: REP-233, REP-234, REP-237, REP-238, REP-242, REP-243, REP-244 = 7 tasks (~14%)
  - Channel-agnostic UX: REP-111, REP-235, REP-245, REP-246, REP-247, REP-248, REP-244 = 7 tasks
  - Test coverage: ~30+ tasks (majority)
  - Docs: REP-253
- **60%+ non-ui_sensitive** → worker auto-merges most ✓

## Concerns flagged

- **wip/quality-* branches from 2026-04-21 (now 2 days old)**: REP-016, REP-017, REP-048 are P1 human tasks. At the 7-day mark (2026-04-28) the planner must add a P1 reminder to close them. Human should prioritize before that.
- **REP-228 has TWO competing implementations**: worker-145504 and worker-161500 both created wip branches for the same task. Human should review both diffs and pick the better implementation (or cherry-pick from each). Both branches pass `swiftc -typecheck`; neither has been `swift test` verified.
- **Worker-171932 claim timeout**: Claims reset this run. If this worker keeps timing out on S-effort tasks (REP-233 = S), there may be a cold-cache MLX problem even for small tasks. Consider adding a note in AGENTS.md suggesting workers detect MLX cache state before committing to compile-and-test.
- **REP-229 vs REP-236 overlap**: REP-229 (now P1) specifies `AppleScriptMessageReader.recentChats()` as standalone. REP-236 (P0) absorbs this spec and adds the InboxViewModel wiring. Worker picking up REP-236 should treat REP-229 as done after completing REP-236, or pick REP-229 first and note REP-236 depends on it. Planner next cycle: if REP-229 ships, update REP-236's `files_to_touch` to reflect that `AppleScriptMessageReader.swift` already exists.
