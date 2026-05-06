# .automation/

Source of truth for the three scheduled Claude agents. The cron entries in the Anthropic scheduled-tasks UI just point back at these prompts — editing them here is how you change the automation's behavior.

> **Operating mode (2026-05): single-agent autopilot.** The per-role
> `*.prompt` files below describe the legacy 7-agent pipeline. Today the
> active scheduled task is `replyai-autopilot` only — its skill lives at
> `~/.claude/scheduled-tasks/replyai-autopilot/SKILL.md` (not in this repo)
> and consolidates the responsibilities of all the legacy prompts. Logs
> from the autopilot land in `logs/autopilot-YYYY-MM-DD-HHMM.md` (one
> consolidated log per fire) rather than per-agent. The legacy `*.prompt`
> files are kept for reference and would be re-pointed at if Elijah
> reactivates the multi-agent pipeline.

## Files

| File | Owner | Read by |
| --- | --- | --- |
| `planner.prompt` | planner agent (daily 03:00 UTC) | planner only |
| `worker.prompt` | worker agent (hourly) | worker only |
| `reviewer.prompt` | reviewer agent (Sun 20:00 UTC) | reviewer only |
| `budget.json` | all three | commit caps, LOC caps, concurrent-branch caps |
| `logs/` | each agent appends one file per run | planner, worker, reviewer, humans |

## Log format

Every run appends `YYYY-MM-DD-HHMMSS-<agent>.md` to `logs/`:

```
# worker run 2026-04-21T14:00:00Z

## task
REP-003 — better AttributedBodyDecoder

## outcome
[shipped | blocked | over-budget]

## diff
- Sources/ReplyAI/Channels/AttributedBodyDecoder.swift +412 -89
- Tests/ReplyAITests/AttributedBodyDecoderTests.swift +156 -0

## tests
- before: 55 passing
- after:  61 passing

## notes
...
```

Humans can read these to audit what the automation did. The planner reads them to tune task scoping next day.

## Changing an agent's behavior

1. Edit the `.prompt` file here
2. Commit + push
3. Next run picks up the change automatically — no redeploy needed

The schedule itself (cron expressions, timeouts, model selection) lives in the Anthropic scheduled-tasks UI and isn't version-controlled. If you change those, note the change in `AUTOMATION.md`.
