# AUTOMATION.md

Autonomous work loop for ReplyAI. Three Claude agents run on cron in Anthropic sandboxes, clone this repo, do scoped work, and push back to `origin/main`. You don't touch it unless something goes wrong.

## The three agents

| Agent | Cadence | Max runtime | Touches |
| --- | --- | --- | --- |
| `replyai-planner` | every 6 hours | 90 min | `BACKLOG.md`, `.automation/logs/planner-*` |
| `replyai-worker` | hourly (55-min loop) | 55 min | code under `Sources/`, `Tests/`, `BACKLOG.md`, `wip/*` branches |
| `replyai-reviewer` | Sun 20:00 UTC | 45 min | `REVIEW.md`, `AGENTS.md`, `.automation/logs/review-*` |

All three use the prompts in `.automation/*.prompt`. The prompts are the source of truth — the schedule definitions just point at them.

## What each agent is allowed to do

### Planner (CEO)

- **Writes**: `BACKLOG.md`, `.automation/logs/planner-YYYY-MM-DD.md`
- **Does NOT write**: any `.swift` file, `Package.swift`, `scripts/`, or AGENTS.md's code sections
- Refreshes the backlog based on git log, test state, and AGENTS.md priority queue
- Every task has `id`, `title`, `scope`, `success_criteria`, `effort` (S/M/L), `ui_sensitive` (bool), `test_plan`, `files_to_touch`, `priority` (P0/P1/P2), `status`
- If the worker has been shipping well, the backlog will shrink — that's correct. Planner fills gaps; doesn't invent busywork.

### Worker

- **Writes**: any source/test file needed for the current task, `BACKLOG.md` (status field only), `.automation/logs/worker-*`
- **Picks**: the highest-priority `status=open`, `ui_sensitive=false` task
- **Substantiveness gate**: if the top task is `effort=S`, must bundle with another S/M at the same priority. No single-S commits unless that's the only work available.
- **Tests must pass**: `swift test` green AND `./scripts/build.sh debug` success are hard preconditions for merging to main.
- **UI-sensitive work** goes to `wip/YYYY-MM-DD-HHMMSS-<slug>` branches, never main. Human reviews + merges.
- **Time-box**: 60 min. Over that → commit WIP to branch, mark task `status=blocked`.

### Reviewer

- **Writes**: `REVIEW.md`, `AGENTS.md`, `.automation/logs/review-*`
- **Does NOT write**: any code
- Reads last 7 days of commits + test-suite state, produces a 1-page quality assessment.
- If quality is dropping for 2 weeks running, writes a `STOP AUTO-MERGE` task at the top of `BACKLOG.md` — the worker will refuse to merge until you clear it.

## Hard bans (same in all three prompts)

- `git push --force*`, `git reset --hard`, `git branch -D`
- Re-enabling `com.apple.security.app-sandbox` in entitlements
- Adding `#Preview` macros (breaks the SwiftPM build path)
- Deleting tests to get a green run
- Modifying anything under `design_handoff_replyai/` (read-only design reference)
- Committing secrets, tokens, or PATs

## How to pause, redirect, or kill it

### Pause for a day
Edit `BACKLOG.md`, add this line at the top:

```
PAUSED_UNTIL: 2026-04-25
```

The worker honors it and exits immediately.

### Redirect to a specific feature
Edit `BACKLOG.md`, give your chosen task `priority: P0` and `claimed_by: human`. The worker respects manual claims and picks the next-highest unclaimed item.

### Full stop
Delete the cron tasks from your Anthropic scheduled-tasks UI. The prompts stay in the repo — you can resume later by recreating the schedule entries.

## Setup (one-time)

Each scheduled task needs a `GITHUB_PAT` secret so it can clone + push. Provision once:

1. github.com → Settings → Developer settings → Personal access tokens → Fine-grained → Generate new token
2. Name: `replyai-automation`
3. Expiration: 90 days (the reviewer will nag you in REVIEW.md when the expiry is within 14 days)
4. Resource owner: your account
5. Repository access: **Only select repositories → ReplyAII**
6. Permissions → Repository:
   - **Contents**: Read and write
   - Metadata: Read-only (auto-added)
7. Generate → copy the `github_pat_...` value
8. In the Anthropic scheduled-tasks UI, when creating each of the three tasks, paste the token into the **Secrets** field under the name `GITHUB_PAT`. All three tasks share the same secret value.

The token doesn't need anything else — no workflow permissions, no deployments, no packages.

## Budget + rate limits

See `.automation/budget.json`. Current caps:
- Max 8 commits to main per 24h (prevents runaway chatter)
- Max 1500 LOC changed per single worker run
- Max 3 `wip/` branches open at once — above that, planner marks old branches for human triage

Violations abort the run with a note in `.automation/logs/`.

## What to do when something breaks

1. **Bad commit on main** — `git revert <sha>` it, then add a task to `BACKLOG.md` describing the constraint the automation missed. Planner will update prompts next day.
2. **Agent won't stop picking a bad task** — mark the task `status=blocked` in BACKLOG.md with `blocker: "human-only"`. Worker skips it forever.
3. **Quality drop** — reviewer's `STOP AUTO-MERGE` handles this automatically. If you see it, read the latest `REVIEW.md` to understand why.
4. **Spend is too high** — edit `.automation/budget.json` to tighten caps, or delete the hourly cron and keep only planner + weekly reviewer.

## Current state on first launch

Initial `BACKLOG.md` is seeded from the "What's still stubbed" section of AGENTS.md — maybe 10 tasks. Worker will start consuming them within an hour of the first cron fire. Planner refreshes them daily.

First week expectation: 8-15 main-branch commits, 1-3 `wip/` branches, one `REVIEW.md` on Sunday. If after 2 weeks you don't see that volume, something's misconfigured — check the Anthropic scheduled-tasks UI for agent failures.
