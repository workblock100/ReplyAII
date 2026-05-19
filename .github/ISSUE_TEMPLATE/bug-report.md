---
name: Bug report
about: Something in ReplyAI is broken or behaves unexpectedly
title: '[bug] '
labels: bug
assignees: ''
---

## What happened

<!-- One paragraph. What did you observe? What did you expect to see instead? -->

## Reproduction

<!-- Step-by-step. The simpler the repro, the faster a fix lands. -->

1.
2.
3.

## Environment

- ReplyAI commit hash (`git rev-parse HEAD` from the workspace, or commit from `Help → About ReplyAI`):
- macOS version (`sw_vers -productVersion`):
- Mac model (Apple Silicon vs Intel, RAM):
- Channels in use (iMessage / Slack / demo only / …):
- MLX on? (`defaults read co.replyai.mac pref.model.useMLX`):

## Logs / screenshots

<!-- Relevant lines from `log show --last 5m --predicate 'process == "ReplyAI"'`,
     or a screenshot of the failure. If the app crashed, attach the .ips report
     from ~/Library/Logs/DiagnosticReports/. -->

## Workaround

<!-- Have you found a way to avoid the bug? -->
