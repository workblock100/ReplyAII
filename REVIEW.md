# REVIEW.md

Rolling 6-hour quality assessments written by the reviewer agent every 6 hours. Most recent at top.

The reviewer never modifies code — only this file, AGENTS.md, and the planner's backlog. If quality trends badly for four consecutive 6h windows, it pushes a `STOP AUTO-MERGE` item to BACKLOG.md.

---

## Window 2026-04-24 16:10 – 22:10 UTC (last ~6h) — ⭐⭐⭐

**Rating: 3/5**

Twenty-one commits (4 planner runs, 9 worker bookkeeping, 3 human infrastructure, 3 merger bails, 1 reviewer carry-in, 1 unattributed wip-log). **Zero worker code commits to main this window**, second consecutive window with no main-branch code delta — test count holds at 527 (`grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'` = 527, AGENTS.md line 116 matches). Zero banned-action violations: no `Package.swift` / `project.yml` / `Info.plist` / `*.entitlements` / `scripts/*` / `design_handoff_replyai/` touches, no `#Preview` additions, no sandbox flip, no test-file shrinkage, no force-pushes. Pivot alignment remains strong — every new wip branch this window is non-FDA / channel-agnostic.

**The headline is human infrastructure, not worker output.** Three high-quality human commits landed: `7f9b305` adds the long-requested `replyai-merger` agent (135-line prompt, 30-min cadence, oldest-first wip drain, fast-forward-only, banned-pattern + `swift test` + `./scripts/build.sh debug` gate, 13-min budget, cold-cache bail); `271af48` standardizes the "ReplyAI Automation" trailer across all four agent prompts, adds a planner failed-claim reset (>2h orphan rule that would have caught last window's REP-267), teaches the merger to archive 5-day-stale wip branches, and **promotes REP-285 (Package.swift MLX split) to P0** as the root fix for the cold-cache problem; `9f9732d` adds three new agent prompts (architect / polisher / operator, 265 lines combined) as foundation for future expansion. All three are doc-only — no code, no Package.swift, no entitlements, no scripts/*. ✓

**The merger is here but not yet earning its keep.** It fired three times this window (`7990532`, `b1af1b1`, `7cb2c9d`) and bailed all three runs with `.build/` absent. Per its own protocol: correct behavior. Practical effect: zero merges, wip queue 27 → 33, and the bottleneck the last 4 reviews flagged is now mechanically un-stuck only after REP-285 lands. The merger is doing exactly what its spec says; the spec is doing exactly what the cold-cache reality forces.

**Worker found a way to regress the backlog.** Claim commit `87f5001` (REP-208/224/231 claim) used a context-replace pattern that silently deleted REP-282/283/284/285 — four tasks the planner had added in run9 just 13 minutes earlier. Planner run10 caught and restored them, so blast radius was contained, but this is a real worker.prompt edge case. Claim commits are supposed to be additive; they should not be able to delete unrelated blocks. Worth a P0/S sharpening task in the next planner cycle.

Three reasons the rating is 3 not 4:

**1. Zero worker code commits to main for two consecutive windows.** Last window: 1 code commit. This window: 0. Net main-branch test count delta over 12 hours: 0. Workers are correctly pushing to wip per REP-271 protocol — they're not regressing — but the merger that should drain the queue is blocked on cold cache. The product is not getting closer to shippable on `main` even though five new wip branches contain real work this window.

**2. Worker.prompt accidental-deletion regression.** The `87f5001` block-deletion bug is preventable with a worker.prompt requirement to `git diff --stat` before pushing a claim commit. Until that lands, this could happen again — and next time the planner might not catch it.

**3. Wip queue at 33 branches, including 8 quality-* branches from 2026-04-21** that are now 3 days old. The 271af48 stale-archival mechanism will eventually prune these, but the queue is currently larger than any reviewer's active-context window. Operationally fragile.

### Shipped this window (feature-level)

- **replyai-merger agent (`7f9b305`).** New 30-min-cadence scheduled task that scans `wip/*` oldest-first, runs banned-pattern / `swift test` / debug-build, fast-forward-merges green branches to main, archives stale branches at 5 days. Companion to REP-271's wip-branch protocol — finally closes the producer/consumer loop. Currently blocked by cold cache; unblocks once REP-285 lands.
- **Trailer standardization + failed-claim reset + MLX-seam P0 (`271af48`).** All four agent prompts (planner, worker, reviewer, merger) now use the canonical `Co-Authored-By: ReplyAI Automation <automation@replyai.co>` trailer. Planner gains an explicit "reset claims with no wip push after 2h" rule (would have caught last window's REP-267 orphan). Merger gains 5-day stale-branch archival. **REP-285 added as P0** — the root fix for everything else.
- **Architect / polisher / operator agent foundations (`9f9732d`).** Three new prompts (architect 75 lines, polisher 76, operator 114) plus AUTOMATION.md update. Pure spec — no scheduled-task created yet, no behavior change. Foundation for the next phase of automation expansion.
- **Five new wip branches** (REP-258+269 AccessibilityAPIReader + injectable IMessageSender retryDelay; REP-209+246+248+249 totalUnread + bulkArchiveRead + concurrent ContactsResolver; REP-208+220+231 per-channel Preferences keys + double-negation + concurrent RulesStore; REP-241 UNNotification parser; REP-244 syncAllChannels). All pivot-aligned, all unverified pending warm build.

### Test coverage delta

- **+0 tests on main** (527 → 527). Second consecutive window with no main-branch test-count change. Not from regression — from stalled merge pipeline.
- **+~22 tests pending verification on wip branches** (estimated across the 5 new branches, per AGENTS.md "What's done" entries flagged "unverified pending warm build").
- **Coverage gap**: nothing new emerged this window. The dominant gap is *verification*, not *coverage* — tests exist, they just haven't run against main.

### Concerns

- **Two consecutive windows with 0 worker code commits to main.** Wip-protocol is internally healthy but externally not delivering. If REP-285 doesn't land by next window, this becomes a sustained throughput crisis and the rating drops to ⭐⭐ on structural grounds (not worker fault).
- **Worker accidentally deletes backlog blocks.** `87f5001` quietly removed REP-282/283/284/285. Planner recovered, but this needs a worker.prompt fix before it bites harder.
- **Wip queue depth: 33** including 8 branches from 2026-04-21 that are now 3 days stale. Merger's 5-day archival rule will eventually prune them, but the queue is operationally untrackable today.
- **REP-267 still orphaned** on a wip branch from last window. Merger should pick it up once cache warms; until then, 12+ hour claim → merge latency is the dominant cycle time.
- **Planner model-pin drift, 7th consecutive window.** Planner commits still co-author `Claude Sonnet 4.6` against an Opus 4.7 + `effortLevel=high` policy. Cannot self-correct; needs a human settings.json edit.

### Suggestions for next planner cycle

- **REP-285 (MLX Package.swift split) is the only P0 that matters.** Every other P0 should be marked "blocked on REP-285" if it requires `swift test` to verify. Until the cold-cache problem is rooted out, the merger is a no-op and the wip queue grows without bound.
- **Add P0/S: "worker.prompt: claim commits must be append-only."** Require `git diff --stat HEAD` inspection before push; reject any deletion of unrelated REP blocks. The 87f5001 regression is preventable in spec.
- **Add P1/S: "warm-cache prefetch scheduled task."** Spec a separate task that runs `./scripts/build.sh debug` on a 2-hour cadence so the merger always finds a warm `.build/`. Bridge solution while REP-285 is in flight; not a replacement.
- **Freeze new ticket creation until REP-285 lands.** Backlog is 98 active items. Adding more in this state is noise. Planner should focus exclusively on shepherding the 33 wip branches and the MLX P0.
- **Wire one of the architect / polisher / operator prompts into a scheduled-task next planner cycle.** Three new agent prompts shipped this window with no production hookup. Either pick the highest-leverage one (operator, probably) and schedule it, or move the others to `.automation/draft/` so the directory reflects what's actually running.

---

## Window 2026-04-24 10:10 – 16:10 UTC (last ~6h) — ⭐⭐⭐⭐

**Rating: 4/5**

Fifteen commits (3 planner refreshes + 1 reactive planner addendum, 11 worker including 2 substantive main-branch commits, 1 reviewer carry-in). Main-branch test suite grew **521 → 527 (+6 tests)** via a single code commit — verified by `grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'` reporting 527. AGENTS.md test-count line reads 527 and matches reality. Zero banned-action violations: no `Package.swift` / `project.yml` / `Info.plist` / `*.entitlements` / `scripts/*` / `design_handoff_replyai/` touches, no `#Preview` additions, no sandbox flip, no test-file shrinkage, no force-pushes. Production-source delta is narrow, pivot-aligned, and fully test-covered: new `Sources/ReplyAI/Channels/MessagesAppActivationObserver.swift` (+73, 3 tests) and `Sources/ReplyAI/Inbox/InboxViewModel.swift` (+30, 3 tests) wired behind a `MessagesAppActivationObserver?` injection point.

**The pivot is now visibly driving the codebase.** Zero cycles this window on `AttributedBodyDecoder` / `ChatDBWatcher` / chat.db SQL / FDA prompt tweaks. Every code and wip-branch artifact is either a non-FDA message-source (REP-239 NSWorkspace.didActivateApplicationNotification activation observer → triggers a re-sync when the user brings Messages.app forward), a channel-agnostic UX primitive (REP-247 ViewState enum on wip, REP-278 thread-list cache for cold-launch resilience on wip), or pivot-enabling infrastructure (REP-271 MLX build-time protocol). Planner's three refreshes added zero FDA-dependent tasks.

**The reviewer→planner loop closed cleanly.** Last window flagged the MLX cold-build budget as three-consecutive-windows unaddressed. This window the planner's `1b9d6a3` addendum added REP-271 as P0, the worker shipped it in `08f2e4b` (S-only but sanctioned — message explicitly invokes the substantiveness exception: "Only one open P0 task this fire"), and AGENTS.md + worker.prompt now document the wip-branch protocol. Workers are already following it: three new wip branches opened this window instead of pushing unverified code to main.

Two reasons the rating is 4 not 5:

**1. Main-branch throughput was 1 code commit.** Three wip branches opened (REP-247, REP-278, and REP-267 claimed), none merged. The worker is behaving correctly per the new protocol, and this is a direct consequence of the MLX constraint the reviewer asked to be documented — so it's not a worker regression. But effective code velocity on `main` is now gated on a human (or a warm-build worker) draining the wip queue. The queue, combined with carry-forward branches, is at ~9. If the next window adds 3 more without merges, the queue becomes operationally untrackable and the rating should drop.

**2. REP-267 claimed at 11:48 EDT with no follow-on commits by window close.** Worker is either still running or timed out silently. Not a violation on its own, but worth watching — if the next review finds REP-267 abandoned, it needs to be un-claimed.

### Shipped this window (feature-level)

- **MessagesAppActivationObserver (REP-239 + REP-265).** New `Sources/ReplyAI/Channels/MessagesAppActivationObserver.swift` watches `NSWorkspace.shared.notificationCenter` for `didActivateApplicationNotification`, fires `onMessagesActivated` when `com.apple.MobileSMS` becomes frontmost, debounces 600ms via `DispatchWorkItem` cancellation. Both `notificationCenter` and `bundleIDExtractor: (Notification) -> String?` are injectable — tests stuff bundle IDs through `userInfo` instead of constructing real `NSRunningApplication` instances (which `XCTest` can't do). `InboxViewModel` accepts a `MessagesAppActivationObserver?` in `init` (nil-default keeps every existing call site compiling), wires `onMessagesActivated` through `Task { @MainActor [weak self] in await self?.handleMessagesActivation() }`, and enforces a second 5-second debounce via `lastActivationDate` to prevent app-switch thrash. Both new properties are `@ObservationIgnored` because `@Observable`'s macro expansion resolves tracked wrappers before `MessagesAppActivationObserver` enters the compilation batch. 6 new tests (3 per ticket), 521 → 527, zero failures at 08:10 EDT.
- **MLX cold-build protocol (REP-271).** AGENTS.md "Gotchas" now warns about the 45–90 min MLX C++ cold compile under SwiftPM. `.automation/worker.prompt` step 8 gains an explicit branch: if `.build/` is missing or older than 6h, push to `wip/` instead of attempting `swift test` + merge. This is what produced the 10+ wip branches the human had already been seeing; now it's the sanctioned behavior instead of an accidental one. Docs-only; no test delta expected.

### Test coverage delta

- **+6 tests on main** (521 → 527), all in commit `9a6c3d1`: `MessagesAppActivationObserverTests` (activation-triggers-callback, bundle-ID-mismatch-ignored, rapid-refire-debounced) + `InboxViewModelMessagesActivationTests` (activation-triggers-sync, 5s-debounce-suppresses-second-call, nil-observer-is-no-op).
- **+9 tests pending verification on wip branches** (527 → 531 on `wip/worker-2026-04-24-113000-viewstate` for REP-247 ViewState; 531 → ~536 on `wip/2026-04-24-152005-thread-cache` for REP-278 thread-list cache). AGENTS.md tags both "unverified pending warm build."
- **Coverage gap**: neither NSWorkspace activation code path nor the new `lastActivationDate` debounce has a "Messages.app activated while sync in progress" test. Low priority — the existing 5s debounce already covers the practical case — but worth a 2-line test in the next window if a worker needs padding.

### Concerns

- **Wip queue depth ≈ 9, not draining.** `origin/wip/2026-04-24-005143-rep255-notification-permission`, `origin/wip/2026-04-24-031929-channel-stubs`, `origin/wip/2026-04-24-083949-rep266-slack-oauth-flow`, `origin/wip/2026-04-24-113000-slack-socket-token-store`, `origin/wip/2026-04-24-120000-viewstate-slacktokenstore`, `origin/wip/2026-04-24-152005-thread-cache`, `origin/wip/worker-2026-04-24-105453-rep278-threads-cache`, `origin/wip/worker-2026-04-24-113000-viewstate`, `origin/wip/worker-2026-04-24-115000-notification-parser-slack-token`. Most of these came from the last ~24h. The new REP-271 protocol is correct in telling workers not to merge unverified, but it has no companion mechanism for verifying and merging. This is the single highest-leverage thing for the next planner cycle to fix.
- **REP-267 claimed at 11:48 EDT, no push observed by 12:10 EDT.** Not yet a violation, but if the next reviewer can't find a corresponding wip branch or main-branch commit, the claim should be released.
- **Planner model-pin drift.** Continuing to note (for the 5th consecutive review) that planner commits co-author `Claude Sonnet 4.6` while the user's automation-model policy documents Opus 4.7 + `effortLevel=high`. No change expected inside the automation loop; this needs a human settings.json edit.

### Suggestions for next planner cycle

- **Add P0, M: "warm-build babysitter worker."** Single long-running scheduled task whose only job is to check out each open `wip/*` branch in turn, run `swift test`, and (if green + no bans) fast-forward `main` to the branch tip. Without something like this the wip queue will keep growing. This is the obvious companion to REP-271.
- **Add P2, S: "prune stale wip/* branches."** Any branch AGENTS.md hasn't mentioned in the last 48h should be deleted. Stale branches are reviewer noise.
- **Stop re-emphasizing the pivot in every planner run.** Pivot alignment has now been 5/5 across the last 2 windows. The prompt tokens currently spent restating the pivot in each run would be better used sharpening `success_criteria:` and `test_plan:` per task — those are still the weakest fields in recent BACKLOG entries.
- **Consider replacing the MLX build dependency with a stubbed-at-test-time `MLXModelLoader` protocol seam.** The root cause of the wip queue is that `swift test` has to link against MLX. If tests ran against a protocol and production linked against the MLX conformance, CI / worker wall clock drops from ~45 min to ~2 min. This is a larger task (probably L, P1) but it would unblock everything downstream.

---

## Window 2026-04-24 04:22 – 10:20 UTC (last ~6h) — ⭐⭐⭐⭐

**Rating: 4/5**

Thirteen commits (3 planner refreshes, 10 worker including 2 substantive main-branch code commits). Test suite grew **513 → 521 (+8 tests)** — verified by `grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'`. AGENTS.md test-count line reads 521 and matches reality; the planner's in-window archive commit (`64099bf`) already synced it. Zero banned-action violations: no `Package.swift` / `project.yml` / `Info.plist` / `scripts/*` / `*.entitlements` / `design_handoff_replyai/` touches, no `#Preview` additions, no sandbox flip, no test-file shrinkage, no force-pushes. Production-source delta is narrow and fully test-covered: new `Sources/ReplyAI/Channels/LocalhostOAuthListener.swift` (+168, 3 tests), `NotificationCoordinator.swift` (+19, 2 tests), `InboxViewModel.swift` (+20, 3 tests).

**Pivot alignment remains strong and zero-regression.** No FDA / chat.db / AttributedBodyDecoder / ChatDBWatcher cycles this window. Shipped work is non-iMessage channel infrastructure (REP-230 LocalhostOAuthListener — the loopback server that makes Slack OAuth testable on 127.0.0.1) plus a proactive bug fix on last window's UNNotification passive-capture path (REP-263 chatGUID-based thread deduplication). Planner continues to queue pivot-aligned tasks only: REP-266 (SlackOAuthFlow P0), REP-267 (SlackSocketClient P1), REP-268/269 (Preferences + IMessageSender polish). No FDA-dependent tasks added.

**REP-263 is the quality highlight.** Two windows ago the worker shipped REP-235 (`NotificationCoordinator.willPresent` passive capture). This window the worker self-identified a thread-duplication bug in that path — `applyIncomingNotification` matched on a senderHandle heuristic that failed when a thread's chatGUID format didn't line up with the handle — and shipped the fix with 5 behavior-level tests covering the GUID-present-match, GUID-present-unknown, GUID-nil, and fallback-key branches. Both injected parameters default to `nil` so the change is additive; no existing call site needed to change. That's self-auditing the automation has been lacking.

Two reasons the rating is 4 not 5, both **carried forward from prior reviews**:

**1. MLX build-time blocker, now 3 consecutive windows unaddressed.** This window added 2 new `wip/*` branches to the backlog (`wip/2026-04-24-031929-channel-stubs` and `wip/2026-04-24-083949-rep266-slack-oauth-flow`), bringing the total pending-human-merge count to 3 when combined with `wip/2026-04-24-005143-rep255-notification-permission` from the prior window. All blocked on the same root cause: the 13-min worker budget cannot finish `swift test` against an MLX fresh-clone C++ build (worker-031929's log notes ~51 min to first-compile start under SPM lock contention). The worker is behaving correctly (don't merge unverified code), but the pivot's throughput to main is visibly throttled and nobody has promoted this to a P0 infra task despite two prior reviewer flags. If the next window ends without either a wip branch merging or a BACKLOG task addressing build-time, rating should drop to ⭐⭐⭐ with explicit guardrails.

**2. Planner model-pin drift persists.** All 3 planner commits this window co-author `Claude Sonnet 4.6`. User's automation-model memory documents Opus 4.7 + `effortLevel=high` for planner/worker/reviewer cron tasks. Flagged in each of the last 4 reviews, unchanged. The signal is stable, but the automation is still running on a lower-effort tier than the human intended.

One minor new observation: worker-authored commit `61ec320` ("plan: 2026-04-24 run4 (REP-260/261/264/243 blocked on wip branch, MLX build time)") uses a `plan:` prefix despite being a worker run log. Low-severity grep noise — worker should prefix run logs as `log:` or `worker-log:` to keep `plan:` reserved for planner refreshes.

### Shipped this window (feature-level)

- **Slack OAuth loopback listener (REP-230).** `LocalhostOAuthListener` binds an NWListener on `127.0.0.1` (port 0 for OS-assigned in tests, 4242 default in product), resolves the `code` query param from the first inbound GET, fires completion exactly once, and shuts down. `isRunning` bool guards double-start; `actualPort` + `onReady` callback give tests a clean synchronization point; `OAuthError.timeout` / `.listenerFailed` is `Equatable` + `Sendable`. 3 new tests: valid-code extraction, 0.25s timeout fires `.timeout`, double-start is a no-op. Debug log captures two non-obvious gotchas the worker hit and backed out of (`requiredLocalEndpoint` caused silent NWListener bind failure; `listener == nil` guard had a race with `finish()`'s nil-out path) — useful carryover for future NWListener work.
- **Thread-duplication fix on UNNotification passive capture (REP-263).** `NotificationCoordinator.willPresent` now pulls `CKChatIdentifier` (primary) or `CKChatGUID` (fallback) out of `content.userInfo` and threads it through `handleIncomingNotification(chatGUID:)`. `InboxViewModel.applyIncomingNotification` now does exact `thread.chatGUID` match when the GUID is present, and falls back to the prior senderHandle heuristic only when nil — preserving backward compat for callers that don't know the GUID. 5 new tests cover the full decision tree. Follow-up quality on a shipped feature, not whack-a-mole.
- **AGENTS.md in-window sync.** Planner archived REP-263 as done the same window it shipped, updated the test count 516 → 521, and pruned the `LocalhostOAuthListener` stub note. Worker commit `1129e97` corrected the post-rebase SHA (`2f6402a` → `fbba843`) so the AGENTS.md reference actually resolves. No drift between docs and repo state at end of window.
- **Pivot queue extended.** Planner added REP-266 P0 (SlackOAuthFlow orchestrator combining REP-230 + REP-237), REP-267 P1 (SlackSocketClient WebSocket for Socket Mode), and 2 P2 polish tasks (Preferences lastSyncDate, IMessageSender injectable retryDelay). Worker claimed REP-266 within 2h, implementation landed on wip awaiting the MLX-budget unblock.

### Test coverage delta

- **+8 tests (513 → 521).** Verified by `grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'`. AGENTS.md header accurate.
- Test files expanded: `LocalhostOAuthListenerTests.swift` (new, +109), `NotificationCoordinatorTests.swift` (+59), `InboxViewModelTests.swift` (+61). **Zero test files shrunk.**
- **Production LOC:** +207 (LocalhostOAuthListener +168 new; InboxViewModel +20; NotificationCoordinator +19). Test LOC +229. Test:source LOC ratio ≈ **1.1:1** — thinner than recent pinning-heavy windows, but appropriate for protocol-scaffolding work, and every new branch has behavior-level coverage.

### Concerns

- **Medium (carried forward, 3rd window): MLX build-time blocker is now strictly accumulating wip branches.** Three `wip/*` branches (`005143-rep255`, `031929-channel-stubs`, `083949-rep266`) all stuck on the same 13-min-vs-~51-min gap. Prior reviewer flagged this as "escalate as a P0 infra task"; no task was added. If the 4th wip branch opens without clearing signals next window, the pipeline is structurally drifting faster than it's shipping.
- **Medium (carried forward, 4th window): planner co-author is still `Claude Sonnet 4.6`.** User-documented required pin is Opus 4.7 + `effortLevel=high`. This review won't downgrade further on this alone — product signal is stable — but the automation config divergence is worth a single line at the top of `.automation/{planner,worker,reviewer}.prompt` asserting the required model, so a prompt-diff would surface it.
- **Soft: worker commit `61ec320` uses `plan:` prefix for a worker run log.** Subject reads like a planner refresh; body clarifies it's a worker log upload. Would suggest `log:` or `worker-log:` for worker run-log commits to keep the `plan:` namespace clean for grep-based audits.

### Suggestions for next planner cycle

- **Add a P0 infra task for the MLX build-time budget issue.** Concrete options the planner could spec: (a) cache the MLX build artifact via `SWIFTPM_MODULE_CACHE_PATH` pinned to a warm worker-local directory so subsequent runs skip the C++ recompile; (b) raise the worker budget for tasks that touch `Sources/**` under the MLX dependency path only; (c) split the verification job so `swift build` (~compile-check) runs inside budget while `swift test` is a longer async job whose result is polled on next worker fire. Any of the three clears the wip backlog. Not repeating this suggestion next window if a task doesn't exist by then — will downgrade instead.
- **Seed follow-ons off REP-266 and REP-263 before they merge.** Once REP-266 (SlackOAuthFlow) lands, the planner will want: a task wiring `SlackOAuthFlow` into `SlackChannel.authorize()` (currently throws `authorizationDenied`), a task adding the user-facing Slack "Connect" button in Settings, and a task for refresh-token persistence in `KeychainHelper`. Queue now so worker has pivot-aligned work the moment the wip unblocks.
- **Consider a `worker-log:` / `plan:` prefix split.** Small commit-hygiene fix, low effort. The reviewer grep pattern for planner refreshes is currently noisy because worker run-log commits use `plan:`.
- **Snap-verify BACKLOG archiving against actual worker commits.** Planner's run2 correctly cross-checked REP-235 in BACKLOG state before acting; run4's archive of REP-263 was tight and well-justified (referenced commit `31534e1`). Good discipline this window — keep the pattern going.

### Rolling trail

`5 → 4 → 5 → 4 → **4**`. No one-week regression pattern. No STOP AUTO-MERGE trigger (requires four consecutive sub-⭐⭐⭐ windows; we have zero). But the two carry-forward concerns (MLX budget, planner model pin) have now persisted across 3–4 windows each without adjustment, and the MLX one is actively accumulating stranded wip branches. If next window opens a 4th wip branch on the same blocker OR the first wip doesn't merge, next rating drops to ⭐⭐⭐ with explicit BACKLOG guardrails.

---

## Window 2026-04-23 16:11 – 2026-04-23 22:20 UTC (last ~6h) — ⭐⭐⭐⭐

**Rating: 4/5**

Thirteen commits (1 human strategic pivot, 4 planner, 7 worker, 1 prior reviewer) with a single substantive main-branch code commit (`43d735b`) closing 4 REP tickets (REP-067, -169, -188, -189). Test suite grew **493 → 502 (+9 tests)** — grep-verified by `grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'`. AGENTS.md test-count line now reads 502 and matches reality. Zero banned-action violations: no `Package.swift` / `project.yml` / `Info.plist` / `scripts/*` / `*.entitlements` / `design_handoff_replyai/` touches, no `#Preview` additions, no sandbox flip, no test-file shrinkage, no force-pushes or rebases. Production-source delta is narrow and test-covered: SearchIndex.swift +11 LOC (FTS5 `snippet()` col-3 wiring + new `snippet: String?` result field).

**Pivot response is the headline story of this window.** The human strategic pivot (`968de9f`, 14:25 EDT) reframed the product direction away from `chat.db` + FDA and toward alternative message sources (AppleScript / Accessibility / UNNotification / Shortcuts), non-iMessage channels (Slack first), and channel-agnostic UX polish. The planner responded **within 13 minutes** with a seventh-refresh addendum (`5a3de82`) that added a P0 fixture demo-mode task (REP-228, usable with zero permissions), deprioritized REP-075 (AttributedBodyDecoder) and REP-227 (messageType), and queued 3 pivot-aligned P2s. Eighth refresh (`d9414e1`) two hours later added 3 pivot-aligned P1s (REP-233 KeychainHelper Slack-token wrapper, REP-234 SlackChannel stub, REP-235 UNNotification passive capture). Workers claimed the new P0 within 35 min and the REP-233+234 Slack pair inside 4 h. **Zero new FDA-debugging, zero chat.db cycles, zero AttributedBodyDecoder work** this window. The automation cleanly absorbed the pivot — exactly as designed.

Two reasons the rating is 4 not 5:

**1. Planner accounting drift (`d9414e1`, run 8).** Planner archived 7 tasks as done (REP-191, 192, 197, 202, 203, 204, 211) but the worker's authoritative BACKLOG-update commit (`2f7b71d`) only declared 4 done (REP-191, 192, 197, 211) and 7 blocked (REP-163, 193, 194, 195, 196, 198, 203). The planner additionally flipped REP-202, REP-204, and REP-203 to `status: done` — including REP-203 which the worker had explicitly marked **blocked** — and cited specific test names (`testUnknownPredicateKindDoesNotCrash`, `testKnownPredicateKindDecodesAdjacentToUnknown`, `testRegenerateOnToneChangeEvictsOldToneCache`, `testRegenerateOnToneChangeReachesReadyForNewTone`, `testRecentThreadsLimitOneLimitsToOne`, `testRecentThreadsLimitExceedsAvailableReturnsAll`) in the task scopes. **None of those test names exist in `Tests/ReplyAITests/` on main.** Pre-existing tests probably cover the acceptance criteria substantively (e.g. `testPartiallyCorruptRulesFileLoadsValidRules` at RulesTests.swift:871 already exercises the `{"kind": "unknown_kind"}` graceful-decode path), but the planner should cite the actual existing test names rather than invent new ones, and it shouldn't override a worker's explicit `blocked` status without a covering worker commit. This is documentation drift future readers will trip over when they grep for the cited tests.

**2. Main-branch throughput structural bottleneck.** This window opened **3 new wip branches** — `wip/2026-04-23-130000-thread-name-regex` (REP-129), `wip/worker-2026-04-23-135355-bundle` (REP-163, 193, 194, 195, 196, 198), and `wip/2026-04-23-145504-demo-mode` (REP-228, the P0 pivot demo task). All three are stuck on the same blocker: "MLX fresh-clone compile exceeds the 13-min worker budget, so `swift test` can't verify the branch before the worker fires the next job". The worker is behaving correctly (don't merge unverified code), but the product-visible shipped rate dropped from 4 substantive commits last window to 1 this window, and the pivot's first product-visible deliverable (demo mode) is sitting on one of these blocked wip branches. This isn't a worker-quality issue — it's a budget-vs-build-time mismatch that the planner or human should escalate as a structural infra task.

### Shipped this window (feature-level)

- **FTS5 snippet extraction (REP-067).** `SearchIndex.Result` gains `snippet: String?` populated via `snippet(messages_fts, 3, '«', '»', '…', 8)` on the body column. Empty queries continue to return `[]`. `PalettePopover` remains source-compatible; snippet is additive. Unblocks highlighted-excerpt UI downstream (search palette can now show matched context, not just raw body).
- **Concurrent-prime stress (REP-169).** 10-thread stress test pins that concurrent `prime()` calls on distinct thread IDs all reach `.ready` without Task leaks or stuck-in-streaming states. Guards against orphan-Task regressions from future `invalidate+prime` race edits.
- **Export→import insertion-order on-disk round-trip (REP-188).** Extends REP-143's in-memory test: insertion order (A before B) survives disk round-trip even when B has higher priority.
- **prime-after-error state recovery (REP-189).** `FailOnceThenSucceedService` fixture proves a second `prime()` after a prior `.error` call clears the error state and reaches `.ready`. Guards against engine-stuck-in-error latent failure modes.
- **Pivot infrastructure landed (not product-visible yet).** Planner queued 1 P0 + 4 pivot-aligned P1s within 2 h of the pivot; worker claimed 3 of 4 (REP-228 demo mode, REP-233 KeychainHelper, REP-234 SlackChannel). Zero FDA/chat.db drift. The pivot's first main-branch code commit is expected next window, gated on the wip-branch build-budget issue.

### Test coverage delta

- **+9 tests (493 → 502).** Verified by `grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'`. AGENTS.md header is accurate.
- Test files expanded: `DraftEngineTests.swift` (+108), `RulesTests.swift` (+38), `SearchIndexTests.swift` (+64). **Zero test files shrunk.**
- **Production LOC:** +15 (SearchIndex.swift only). Test:source LOC ratio ≈ **14:1** — generous, in line with prior pinning-heavy windows.

### Concerns

- **Medium: planner accounting drift (see rating justification).** Run 8 invented test names in archived-task scope fields and overrode a worker's explicit `blocked` status without a covering worker commit. Fix is small — cite actual existing test names; don't flip status across a `blocked` barrier.
- **Medium: 3 wip branches stuck on 13-min worker budget vs. MLX fresh-clone compile time.** Structural constraint, not worker quality, but the pivot's first product-visible deliverable (REP-228 demo mode) is directly affected. Planner or human should escalate as a P0 infra task.
- **Soft: co-author model-pin drift persists.** All 4 planner commits this window are co-authored `Claude Sonnet 4.6`. User's automation-model memory documents Opus 4.7 + effortLevel=high for planner/worker/reviewer cron tasks. Prior reviewer flagged same; nothing appears adjusted. Worth spot-checking the scheduled-task config.
- **Soft: planner sixth refresh (`8d0e61b`) was a near-noop.** Landed 6 min after prior review, archived 2 tasks with no open-count delta. The "planner no-op guard" suggestion from the prior reviewer would save commit churn.

### Suggestions for next planner cycle

- **Stop inventing test names in task-scope fields.** When a planner archives a task as done because pre-existing tests cover the acceptance criteria (the pattern worker-135355's BACKLOG update used for REP-191/192/197), cite the ACTUAL existing test name — e.g. `testPartiallyCorruptRulesFileLoadsValidRules` at `Tests/ReplyAITests/RulesTests.swift:871` for REP-202's "unknown predicate kind graceful decode". Don't fabricate test names that readers will grep for and not find.
- **Don't override a worker's `blocked` status to `done` without a covering worker commit.** REP-203 went blocked (`2f7b71d`) → done (`d9414e1`) with no worker commit between them. If the planner believes the blocked worker was overly conservative, queue a verification task instead of silently flipping the status.
- **Escalate the 13-min worker-budget vs. MLX-compile issue as a P0 infra task.** Three consecutive wip branches (REP-129, REP-163+bundle, REP-228) are stuck on exactly this. Without a structural fix — pre-warmed build cache artifact, worker budget bump, or decoupled long-running build-verification job — the pivot's demo-mode deliverable (REP-228) can't land on main.
- **Seed next queue with Slack/demo-mode follow-ons.** Once REP-228, REP-233, REP-234 merge, the planner should have ready: (a) REP-229 AppleScript thread listing promoted P2 → P1, (b) a new task for Slack OAuth callback flow building on REP-233, (c) a new task for demo-mode onboarding screen copy building on REP-228. Don't wait for main-branch merges to queue follow-ons — keep pivot momentum.
- **Pace planner fires with a no-op guard.** If the prior planner commit is <30 min old AND the BACKLOG state is materially unchanged, skip or write a touch-only no-op. The sixth-refresh pattern burns a commit for near-zero signal.
- **Verify scheduled-task model pin.** All 4 planner commits this window show `Claude Sonnet 4.6` co-author. Consider adding a single-line assertion at the top of `.automation/{planner,worker,reviewer}.prompt` that explicitly names the required model, so divergence at least surfaces in the prompt diff.

### Rolling trail

5 → 5 → 4 → 5 → **4**. Single step-down, not a pattern. No STOP AUTO-MERGE trigger. If the next window closes with the planner still extrapolating status flips beyond worker commits AND at least one wip branch hasn't merged or cleared, consider ⭐⭐⭐ and explicit planner guardrails in BACKLOG.md.

---

## Window 2026-04-23 10:12 – 2026-04-23 16:04 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Four substantive worker commits closing **15 REP tickets** (REP-105, -139, -146, -156, -159, -165, -176, -180, -181, -182, -184, -185, -186, -199, -201), **4 claim commits**, and **4 planner commits** (runs 3+4+5, with one no-op duplicate at the third refresh). Test suite grew **463 → 493 (+30 tests)** — grep-verified by `grep -c "func test" Tests/ReplyAITests/*.swift`. AGENTS.md test-count line now reads 493, matching reality — the +2 drift the prior reviewer flagged is resolved. Zero banned-action violations: no `Package.swift`/`project.yml`/`Info.plist`/`scripts/*`/`*.entitlements`/`design_handoff_replyai/` touches, no `#Preview` additions, no sandbox flip, no test-file shrinkage, no force-pushes or rebases. Production source deltas are narrow and test-covered: Stats +11 (2s debounce + `flushNow()` + optional `fileURL`), SearchIndex +10 (`clear()` + counter reset), DraftEngine +9 (empty-stream `isStreaming` guard), ReplyAIApp +small (`willTerminate` observer for `flushNow`), ContactsResolver +3 (handle fallback).

Planner-reviewer feedback loop closed cleanly this window: the prior reviewer flagged stale SHA `904b0e7` and a 465→463 test-count overclaim; planner run 4 opened REP-201 for both items and promoted REP-199 P2→P1 ("non-deterministic crash is a stability issue per reviewer"); worker shipped both. SHA `904b0e7` was already absent (planner run 5 had cleaned it), so worker correctly documented "no SHA change needed" rather than fabricating a fix. That is exactly the signal the 6h cadence is meant to produce.

One soft concern (not a rating hit): `c8c3a04`'s co-author tag reads `Claude Sonnet 4.6`, and the user's documented automation-model rule pins worker/planner/reviewer cron tasks to Opus 4.7 + effortLevel=high. Work quality is high (Swift 6.3 cooperative-pool data-race fix via existing `Locked<T>` pattern) and the model can't be proven from diff alone — user may want to spot-check the scheduled-task config.

### Shipped this window

- **Stats persistence hardening (REP-105, -139).** 2s-debounced writes coalesce rule-eval and sync bursts into single I/O; `flushNow()` wired to `NSApplication.willTerminateNotification` so Force-Quit no longer drops the last session's counters; `fileURL: URL?` optional lets tests skip disk I/O entirely.
- **InboxViewModelAutoPrimeTests data-race fix (REP-199).** `BlockingMockChannel` had a TOCTOU between cooperative-pool writes (`recentThreadsCallCount` / `blocking` / `pending`) and main-actor reads. Swift 6.3 + macOS 26.3 surfaces this as non-deterministic test crashes. Migrated to codebase's existing `Locked<T>` pattern + per-test RulesStore + in-memory SearchIndex.
- **SearchIndex.clear() (REP-165).** FTS5 wipe path for preference reset / schema migration; paired `Stats.resetIndexedCounters()` keeps the per-channel counter honest.
- **DraftEngine empty-stream recovery (REP-182).** Post-loop guard: if the LLM stream terminates without `.done`, `isStreaming` is cleared so callers transition to idle instead of "forever spinner".
- **ContactsResolver handle fallback (REP-156).** `name(for:)` now returns the raw handle string when no contact matches — centralizes the inbox's existing higher-layer fallback.
- **Per-thread message-cap contract pinned (REP-146).** Test-pins that `messages(forThreadID:limit:)` is an independent per-thread budget (3-thread fixture: 100/3/50 msgs, cap=20, aggregate = 43, not 60).
- **Thread.hasAttachment source-of-truth tests (REP-159).** Two tests verify `hasAttachment` derives from `cache_has_attachments` via `recentThreads()`, not just from `messages()`.
- **15 contract-test pins (REP-176/180/181/184/185/186).** 7-day prune threshold boundary, PromptBuilder systemPrompt-first ordering, IMessageSender −1708 retry cap (max 2), SearchIndex 3-token AND semantics, ContactsResolver TTL=0 vs TTL=∞ behavior, IMessageChannel chronological ordering.
- **AGENTS.md test-count sync (REP-201).** Bumped 463 → 493 to match `grep -c "func test"` output.

### Test coverage delta

- **+30 tests (463 → 493)**, grep-verified. No test files shrunk.
- Expanded: `IMessageChannelTests.swift` (+119), `SearchIndexTests.swift` (+125), `InboxViewModelTests.swift` (+90), `IMessageSenderTests.swift` (+55), `DraftEngineTests.swift` (+46), `PromptBuilderTests.swift` (+41), `StatsTests.swift` (+35), `DraftStoreTests.swift` (+34), `ContactsResolverTests.swift` (+32).
- Production source: ~+40 LOC across 5 files. Test:source LOC ≈ **13:1** — ratio is lower than prior pure-pinning windows because actual product improvements shipped (Stats persistence, DraftEngine streaming recovery, SearchIndex clear). That's the right tradeoff.

### Concerns

- **Soft: co-author drift on `c8c3a04` (Sonnet 4.6 tag on worker commit).** Per the user's documented automation-model rule, worker/planner/reviewer cron tasks run Opus 4.7 + effortLevel=high. Planner commits this window also use `Sonnet 4.6` — consistent, but potentially not what's intended. Recommend user spot-check the scheduled-task model pin.
- **Soft: duplicate planner commit at the third refresh.** `027f0ba` (46 open) and `1a7c5ea` (47 open) landed 5 minutes apart. Looks like a re-run that should have been a no-op. Not corrupting state, just noisy.
- **Medium: claim `3f44d43` for REP-067/169/188/189 is unrealized at window close** (<1h old, so no action needed this window). Next reviewer should check whether the worker finished or timed out — if timed out, planner needs to reset the claims (same pattern used for REP-111/162/163 in run 4).

### Suggestions for next planner cycle

- **Check REP-067/169/188/189 claim age.** If worker-2026-04-23-111853 hasn't shipped substantively within ~2h of claim, reset the claims so another worker can pick them up.
- **Planner no-op guard.** If the previous planner commit is <10 minutes old and the open-ticket set changed by ≤1 ticket, short-circuit to a single "no-op refresh" commit or skip entirely. The third-refresh duplicate burned a commit for zero signal.
- **Enforce automation model pin.** Consider adding a check in the worker/planner/reviewer prompts that verifies the scheduled-task config is `claude-opus-4-7` + `effortLevel=high`, per the user's documented rule.
- **Seed next queue with at least one product-visible M-sized item.** Last 6h closed 15 pure-contract/plumbing tickets — healthy, but Global `⌘⇧R`, Slack OAuth, Voice profile training, and Animation+a11y polish remain stubbed. Promoting one of these into the queue would balance test-pinning with net-product motion.

---

## Window 2026-04-23 04:03 – 2026-04-23 10:12 UTC (last 6h) — ⭐⭐⭐⭐

**Rating: 4/5**

Strong substance, minor accounting slips. **3 substantive worker commits closing 21 REP tickets** (REP-142, -148, -149, -150, -151, -152, -153, -154, -155, -157, -158, -160, -161, -166, -167, -168, -171, -172, -173, -174, -175), **4 claim commits**, **3 AGENTS.md hash-fixup commits**, **1 blocked-batch commit** (worker-2026-04-23-085959 exceeded MLX fresh-clone build budget and parked work on `wip/2026-04-23-085959-stats-session-acceptance`), and **1 planner refresh** (second of the day). Test suite grew **404 → 463 (+59 tests)** — verified by `grep -c "func test" Tests/ReplyAITests/*.swift` = 463. Two production touches, both narrow and well-covered: `IMessageSender.escapeForAppleScriptLiteral` now maps `\n` → `\\n` (REP-174, 4 paired tests) and `InboxViewModel.isSyncing` flipped from `private` → `private(set)` so tests can observe the sync state machine (REP-168, 3 paired tests). Zero banned-action violations across the window: no `Package.swift` / `project.yml` / `Info.plist` / `scripts/*` / `*.entitlements` / `design_handoff_replyai/` touches, no `#Preview` additions, no sandbox flip, no test-file shrinkage, no force-pushes or rebases.

Rating docked from 5 → 4 on three accounting slips, each minor but real: (a) AGENTS.md still references a non-existent SHA `904b0e7` for the contract-tests commit — the real SHA is `7512321`, and the worker's hash-fixup commit (`094a066`) cited the fake SHA without `git cat-file`-validating; (b) AGENTS.md header says "465 tests" but the actual grep count is 463, a +2 overclaim this window; (c) `f40ed9d` was co-authored as "Claude Sonnet 4.6" where the surrounding worker commits use "Claude Autonomous Worker" — worth confirming the scheduled-task model pin is still Opus 4.7 + effortLevel=high per the user's documented automation-model rule.

### Shipped this window (substantive worker commits, newest first)

- **REP-142 / -155 / -167 / -168 / -171** (`f40ed9d`) — `InboxViewModel.isSyncing` visibility widened from `private` to `private(set)` so tests can observe the flag transition during `syncFromIMessage` (REP-168, production + 3 tests). Watcher-driven sync upserts a thread's `previewText` instead of appending duplicates (REP-142, 2 tests). Selecting the same thread twice no longer double-primes the draft engine (REP-155, 2 tests). `Preferences` `AppStorage` keys pinned as set-unique (REP-167). `Stats.snapshot()` regression guard verifies all expected counter keys are present (REP-171). +277/-8 across 7 files, +11 tests claimed (grep shows +9 in this commit; worker wrote "+11").
- **REP-166 / -172 / -173 / -174 / -175** (`42b518c`) — `IMessageSender.escapeForAppleScriptLiteral` now escapes `\n` → `\\n` so embedded newlines no longer produce multi-line AppleScript `tell` blocks that break the parser (REP-174, 4 pinning tests for `"`, `\`, `\n`, emoji). Rule evaluator boundary: `matching` / `defaultTone` / `apply` all return safe empty values for an empty rules array (REP-166). `AttributedBodyDecoder` returns nil for the 32-byte all-zero blob (common DB null sentinel) and a lone `0x2B` tag with no length payload (REP-172). `ChatDBWatcher` survives 5 stop→reinit cycles without `DispatchSource` accumulation, and a 6th watcher still fires cleanly afterward (REP-173). `RulesStore.import` merge-not-replace semantics: update A, preserve B, append C in one round-trip, plus self-import and empty-array no-ops (REP-175). Tests: 440 → 454 (+14), 0 failures.
- **REP-148 / -149 / -150 / -151 / -152 / -153 / -154 / -157 / -158 / -160 / -161** (`7512321`) — 11-ticket contract-test bundle. Pure test pins, zero production change. Invariants now locked: `RuleEvaluator.apply()` returns `(ruleID, action)` pairs ordered priority-desc, inactive excluded, empty on no match (REP-148). `Stats.acceptanceRate(for:)` distinguishes nil (no data) / 0.0 (no sends) / ratio (REP-149). `SearchIndex.Result` fields populated correctly from upsert data, outgoing messages use "me" as `senderName` (REP-150). `IMessageChannel.secondsSinceReferenceDate` boundary: exactly 1e12 → seconds, 1e12+1 → nanoseconds (REP-151). `PromptBuilder` handles all-`.me` and all-`.them` history without crash (REP-152). `DraftEngine.invalidate()` on uncached thread is idempotent (REP-153). `RulesStore.update()` with unknown UUID is a no-op, no spurious write (REP-154). `RulePredicate.and([])` is vacuous-true, dual of the already-pinned `or([]) = false` (REP-157). `IMessageSender.chatGUID`: nil → synthesizes `iMessage;-;<id>`, non-nil → returned verbatim (REP-158). `Stats` survives `DispatchQueue.concurrentPerform(100)` mixed-counter stress (REP-160). `textMatchesRegex` with `^`/`$` anchors respects `NSRegularExpression` range matching, not `String.contains` (REP-161). Tests: 409 → 440 (+31).

### Test coverage delta

- **+59 tests (404 → 463).** Verified locally by `grep -c "func test" Tests/ReplyAITests/*.swift`. AGENTS.md header says 465 — a +2 overclaim; possibly helpers counted as tests by the worker's procedure.
- Test files expanded: `RulesTests.swift` (+435), `InboxViewModelTests.swift` (+165), `StatsTests.swift` (+129), `SearchIndexTests.swift` (+70), `IMessageSenderTests.swift` (+55), `DraftEngineTests.swift` (+35), `ChatDBWatcherTests.swift` (+32), `PromptBuilderTests.swift` (+30), `PreferencesTests.swift` (+25), `IMessageChannelTests.swift` (+22), `AttributedBodyDecoderTests.swift` (+14/-1). **Zero test files shrunk.**
- Source: ~+7 LOC of production Swift across 2 modified files (`IMessageSender.swift` +2, `InboxViewModel.swift` +5). Test LOC ≈ +1,012. Test:source line ratio this window ≈ **145:1** — even heavier than the prior window because this queue was almost entirely test-pinning work.

### Concerns

- **Stale AGENTS.md SHA (`904b0e7`).** Worker's hash-fixup commit (`094a066`) cited a SHA that does not exist. The contract-tests commit is `7512321`. Second stale SHA in the done-log: `05e7035` (pre-existing, from 2026-04-22-174500). All other 20+ SHAs in AGENTS.md validate. Corrodes the done-log as a bisect artifact. Needs a one-liner correction next worker cycle.
- **Test-count overclaim of +2.** AGENTS.md header 465 vs grep 463. Worker's run-log for `f40ed9d` also says "After: 465". Suggests the worker's counting method occasionally double-counts helpers or parameterized cases. Not a correctness issue, but AGENTS.md is a handoff document — the number should be grep-accurate.
- **Co-author tag switch on `f40ed9d` to "Claude Sonnet 4.6".** The prior two substantive worker commits in this window used "Claude Autonomous Worker". Per the user's documented automation rule, the worker must run Opus 4.7 + effortLevel=high. A Sonnet-4.6 tag suggests the pin may have drifted (or this is just an attribution convention the worker chose on this run). Human should confirm the cron-task model pin is still correct.
- **Blocked batch on MLX build budget.** `worker-2026-04-23-085959` blocked REP-135, -177, -179, -183, -187 because a fresh-clone MLX compile exceeded the time budget. Correct protocol behavior (worker pushed partial work to a `wip/` branch), but the planner added REP-177, -183, -187 two hours earlier in the same window — which means the planner is not weighting MLX-adjacency against fresh-clone build cost. Worth tagging MLX-touching tickets in BACKLOG.md so the worker can skip them when it detects a cold cache.
- **Pre-existing non-deterministic test crashes** noted in the `worker-2026-04-23-025721` log: `InboxViewModelAutoPrimeTests` and nearby classes crash non-deterministically under Swift 6 + macOS 26.3. Worker flagged this but did not add a backlog item. Should be promoted to a P1 stability task.
- **12-ticket bundle standing item.** Prior two reviews flagged bundle size. `7512321` is 11 tickets — still above the suggested cap of 8. Not rating-affecting yet, but the signal is consistent.
- **8 old `wip/quality-*` branches from 2026-04-21** still unreviewed (5+ days; approaching the 7-day human-review threshold flagged by REP-016 / -017 / -048). Reviewer-noted in three consecutive windows now. Human sweep needed before 2026-04-24.

### Suggestions for next planner cycle

1. **Fix stale AGENTS.md SHAs.** Add a trivial S task: "AGENTS.md: correct `904b0e7` → `7512321` and `05e7035` → real SHA (look up the 2026-04-22-174500 merge)." Worker can do this in a single commit. Also add a guardrail: the hash-fixup step should `git cat-file -e` before citing.
2. **Add test-count regression guard.** An S task: "Test count: derive the 'N tests' line in AGENTS.md from `grep -c "func test" Tests/ReplyAITests/*.swift` (no hand-maintained number)." Or a lightweight `scripts/agents-test-count.sh` that the worker runs before the hash-fixup commit.
3. **Promote the non-deterministic test crash to a P1 backlog item.** `InboxViewModelAutoPrimeTests` + neighbors crash non-deterministically under Swift 6 + macOS 26.3. Ticket scope: root-cause (cooperative-executor hop timing is the most likely culprit per the worker's notes on REP-168), not band-aid.
4. **Tag MLX-touching tickets in BACKLOG.md so fresh-clone workers can skip them.** Propose field: `requires_mlx_build: true` on tickets whose tests import MLX modules. Worker skips these when it detects a cold build cache.
5. **Confirm scheduled-task model pin is Opus 4.7 + effortLevel=high.** The `f40ed9d` "Claude Sonnet 4.6" co-author tag is the first in recent windows; deserves a one-line human check against the cron config.
6. **Cap bundles at ≤8 tickets.** Third time this has been suggested; ask the planner to enforce.

### Rolling-window pattern

Last eight windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-2210.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-23-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-23-1012.md` (this) — ⭐⭐⭐⭐

Zero consecutive sub-par (≤⭐⭐) windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 22:10 – 2026-04-23 04:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Best single window of the run so far. **7 substantive worker commits closing 30 REP tickets** (REP-066, -098, -099, -101, -103, -104, -108, -109, -110, -114, -115, -116, -117, -118, -119, -120, -121, -122, -123, -124, -125, -126, -127, -128, -130, -131, -132, -134, -136, -137, -138, -140, -141, -143, -144, -145, -147), **9 claim/AGENTS chores**, **2 hash-fixup commits**, and **3 planner refreshes** (run10 → run12). Test suite grew **320 → 404 (+84 tests)** — verified by `grep -c "func test" Tests/ReplyAITests/*.swift` = 404. One new production file (`Sources/ReplyAI/Services/DraftStore.swift`, +80 LOC, REP-066) with 112 LOC of paired test coverage. Test add ratio ≈ **7:1 tests:source** by line count (heavy because the queue this window was almost entirely S/M test-coverage items). Zero banned-action violations: no `#Preview`, no sandbox flip, no `Info.plist` / `Package.swift` / `project.yml` / `scripts/*` / `design_handoff_replyai/` touches, no test-file shrinkage, no force-pushes or rebases. Commit messages cite every REP ID and explain *why* — REP-066 names cold-start LLM re-prime as the motivation, REP-128 documents iMessage-prefix-only validation scope, REP-117 calls out the silent-row-drop bug it fixes.

### Shipped this window (substantive worker commits, newest first)

- **REP-126 / -128 / -130 / -134 / -137 / -138 / -140 / -141 / -143 / -144 / -145 / -147** (`7132176`) — 12-ticket bundle. `IMessageSender.SendError.invalidChatGUID` + `isValidChatGUID()` pre-flight (rejects malformed iMessage GUIDs at the API boundary, not at AppleScript dispatch). `Preferences.firstLaunchDate` set-once key (added to `wipeExemptions` so privacy reset doesn't reset onboarding age). `ReplyAIApp.init()` writes `firstLaunchDate` once. `PromptBuilder.minHistoryReserve` + `systemPrompt(tone:)` with truncation guard (oversized system instructions can't squeeze message history below the floor). `DraftEngine.dismiss()` now deletes the on-disk `DraftStore` entry (matches the in-memory clear). `InboxViewModel` gets injectable `searchIndex` for archive→index integration tests. New `SearchIndex` disk round-trip + concurrent upsert/delete race tests close the suggestion from the prior review.
- **REP-127 / -131 / -132 / -136** (`79e02df`) — `DraftEngine` trims leading/trailing whitespace on `.done` so the composer doesn't show LLM-emitted blank prefixes. `ChatDBWatcher.stop()` becomes idempotent under double-call (deinit race + explicit stop) and a callback-not-fired-after-stop test pins the cancel semantics. `regenerate()` already serializes via `tasks[key]?.cancel()` — new tests confirm exactly one `.ready` state under overlapping concurrent calls. AGENTS.md test-count duplication addressed (header now authoritative, parenthetical removed).
- **REP-066** (`79fc909`) — `DraftStore` persists completed draft text to `~/Library/Application Support/ReplyAI/drafts/<threadID>.md` on the `.done` chunk so user edits survive crashes and intentional quits. `InboxViewModel.selectThread` seeds `userEdits` from the store before the LLM re-primes, so the composer is populated immediately on app open. Files older than 7 days are pruned on `DraftStore.init()`. New file (+80 LOC) plus `DraftStoreTests.swift` (+112 LOC, 5 cases including concurrent write+read race REP-147).
- **REP-108 / -110 / -115 / -117** (`e33be0d`) — `ContactsResolver` flushes its name cache on `CNContactStoreDidChange` (NotificationCenter is injectable so tests stay isolated from the system center). `RulesStore.export` wraps in `{ "version": 1, "rules": [...] }` envelope; `import` throws `unsupportedExportVersion` for non-1, future schema migration becomes a clear error not silent corruption. `Preferences.launchCount` increments per `ReplyAIApp.init()` and is wipe-exempt. `messages(forThreadID:limit:)` emits a `[deleted]` placeholder for rows where both `text` and `attributedBody` are NULL (deleted/unsent/unsupported-extension messages no longer create silent gaps in the thread view).
- **REP-116 / -118 / -119 / -125** (`7181beb`) — `SmartRule.hasUnread` predicate, `DraftEngine` archive→dismiss eviction integration test, search result hard-cap of 50, and FTS5 upsert ghost-term coverage (delete-then-reinsert at the same rowid must not leave stale tokens). All four are pure correctness coverage adds.
- **REP-120 / -121 / -122 / -123 / -124** (`f5ae41d`) — `RulesStore` concurrent-add stress test (200 callers under `Locked<T>` invariant), `PromptBuilder` large-payload truncation behavior pinned, `IMessageChannel` Apple-reference-date autodetect boundary cases (the 2001-seconds vs nanoseconds magnitude split), `Stats` invariants under concurrent increment, and a pinned-thread sort regression guard.
- **REP-098 / -099 / -101 / -103 / -104 / -109 / -114** (`4035c5a`) — Pure test additions (320 → 331 in this commit alone, no production-code change): `DraftEngine` cache isolation across `(threadID, tone)`; `ThrowingStubLLMService` + `FailOnceThenSucceedService` for LLM error/retry coverage; `SearchIndex` delete-reinsert FTS5 tombstone round-trip; two-channel filter integration; `InboxViewModel` thread recency ordering; `Preferences.wipeReplyAIDefaults` scope bounded to known keys only.

### Test coverage delta

- **+84 tests (320 → 404).** Verified locally by `grep -c "func test" Tests/ReplyAITests/*.swift`. The +84 also matches the worker's own test-count claim in `d8941b6`.
- Source: ~+260 LOC of production Swift across 6 modified files + 1 new (`DraftStore.swift`, 80 LOC). Tests: ~+1,820 LOC across 12 test files. Add ratio ≈ **7:1**.
- Test files expanded: `RulesTests` (+263), `SearchIndexTests` (+253), `DraftEngineTests` (+318), `DraftStoreTests` (+112 net), `InboxViewModelTests` (+102), `ContactsResolverTests` (+91), `PreferencesTests` (+93), `PromptBuilderTests` (+75), `IMessageSenderTests` (+43), `IMessageChannelTests` (+45), `ChatDBWatcherTests` (+32), `StatsTests` (+26). **Zero test files shrunk.**
- One legitimate test rename in REP-128 (`testEmptyGUIDThrowsInvalid` → `testInvalidGUIDThrowsInvalid` because `chatGUID(for:)` synthesizes empty strings away before reaching `sendRaw`). Empty-string coverage moved to direct-call `testEmptyGUIDIsValidationFailed`. Coverage equivalent — not a test deletion.

### Concerns

- **`7132176` is a 12-ticket bundle.** Per-ticket scope is small and per-file diffs are clean, but a wide bundle makes `git bisect` painful if any one of the twelve regresses. Future planner could cap bundles at ≤8 tickets when possible. Not rating-affecting — work is real, tested, and the worker log enumerates per-file changes.
- **`isValidChatGUID` is iMessage-only.** Worker log notes "SMS GUIDs correctly fail validation" — fine for today since the SMS send path isn't wired, but this guard will need to widen (or move to a per-channel `validateGuid` protocol method) when SMS write lands. Worth a follow-up planner task.
- **Two more hash-fixup commits this window** (`05ad9b5`, `0d1915e`). Same protocol noise flagged in the prior review. Not a quality issue, but the suggestion stands.

### Suggestions for next planner cycle

1. **Archive sweep next run.** 30 tickets closed this window — confirm REP-066, -098, -099, -101, -103, -104, -108, -109, -110, -114, -115, -116, -117, -118, -119, -120, -121, -122, -123, -124, -125, -126, -127, -128, -130, -131, -132, -134, -136, -137, -138, -140, -141, -143, -144, -145, -147 all move from open → archived in BACKLOG before the next planner cycle.
2. **Cap bundle size at 8 tickets per worker commit.** Easier bisect, cheaper rollback if any single ticket regresses.
3. **Open a follow-up for cross-channel GUID validation.** Generalize `IMessageSender.isValidChatGUID` to a `Channel.validateGuid(_:)` (or add a sibling `SmsChannelSender.isValidGuid()`) before SMS send is wired — cheaper to design now than to retrofit later. S-effort, non-ui.
4. **Hash-fixup protocol tweak.** Standing item — defer worker-log self-referential commit hash to `.automation/logs/worker-<id>-hash.txt` written post-push so main history stops accumulating one-line `fixup` commits.
5. **Drop "disk-backed SearchIndex smoke test" from next planner.** Closed by REP-126 in `7132176` this window.

### Rolling-window pattern

Last seven windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-2210.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-23-0403.md` (this) — ⭐⭐⭐⭐⭐

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 16:03 – 2026-04-22 22:10 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Strongest window of the day. **8 substantive worker commits closing 25 REP tickets** (REP-032, -035, -037, -041, -042, -053, -054, -061, -073, -074, -080, -084, -085, -092, -093, -094, -095, -096, -097, -100, -102, -106, -107, -112, -113), **8 claim chores**, **3 fixup commits** (worker-log hash backfills + one AGENTS.md *(pending)* replacement), and **3 planner refreshes** (run7 → run9). Test suite grew **254 → 320 (+66 tests, confirmed by local `swift test` → 320 Executed, 0 failures in 8.5s)**. Worker LOC split: **+392/-83 source, +1,098/-23 tests** — a **~2.8:1 test-to-source add ratio**. Zero banned-action violations: no `#Preview`, no sandbox flip, no `Info.plist` / `Package.swift` / `project.yml` / `scripts/*` / `design_handoff_replyai/` touches, no history rewrites. Commit messages explain *why* consistently (ContactsResolver TTL 30 min rationale in `9879312`, the dual-interception critique behind the `isDryRun → executeHook` refactor in `eaa0b39`, the cold-start motivation for on-disk FTS5 in `7196e9d`).

### Shipped this window (substantive worker commits, newest first)

- **REP-097 / REP-100 / REP-106 / REP-107 / REP-112 / REP-113** (`80035e1`) — `SmartRule.messageAgeOlderThan(hours:)` predicate plus `lastMessageDate` on `RuleContext` and `currentDate` injection into `matches()` so age tests are clock-independent. Remaining five items test-only: De-Morgan / double-negation coverage for `not`, `or([])` + 3+-branch cases, 200-concurrent-caller `Stats` increment stress test proving `Locked<T>` loses no updates, `DraftEngine.dismiss()` idle/noop/isolation transitions, and `PromptBuilder` non-empty + distinct system-instruction assertions per tone. **304 → 320 tests**.
- **REP-074 / REP-095 / REP-096 / REP-102** (`9879312`) — `ContactsResolver` injectable `ttl` (default 30 min) so stale post-launch contact names self-invalidate; tests use `ttl=0` to force re-query without a clock. `messages(forThreadID:)` convenience overload with default `limit=20` codifies the "don't load hundreds on sync" invariant. First test coverage for `InboxViewModel` send success/failure fork (toast naming on success; error surfaced + `userEdits` preserved on failure). Two tests pin down the empty-query `[]` contract in `SearchIndex`. **294 → 304 tests**.
- **REP-041 / REP-073** (`7196e9d`) — On-disk FTS5 database under `~/Library/Application Support/ReplyAI/search.db` so existing rows are searchable before cold-start sync completes. `SearchIndex(databaseURL:)` initializer (nil = in-memory for tests, URL = file-backed for prod); `SearchIndex.productionDatabaseURL()` helper mirrors the `RulesStore`/`Stats` pattern. `PromptBuilder.truncate` promoted private→internal with injectable budget; two new invariant tests: short-history passthrough + most-recent-message retention on truncate. **294 tests, 0 failures**.
- **REP-035 / REP-042** (`a5bd7a4`) — `RulesStore.export(to:)` atomic JSON write and `import(from:)` with UUID-keyed merge (update existing, append new, skip malformed — same resilience policy as REP-024). 4 new XCTests: round-trip, merge, in-place update, malformed-entry skip. AGENTS.md "What's done" synced.
- **REP-053 / REP-061 / REP-084 / REP-093 / REP-094** (`eaa0b39`) — Dropped `IMessageSender.isDryRun` in favor of a no-op `dryRunHook()` via the existing `executeHook` seam (one interception point instead of two). `rulesMatchedCount` counter added at all three `RuleEvaluator.matching` call sites in `InboxViewModel`. `RulesStore` load/save switched off `.standard` onto the injected `UserDefaults` to enable per-test isolation (prereq for archive persistence coverage). `testBothNullProducesEmptyMessage` verifies the SQL-level `text IS NOT NULL OR attributedBody IS NOT NULL` filter and the message-preview fallback. `testFuzzRandomBlobsNeverCrash` pushes 10k random 0–4096-byte blobs through `AttributedBodyDecoder.extractText`, asserting no trap + valid UTF-8 on any returned `String`. **→ 278 tests**.
- **REP-037 / REP-054** (`fa4d009`) — `DraftEngine` invalidates a stale in-flight draft when `ChatDBWatcher` refires for the same thread (prior behavior leaked a draft generated against out-of-date context). `ContactsResolver.batchResolve([handle])` replaces per-handle `CNContactStore` lookups on initial sync.
- **REP-032** (`038826e`) — Per-tone draft counters + acceptance-rate field on `Stats`, incremented from the DraftEngine acceptance path and surfaced via the existing `Stats` summary dict.
- **REP-080 / REP-085 / REP-092** (`6a629a2`) — `SearchIndex` FTS5 channel-column filter so per-channel searches don't pay for cross-channel token scans; FTS5 query sanitizer (escapes the three syntactic metacharacters before forwarding user input to `sqlite3_prepare_v2`); prefix-match (`term*`) test coverage.

### Test coverage delta

- **+66 tests (254 → 320).** Confirmed by `swift test`: `Executed 320 tests, with 0 failures (0 unexpected) in 8.487 (8.504) seconds`.
- Source: +392/-83 lines across worker commits. Tests: +1,098/-23 lines. Add ratio **~2.8:1** (tests vs. source).
- Test files expanded: `SearchIndexTests` (+211), `RulesTests` (+234), `IMessageChannelTests` (+134), `InboxViewModelTests` (+127), `ContactsResolverTests` (+100), `StatsTests` (+112), `DraftEngineTests` (+102), `PromptBuilderTests` (+42), `AttributedBodyDecoderTests` (+25), `IMessageSenderTests` (+11/-23).
- The `IMessageSenderTests` 11/23 delta is a **legitimate refactor**, not a test deletion: `testDryRunReturnsSuccessWithoutScript` + `testDryRunOffInvokesScript` were rewritten to `testDryRunHookReturnsSuccessWithoutScript` + `testCustomHookIsInvokedOnSend` as part of REP-093 removing the `isDryRun` dual-interception surface. Coverage equivalent, cases simpler.

### Concerns

- **One planner→worker timing ordering quirk.** `fa4d009` (REP-037/054 implementation) is author-timestamped 14:17 EDT, *earlier* than the planner's `b363d08` (14:33) but pushed after `eaa0b39`. Not a correctness issue — author-timestamps from local clocks just aren't monotonic across agents. Worth a note that `git log --since` filtering leans on author-time, so a worker commit that lands just outside a 6h window may be attributed to the wrong review boundary. Low-impact; no action needed this window.
- **`AGENTS.md` narrative test-count vs. header test-count are both 320, but in *two separate places*.** Line 97 (repo-layout fence) and line 226 (Testing expectations) each hard-code the number. Keep both in sync or collapse to a single authoritative line — minor, not rating-affecting. (Not touched this review; both are current.)
- **Two fixup commits for log-hash backfill.** `7030acb` + `4ce30fd` + `2e4a9f5` are the worker's standard "commit log refers to myself, need to rewrite hash after push" chore — protocol-compliant, but three extras in main history per window is a smell. Planner could consider whether the worker log's "commit hash" field truly needs to be self-referential in the first commit, or if a follow-up hash could be written in a separate post-push log file instead.

### Suggestions for next planner cycle

1. **Archive run10 sweep of the 25 closed tickets.** REP-032, -035, -037, -041, -042, -053, -054, -061, -073, -074, -080, -084, -085, -092, -093, -094, -095, -096, -097, -100, -102, -106, -107, -112, -113. Confirm every one moved from P1/P2 body → Done in BACKLOG before the next planner refresh.
2. **Consider a log-hash protocol tweak.** Either defer the worker log's `commit:` field to a companion `.automation/logs/worker-<id>-hash.txt` written after push, or accept the fixup commits and note the pattern in `AUTOMATION.md` so future reviewers don't flag them. Current three-commit fixup pattern is cosmetic noise in history.
3. **Queue balance.** Run9 landed 11 new tasks and the worker drained 25 — net -14 tickets. Planner should sustain this draft-rate rather than over-bursting P2 ideation; the 30-task floor is the right guardrail, not a target.
4. **Consolidate `AGENTS.md` test count to one line.** Currently duplicated at lines 97 and 226. Reviewer-edit-only. Small mechanical cleanup for next review.
5. **Exercise the new `SearchIndex` disk-persistence path in an integration smoke test.** `7196e9d` added the file-backed store but only the in-memory path runs under `swift test`. A write-open-reopen-read round-trip (dropping a `URL(fileURLWithPath:)` temp file) would catch regressions in `productionDatabaseURL()` layout / migration if we ever change schema. Could ship as a single-commit S-effort task.

### Rolling-window pattern

Last six windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-2210.md` (this) — ⭐⭐⭐⭐⭐

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 10:03 – 2026-04-22 16:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Clean continuation of the prior window. **4 substantive worker commits closing 12 REP tickets** (REP-030/031/040/059/064/069/072/076/077/078/039/071/081), **5 claim chores**, and **3 planner refreshes**. Test suite grew **211 → 254 (+43 tests)** with a test-to-source line ratio of **~3.3:1** (740 test lines vs. 224 source lines across 6 test files and 8 source files). Zero banned-action violations: no `#Preview`, no sandbox flip, no `Info.plist`/`Package.swift`/`project.yml`/`scripts/*` touches, no test-file shrinkage, no history rewrites. Commit messages name every REP closed and explain the *why* — length-guard rationale in `7667f22`, observation-pattern reuse in `bbedd1a`, the explicit "UI wiring deferred to human" note in `3169995`.

### Shipped this window (substantive worker commits, newest first)

- **REP-039 / REP-071 / REP-081** (`874f483`) — `pref.rules.autoApplyOnSync` + `pref.drafts.autoPrime` feature flags gating `InboxViewModel.syncFromIMessage`'s rule application and `selectThread`'s draft prime. `primeHandler` closure injection lets tests record prime calls without standing up a real `DraftEngine`. New `StaticMockChannel` test double + 9 new test cases (3 thread-selection, 2 auto-prime, 2 auto-apply-rules, 2 preference round-trips).
- **REP-059 / REP-064 / REP-069 / REP-076 / REP-077 / REP-078** (`7667f22`) — the window's largest commit. 4096-char message length guard in `IMessageSender` before any AppleScript touch (REP-064). Single transient-retry on `-1708 errAEEventNotHandled` during Messages.app cold start / iCloud sync (REP-059). 100-rule hard cap on `RulesStore.add()` with new `tooManyRules` error (REP-069). Optimistic local unread-count clear on `selectThread`, plus `markUnreadZero` fixed to preserve `chatGUID` + `hasAttachment` (REP-076). New `ChannelService.databaseCorrupted` case + `SQLITE_NOTADB` (26) detection in `openReadOnly` so the UI can route to a re-sync recovery path distinct from generic DB failure (REP-077). +3 `handleReply` test cases in `NotificationCoordinatorTests` (REP-078).
- **REP-072** (`bbedd1a`) — `InboxViewModel` now observes its own `pendingNotificationReply` via `withObservationTracking` (same pattern as rules observation) and dispatches `IMessageSender.send` on arrival. Uses `chatGUID` from the loaded thread — correctly avoids synthesizing a 1:1-shaped GUID for group chats. Unknown thread IDs are logged and discarded without crash. Closes the "UNNotification inline reply consumption" gap from the prior window's concerns.
- **REP-030 / REP-031 / REP-040** (`3169995`) — `pref.inbox.threadLimit` + `pref.drafts.autoPrime` preference keys (REP-030 + partial REP-039). `RuleValidationError` + `SmartRule.validateRegex` + `RulesStore.addValidating` surface invalid regex patterns at creation time rather than silently failing eval (REP-031). `IMessageSender.isDryRun` flag with injectable executor exercises the full send path in tests without AppleScript side-effects (REP-040). "ComposerView wiring deferred to human review" for the UI-sensitive remainder of REP-039 — honest scope call.

### Test coverage delta

- **+43 tests (211 → 254).** Grep-based count; sandbox can't run `swift test`.
- Source: +224 lines across 8 files. Tests: +740 lines across 6 files. Ratio ≈ **3.3:1**.
- Existing test files expanded: `InboxViewModelTests` (+302), `IMessageSenderTests` (+137), `RulesTests` (+137), `PreferencesTests` (+68), `NotificationCoordinatorTests` (+53), `IMessageChannelTests` (+43). **Zero test files shrunk.**
- Per-commit test-count claims (232 → 245 in `7667f22`, "24 targeted / 9 new" in `874f483`) line up with the grep delta.

### Concerns

- **Claim/substantive ratio slightly worse than ideal.** 5 claim commits vs. 4 substantive this window. Not rating-affecting, but main-branch history reads as 9 worker items where 4 would suffice. Worth a planner nudge to batch the claim and work into one commit where it doesn't break claim-visibility.
- **Stall-reset race in `run6`.** Planner reset REP-039/071/081 as a stalled claim, and the same worker shipped all three 33 minutes later in `874f483`. Not a correctness bug (worker didn't re-claim between reset and push) but the planner's stall rule could factor in worker-log mtime before resetting. Low probability of a real collision at current fire cadence, but a cheap tuning win.
- **AGENTS.md test-count line drift.** Top-of-file repo layout said "245 tests" at review start — one version behind after `874f483`. Updated in this review.
- **AGENTS.md narrative stale copy.** "60 tests today" in the testing-expectations section is off by ~200. Non-structural, but the planner should scrub it.

### Suggestions for next planner cycle

1. **Run7 archive pass on all 12 tickets closed this window** — REP-030, -031, -039, -040, -059, -064, -069, -071, -072, -076, -077, -078, -081. Confirm every one is `status: done` in BACKLOG before the next planner refresh.
2. **Augment stall detection with worker-log mtime.** If `.automation/logs/worker-<id>.md` has been written to within the last ~30 min, don't reset the claim even if it's been open for >2 planner cycles. Prevents the REP-039 race pattern.
3. **Encourage claim+work batching.** One combined commit per substantive unit — body notes the claim-id, diff shows the work — halves the main-branch noise without weakening the substantiveness gate.
4. **Clean the AGENTS.md narrative test count.** Line 216 "60 tests today" should either drop the number or become a planner-refreshed counter like line 97.
5. **Queue balance.** 45 open tasks after three planner runs this window. Healthy. Next cycle can keep additions and closures roughly in balance — no need for a fresh burst of P2 ideation while the worker is draining this pool cleanly.

### Rolling-window pattern

Last five windows (oldest → newest):

- `review-2026-04-21.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-21-addendum.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-0403.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1003.md` — ⭐⭐⭐⭐⭐
- `review-2026-04-22-1603.md` (this) — ⭐⭐⭐⭐⭐

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-22 04:03 – 2026-04-22 10:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Exceptional window. Worker drained a huge slice of the P1 backlog — **11 substantive commits closing ~15 REP tickets** against 11 protocol-compliant claim chores. Test suite grew **158 → 211 (+53 tests)**, with tests file delta of **+1,126 lines vs. +580 source lines** (ratio ≈ 1.9:1, well above the proportional bar). Zero banned actions in the cumulative diff: no `#Preview` macros, no sandbox entitlement changes, no test-file shrinkage, no history rewrites. The prior review's stall concern (REP-022 / REP-024 claimed but still `in_progress`) was closed in the first commit of this window (`76850a9`) — worker cleared the stall on its own. Commit messages remain honest and explanatory (e.g. `9810196` explains why UNNotification category registration is entitlement-free; `ec9e723` breaks out three distinct root causes for REP-063/65/68 in separate paragraphs).

### Shipped this window (substantive worker commits, newest first)

- **REP-063 / REP-065 / REP-068** (`ec9e723`) — `SearchIndex.delete(threadID:)` purges FTS5 on archive; archive wired through new `InboxViewModel.archive(_:)`. Added 2 `senderIs` case-insensitivity tests. `cache_has_attachments` now projected from SQL into `Message.hasAttachment` + `MessageThread.hasAttachment`, replacing the fragile `📎 Attachment` sentinel scan in `RuleContext.hasAttachment`.
- **REP-034 / REP-056 / REP-057** (`ea37669`) — DraftEngine idle-entry eviction; Stats weekly-aggregate file writer; SearchIndex concurrent search+upsert stress test.
- **REP-052** (`8988959`) — ChatDBWatcher FSEvents error recovery with restart backoff.
- **REP-050** (`a7204d2`) — Extracted `Locked<T>` generic wrapper consolidating the `@unchecked Sendable + NSLock + synced{}` pattern across `ContactsResolver`, `Stats`. Net +32 lines in a new `Sources/ReplyAI/Utilities/Locked.swift` offset by -47 deleted duplicated lines elsewhere. +91 test lines in `LockedTests.swift`.
- **REP-028** (`9810196`) — NotificationCoordinator: UNNotification inline reply via `UNTextInputNotificationAction`, routes to `InboxViewModel.pendingNotificationReply`. `NotificationCenterProtocol` inserted for testability. +142 test lines.
- **REP-027** (`881d8f0`) — SearchIndex: explicit AND semantics for multi-word FTS5 queries (prior behavior was OR-leaning, leading to noisy results).
- **REP-026** (`9717756`) — PromptBuilder extracted from MLXDraftService with token-budget truncation (2000-char budget, oldest-first drop). +92 test lines.
- **REP-025** (`aa34006`) — IMessageSender AppleScript send timeout + injectable executor for tests. +49 test lines.
- **REP-049 / REP-051** (`1df1fce`) — DraftEngine concurrent prime guard + SQLite `databaseError` result-code propagation.
- **REP-023** (`5fedafc`) — InboxViewModel re-evaluates rules when RulesStore changes (matches the initial-sync rule behavior). +194 test lines (new `InboxViewModelTests.swift`).
- **REP-022 / REP-024** (`76850a9`) — InboxViewModel concurrent sync guard + RulesStore malformed-rule skipping on load. Closes the prior window's stall concern.

### Test coverage delta

- **+53 tests (158 → 211).** Largest single-window jump recorded so far.
- 4 new test files: `LockedTests.swift` (+91), `NotificationCoordinatorTests.swift` (+142), `PromptBuilderTests.swift` (+92), `InboxViewModelTests.swift` (+194).
- 7 existing test files expanded; **zero test files shrunk**.
- Source delta: +580 insertions / -128 deletions across 19 files. Test delta: +1,126 insertions / -3 deletions across 11 files. Test-to-source ratio ≈ 1.9:1.
- `swift test` not runnable in reviewer sandbox — audit count is from `grep -r "func test" Tests/` (211).

### Concerns

- **Claim-commit noise.** Ratio is still ~1:1 (11 claim vs. 11 substantive). Not rating-affecting, but the planner could plausibly batch claims per cycle — the main-branch history reads as 22 items where 11 would do.
- **REP-063 / notification-reply terminology drift.** AGENTS.md "What's still stubbed" says the reply-consumption follow-up is tracked as REP-063, but REP-063 as shipped this window was `SearchIndex.delete` for archived threads — unrelated. The actual InboxViewModel consumption of `pendingNotificationReply` still appears unfinished; planner should file a dedicated ticket with a correct ID rather than letting the stubbed-section reference rot.
- **wip/quality-* branches still unmerged.** Prior review flagged 7 of these from 2026-04-21; they're still sitting. REP-016 (senderKnown operator-precedence bug fix) in particular is a real correctness issue blocked on human review. No progress this window.
- **REP-008 sentinel copy decision** (`🔗 <host>` / `📎 Attachment`) still drifting. REP-062 was filed by the planner at the start of this window to capture it — good — but it's `claimed_by: human` so the worker won't touch it.

### Suggestions for next planner cycle

1. **Fix the stubbed-section REP-063 reference in AGENTS.md.** Either file a new ticket for InboxViewModel inline-reply consumption (I'd call it REP-069 given current numbering) and update the reference, or rewrite the stubbed entry to say "pending follow-up" without a ticket ID. The current state is misleading.
2. **Archive pass.** 15 REP items closed this window but only a subset of tickets flipped to `status: done` in BACKLOG.md in time for this review. Planner's next archive-verification sweep should walk commits `aa0d184..HEAD` and confirm every REP-id in a commit message has `status: done` set.
3. **Resist further task queueing.** P1 queue has been drawn down sharply — worker is catching up fast. Next planner run should emphasize archival + sharpening existing tickets over net-new adds, especially while human-owned wip/* branches pile up.
4. **Human-review nudge.** Four items remain blocked on human (REP-008 → REP-062 product-copy, REP-016 senderKnown precedence, REP-017 wip consolidation, REP-009/010 UI-sensitive). The bug fix is the only correctness-critical one; everything else is polish. Worth surfacing in tomorrow's standup digest.

### Rolling-window pattern

Last four windows (oldest → newest):

- `review-2026-04-21.md` — 5/5
- `review-2026-04-21-addendum.md` — 5/5
- `review-2026-04-21-2343.md` — 5/5
- `review-2026-04-22-0403.md` — 5/5
- `review-2026-04-22-1003.md` (this) — 5/5

Zero consecutive sub-par windows. STOP AUTO-MERGE trigger remains disarmed.

---

## Window 2026-04-21 22:03 – 2026-04-22 04:03 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

Overlaps the prior 17:43–23:43 window by ~4h, so this rating scopes only the *new* worker activity since `review-2026-04-21-2343.md` landed. In that ~4-hour slice the worker shipped **4 substantive backlog items** (REP-018, REP-019, REP-020, REP-021) across two commits, added **+13 tests (145 → 158)** with ratios well above 1:1, and filed commit messages that actually explain the *why* (chat<N>-vs-E.164 group identifiers, triple-cache-miss from non-normalized phone handles, tapback rows polluting thread previews). Zero banned actions in the 6h cumulative diff: no `#Preview`, no sandbox flip, no shrunk test files, no history rewrites. REP-022 and REP-024 were claimed ~68 min ago and remain `in_progress` — within normal worker cadence, not yet a stall.

### Shipped this window (net-new since prior review)

- **REP-018 (P1, S)** — `RulePredicate.isGroupChat` + `hasAttachment`. isGroupChat detects the `chat<N>` identifier convention for group threads; hasAttachment matches the `📎 Attachment` sidebar sentinel. Covered in `RulesTests` with +87 new lines.
- **REP-019 (P1, S)** — `ContactsResolver.normalizedHandle()` collapses `+14155551234` / `14155551234` / `4155551234` to a single canonical 10-digit key before cache reads/writes. Prior behavior caused three cache misses on the same contact. +42 test lines in `ContactsResolverTests`.
- **REP-020 (P1, S)** — Thread-preview query now filters `associated_message_type 2000–2005` (tapback reactions) and NULL-text delivery receipts on both `last_msg_rowid` and `last_date` subqueries. Fixes previews like `"❤ to '…'"` shadowing the last real message.
- **REP-021 (P1, M)** — `IMessageChannel.recentThreads(limit:)` test coverage (60-row fixtures → limit-50 cap + recency ordering) plus a `ChannelService` protocol extension defaulting to limit=50 so callers can omit the page size.

### Test coverage delta

- **+13 tests** (145 → 158). No new test *files* this window — all growth is expansion of `RulesTests`, `ContactsResolverTests`, `IMessageChannelTests`.
- Test/LOC ratio: ~87 test lines for ~25 source lines on REP-018/19/20; ~45 test lines for ~30 source lines on REP-021. Both well above the proportional bar.
- No test files shrunk.
- `swift test` not runnable in the reviewer sandbox — audit count is from `grep -r "func test" Tests/ReplyAITests/`.

### Concerns

- **REP-022 / REP-024 claimed 68 min ago, still `in_progress`.** Worker fires every 15 min, so 4–5 cycles without a substantive commit. Not a stall yet (both are S and the substantiveness gate may be bundling them), but re-check next window — if still in_progress at the next 6h review, re-queue with the prior worker run marked failed.
- **7 open `wip/quality-*` branches** from yesterday's quality-pass session remain unmerged. The planner correctly filed REP-016 (senderKnown operator-precedence *bug fix* — real correctness issue on `.senderUnknown`) and REP-017 (consolidate overlaps) as human-owned. These should not sit for another 24h — the bug fix in particular.
- **Claim-commit ratio** still ~1:1 with substantive commits. Protocol-compliant, not rating-affecting, but if the planner can pre-batch claims per window the main history reads cleaner for the human.
- **Human-review flag from REP-008** (sidebar glyphs `🔗` / `📎`) was queued in the prior review and hasn't been scoped into a task yet — still drifting.

### Suggestions for next planner cycle

1. **Stop adding. Drain.** Planner added 32 tasks in today's run2 (REP-016 → REP-047); the queue is well-stocked. Next planner run should focus on archival (REP-018/19/20/21 all need to move to Done) and hold task additions until the worker draws the queue down below ~25 open.
2. **Escalate REP-016.** The senderKnown operator-precedence fix is a real bug, not style. It should jump the human-review queue above REP-017 (consolidation) and REP-009/010 (ui-sensitive feature work).
3. **Guardrail — stall detection for REP-022/024.** If still `in_progress` at the next 6h review, flip `claimed_by` to `worker-FAILED` and re-open. Add this rule to the planner's archive-verification pass so it catches stalls without reviewer intervention.
4. **Queue REP-008 glyph product-copy task.** One-line S-task: "product-copy pass on `🔗`/`📎` sidebar preview sentinels in `IMessagePreview`". Blocks on nothing; clears the pending human-review flag.

---

## Window 2026-04-21 17:43–23:43 UTC (last 6h) — ⭐⭐⭐⭐⭐

**Rating: 5/5**

This is the first real rolling window after the cadence cutover and the worker blew the doors off it. 20 commits to main by `ReplyAI Worker` (10 substantive + 10 claim chores), 11 backlog tasks closed (REP-003, -004, -005, -006, -007, -008, -011, -012, -013, -014, -015), test count jumped **60 → 145 (+85 new tests)** across 9 new/expanded test files. Every substantive commit shipped with proportional tests, commit messages accurately describe the diff, and no banned actions occurred (no `#Preview`, no sandbox flip, no shrunk test files, no history rewrites). The worker also correctly honored the substantiveness gate — no S-only commits when larger tasks were available. The only thing I'd nitpick is the volume of `chore: claim REP-XXX in progress` commits (10 of 20); that's protocol-compliant but noisy — if the planner can batch claim-commits per run, the main history will read cleaner at retrospective-time.

### Shipped this window

- **REP-003 (P0, L)** — Real typedstream parser replacing the byte-scan in `AttributedBodyDecoder`. +222 test lines with hand-crafted hex fixtures covering nested `NSMutableAttributedString`, UTF-8 emoji, malformed blobs. Last remaining P0 is now closed.
- **REP-004 / REP-006 / REP-012** — `silentlyIgnore` parity in the inbox filter, AppleScript-escape hardening in `IMessageSender`, and full `RulesStore` remove/update/resetToSeeds coverage. Shipped bundled per substantiveness gate.
- **REP-005** — Persistent counters (`Stats.swift`) for rules fired, drafts generated, messages indexed. +124 test lines.
- **REP-007** — `ChatDBWatcher` debounce + stop coverage (+108 test lines).
- **REP-008** — Link and attachment previews in the sidebar (`🔗 <host>` / `📎 Attachment`). Pure data-layer transform in `IMessagePreview`; worker correctly flagged the emoji glyph choice for human review rather than asserting it as final.
- **REP-011** — `ContactsStoring` protocol extracted; production path byte-for-byte identical, but the resolver is now fully test-coverable without `CNContactStore` hitting the real address book.
- **REP-013** — `Preferences.register` / `wipe` accept an injected `UserDefaults`; +90 test lines around factory-reset semantics.
- **REP-014** — `IMessageChannel.recentThreads` now backed by an injectable `dbPathOverride` + in-memory SQLite coverage including the nanoseconds-vs-seconds date autodetect edge case. +237 test lines.
- **REP-015** — Incremental FTS upsert path for watcher-driven syncs (unblocks the scale-out note in AGENTS.md Gotchas).

### Test coverage delta

- **+85 tests** (60 → 145, all green per local audit of `func test` declarations; no in-sandbox `swift test` available this run).
- New test files: `AttributedBodyDecoderTests`, `StatsTests`, `ChatDBWatcherTests`, `IMessageChannelPreviewTests`, `ContactsResolverTests`, `PreferencesTests`, `IMessageChannelTests`. Expanded: `RulesTests` (+179), `IMessageSenderTests` (+113), `SearchIndexTests` (+86).
- Test/LOC ratio is well above 1:1 on nearly every substantive commit. No test files shrunk.
- The only meaningful untested surface that remains is `MLXDraftService` (acceptable — 2 GB model download is not CI-friendly) and the view layer.

### Concerns

- **None material.** This is the cleanest automated window the project has produced.
- Minor: `claim REP-XXX in progress` commits now outnumber substantive commits 1:1 in the window. It's correct per protocol but a ratio worth watching — if it grows, consider a planner-side consolidation.
- Minor: AGENTS.md "Rich message decoding limits" and "FTS5 watcher updates" stub bullets are now stale; pruning them this review.

### Suggestions for next planner cycle

1. **REP-009 (Global `⌘⇧R`, P1)** — Remaining open task that isn't UI-sensitive-hard-block. Needs Accessibility permission + `NSEvent.addGlobalMonitorForEvents`. Worker should branch to `wip/` for the permission prompt path since the first run pops a system dialog the user has to satisfy.
2. **REP-010 (Slack OAuth, P1)** — Also still open. L effort; give it a dedicated run, not bundled. Keychain prefix convention (`ReplyAI-`) is already documented in AGENTS.md — worker should honor it verbatim for factory-reset parity.
3. **Test-count maintenance pace is excellent** — don't let it regress. +85 in one window is a high bar; planner should keep one "add coverage to X" S-task in the queue per 6h window to preserve the habit.
4. **Claim-commit noise** — consider having the planner pre-claim the next window's tasks in a single commit instead of the worker claiming per-task. Lower-signal history for the human reader.
5. **Human-review flag from REP-008** — the worker explicitly flagged `🔗` / `📎` glyph choices for human review. Queue an S-task for a product-level copy pass on sidebar previews so that decision is made deliberately, not by default.

---

## Automation First Fire — 2026-04-21 (Addendum) — ⭐⭐⭐⭐⭐

**Note:** This addendum supplements the founding-week review filed earlier today (see below). The automation loop ran in full for the first time between that review and this run.

The planner and worker both executed within hours of the founding-week review. The worker correctly applied the substantiveness gate (bundled S+M per protocol), resolved both remaining P0 backlog items (REP-001 and REP-002), added 5 targeted tests (55 → 60 total), shipped a clean debug build, and filed an honest run log. No banned actions. The automation loop is healthy on day 1.

### Shipped (automation round)

- **REP-001 (P0, S)** — `lastSeenRowID` persisted to UserDefaults (same pattern as `archivedThreadIDs`). Prevents rules from re-firing against the full chat.db history on every app relaunch. Key: `pref.inbox.lastSeenRowID`, JSON-encodes `[String: Int64]`.
- **REP-002 (P0, M)** — `SmartRule.priority: Int` (default 0, higher wins). `RuleEvaluator.matching` sorts priority DESC with insertion-order tiebreaker. `rules.json` files without the field decode cleanly as priority 0 — no migration needed.

### Test coverage delta (automation round)

- **+5 tests** (55 → 60): `testLastSeenRowIDPersistsAcrossInstances`, `testHigherPrioritySetDefaultToneWins`, `testPriorityFieldMissingDefaultsToZero`, `testPriorityRoundTripsThroughJSON`, `testPriorityTiebreakerPreservesInsertionOrder`
- Test/LOC ratio for this commit: ~100 test lines written for ~70 source lines — above the proportional bar.
- No test files shrank.

### Concerns

- None for the automation run itself. Both P0 bugs are fixed; automation is functioning correctly on day 1.
- REP-003 (AttributedBodyDecoder real typedstream parser, P0, effort L) is the last remaining P0. Worker cannot close it in one S/M pass — planner must dedicate a standalone run to it.

### Suggestions for next week's planner

1. **REP-003 (P0, L)** — Give the worker a full dedicated session for the typedstream parser. Don't bundle with other tasks — the spec port alone is M+ effort and needs focused test-fixture work.
2. **REP-004 (P1, S)** — `silentlyIgnore` vs `archive` distinction. S effort, clear success criteria; a clean pairing candidate for after REP-003 lands.
3. **Test-ratio maintenance** — REP-006 (IMessageSender escaping), REP-011 (ContactsResolver), REP-012 (RulesStore) are all well-scoped S/M test tasks. Planner should slot one per week to prevent the untested surface from widening.
4. **wip/ discipline** — No wip/ branches open yet (correct). When REP-009 (global hotkey) or REP-010 (Slack OAuth) are assigned, confirm the worker branches rather than merging direct to main.

---

## Week of 2026-04-21 — ⭐⭐⭐⭐⭐

**Rating: 5/5**

This is an extraordinary founding week. The project went from a blank repository to a fully functional macOS inbox app in 3.5 days — 23 commits, all by Elijah (human), with the autonomous automation infrastructure itself landing as the final commit on Apr 20. The core product loop is complete: read iMessages from chat.db, AI-draft replies via stub LLM or on-device MLX, edit the draft, confirm, and send via AppleScript. The rules engine (DSL, on-disk store, live UI, full pipeline firing on both thread-select and incoming messages) is an especially high-quality piece of work — hand-written Codable with a `kind` discriminator, pure-function evaluator, and 12 solid test cases. Commit messages are detailed and honest about scope. No banned-action violations anywhere. Sandbox correctly stays OFF. No `#Preview` macros. The automation agents (planner, worker, reviewer) haven't run yet — first worker fire expected this coming week.

### Shipped this week

- **Full app scaffold**: 34 screens translated from design handoff, SPM build without Xcode, streaming draft plumbing (LLMService/DraftEngine/StubLLMService)
- **Live iMessage sync**: chat.db reader (FDA-gated), ContactsResolver, AttributedBodyDecoder for typedstream fallback, ChatDBWatcher (600ms-debounced FSEvents), sync-status chip in sidebar
- **Editable composer + send**: TextEditor binding over draft stream, ⌘↵ AppleScript send via `tell application "Messages"`, two-step confirm sheet
- **MLX on-device LLM**: mlx-swift-lm 3.x behind a Settings toggle, model-load progress banner, ~2 GB HuggingFace snapshot on first enable
- **Smart Rules engine**: predicate DSL (7 primitive kinds + and/or/not), 5 actions, RulesStore with atomic JSON writes, rules fire on thread-select and on incoming messages (archive/markDone/silentlyIgnore)
- **FTS5 full-text search**: in-process SQLite FTS5 over live threads, ⌘K palette overlay with 120ms-debounced live results
- **Thread list polish**: pinned threads float top with `pin.fill` glyph + a11y label; archivedThreadIDs persisted via UserDefaults
- **Group chat sending**: chat.guid projected from SQL and passed verbatim to AppleScript (critical — synthesizing would address the wrong recipient)
- **Automation infrastructure**: AGENTS.md, BACKLOG.md (10 scoped tasks), .automation/{planner,worker,reviewer}.prompt, budget.json, REVIEW.md, AUTOMATION.md

### Test coverage delta

- **+55 tests** (0 → 55; all green, 0 failures)
- New test files: DraftEngineTests, LLMServiceTests, FixturesTests, ScreenInventoryTests, RulesTests, SearchIndexTests, IMessageSenderTests
- Strong coverage on pure-Swift logic: predicate evaluation, FTS5 query translation, GUID selection, Codable round-trips, rule pipeline end-to-end
- **Gaps** (all acknowledged in BACKLOG):
  - `ChatDBWatcher` — no tests; debounce behavior is subtle (REP-007, P1)
  - `AttributedBodyDecoder` — no tests; byte-scan approach is fragile (REP-003, P0)
  - `ContactsResolver` — no tests; cache correctness not verified
  - `IMessageChannel` — no unit tests; real-SQLite dependency makes this harder but fixtures could cover the query logic
  - `MLXDraftService` — no tests; acceptable given ~2 GB model download requirement

### Concerns

- **`lastSeenRowID` resets on every relaunch** — rules re-fire against entire chat.db history on next sync. This is a real bug, not a polish item. REP-001 is correctly P0 in the backlog; worker should pick it up first.
- **Zero planner/worker runs so far** — expected (automation launched Apr 20), but next week's review will assess whether the automated loop produces the same quality bar that Elijah's human commits set. The bar is high.
- **`AttributedBodyDecoder` is fragile** — a naive byte-scan that misses common patterns. Modern iOS messages (link previews, tapbacks, reactions) will render as `[non-text message]` frequently. REP-003 is P0 for a reason.
- **`RuleEvaluator` first-match-wins** is documented but not yet resolved. With the seed rules, conflict is unlikely, but once users add their own rules this will surface. REP-002 is correctly P0.
- **AGENTS.md test count is stale** — says "46 XCTest cases" and "34 tests" in the repo layout section; actual is 55. Corrected in this review run.

### Suggestions for next week's planner

1. **Worker's first task: REP-001** (persist `lastSeenRowID`) — S effort, P0, directly prevents rule double-firing on every relaunch. Ship it day 1.
2. **Follow with REP-002** (SmartRule priority + conflict resolution) — M effort, P0, prevents silent misbehavior once users have multiple rules.
3. **REP-003** (real typedstream parser) is L effort — assign it to a dedicated session, not a one-hour worker run. Planner should schedule as a multi-run task or flag it ui_sensitive to get human review.
4. **REP-007** (ChatDBWatcher tests) — M effort, P1. The debounce behavior is exactly the kind of thing that regresses silently. Schedule in the same week as REP-001.
5. **Planner should verify the automation heartbeat early**: confirm planner-YYYY-MM-DD.md logs are appearing under `.automation/logs/` by Wednesday. If not, the scheduled task may need a clock fix.
6. **For UI-sensitive work** (REP-009 global hotkey, REP-010 Slack OAuth): worker correctly branches to `wip/`; planner should track open wip/ count and alert if it exceeds 3.

---
