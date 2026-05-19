<!--
Thanks for opening a PR! Fill in the sections below to make review easier.
See CONTRIBUTING.md for the full dev-flow, branch strategy, and commit format.
-->

## Summary

<!-- 1–3 sentences. What changed and why, not how. -->

## Closes / relates to

<!-- Link the BACKLOG REP or GitHub issue this PR addresses. -->

Closes REP-XXX

## Test plan

<!-- Tick what applies. The bar is `./scripts/verify.sh` green before merge. -->

- [ ] `./scripts/verify.sh` passes locally (3-skip XCTest gate + build + UI smoke)
- [ ] New tests added for new code (XCTest in `Tests/ReplyAITests/`)
- [ ] Manually smoke-launched the bundled `.app` and confirmed the change renders as intended (UI-touching changes only)
- [ ] No new banned-pattern violations (Theme literals outside Theme/, `#Preview` macros, `app-sandbox` re-enable, force-push to main, etc.)
- [ ] Updated `BACKLOG.md` if this closes a REP, or added a new entry if this introduces follow-on work
- [ ] Updated `AGENTS.md` gotchas if this surfaces a new pitfall

## Screenshots / recordings

<!-- Drag images or paste links for UI-touching changes. Skip if N/A. -->

## Risk

<!-- One sentence on what could go wrong + how to roll back. -->
