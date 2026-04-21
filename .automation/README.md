# .automation/

Source of truth for the three scheduled Claude agents. The cron entries in the Anthropic scheduled-tasks UI just point back at these prompts — editing them here is how you change the automation's behavior.

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
