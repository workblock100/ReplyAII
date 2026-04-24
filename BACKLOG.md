# BACKLOG.md

Prioritized, scoped task list maintained by the planner agent. The hourly worker picks the highest-priority open, non-ui-sensitive task and ships it.

**Format per task:**

```
### REP-NNN — <title>
- priority: P0 | P1 | P2
- effort:   S | M | L
- ui_sensitive: true | false
- status:   open | in_progress | blocked | done
- claimed_by: null | <run-id> | human
- files_to_touch: [list of primary paths]
- scope: 2-4 sentences of what "done" means
- success_criteria:
  - ...
- test_plan: ...
```

---

## P0 — ship-blocking or bug-fix

### REP-228 — InboxViewModel: fixture demo mode when no channel provides threads
- priority: P0
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-145504
- blocker: TWO complete implementations available: `wip/2026-04-23-145504-demo-mode` (worker-145504, +193 LOC, 3 tests) and `wip/worker-2026-04-23-161500-demo-mode` (worker-161500, +207 LOC, 3 tests). Human should diff both, pick the cleaner implementation (or cherry-pick best parts), run `swift test`, and merge. Mark done after merge.
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Fixtures/Fixtures.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: **Strategic pivot P0: app must be useful with zero permissions.** When `syncFromIMessage()` returns 0 threads AND no other channel provides threads, populate `viewModel.threads` from `Fixtures.demoChatThreads` (a new `static let` on `Fixtures`). Each demo thread carries `isDemoThread: Bool = true`. Demo threads are excluded from `send()` (throws `InboxError.demoModeNotSendable`). Rules do not auto-apply to demo threads. `Preferences.demoModeActive: Bool` (defaults `true`; auto-set to `false` after any real sync returns ≥1 thread; exempt from `wipe()`). Tests: demo threads appear when real sync returns empty; demo mode flag persists to Preferences; demo mode disables after successful real sync; `send()` on demo thread throws `demoModeNotSendable`.
- success_criteria:
  - `Fixtures.demoChatThreads: [MessageThread]` — 3–5 realistic seed threads (distinct from the gallery Fixtures.threads)
  - `InboxViewModel` populates from demo fixtures when threads empty after sync
  - `Preferences.demoModeActive` key set false after first real sync ≥1 thread
  - `MessageThread.isDemoThread: Bool` field
  - `testDemoThreadsAppearsWhenSyncReturnsEmpty`
  - `testDemoModeFlagClearsAfterRealSync`
  - `testSendOnDemoThreadThrows`
  - Existing InboxViewModelTests remain green
- test_plan: 3 new tests in `InboxViewModelTests.swift`; use `StaticMockChannel` returning empty threads for first test, non-empty threads for second.

### REP-254 — human: investigate + fix MLX fresh-clone build time exceeding 13-min worker budget
- priority: P0
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `.automation/worker.prompt` (build hints), `scripts/build.sh` (pre-warm artifacts)
- scope: **Structural blocker for main-branch throughput — ESCALATED.** 31 wip branches are now stuck awaiting `swift test` + merge because MLX fresh-clone compile takes 20+ min (exceeds 13-min worker budget). Every worker run creates another blocked branch; code is accumulating faster than it ships. **Pending wip branches as of 2026-04-24 (planner run 10):** `wip/quality-*` (8 branches, REP-016/017/048, since 2026-04-21), `wip/2026-04-23-085959-stats-session-acceptance` (REP-200), `wip/2026-04-23-130000-thread-name-regex` (REP-217), `wip/2026-04-23-145504-demo-mode` (REP-228 impl-A), `wip/worker-2026-04-23-161500-demo-mode` (REP-228 impl-B), `wip/2026-04-23-191507-appleScript-fallback` (REP-236/229), `wip/2026-04-23-200831-slack-http-keychain-deleteall` (REP-237/238), `wip/2026-04-23-230824-telegram-channel-tests` (REP-256/205/206), `wip/2026-04-24-005143-rep255-notification-permission` (REP-255), `wip/2026-04-24-031929-channel-stubs` (REP-243/260/261/264), `wip/2026-04-24-083949-rep266-slack-oauth-flow` (REP-266), `wip/worker-2026-04-24-113000-viewstate` (REP-247 standalone), `wip/2026-04-24-120000-viewstate-slacktokenstore` (REP-247+274 bundled), `wip/2026-04-24-113000-slack-socket-token-store` (claim only, no code), `wip/2026-04-24-152005-thread-cache` (REP-278), `wip/2026-04-24-114653-slack-socket-client` (REP-267), `wip/2026-04-24-133823-inbox-bulk-filter` (REP-224/245/246/248), `wip/2026-04-24-143143-prefs-channels-negation-concurrent` (REP-231/208/220 NEWLY added), `wip/2026-04-24-163229-un-notification-parser` (REP-241), `wip/2026-04-24-152614-unread-bulk-concurrent` (REP-246/248/209/249 NEWLY added), `wip/2026-04-24-170301-sync-all-channels` (REP-244), plus `wip/worker-2026-04-23-135355-bundle`, `wip/worker-2026-04-24-105453-rep278-threads-cache` (superseded), `wip/worker-2026-04-24-115000-notification-parser-slack-token` (superseded). **31 branches total.** **Partial fix in place**: Human added `replyai-merger` agent (commit `7f9b305`, `.automation/merger.prompt`) which drains the wip queue automatically when `.build/` is warm — this is the "warm-build babysitter" the reviewer requested. The merger covers the automated-drain case; REP-285 (Package.swift MLX split) remains the structural fix that makes `swift test` fast on any machine. Human should: (a) ensure merger runs on a machine with warm `.build/`; (b) action REP-285 to remove the cold-build dependency entirely; (c) close the 3 superseded/claim-only branches.
- success_criteria:
  - Merger agent runs on a warm-build machine and drains ≥5 wip branches per day
  - REP-285 (Package.swift MLX split) actioned so fresh-clone `swift test` completes in <5 min
  - All 31 current stuck wip branches either merged or closed
  - Reviewer confirms throughput improved in next 6h window
- test_plan: Human ensures merger fires on warm machine; verifies wip queue depth trending down in merge logs.


### REP-236 — InboxViewModel: wire AppleScript fallback when chat.db returns authorizationDenied
- priority: P0
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-191507
- blocker: Implementation complete on wip/2026-04-23-191507-appleScript-fallback (+228 LOC, 4 tests). MLX fresh-clone build time exceeded 13-min budget; human should run `swift test` locally and merge if green.
- files_to_touch: `Sources/ReplyAI/Channels/AppleScriptMessageReader.swift` (new), `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: **Pivot-aligned P0: app must list threads without FDA.** Implement `AppleScriptMessageReader` (from REP-229 spec, consolidated here) with `recentChats() -> [MessageThread]` using an injectable executor that runs `tell application "Messages" to get every chat`. Wire into `IMessageChannel.recentThreads()`: if `openReadOnly()` throws `ChannelError.authorizationDenied`, call `AppleScriptMessageReader.recentChats()` as the fallback. Returns `[MessageThread]` with `displayName`, `chatGUID`, placeholder `previewText`, and `channel: .iMessage`. No FDA required — uses macOS Automation permission. Tests: mock executor returning chat list → threads populated; mock FDA failure → fallback executor called; executor throws → propagates error; successful fallback results sorted by displayName.
- success_criteria:
  - `AppleScriptMessageReader.recentChats() -> [MessageThread]` with injectable executor
  - `IMessageChannel.recentThreads()` calls fallback when `openReadOnly()` throws `authorizationDenied`
  - `testAppleScriptFallbackCalledWhenFDADenied` — FDA denied + executor returns data → non-empty thread list
  - `testAppleScriptFallbackExecutorIsInjectable` — captures AppleScript string for assertion
  - `testAppleScriptFallbackErrorPropagates` — executor throws → error surfaced
  - `testFDASuccessSkipsFallback` — when chat.db opens successfully, fallback never called
  - Existing IMessageChannelTests remain green
- test_plan: 4 new tests in `IMessageChannelTests.swift`; injectable executor returns either structured data or throws without executing real AppleScript.

### REP-255 — NotificationCoordinator: request UNUserNotificationCenter authorization on startup
- priority: P0
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-005143
- blocker: code complete; swift test timed out due to MLX fresh-clone build time (REP-254); wip/2026-04-24-005143-rep255-notification-permission
- files_to_touch: `Sources/ReplyAI/Services/NotificationCoordinator.swift`, `Tests/ReplyAITests/NotificationCoordinatorTests.swift`
- scope: **Pivot-aligned P0 (enables notification-based thread capture without FDA).** `NotificationCoordinator` already handles inline reply and passive capture (REP-028, REP-235). Without an explicit `requestAuthorization` call, macOS will never show the permission prompt and the UNNotification capture path (REP-235) silently produces zero events. Add `requestPermissionIfNeeded()` to `NotificationCoordinator`: calls `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])` if the current status is `.notDetermined`. Injectable `UNUserNotificationCenter` protocol for test isolation (same pattern as REP-028). `InboxViewModel.init()` calls `notificationCoordinator.requestPermissionIfNeeded()` — fires early so macOS permission dialog appears at app launch. Tests: `requestAuthorization` called when status is `.notDetermined`; NOT called when status is `.authorized` (idempotent); NOT called when status is `.denied` (no re-prompt).
- success_criteria:
  - `NotificationCoordinator.requestPermissionIfNeeded()` method added
  - Calls `requestAuthorization` only when status is `.notDetermined`
  - `InboxViewModel.init()` calls `requestPermissionIfNeeded()`
  - `testRequestPermissionCalledWhenUndetermined` — mock status=.notDetermined → requestAuthorization called
  - `testRequestPermissionNotCalledWhenAuthorized` — mock status=.authorized → requestAuthorization not called
  - `testRequestPermissionNotCalledWhenDenied` — mock status=.denied → requestAuthorization not called
  - Existing NotificationCoordinatorTests remain green
- test_plan: 3 new tests in `NotificationCoordinatorTests.swift`; injectable `MockUNUserNotificationCenter` that returns configured authorization status.

### REP-266 — SlackOAuthFlow: complete OAuth2 orchestrator — LocalhostOAuthListener + token exchange + KeychainHelper
- priority: P0
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-083949
- blocker: code complete (+115 LOC source, +145 LOC tests, 5 tests); MLX fresh-clone build time exceeded 13-min worker budget (REP-254); human should run `swift test` and merge if green; wip/2026-04-24-083949-rep266-slack-oauth-flow
- files_to_touch: `Sources/ReplyAI/Channels/SlackOAuthFlow.swift` (new), `Tests/ReplyAITests/SlackOAuthFlowTests.swift` (new)
- scope: **Pivot-aligned P0: first end-to-end non-iMessage channel path — no FDA required.** `LocalhostOAuthListener` (REP-230, shipped fbba843) handles the callback server. `KeychainHelper` (REP-233, shipped c001d7e) handles token storage. New `SlackOAuthFlow` orchestrates both: `authorize(clientID: String, clientSecret: String, completion: (Result<Void, OAuthError>) -> Void)` — (1) starts `LocalhostOAuthListener` on port 4242; (2) opens `https://slack.com/oauth/v2/authorize?client_id=<id>&scope=channels:read,chat:write&redirect_uri=http://localhost:4242/callback` via injectable `URLOpener` protocol (default: `NSWorkspace.shared.open`); (3) on `code` received, POSTs to `https://slack.com/api/oauth.v2.access` with `code + client_id + client_secret` via injectable `URLSession`; (4) parses `access_token` from JSON response; (5) stores via `KeychainHelper.set(value: token, for: "slack-access-token")`. `LocalhostOAuthListenerFactory: (port: UInt16, timeout: TimeInterval) -> LocalhostOAuthListener` injectable for tests. Tests: mock `URLOpener` captures constructed auth URL (assert clientID, scope, redirectURI params); mock listener factory delivers `code=testcode`; mock URLSession returns `{"ok":true,"access_token":"xoxb-test"}` → token stored in KeychainHelper; `{"ok":false}` response throws `OAuthError.tokenExchangeFailed`; listener timeout propagates as `OAuthError.timeout`.
- success_criteria:
  - `SlackOAuthFlow.authorize(clientID:clientSecret:completion:)` in new file
  - Injectable `URLOpener` protocol (default `NSWorkspace.shared.open`)
  - Injectable `URLSession` for token exchange POST
  - Injectable `LocalhostOAuthListenerFactory` for test isolation
  - `testSlackOAuthOpensCorrectAuthURL` — mock URLOpener captures URL with correct clientID + scope + redirectURI
  - `testSlackOAuthExchangesCodeForToken` — mock listener delivers code → URLSession called with correct POST params
  - `testSlackOAuthStoresTokenInKeychain` — successful exchange → `KeychainHelper.get("slack-access-token")` returns token
  - `testSlackOAuthFailedExchangeThrows` — `{"ok":false}` → `OAuthError.tokenExchangeFailed`
  - `testSlackOAuthListenerTimeoutPropagates` — listener timeout → `OAuthError.timeout`
  - Existing tests remain green
- test_plan: 5 new tests in `SlackOAuthFlowTests.swift`; inject mock `URLOpener`, listener factory, and `URLSession`; no real network or OS calls.

### REP-278 — InboxViewModel: persist last-known thread list to disk for cold-launch resilience
- priority: P0
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-152005
- blocker: code complete on wip/2026-04-24-152005-thread-cache (est. 531→536 tests, 5 new tests); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` locally and merge if green; see REP-279 for human review task
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: **Pivot P0: app must show something useful when all channels fail at cold launch.** When FDA is denied, Automation is denied, and no Slack token exists, the inbox is blank. If a prior launch had real threads, persisting the thread list means the user sees recognizable conversation rows immediately, not a blank screen. After every successful `syncFromIMessage()` (or any channel sync) that returns ≥1 thread, JSON-serialize the thread list (fields: `id, displayName, chatGUID, previewText, channel, isRead`) to `~/Library/Application Support/ReplyAI/last-threads-cache.json`. On `InboxViewModel.init()`, if `threads.isEmpty`, read this file and populate `threads` from cache. Cache is only used as initial-state fill — any real sync result (even empty) replaces it. Cache entries do NOT carry `isDemoThread: true`; they are presented as-is. `Preferences.lastThreadsCacheURL: URL` is a computed property returning the cache path. Tests: successful sync → cache file written with correct JSON; cold-init with cache present → `threads` populated; second sync → cache updated; failed sync → existing in-memory threads unchanged (cache file unchanged); cache file absent at init → empty threads (no crash).
- success_criteria:
  - `InboxViewModel` writes thread-list JSON after successful sync
  - `InboxViewModel.init()` populates from cache when threads are empty
  - `Preferences.lastThreadsCacheURL: URL` computed property
  - `testSuccessfulSyncWritesCache` — sync returns threads → cache file exists with serialized threads
  - `testColdInitFromCache` — fresh ViewModel + cache file present → threads populated
  - `testSecondSyncUpdatesCacheFile` — sync twice → cache reflects second sync's thread list
  - `testFailedSyncLeavesThreadsUnchanged` — cache loaded, sync throws → threads unchanged
  - `testMissingCacheAtInitProducesEmptyThreads` — no cache file → threads empty, no crash
  - Existing InboxViewModelTests remain green
- test_plan: 5 new tests in `InboxViewModelTests.swift`; use injected temp directory URL for cache; `StaticMockChannel` for sync results; no file system side-effects in existing tests.

### REP-501 — MLX extraction step 1: move Swift sources to new SPM target directories + rewrite Package.swift
- priority: P0
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- depends_on: []
- files_to_touch:
  - `Package.swift` (rewrite: 4 targets — ReplyAICore library, ReplyAIMLX library, ReplyAI executable, ReplyAITests testTarget)
  - `Sources/ReplyAICore/**` (new: all Sources/ReplyAI/** content except MLXDraftService.swift + ReplyAIApp.swift)
  - `Sources/ReplyAIMLX/MLXDraftService.swift` (moved from Sources/ReplyAI/Services/MLXDraftService.swift)
  - `Sources/ReplyAIApp/ReplyAIApp.swift` (moved from Sources/ReplyAI/App/ReplyAIApp.swift)
  - `Sources/ReplyAI/` (deleted after move — all files relocated)
- scope: Create three new SPM source directories (Sources/ReplyAICore/, Sources/ReplyAIMLX/, Sources/ReplyAIApp/), then use `git mv` to relocate every .swift file and the Resources/ subtree from Sources/ReplyAI/ to the appropriate new location (preserving subdirectory structure in ReplyAICore), then rewrite Package.swift to declare the four targets with correct dependencies. After this commit the directory layout is correct but the build will fail: MLXDraftService.swift and ReplyAIApp.swift are missing cross-module imports, and test files still reference `@testable import ReplyAI`. Do NOT attempt `swift test`. Push to `wip/REP-500-mlx-extraction` branch.
- success_criteria:
  - `Sources/ReplyAI/` directory no longer exists (all .swift files relocated)
  - `Sources/ReplyAICore/` mirrors the former Sources/ReplyAI/ hierarchy (Theme/, Components/, Channels/, Rules/, Services/, Inbox/, MenuBar/, Screens/, Fixtures/, Models/, Resources/) minus the two extracted files
  - `Sources/ReplyAIMLX/MLXDraftService.swift` exists (file moved, content unchanged)
  - `Sources/ReplyAIApp/ReplyAIApp.swift` exists (file moved, content unchanged)
  - `Package.swift` declares exactly 4 targets: `ReplyAICore` (library, deps: swift-huggingface + swift-transformers only, no MLX), `ReplyAIMLX` (library, deps: ReplyAICore + MLXLLM + MLXLMCommon + MLXHuggingFace), `ReplyAI` (executable, deps: ReplyAICore + ReplyAIMLX), `ReplyAITests` (testTarget, deps: ReplyAICore only)
  - `git diff --stat HEAD` shows all Sources/ReplyAI/* deleted and matching Sources/ReplyAICore/* + Sources/ReplyAIMLX/* + Sources/ReplyAIApp/* added
  - Pushed to `wip/REP-500-mlx-extraction` (build expected broken — cross-module imports missing, fixed in REP-502)
- test_plan: No `swift test` (build expected broken after this step). Worker validates file counts: `find Sources/ReplyAICore -name "*.swift" | wc -l` plus 2 (for the moved MLXDraftService + ReplyAIApp) equals the prior `find Sources/ReplyAI -name "*.swift" | wc -l`. Inspect Package.swift to confirm 4-target structure and that ReplyAITests has no MLX dependency.

### REP-502 — MLX extraction step 2: add cross-module import statements to MLXDraftService.swift and ReplyAIApp.swift
- priority: P0
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- depends_on: [REP-501]
- files_to_touch:
  - `Sources/ReplyAIMLX/MLXDraftService.swift`
  - `Sources/ReplyAIApp/ReplyAIApp.swift`
- scope: MLXDraftService.swift now lives in the ReplyAIMLX target and can no longer implicitly see ReplyAICore's types (LLMService, DraftChunk). Add `import ReplyAICore` at the top of MLXDraftService.swift. ReplyAIApp.swift now lives in the ReplyAI executable target and must import both sub-libraries; add `import ReplyAICore` and `import ReplyAIMLX` at the top of ReplyAIApp.swift. No other source files need changes — everything else is within ReplyAICore and shares its module namespace. Attempt `swift build --product ReplyAI` on warm cache; push to same `wip/REP-500-mlx-extraction` branch.
- success_criteria:
  - `Sources/ReplyAIMLX/MLXDraftService.swift` begins with `import ReplyAICore` (before any existing `import MLXLLM` etc.)
  - `Sources/ReplyAIApp/ReplyAIApp.swift` contains both `import ReplyAICore` and `import ReplyAIMLX` lines
  - No files in `Sources/ReplyAICore/` are modified (same-module; no imports needed)
  - `swift build --target ReplyAICore` exits 0 on warm cache
  - `swift build --target ReplyAIMLX` exits 0 on warm cache (if MLX cold-build constraint hit, skip — push to wip with note)
  - Tests still expected to fail at this step (fixed in REP-503)
- test_plan: Worker runs `swift build --target ReplyAICore` to confirm the core library compiles. Attempts `swift build --product ReplyAI` — compile errors, if any, should only be in test files (which reference the old module name). Push to `wip/REP-500-mlx-extraction` with a note on build status.

### REP-503 — MLX extraction step 3: bulk-update test file imports @testable import ReplyAI → @testable import ReplyAICore
- priority: P0
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- depends_on: [REP-502]
- files_to_touch:
  - `Tests/ReplyAITests/*.swift` (all test files — bulk import name replacement)
- scope: Every XCTest file in Tests/ReplyAITests/ currently imports `@testable import ReplyAI`. The library target was renamed to ReplyAICore; all test imports must be updated. Use `sed -i '' 's/@testable import ReplyAI$/@testable import ReplyAICore/g'` across all test files (or equivalent). Also grep for bare `import ReplyAI` (non-testable) and update those. After this step the full build — including tests — should compile. Push to `wip/REP-500-mlx-extraction`; do NOT attempt `swift test` if MLX cold-build constraint applies (human runs tests in REP-505).
- success_criteria:
  - `grep -r "@testable import ReplyAI$" Tests/ReplyAITests/` returns no output (all replaced)
  - `grep -r "import ReplyAI$" Tests/ReplyAITests/` returns no output (no bare imports remain)
  - `grep -r "@testable import ReplyAICore" Tests/ReplyAITests/ | wc -l` equals the prior count of `@testable import ReplyAI` occurrences
  - `swift build --target ReplyAITests` exits 0 on warm cache (if MLX cold-build constraint hit, push to wip with note)
- test_plan: Worker runs `grep -rc "@testable import ReplyAI$" Tests/` — count before must match count replaced; count after must be 0. Attempts `swift build` (not `swift test`); all test-file compile errors should be resolved. If `swift build` exits 0, that is the green signal for this step.

### REP-504 — MLX extraction step 4: fix scripts/build.sh resource paths + validate dep graph + push for human merge
- priority: P0
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- depends_on: [REP-503]
- files_to_touch:
  - `scripts/build.sh`
- scope: The bundler script references `Sources/ReplyAI/Resources/` for copying Info.plist, entitlements, Assets.xcassets, and Fonts into the .app bundle. Update every such reference to `Sources/ReplyAICore/Resources/`. Grep for any remaining `Sources/ReplyAI/` references in build.sh and fix them. Run `swift package show-dependencies` to confirm that the ReplyAITests dependency graph does NOT include mlx-swift-lm. Run `swift build` one final time to confirm the full chain is clean. Push to `wip/REP-500-mlx-extraction`. The subsequent REP-505 task handles human `swift test` + `./scripts/build.sh debug` verification before merge.
- success_criteria:
  - `grep "Sources/ReplyAI/" scripts/build.sh` returns empty (all paths updated to ReplyAICore)
  - `swift package show-dependencies 2>&1 | grep "mlx-swift-lm"` returns empty when checking the ReplyAITests target (or overall graph no longer pulls in MLX through the test path)
  - `swift build` exits 0 on warm cache
  - `wip/REP-500-mlx-extraction` branch pushed with all 4 worker-authored commits ready for human review
- test_plan: Worker runs `grep -r "Sources/ReplyAI/" scripts/build.sh` (must return empty after fix). Worker runs `swift package show-dependencies` and confirms mlx-swift-lm absent from ReplyAITests resolution. Worker runs `swift build` to confirm zero compile errors. Worker pushes branch.

### REP-505 — human: verify wip/REP-500-mlx-extraction — run swift test + build.sh debug before merging to main
- priority: P0
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- depends_on: [REP-504]
- files_to_touch: wip/REP-500-mlx-extraction (review only; merge to main if green)
- scope: Human verification gate for the full REP-500 MLX extraction chain (REP-501 through REP-504). Workers pushed code to wip/REP-500-mlx-extraction but could not run swift test due to the MLX cold-build budget constraint. Human should: (1) checkout the branch; (2) run `swift test` and confirm all 527+ tests pass with zero regressions; (3) run `./scripts/build.sh debug` and confirm the .app bundles and launches; (4) enable the MLX toggle in Settings and verify draft generation still produces tokens (MLX path intact); (5) confirm `swift package show-dependencies` excludes mlx-swift-lm from the ReplyAITests graph; (6) merge to main if all green and mark REP-500 through REP-505 done.
- success_criteria:
  - `swift test` exits 0 with ≥527 tests passing (no regressions in test count or correctness)
  - `./scripts/build.sh debug` produces a launchable .app without errors
  - MLX draft generation works end-to-end after enabling the toggle in Settings
  - `swift package show-dependencies 2>&1 | grep mlx` returns empty (tests no longer link MLX)
  - wip/REP-500-mlx-extraction merged into main; REP-500 through REP-505 marked done
- test_plan: Human runs all verification steps listed in scope. Merges if and only if all criteria are met. Reports any failures back as new bug tasks if the branch does not pass.

---

## P1 — significant value, not urgent

### REP-016 — human: review + merge wip/quality-senderknown-fix
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Branch `wip/quality-2026-04-21-193800-senderknown-fix` (commit d672ab4) contains a real bug fix: operator-precedence in `RuleContext.from(thread:)` caused `&&` to bind tighter than `||`, so emails and digit-only phone numbers were misclassified as known contacts. The consequence is that the `.senderUnknown` rule predicate silently misfired since initial shipping. This is a correctness bug affecting any user who has set up `.senderUnknown` rules. Human should review the fix (it changes production logic), merge if correct, then check whether sibling wip branches' tests still pass with the corrected logic.
- success_criteria:
  - `senderKnown` correctly returns false for raw email addresses (e.g. "user@example.com")
  - `senderKnown` correctly returns false for digit-only phone strings (e.g. "4155551234")
  - `senderKnown` correctly returns true for display names (e.g. "Alice Smith")
  - Existing test suite remains green after merge
- test_plan: The wip branch includes tests covering these cases; human verifies they pass after merge.

### REP-017 — human: consolidate overlapping wip quality branches
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Seven wip/ branches contain overlapping quality-pass test additions. Human should cherry-pick the cleanest, non-duplicating tests into main (or merge the best single branch per subsystem). Priority order: (1) wip/quality-2026-04-21-193800-senderknown-fix (REP-016, do first); (2) best of wip/quality-2026-04-21-212529 or wip/quality-2026-04-21-215030 for RuleContext.from + senderIs/senderUnknown/or coverage; (3) best of wip/quality-2026-04-21-211100 or wip/quality-2026-04-21-213914 for DraftEngine gap coverage. Drop wip/quality-2026-04-21-184250 (superseded by the bug fix branch) and wip/quality-2026-04-21-191222 (log-only commit). REP-048 covers wip/quality-2026-04-21-221100 separately. Close all branches after merge.
- success_criteria:
  - All 6 wip/ branches from this group closed after review (wip/quality-2026-04-21-221100 handled by REP-048)
  - Test count on main increases from 218 (minimum: +8 from RuleContext/RuleEvaluator coverage, +5 from DraftEngine coverage = 231+)
  - No duplicate test functions in merged result
- test_plan: Human runs `grep -r "func test" Tests/ReplyAITests/ | wc -l` before and after to confirm net gain.

### REP-048 — human: review + merge wip/quality-2026-04-21-221100
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Branch `wip/quality-2026-04-21-221100` (commit db4a329) adds DraftEngine test coverage for the error path, stats integration, and `modelLoadStatus` transitions — 115 new test lines. This branch does not overlap with the REP-017 consolidation group (those target RuleEvaluator and early DraftEngine gap coverage). Human should review the test additions, confirm no duplicate function names with any branches merged via REP-017, then merge if clean. Close the branch after merge.
- success_criteria:
  - Branch merged and closed after review
  - Test count on main grows by the number of new `func test` declarations in this branch
  - No duplicate test function names after merge
  - `swift test` all green after merge
- test_plan: Human runs `swift test` after merge to confirm all green.

### REP-200 — human: review and merge wip/2026-04-23-085959-stats-session-acceptance
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`, `Tests/ReplyAITests/RulesTests.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Worker-085959 implemented REP-135 (Stats.sessionStartedAt + sessionDuration), REP-177 (Stats.overallAcceptanceRate), REP-179 (RuleEvaluator equal-priority determinism), REP-183 (Preferences wipe-exempt regression guard), and REP-187 (Stats.snapshot() JSON validation) but was blocked by MLX full-project build time exceeding the 13-min worker budget. All 5 implementations are on branch `wip/2026-04-23-085959-stats-session-acceptance`. Human should: (1) review the wip branch diff; (2) run `swift test` on main for baseline; (3) cherry-pick or merge the branch; (4) run `swift test` to confirm new tests pass; (5) mark REP-135, REP-177, REP-179, REP-183, REP-187 as done in BACKLOG.
- success_criteria:
  - wip/2026-04-23-085959-stats-session-acceptance merged into main
  - REP-135, REP-177, REP-179, REP-183, REP-187 all marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` before and after merge to confirm baseline and pass.

### REP-217 — human: review + merge wip/2026-04-23-130000-thread-name-regex
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Screens/Surfaces/SfcRulesView.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Worker-2026-04-23-130000 implemented REP-129 (`threadNameMatchesRegex(pattern:)` predicate) but was blocked by MLX full-project build time exceeding the 13-min budget. Implementation is complete on branch `wip/2026-04-23-130000-thread-name-regex`. Human should: (1) review the wip branch diff; (2) run `swift test` on main for baseline; (3) cherry-pick or merge the branch; (4) run `swift test` to confirm new tests pass; (5) mark REP-129 as done in BACKLOG.
- success_criteria:
  - wip/2026-04-23-130000-thread-name-regex merged into main
  - REP-129 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` before and after merge to confirm baseline and pass.

### REP-232 — human: review + merge wip/worker-2026-04-23-135355-bundle
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Tests/ReplyAITests/DraftStoreTests.swift`, `Tests/ReplyAITests/RulesTests.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`, `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: Worker-2026-04-23-135355 implemented 6 tasks but was blocked by MLX full-project build time. All 6 implementations are on branch `wip/worker-2026-04-23-135355-bundle`: REP-163 (DraftStore.listStoredDraftIDs), REP-193 (IMessageSender 4096-char boundary), REP-194 (Preferences.threadLimit clamped [1,200]), REP-195 (DraftEngine dismiss-on-unprimed is no-op), REP-196 (SearchIndex repeated-search order stability), REP-198 (IMessageChannel empty-thread exclusion). Human should: (1) review the diff; (2) run `swift test` on main for baseline; (3) merge or cherry-pick the branch; (4) run `swift test` to confirm; (5) mark REP-163, REP-193, REP-194, REP-195, REP-196, REP-198 done in BACKLOG.
- success_criteria:
  - wip/worker-2026-04-23-135355-bundle merged into main
  - REP-163, REP-193, REP-194, REP-195, REP-196, REP-198 all marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` before and after merge to confirm baseline and pass.

### REP-275 — human: resolve competing REP-247 ViewState implementations (pick one wip branch, merge)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Two competing ViewState implementations exist and one must be selected. `wip/worker-2026-04-24-113000-viewstate` contains REP-247 alone (527→531 tests, +4 tests). `wip/2026-04-24-120000-viewstate-slacktokenstore` contains REP-247 + REP-274 (SlackTokenStore) bundled (more tests). Human should: (1) diff both branches; (2) run `swift test` on each; (3) pick the cleaner implementation — prefer the bundled branch if both pass, since REP-274 is also needed; (4) close the other branch; (5) mark REP-247 and REP-274 done after merge; (6) close the orphaned `wip/2026-04-24-113000-slack-socket-token-store` branch (only a claim commit, no code).
- success_criteria:
  - Exactly one wip branch merged to main
  - The other wip branch closed
  - REP-247 and (if bundled) REP-274 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` on each branch before choosing; verifies 4+ new tests present.

### REP-276 — human: review + merge wip/2026-04-23-230824-telegram-channel-tests (REP-256+205+206)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Channels/TelegramChannel.swift` (new), `Tests/ReplyAITests/TelegramChannelTests.swift` (new), `Tests/ReplyAITests/SearchIndexTests.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: Worker-2026-04-23-230824 implemented REP-256 (TelegramChannel stub), REP-205 (SearchIndex.delete regression test), and REP-206 (PromptBuilder drop-oldest test) but was blocked by MLX build time. Code is complete on `wip/2026-04-23-230824-telegram-channel-tests`. Human should: (1) review the diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-256, REP-205, REP-206 done.
- success_criteria:
  - wip/2026-04-23-230824-telegram-channel-tests merged into main
  - REP-256, REP-205, REP-206 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally before and after merge.

### REP-277 — human: review + merge wip/2026-04-24-031929-channel-stubs (REP-243+260+261+264)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Models/Channel.swift`, `Sources/ReplyAI/Channels/WhatsAppChannel.swift` (new), `Sources/ReplyAI/Channels/TeamsChannel.swift` (new), `Sources/ReplyAI/Channels/SMSChannel.swift` (new), and corresponding test files
- scope: Worker-2026-04-24-031929 implemented REP-243 (Channel enum `.telegram/.whatsapp/.teams/.sms` cases + `displayName/iconName`), REP-260 (WhatsAppChannel stub), REP-261 (TeamsChannel stub), and REP-264 (SMSChannel stub) bundled with 13 new tests (4 ChannelTests + 3 per channel stub). Code complete on `wip/2026-04-24-031929-channel-stubs`. Human should: (1) review diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-243, REP-260, REP-261, REP-264 done.
- success_criteria:
  - wip/2026-04-24-031929-channel-stubs merged into main
  - REP-243, REP-260, REP-261, REP-264 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally before and after merge; confirms 13 new tests appear.

### REP-279 — human: review + merge wip/2026-04-24-152005-thread-cache (REP-278)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Worker-2026-04-24-152005 implemented REP-278 (InboxViewModel: persist thread list to disk for cold-launch resilience) but was blocked by MLX fresh-clone build time exceeding the 13-min budget. Implementation is complete on branch `wip/2026-04-24-152005-thread-cache` (est. 531→536 tests, 5 new tests: successful sync writes cache; cold-init from cache populates threads; second sync updates cache; failed sync leaves threads unchanged; missing cache at init is safe). Human should: (1) review the wip branch diff; (2) run `swift test` on main for baseline; (3) cherry-pick or merge the branch; (4) run `swift test` to confirm; (5) mark REP-278 done in BACKLOG.
- success_criteria:
  - wip/2026-04-24-152005-thread-cache merged into main
  - REP-278 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally before and after merge to confirm baseline and pass; verifies 5 new tests appear.

### REP-280 — warm-build wip-drain: run `swift test` on oldest open wip/* branch and merge if green
- priority: P0
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- blocker: **Superseded by `replyai-merger` agent (commit `7f9b305`).** The merger runs every 30 min on a schedule, drains `wip/*` branches automatically when `.build/` is warm, and is more reliable than a worker fire for this purpose. Workers should NOT claim REP-280 — the merger handles the drain. If the merger is not yet running on a warm machine, workers may fall back to this task's protocol as a one-shot manual drain.
- files_to_touch: whichever `wip/*` branch is oldest and still referenced in BACKLOG as `status: blocked`
- scope: **SUPERSEDED by merger agent — see `.automation/merger.prompt`.** Original scope preserved for reference: Worker MUST check that `.build/` is fresh (<6 hours old via `find .build -maxdepth 0 -mmin -360`) BEFORE claiming this task. If `.build/` IS fresh: (1) checkout oldest blocked wip branch; (2) `swift test 2>&1 | tail -20`; (3) if green, fast-forward merge to main and push; (4) update BACKLOG.md and AGENTS.md. Priority order: `wip/2026-04-23-085959-stats-session-acceptance` (oldest), then chronological order. Skip `wip/quality-*` (human review per REP-016/017/048).
- success_criteria:
  - Merger agent drains wip branches automatically (preferred path)
  - If merger not available: worker follows manual protocol above on warm build
  - No broken tests on main after merge
- test_plan: Worker or merger runs `swift test` on the target branch; all tests must pass before merge.

### REP-284 — human: review + merge wip/2026-04-24-170301-sync-all-channels (REP-244)
- priority: P0
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: wip/2026-04-24-170301-sync-all-channels
- scope: **Pivot P0.** Worker implemented REP-244 (`syncAllChannels()` multi-channel aggregation) on `wip/2026-04-24-170301-sync-all-channels`. This is the core multi-channel aggregation enabling the app to show threads from Slack, AppleScript fallback, and UNNotification capture without FDA. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-244 done.
- success_criteria:
  - wip/2026-04-24-170301-sync-all-channels merged into main
  - REP-244 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally; confirms new syncAllChannels tests pass.

### REP-285 — Package.swift: split MLX into separate optional target (root fix for `swift test` budget)
- priority: P0
- effort: L
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Package.swift` (commit message MUST start with `build:` prefix)
- scope: **Root structural fix for the wip-queue buildup.** Current `Package.swift` forces SwiftPM to compile MLX C++ dependencies on every fresh clone, taking 20–90 min and exceeding the 13-min worker budget. Fix: move MLX and related AI dependencies into a separate optional target (`ReplyAIML`) that the main app target references conditionally or as a standalone module. After this change `swift test` on any machine should complete in <5 min on a fresh clone. Commit message MUST start with `build:` so the merger agent allows the Package.swift edit through its banned-pattern check. Human should implement and validate on a fresh clone.
- success_criteria:
  - `swift test` completes in <5 min on a fresh clone (no `.build/` cache)
  - MLX isolated in separate target; test target excludes it
  - All existing tests still pass
  - Main app still links and runs (MLX functionality preserved, compile cost isolated)
- test_plan: Human clones fresh, runs `swift test`; confirms <5 min completion.

### REP-286 — human: review + merge wip/2026-04-24-143143-prefs-channels-negation-concurrent (REP-231+208+220)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Worker-2026-04-24-143143 implemented REP-231 (per-channel enable/disable Preference keys for iMessage and Slack), REP-208 (double-negation predicate correctness tests), and REP-220 (concurrent add+remove RulesStore correctness tests) on `wip/2026-04-24-143143-prefs-channels-negation-concurrent`. Bundled into one commit (+195 LOC, 8 tests). MLX fresh-clone build time exceeded budget. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-231, REP-208, REP-220 done.
- success_criteria:
  - wip/2026-04-24-143143-prefs-channels-negation-concurrent merged into main
  - REP-231, REP-208, REP-220 all marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally; confirms 8 new tests appear.

### REP-288 — human: review + merge wip/2026-04-24-161734-accessibility-retrydelay (REP-258+269)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Channels/AccessibilityAPIReader.swift` (new), `Tests/ReplyAITests/AccessibilityAPIReaderTests.swift` (new), `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: Worker-2026-04-24-161734 implemented REP-258 (AccessibilityAPIReader: alt message source via macOS Accessibility API, 6 tests) and REP-269 (IMessageSender.retryDelay injectable, removes hardcoded 0.5s sleep, 1 new test + 3 updated). Both complete on `wip/2026-04-24-161734-accessibility-retrydelay`. MLX cold build exceeds budget. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-258 and REP-269 done.
- success_criteria:
  - `swift test` green on the wip branch (est. 527→534 tests)
  - merged to main
  - REP-258 and REP-269 marked done
- test_plan: Human runs `swift test` locally; confirms 7 new/updated tests pass.

### REP-287 — human: review + merge wip/2026-04-24-152614-unread-bulk-concurrent (REP-246+248+209+249)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: wip/2026-04-24-152614-unread-bulk-concurrent
- scope: Worker-2026-04-24-152614 implemented REP-246 (totalUnreadCount), REP-248 (bulkArchiveRead), REP-209 (selectThread unread clear), REP-249 (concurrent ContactsResolver correctness) on `wip/2026-04-24-152614-unread-bulk-concurrent`. +14 new tests. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-246, REP-248, REP-209, REP-249 done.
- success_criteria:
  - `swift test` green on the wip branch
  - wip/2026-04-24-152614-unread-bulk-concurrent merged into main
  - REP-246, REP-248, REP-209, REP-249 marked done
- test_plan: Human runs `swift test` from repo root on the branch; confirms 14 new tests pass.

### REP-282 — human: review + merge wip/2026-04-24-133823-inbox-bulk-filter (REP-224+245+246+248)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: wip/2026-04-24-133823-inbox-bulk-filter
- scope: Worker implemented REP-224 (InboxViewModel bulk-archive), REP-245 (filter by channel), REP-246 (totalUnreadCount), REP-248 (bulkArchiveRead) on `wip/2026-04-24-133823-inbox-bulk-filter`. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-224, REP-245, REP-246, REP-248 done.
- success_criteria:
  - wip/2026-04-24-133823-inbox-bulk-filter merged into main
  - REP-224, REP-245, REP-246, REP-248 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally; confirms new InboxViewModel tests appear.

### REP-283 — human: review + merge wip/2026-04-24-163229-un-notification-parser (REP-241)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: wip/2026-04-24-163229-un-notification-parser
- scope: Worker implemented REP-241 (UNNotificationParser: passive notification capture without FDA) on `wip/2026-04-24-163229-un-notification-parser`. Pivot-aligned: passive capture path works without Full Disk Access. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-241 done.
- success_criteria:
  - wip/2026-04-24-163229-un-notification-parser merged into main
  - REP-241 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally; confirms UNNotificationParser tests pass.

### REP-281 — human: review + merge wip/2026-04-24-114653-slack-socket-client (REP-267)
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Channels/SlackSocketClient.swift` (new), `Tests/ReplyAITests/SlackSocketClientTests.swift` (new)
- scope: Worker-2026-04-24-114653 implemented REP-267 (SlackSocketClient: injectable WebSocket wrapper for Slack Socket Mode). Implementation complete on `wip/2026-04-24-114653-slack-socket-client`. Human should: (1) review the wip branch diff; (2) run `swift test` locally; (3) merge if green; (4) mark REP-267 done in BACKLOG.
- success_criteria:
  - wip/2026-04-24-114653-slack-socket-client merged into main
  - REP-267 marked done
  - `swift test` all green after merge
- test_plan: Human runs `swift test` locally before and after merge.

### REP-237 — SlackHTTPClient: injectable URL session wrapper for Slack API GET calls
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-200831
- blocker: Implementation complete on wip/2026-04-23-200831-slack-http-keychain-deleteall. MLX fresh-clone build time exceeded 13-min budget; human should run `swift test` locally and merge if green.
- files_to_touch: `Sources/ReplyAI/Channels/SlackHTTPClient.swift` (new), `Tests/ReplyAITests/SlackHTTPClientTests.swift` (new)
- scope: **Pivot-aligned (Slack channel prereq).** `SlackHTTPClient` is the HTTP layer needed by `SlackChannel` for `conversations.list` and `conversations.history` API calls. Protocol: `func get(endpoint: String, token: String, params: [String: String]) async throws -> Data`. Default conformance: `URLSessionSlackClient` sends `GET https://slack.com/api/<endpoint>?<params>` with `Authorization: Bearer <token>` header. Injectable for tests via protocol. Tests: mock session returns valid JSON → Data returned; auth header is `Bearer <token>`; correct base URL + endpoint + params in request; HTTP 200 → Data; HTTP 401 → throws `ChannelError.authorizationDenied`; HTTP 429 → throws `ChannelError.networkError`; network error → throws `ChannelError.networkError`.
- success_criteria:
  - `SlackHTTPClient` protocol in new file
  - `URLSessionSlackClient: SlackHTTPClient` default conformance
  - `testAuthHeaderIsBearerToken` — request includes `Authorization: Bearer <token>`
  - `testCorrectEndpointURLConstructed` — URL matches `https://slack.com/api/<endpoint>?<params>`
  - `testHTTP401ThrowsAuthDenied` — 401 response → `ChannelError.authorizationDenied`
  - `testHTTP429ThrowsNetworkError` — 429 response → `ChannelError.networkError`
  - `testSuccessfulResponseReturnsData` — 200 response body returned as Data
  - Existing tests remain green
- test_plan: 5 new tests in `SlackHTTPClientTests.swift`; use `MockURLSession` that returns configured `(Data, HTTPURLResponse)` tuples.

### REP-238 — KeychainHelper: `deleteAll(prefix:)` for factory reset
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-200831
- blocker: Implementation complete on wip/2026-04-23-200831-slack-http-keychain-deleteall. MLX fresh-clone build time exceeded 13-min budget; human should run `swift test` locally and merge if green.
- files_to_touch: `Sources/ReplyAI/Channels/KeychainHelper.swift` (depends on REP-233), `Tests/ReplyAITests/KeychainHelperTests.swift` (depends on REP-233)
- scope: **Pivot-aligned (factory reset / channel de-auth).** `Preferences.wipe()` currently clears UserDefaults but leaves Keychain entries (Slack token, future tokens). Add `KeychainHelper.deleteAll(prefix: String)` that uses `SecItemDelete` with a `kSecAttrAccount` prefix match — deletes every item where the account key starts with `prefix`. Called with `"ReplyAI-"` to wipe all channel tokens on factory reset. Tests: 3 keys with `"ReplyAI-"` prefix → all 3 deleted after `deleteAll("ReplyAI-")`; 1 key without prefix → not deleted; calling on empty keychain does not throw.
- success_criteria:
  - `KeychainHelper.deleteAll(prefix:)` implemented
  - `testDeleteAllRemovesPrefixedKeys` — 3 prefixed keys → all deleted
  - `testDeleteAllLeavesNonPrefixedKeys` — unprefixed key survives
  - `testDeleteAllOnEmptyKeychainIsNoop` — no crash on empty keychain
  - Existing KeychainHelperTests remain green (depends on REP-233)
- test_plan: 3 new tests in `KeychainHelperTests.swift`; uses same injectable service as REP-233.

### REP-256 — TelegramChannel: ChannelService conformance stub with bot token gate
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-230824
- blocker: code complete on wip/2026-04-23-230824-telegram-channel-tests (+27 LOC source, 3 tests, bundled with REP-205/206); MLX fresh-clone build time exceeded 13-min budget; human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Channels/TelegramChannel.swift` (new), `Tests/ReplyAITests/TelegramChannelTests.swift` (new)
- scope: **Pivot-aligned (non-iMessage channel scaffolding).** Mirror of REP-233/234 for Telegram. `TelegramChannel: ChannelService` in a new file. `channel` property returns `.telegram` (requires REP-243 adds the case, or add the case here). Injectable `KeychainHelper(service: "ReplyAI-Telegram")`. `recentThreads()` throws `ChannelError.authorizationDenied` when no bot token present; `openReadOnly()` no-ops or returns quickly. `send()` throws `ChannelError.unsupported` (Telegram send via Bot API comes in a follow-up). Tests: no token → `authorizationDenied`; token present → empty `[]` (stub, no real fetch); `channel` property returns `.telegram`.
- success_criteria:
  - `TelegramChannel: ChannelService` in new file
  - `recentThreads()` throws `authorizationDenied` when `KeychainHelper.get("telegram-bot-token")` returns nil
  - `testTelegramChannelThrowsWhenNoToken` — no Keychain entry → `authorizationDenied`
  - `testTelegramChannelReturnsEmptyWithToken` — token present → `[]` (stub)
  - `testTelegramChannelPropertyReturnsTelegram` — `channel == .telegram`
  - Existing tests remain green
- test_plan: 3 new tests in `TelegramChannelTests.swift`; injectable `KeychainHelper` with test-scoped service name.

### REP-257 — SlackChannel: `messagesForThread(threadID:limit:)` via `conversations.history`
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/SlackChannel.swift` (extends REP-234), `Tests/ReplyAITests/SlackChannelTests.swift`
- scope: **Pivot-aligned (Slack first-class, prereq: REP-237 + REP-242).** After `recentThreads()` populates the thread list, the inbox needs to fetch message history for a selected thread. Implement `SlackChannel.messagesForThread(threadID: String, limit: Int) async throws -> [Message]` using `SlackHTTPClient` (REP-237): `GET api/conversations.history?channel=<threadID>&limit=<limit>`. Parse `messages[]` array — each item has `text`, `user`, `ts` (Unix timestamp as string). Build `Message` with `body: text`, `sender: user`, `sentAt: Date(timeIntervalSince1970: Double(ts))`, `channel: .slack`. Tests: mock client returning 3-message history JSON → `[Message]` with correct fields; empty messages array → `[]`; `ts` string parses to correct Date; no token → `authorizationDenied`; HTTP error → `ChannelError.networkError`.
- success_criteria:
  - `SlackChannel.messagesForThread(threadID:limit:) async throws -> [Message]` implemented
  - Injectable `SlackHTTPClient` (same seam as `recentThreads`)
  - `testSlackMessagesForThreadParsesHistoryResponse` — 3-message JSON → `[Message]`
  - `testSlackMessagesForThreadEmptyHistoryReturnsEmpty` — empty messages array → `[]`
  - `testSlackMessagesForThreadTimestampParsedCorrectly` — `ts` string → correct `Date`
  - `testSlackMessagesForThreadNoTokenThrows` — no Keychain token → `authorizationDenied`
  - Existing SlackChannelTests remain green
- test_plan: 4 new tests in `SlackChannelTests.swift`; mock `SlackHTTPClient` returns configured JSON Data.

### REP-260 — WhatsAppChannel: ChannelService conformance stub with session token gate
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-031929
- blocker: code complete on wip/2026-04-24-031929-channel-stubs (+74 LOC source, 3 tests, bundled with REP-261/264/243); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Channels/WhatsAppChannel.swift` (new), `Tests/ReplyAITests/WhatsAppChannelTests.swift` (new)
- scope: **Pivot-aligned (non-iMessage channel scaffolding).** Mirror of REP-256 (Telegram) and REP-233/234 (Slack). `WhatsAppChannel: ChannelService` in a new file. Injectable `KeychainHelper(service: "ReplyAI-WhatsApp")`. `recentThreads()` throws `ChannelError.authorizationDenied` when no session token present; returns `[]` stub when token present. `send()` throws `ChannelError.unsupported` (real send comes in a follow-up). `channel` property returns `.whatsapp` (requires REP-243 adds the case, or add the case here). Tests: no token → `authorizationDenied`; token present → `[]` (stub); `channel` property returns `.whatsapp`.
- success_criteria:
  - `WhatsAppChannel: ChannelService` in new file
  - `recentThreads()` throws `authorizationDenied` when no Keychain entry
  - `testWhatsAppChannelThrowsWhenNoToken` — no Keychain entry → `authorizationDenied`
  - `testWhatsAppChannelReturnsEmptyWithToken` — token present → `[]` (stub)
  - `testWhatsAppChannelPropertyReturnsWhatsApp` — `channel == .whatsapp`
  - Existing tests remain green
- test_plan: 3 new tests in `WhatsAppChannelTests.swift`; injectable `KeychainHelper` with test-scoped service name.

### REP-261 — TeamsChannel: ChannelService conformance stub with Graph API token gate
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-031929
- blocker: code complete on wip/2026-04-24-031929-channel-stubs (+74 LOC source, 3 tests, bundled with REP-260/264/243); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Channels/TeamsChannel.swift` (new), `Tests/ReplyAITests/TeamsChannelTests.swift` (new)
- scope: **Pivot-aligned (non-iMessage channel scaffolding).** Mirror of REP-256 (Telegram) for Microsoft Teams. `TeamsChannel: ChannelService` in a new file. Injectable `KeychainHelper(service: "ReplyAI-Teams")`. `recentThreads()` throws `ChannelError.authorizationDenied` when no Graph API token present; returns `[]` stub when token present. `send()` throws `ChannelError.unsupported`. `channel` property returns `.teams` (requires REP-243 adds the case, or add the case here). Tests: no token → `authorizationDenied`; token present → `[]` (stub); `channel` property returns `.teams`.
- success_criteria:
  - `TeamsChannel: ChannelService` in new file
  - `recentThreads()` throws `authorizationDenied` when no Keychain entry
  - `testTeamsChannelThrowsWhenNoToken` — no Keychain entry → `authorizationDenied`
  - `testTeamsChannelReturnsEmptyWithToken` — token present → `[]` (stub)
  - `testTeamsChannelPropertyReturnsTeams` — `channel == .teams`
  - Existing tests remain green
- test_plan: 3 new tests in `TeamsChannelTests.swift`; injectable `KeychainHelper` with test-scoped service name.

### REP-262 — ShortcutsExportHandler: URL scheme handler for manual iMessage export via Shortcuts.app
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/ShortcutsExportHandler.swift` (new), `Sources/ReplyAI/App/ReplyAIApp.swift`, `Tests/ReplyAITests/ShortcutsExportHandlerTests.swift` (new)
- scope: **Pivot-aligned (alt message-source, no FDA required).** Shortcuts.app can export recent iMessage threads as JSON via a user-triggered shortcut; ReplyAI registers a URL scheme handler to receive that data. `ShortcutsExportHandler` registers for `replyai://import-messages` URL scheme callbacks (via `NSApplication.EventType.openURLs` / `onOpenURL` in SwiftUI Scene). Parses the URL's `data` query parameter (percent-encoded JSON) into `[MessageThread]`. Schema: `[{"id": String, "displayName": String, "preview": String, "channel": "iMessage", "messages": [...]}]`. Injectable URL parser for tests. Returns `[MessageThread]` on success; throws `ShortcutsExportError.malformedPayload` on bad JSON. `ReplyAIApp` wires `onOpenURL` to pass the URL to `ShortcutsExportHandler`; handler calls `InboxViewModel.injectThreads(_:)` (REP-244 provides the multi-source architecture). No FDA required — user triggers the Shortcut manually. Tests: valid JSON URL → `[MessageThread]` with correct fields; malformed JSON → `malformedPayload` error; missing `data` param → `malformedPayload`; empty messages array → thread with empty messages.
- success_criteria:
  - `ShortcutsExportHandler.parse(url:) throws -> [MessageThread]` implemented
  - `ShortcutsExportError.malformedPayload` error case
  - URL scheme `replyai://import-messages` handled in `ReplyAIApp`
  - `testValidJSONPayloadParsesThreads` — correct JSON → `[MessageThread]`
  - `testMalformedJSONThrowsMalformedPayload` — bad JSON → `malformedPayload`
  - `testMissingDataParamThrows` — URL with no `data` param → `malformedPayload`
  - `testEmptyMessagesArrayProducesThreadWithNoMessages` — empty messages → thread with `messages: []`
  - Existing tests remain green
- test_plan: 4 new tests in `ShortcutsExportHandlerTests.swift`; pass literal URL strings to `parse(url:)`; no real URL scheme registration in tests.

### REP-264 — SMSChannel: ChannelService conformance stub with CloudKit relay gate
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-031929
- blocker: code complete on wip/2026-04-24-031929-channel-stubs (+74 LOC source, 3 tests, bundled with REP-260/261/243); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Channels/SMSChannel.swift` (new), `Tests/ReplyAITests/SMSChannelTests.swift` (new)
- scope: **Pivot-aligned (non-iMessage channel scaffolding).** Mirror of REP-256 (Telegram) and REP-260/261 (WhatsApp/Teams). `SMSChannel: ChannelService` in a new file. SMS relay via CloudKit from iPhone is a future feature; stub the plumbing now. Injectable `KeychainHelper(service: "ReplyAI-SMS")`. `recentThreads()` throws `ChannelError.authorizationDenied` when no relay token present; returns `[]` stub when token present. `send()` throws `ChannelError.unsupported`. `channel` property returns `.sms` — add this case to `Channel` enum if REP-243 not yet merged. Tests: no token → `authorizationDenied`; token present → `[]` (stub); `channel` property returns `.sms`.
- success_criteria:
  - `SMSChannel: ChannelService` in new file
  - `recentThreads()` throws `authorizationDenied` when no Keychain entry
  - `testSMSChannelThrowsWhenNoToken` — no Keychain entry → `authorizationDenied`
  - `testSMSChannelReturnsEmptyWithToken` — token present → `[]` (stub)
  - `testSMSChannelPropertyReturnsSMS` — `channel == .sms`
  - Existing tests remain green
- test_plan: 3 new tests in `SMSChannelTests.swift`; injectable `KeychainHelper` with test-scoped service name.

### REP-267 — SlackSocketClient: injectable WebSocket wrapper for Slack Socket Mode real-time event stream
- priority: P1
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-114653
- blocker: code complete on wip/2026-04-24-114653-slack-socket-client; MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` locally and merge if green
- files_to_touch: `Sources/ReplyAI/Channels/SlackSocketClient.swift` (new), `Tests/ReplyAITests/SlackSocketClientTests.swift` (new)
- scope: **Pivot-aligned (real-time Slack updates without polling).** Slack Socket Mode pushes new messages over `wss://` WebSocket from a URL obtained via `apps.connections.open`. `SlackSocketClient(connectionURL: URL, urlSession: URLSession = .shared, reconnectDelay: TimeInterval = 5.0)`: `start()` creates `URLSessionWebSocketTask` and starts receiving. `stop()` cancels task. `onEventReceived: ((Data) -> Void)?` fires for each non-control frame. Envelope filter: silently drop `{"type":"ping"}` and `{"type":"hello"}`; forward only `{"type":"events_callback",...}`. Auto-reconnects up to 3 times on `.abnormalClosure` or `.goingAway` using injectable `reconnectDelay`. Tests: mock WebSocket task delivers `events_callback` message → `onEventReceived` called; `stop()` cancels task; abnormal close → reconnect attempted (count ≤3 with injected 0s delay); `hello` message → callback not fired; fourth disconnect after 3 reconnects → no further reconnect.
- success_criteria:
  - `SlackSocketClient(connectionURL:urlSession:reconnectDelay:)` in new file
  - `start()` and `stop()` methods
  - `onEventReceived: ((Data) -> Void)?` callback property
  - Auto-reconnect up to 3 times after abnormal close
  - `testSlackSocketClientDeliversEventCallbackToHandler` — `events_callback` message → `onEventReceived` fires
  - `testSlackSocketClientStopCancelsTask` — `stop()` cancels WebSocket task
  - `testSlackSocketClientReconnectsOnAbnormalClose` — abnormal close → reconnect attempted
  - `testSlackSocketClientDropsHelloAndPingMessages` — `hello`/`ping` types not forwarded
  - `testSlackSocketClientStopsReconnectAfterThreeAttempts` — 4th disconnect → no reconnect
  - Existing tests remain green
- test_plan: 5 new tests in `SlackSocketClientTests.swift`; use injectable `MockURLSession` with `MockWebSocketTask` that allows manual message delivery and close state control.

### REP-272 — SlackChannel: `authorize(clientID:clientSecret:completion:)` wiring to SlackOAuthFlow
- priority: P1
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/SlackChannel.swift`, `Tests/ReplyAITests/SlackChannelTests.swift`
- scope: **Pivot-aligned (Slack first-class — prereq: REP-266 merged).** `SlackChannel` currently throws `authorizationDenied` for all calls when no token present. Add `authorize(clientID: String, clientSecret: String, completion: @escaping (Result<Void, OAuthError>) -> Void)` that delegates to a `SlackOAuthFlow` instance. Injectable `SlackOAuthFlowFactory: (String, String) -> SlackOAuthFlow` for test isolation. On success: token now in Keychain, completion called with `.success(())`; subsequent `recentThreads()` calls return real data. On failure: completion called with `.failure(error)`. Idempotent: a second `authorize` call while one is in-flight invokes the completion via the existing flow (no double-listener bind). Tests: factory called with correct `clientID` + `clientSecret`; success completion called when flow returns success; failure completion called when flow returns failure.
- success_criteria:
  - `SlackChannel.authorize(clientID:clientSecret:completion:)` method added
  - Injectable `SlackOAuthFlowFactory` protocol for test isolation
  - `testAuthorizeCallsOAuthFlowWithCorrectCredentials` — factory receives correct clientID + clientSecret
  - `testAuthorizeSuccessCompletionCalled` — flow success → completion `.success`
  - `testAuthorizeFailureCompletionCalled` — flow failure → completion `.failure`
  - Existing SlackChannelTests remain green
- test_plan: 3 new tests in `SlackChannelTests.swift`; inject mock `SlackOAuthFlowFactory` delivering configured results.

### REP-273 — Settings: Slack "Connect Workspace" button — UI trigger for SlackChannel.authorize()
- priority: P1
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Screens/Settings/` (existing settings screens), `Sources/ReplyAI/Channels/SlackChannel.swift`
- scope: **Pivot-aligned (Slack UX, prereq: REP-272).** Add a "Channels" section to the Settings screen. The Slack row shows "Connect Workspace" button when no token is stored; shows "Connected: <workspace name>" + a "Disconnect" button when connected (workspace name from `SlackTokenStore`, REP-274). Tapping "Connect Workspace" calls `SlackChannel.authorize(clientID:clientSecret:)` — credentials from `Preferences.slack.clientID/clientSecret` (hard-coded constants for now, Preferences keys in a follow-up). Shows a progress spinner during OAuth. Shows an inline error label on failure with a retry option. UI-sensitive → worker pushes to `wip/` branch. Human reviews layout and copy. Non-UI state transitions (connected/disconnected/loading/error) should be testable via an extracted ViewModel property.
- success_criteria:
  - `wip/` branch with Slack row in Settings channels section
  - "Connect Workspace" button visible when `SlackTokenStore.get() == nil`
  - "Connected: <name>" + "Disconnect" when token present
  - Loading indicator during OAuth flow
  - Inline error state with retry
  - Human reviews copy and layout before merge
- test_plan: Non-UI ViewModel state transitions (connected/disconnected/loading/error) extracted to unit tests; human validates UX in the preview.

### REP-274 — SlackTokenStore: structured Keychain wrapper for Slack access token + workspace name
- priority: P1
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-120000
- blocker: code complete on wip/2026-04-24-120000-viewstate-slacktokenstore (bundled with REP-247, +4 tests); MLX cold-build exceeds 13-min budget; human reviews via REP-275
- files_to_touch: `Sources/ReplyAI/Channels/KeychainHelper.swift` (extends REP-233), `Tests/ReplyAITests/KeychainHelperTests.swift`
- scope: **Pivot-aligned (Slack token management, prereq: REP-233).** The Slack OAuth `v2.access` response includes both `access_token` and `team.name` (workspace name for display). Storing only the token (as REP-266/272 currently does via raw `KeychainHelper.set`) loses the workspace name needed for Settings UI (REP-273). Add `struct SlackTokenStore` (in `KeychainHelper.swift` or a adjacent file): `set(token: String, workspaceName: String)` JSON-encodes and stores under `"slack-access-token"` key; `get() -> (token: String, workspaceName: String)?` retrieves and decodes; `delete()` removes the entry. `SlackOAuthFlow` (REP-266) and `SlackChannel.authorize()` (REP-272) should be updated to use `SlackTokenStore.set(...)` instead of raw `KeychainHelper.set`. Tests: round-trip through set/get preserves both fields; delete removes entry; missing entry returns nil; malformed JSON stored returns nil gracefully.
- success_criteria:
  - `SlackTokenStore.set(token:workspaceName:)`, `get()`, `delete()` implemented
  - `testSlackTokenStoreRoundTrip` — set then get returns same token + workspaceName
  - `testSlackTokenStoreDeleteRemovesEntry` — delete → get returns nil
  - `testSlackTokenStoreMissingEntryReturnsNil` — no prior set → nil
  - `testSlackTokenStoreMalformedJSONReturnsNil` — corrupt stored blob → nil, no crash
  - Existing KeychainHelperTests remain green
- test_plan: 4 new tests in `KeychainHelperTests.swift`; use injectable `KeychainHelper` with test-scoped service name.


---

## P2 — stretch / backlog depth

### REP-009 — Global `⌘⇧R` hotkey (needs Accessibility)
- priority: P1
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/GlobalHotkey.swift` (new), `Sources/ReplyAI/App/ReplyAIApp.swift`, `Sources/ReplyAI/Resources/Info.plist`
- scope: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` to catch `⌘⇧R` from anywhere. On match, `openWindow(id: "inbox")`. Needs `NSAccessibilityUsageDescription`. If Accessibility not granted, show a small banner in the inbox with a deep-link to System Settings. UI-sensitive (new banner surface) → branch-only, human merges.
- success_criteria: code lands on `wip/...` branch; human reviews banner copy + placement before merge.
- test_plan: unit-test the key-matching logic (NSEvent parsing of modifier+key tuples).

### REP-010 — Slack OAuth loopback (first non-iMessage channel)
- priority: P2
- effort: L
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/SlackChannel.swift` (new), `Sources/ReplyAI/Channels/Keychain.swift` (new), AGENTS.md
- scope: Build the `SlackChannel: ChannelService` impl. OAuth flow spins up a local `NWListener` on `:4242` during auth only, opens the Slack authorize URL via `NSWorkspace.shared.open`, captures the `code`, exchanges for token via `oauth.v2.access`, stores in Keychain under `ReplyAI-Slack-<workspace>`. `recentThreads` hits `conversations.list` + `conversations.history` with `prefer_socket_events=true`. Socket Mode for real-time comes in a follow-up.
- success_criteria: `wip/` branch — human reviews scope creep, merges when ready.
- test_plan: mock Slack API responses in tests; no real HTTP in CI.

### REP-043 — InboxViewModel: sync error state + inline error surface
- priority: P2
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Inbox/InboxScreen.swift`, `Sources/ReplyAI/Inbox/FDABanner.swift`
- scope: `syncFromIMessage()` currently swallows errors silently. If FDA is revoked mid-session or chat.db is inaccessible, the thread list silently stops updating. Expose `syncError: Error?` on `InboxViewModel`. In `InboxScreen`, render the existing `FDABanner` when the error is `ChannelError.authorizationDenied`, and a generic "sync paused — tap to retry" banner for other errors. Auto-clear `syncError` on the next successful sync. UI-sensitive → worker pushes to `wip/` branch. Human reviews banner copy + placement.
- success_criteria: `wip/` branch; human reviews error copy before merge.
- test_plan: `testSyncErrorExposedOnViewModel` (non-ui, auto-merge eligible if extracted).

### REP-044 — MenuBarContent: unread-thread count badge on menu-bar icon
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/MenuBar/MenuBarContent.swift`, `Sources/ReplyAI/App/ReplyAIApp.swift`
- scope: The `MenuBarExtra` currently shows just the `R` label. Add an unread-thread count badge (e.g. `Text("R (\(unread))")` or a `ZStack` overlay with a `Circle` + count label). Count comes from `InboxViewModel.threads.filter { $0.unread > 0 }.count`. Hide badge when count is 0. UI-sensitive → worker pushes to `wip/`. Human reviews icon treatment before merge.
- success_criteria: `wip/` branch; human reviews badge design.
- test_plan: N/A (view-only); human verifies dark-mode rendering.

### REP-045 — Stats: surface counters in set-privacy screen
- priority: P2
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Screens/Settings/SetPrivacyView.swift` (or equivalent), `Sources/ReplyAI/Services/Stats.swift`
- scope: The set-privacy screen (sfc-privacy gallery screen) is currently a stub. Wire `Stats.shared` counters into a real view: rules fired (total + by action), drafts generated vs sent, messages indexed. Rows styled to match the existing Settings screen design (plain list, `SectionLabel` headers, `KbdChip` for counts). UI-sensitive → worker pushes to `wip/`. Human reviews copy and layout before merge.
- success_criteria: `wip/` branch; human reviews stats layout.
- test_plan: N/A (view-only with live Stats data).

### REP-046 — InboxViewModel: optimistic send UI state
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Inbox/Composer/ComposerView.swift`
- scope: After `send(thread:)` returns, the composer continues showing the draft until the watcher fires (up to 600ms). Add an optimistic clear: on send success, immediately clear the draft in `InboxViewModel` and show a brief "Sent ✓" state in the composer before the next sync. Use `Task.sleep(for: .seconds(1.5))` then reset to idle. UI-sensitive → `wip/`. Human reviews the "Sent ✓" microcopy and animation timing.
- success_criteria: `wip/` branch; human reviews copy + timing.
- test_plan: Non-ui logic (clear on success, reset after delay) extractable for unit test in InboxViewModelTests.

### REP-047 — Sidebar: relative-time chip auto-tick every 10s
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/Sidebar/SidebarView.swift` (or `ThreadRow.swift`)
- scope: The "live · 12s ago" relative-time chip in the sidebar renders once on thread-select and doesn't update. Add a `Timer.publish(every: 10, on: .main, in: .common).autoconnect()` in the thread row view (or sidebar view model) so the time string refreshes every 10 seconds. Use `@Environment(\.date)` or a published `Date` to drive re-rendering. UI-sensitive → `wip/`. Human reviews the tick frequency and whether it causes observable CPU overhead.
- success_criteria: `wip/` branch; human reviews before merge.
- test_plan: N/A (view timer); human verifies chip auto-updates without scroll jitter.

### REP-062 — human: product-copy pass on IMessagePreview sidebar sentinel strings
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: human
- files_to_touch: `Sources/ReplyAI/Channels/IMessagePreview.swift`
- scope: When REP-008 shipped the link + attachment preview feature, the worker chose `🔗 <host>` and `📎 Attachment` as the sentinel strings for link and attachment previews in `IMessagePreview`. These glyphs were explicitly flagged by the worker for human review (not asserted as final copy). Human should decide: (1) whether `🔗` and `📎` are the right glyphs vs alternatives (`↗`, `⊞`, `📸`, plain text); (2) whether `"Attachment"` is the right noun vs `"Media"` / `"Photo"` / `"File"`; (3) whether the space before the host name in `🔗 example.com` should be an en-space for visual rhythm. Note: after REP-068 lands, the `📎` sentinel no longer drives rule logic — only display. This is a product-copy decision, not a code question — update the two sentinel constants in `IMessagePreview.swift` once decided.
- success_criteria:
  - `linkPreviewSentinel` and `attachmentPreviewSentinel` constants reflect the decided copy
  - Existing tests updated if the sentinel strings change
  - Reviewer no longer flags this as an open human-review item
- test_plan: Human updates the constants; worker updates the 3 test assertions in `IMessageChannelPreviewTests.swift` that match against the sentinel strings.



### REP-075 — AttributedBodyDecoder: nested NSMutableAttributedString payload handling
- priority: P2
- effort: M
- ui_sensitive: false
- status: deprioritized
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/AttributedBodyDecoder.swift`, `Tests/ReplyAITests/AttributedBodyDecoderTests.swift`
- scope: AGENTS.md "Better AttributedBodyDecoder" (priority queue item #4) notes that the current 0x2B tag scanner misses nested `NSMutableAttributedString` payloads — common for link previews, app clips, and collaborative iMessage features added in iOS 16+. A nested payload wraps the primary `NSAttributedString` inside another attributed string object graph. Extend the scanner to recognise the class-ref sequence for `NSMutableAttributedString` (byte signature differs from `NSAttributedString`) and recurse into the inner blob's UTF-8 extraction. Add hand-crafted hex fixtures representing the nested case (synthesize a minimal valid typedstream; document the byte layout). Tests: nested payload returns correct inner text; previously-passing single-level payloads remain correct; malformed nested blob returns nil.
- success_criteria:
  - Nested `NSMutableAttributedString` payload decoded correctly
  - `testNestedPayloadExtractsInnerText`
  - `testSingleLevelPayloadUnchanged`
  - `testMalformedNestedPayloadReturnsNil`
  - All existing AttributedBodyDecoderTests remain green
- test_plan: Extend `AttributedBodyDecoderTests.swift` with 3 new hex-fixture cases.

### REP-082 — ThreadRow: selection highlight bar animation with matchedGeometryEffect
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/ThreadList/ThreadRow.swift`, `Sources/ReplyAI/Inbox/ThreadList/ThreadListView.swift`
- scope: From AGENTS.md priority queue #2: animate the selected-row accent `Rectangle().fill(isSelected ? accent : .clear)` using `withAnimation(Theme.Motion.std)` and `matchedGeometryEffect` so the highlight slides between rows rather than snapping. The `Namespace` lives in `ThreadListView`; the matched ID is the thread `id`. `ThreadRow` receives `isSelected: Bool` and `animationNamespace: Namespace.ID`. Reduced-motion guard: `ThreadListView` reads `@Environment(\.accessibilityReduceMotion)` and passes a flag to skip the `.matchedGeometryEffect` and use `.animation(nil)` instead. UI-sensitive → worker pushes to `wip/`. Human reviews animation timing and reduced-motion skip before merge.
- success_criteria: `wip/` branch; human reviews animation feel and reduced-motion skip.
- test_plan: N/A (animation, view-only); human verifies no jitter on fast row changes.

### REP-083 — ComposerView + PillToggle: respect accessibilityReduceMotion
- priority: P2
- effort: S
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/Composer/ComposerView.swift`, `Sources/ReplyAI/Components/PillToggle.swift`
- scope: From AGENTS.md priority queue #2: read `@Environment(\.accessibilityReduceMotion)` in `ComposerView` and skip the `withAnimation` crossfade on `editableDraft` appear/disappear when true. Read the same in `PillToggle` (used for tone pills) and skip the spring animation on selection change when true. No logic changes — only the animation modifier is conditionalised. UI-sensitive → worker pushes to `wip/`. Human verifies under System Preferences > Accessibility > Reduce Motion.
- success_criteria: `wip/` branch; human verifies animations skip cleanly under Reduce Motion.
- test_plan: N/A (view-only environment flag); no unit test needed.

### REP-111 — InboxViewModel: snooze thread action + resumption
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Sources/ReplyAI/Models/MessageThread.swift` (or equivalent), `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: The gallery has a `sfc-snooze` screen with a snooze-duration picker. Add the underlying ViewModel action: `snooze(thread: MessageThread, until: Date)`. This sets `thread.snoozedUntil = until`, adds the thread ID to a `snoozedThreadIDs: Set<String>` persisted in Preferences (`pref.inbox.snoozedThreadIDs`), and removes the thread from the `threads` display array. A `Task.sleep(until: date, clock: .continuous)` is started that re-inserts the thread when it wakes. UI that triggers this (the snooze picker view) is ui_sensitive and handled separately. Tests: `testSnoozedThreadHiddenFromList` — snooze a thread, assert it's absent from `threads`; `testSnoozedThreadResurfacesAfterExpiry` — use a mock clock (pass `wakeDate` in the near past) to verify re-insertion; `testSnoozeSetPersistedAcrossInit` — verify `pref.inbox.snoozedThreadIDs` is written.
- success_criteria:
  - `InboxViewModel.snooze(thread:until:)` implemented
  - Snoozed threads hidden from `threads` array
  - Resumption timer re-inserts thread
  - `pref.inbox.snoozedThreadIDs` Preferences key for persistence
  - `testSnoozedThreadHiddenFromList`, `testSnoozedThreadResurfacesAfterExpiry`, `testSnoozeSetPersistedAcrossInit`
- test_plan: Extend `InboxViewModelTests.swift` with 3 new cases; use injected `Date` for deterministic timer tests.




### REP-129 — SmartRule: `threadNameMatchesRegex(pattern:)` predicate
- priority: P2
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-130000
- blocker: MLX full build on fresh clone exceeded time budget; implementation complete on wip/2026-04-23-130000-thread-name-regex; human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Screens/Surfaces/SfcRulesView.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: The predicate DSL has `textMatchesRegex(pattern:)` for message body, but no way to match against the thread's display name or sender handle. Add `case threadNameMatchesRegex(pattern: String)` to `RulePredicate`. `RuleContext` gains `threadDisplayName: String` (from `MessageThread.displayName` or equivalent). `RuleEvaluator` evaluates using `NSRegularExpression` with the same validation path as `textMatchesRegex`. `SfcRulesView.humanize(predicate:)` switch gets a new case string. Codable discriminator: `"threadNameMatchesRegex"`. Tests: pattern matching display name matches; non-matching display name doesn't; invalid regex throws at creation time; Codable round-trip preserves pattern.
- success_criteria:
  - `RulePredicate.threadNameMatchesRegex(pattern:)` case added and Codable
  - `RuleContext.threadDisplayName` field populated from thread
  - `RuleEvaluator` evaluates via NSRegularExpression
  - `SfcRulesView` exhaustive switch updated
  - `testThreadNameMatchesRegexWhenMatching`, `testThreadNameMatchesRegexWhenNotMatching`, `testThreadNameInvalidRegexThrows`, `testThreadNameMatchesRegexCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift` in a `ThreadNameMatchesRegexTests` class.


### REP-135 — Stats: sessionStartedAt timestamp and sessionDuration computed field
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; implementation on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: Add `sessionStartedAt: Date` (set in `Stats.init` to `Date()`) and a computed `sessionDuration: TimeInterval` (= `Date().timeIntervalSince(sessionStartedAt)`). Include `sessionDuration` in the weekly log JSON written by `writeWeeklyLog()` alongside existing counters. No disk persistence for this field (it resets per session by design). Injectable `nowProvider: () -> Date` (default `{ Date() }`) for deterministic tests. Tests: `testSessionStartedAtApproximatelyNow` — initialized within 1s of `Date()`; `testSessionDurationIsNonNegative` — computed field ≥ 0; `testSessionDurationIncludesInWeeklyLog` — JSON from `writeWeeklyLog()` contains `"sessionDuration"` key.
- success_criteria:
  - `Stats.sessionStartedAt: Date` set on init
  - `Stats.sessionDuration: TimeInterval` computed property
  - `sessionDuration` included in weekly log JSON
  - `testSessionStartedAtApproximatelyNow`, `testSessionDurationIsNonNegative`, `testSessionDurationIncludesInWeeklyLog`
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using isolated `Stats` instance (nil URL).








### REP-162 — IMessageSender: extract GUID validation to per-channel protocol method
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/ChannelService.swift`, `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: `IMessageSender.isValidChatGUID(_:)` is currently iMessage-only (validates the `iMessage;[+-];...` prefix). Reviewer noted this guard will need to widen when SMS or other channels add write capability. Refactor: move `isValidChatGUID` to a `static func validateChatGUID(_ guid: String, for channel: Channel) throws` on `IMessageSender`, and add a comment documenting the extension point for future channels. The iMessage validation logic is unchanged — same regex, same `SenderError.invalidChatGUID` throw. SMS path validates that the GUID matches `SMS;[+-];...` format (not yet enforced since SMS send is not wired, but the structure is ready). Tests: existing `isValidChatGUID` tests migrate to `validateChatGUID(for: .iMessage)`; new test `testSMSGUIDFormatRecognized` verifies the SMS branch doesn't throw for a well-formed SMS GUID; `testWrongChannelGUIDThrows` confirms an iMessage GUID passed with `.slack` channel throws. No behavior change for the iMessage path.
- success_criteria:
  - `IMessageSender.validateChatGUID(_:for:)` replaces `isValidChatGUID(_:)` (existing callers updated)
  - iMessage path: identical validation to prior behavior
  - SMS path: `SMS;[+-];...` passes, everything else throws
  - `testSMSGUIDFormatRecognized` — well-formed SMS GUID passes SMS validation
  - `testWrongChannelGUIDThrows` — iMessage GUID on non-iMessage channel throws
  - All existing `IMessageSenderTests` remain green
- test_plan: Migrate existing chatGUID validation tests to new API; add 2 new cross-channel tests.

### REP-163 — DraftStore: `listStoredDraftIDs()` method + orphan detection test
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Sources/ReplyAI/Services/DraftStore.swift`, `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: Add `listStoredDraftIDs() -> [String]` to `DraftStore`. It reads the drafts directory and returns the stem of every `.md` file (each stem is a thread ID). Useful for future "your drafts" UI and detecting orphaned entries whose threads have been deleted. Tests: empty store returns `[]`; after saving 3 drafts returns all 3 IDs; after deleting one draft, that ID is absent from the list; listing is order-independent.
- success_criteria:
  - `DraftStore.listStoredDraftIDs() -> [String]` implemented
  - `testListStoredDraftIDsEmpty` — empty store returns `[]`
  - `testListStoredDraftIDsAfterSave` — 3 saved drafts → 3 IDs returned
  - `testListStoredDraftIDsAfterDelete` — deleted draft ID absent from list
  - Existing DraftStoreTests remain green
- test_plan: 3 new tests in `DraftStoreTests.swift` using temp directory URL injection.

### REP-164 — IMessageChannel: per-thread message pagination with `before:` rowID cursor
- priority: P2
- effort: M
- ui_sensitive: false
- status: deprioritized
- claimed_by: null
- blocker: "pivot: new chat.db SQL queries banned per AGENTS.md strategic direction"
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `messages(forThreadID:limit:)` currently fetches the N most-recent messages. Add an overload `messages(forThreadID:limit:before:)` where `before: Int64?` is an optional SQLite ROWID cursor. When non-nil the SQL WHERE clause includes `message.ROWID < before`, enabling "load older" pagination. The existing overload delegates to `before: nil` for backward compatibility. Tests: messages returned all have `ROWID < before`; `before: nil` matches current behavior; fewer than limit available returns all; `before` equal to minimum ROWID in DB returns empty.
- success_criteria:
  - `messages(forThreadID:limit:before:)` overload added
  - Existing overload delegates to `before: nil`
  - `testMessagesBeforeCursorFiltersCorrectly` — returned messages have rowID < before
  - `testMessagesPaginationNilCursorMatchesCurrent` — nil cursor identical to legacy call
  - `testMessagesPaginationReturnsAllWhenUnderLimit` — fewer than limit → all returned
  - `testMessagesPaginationAtMinRowIDReturnsEmpty` — before=minROWID → empty
  - Existing IMessageChannelTests remain green
- test_plan: 4 new tests in `IMessageChannelTests.swift` using multi-message in-memory SQLite fixture.







### REP-170 — SmartRule: `contactGroupMatchesName(groupName:)` predicate
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Channels/ContactsResolver.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Add `case contactGroupMatchesName(groupName: String)` to `RulePredicate`. `RuleContext` gains `contactGroupNames: [String]` (contact group names for the sender's handle, resolved via `CNContactStore.groups(matching:)` in `ContactsResolver`). `RuleEvaluator` evaluates using `context.contactGroupNames.contains { $0.localizedCaseInsensitiveContains(groupName) }`. Codable discriminator: `"contactGroupMatchesName"`. `SfcRulesView.humanize` gets a new case string. Tests: matching group name matches; non-matching group name doesn't; case-insensitive match; Codable round-trip preserves groupName; empty contactGroupNames returns false.
- success_criteria:
  - `RulePredicate.contactGroupMatchesName(groupName:)` case added and Codable
  - `RuleContext.contactGroupNames: [String]` field
  - `RuleEvaluator` case-insensitive contains check
  - `SfcRulesView.humanize` updated
  - `testContactGroupMatchesWhenGroupPresent`, `testContactGroupNoMatchWhenGroupAbsent`, `testContactGroupCaseInsensitive`, `testContactGroupMatchesCodableRoundTrip`, `testContactGroupEmptyGroupsReturnsFalse`
  - Existing RulesTests remain green
- test_plan: 5 new tests in `RulesTests.swift`; mock `contactGroupNames` in `RuleContext` directly without CNContactStore.






### REP-177 — Stats: overallAcceptanceRate() aggregate across all tone keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; implementation on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Sources/ReplyAI/Services/Stats.swift`, `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.acceptanceRate(for tone:)` gives per-tone rates. A UI surface (e.g. set-privacy screen) may want an aggregate across all tones. Add `Stats.overallAcceptanceRate() -> Double?` that returns `nil` if no drafts generated across any tone, or `Double(totalSent) / Double(totalGenerated)` aggregating across all tone counters. Tests: fresh instance → nil; 3 generated across 2 tones, 1 sent → 0.333...; all generated but none sent → 0.0.
- success_criteria:
  - `Stats.overallAcceptanceRate() -> Double?` added
  - `testOverallAcceptanceRateNilWhenNoData` — nil on fresh instance
  - `testOverallAcceptanceRateAggregatesAcrossTones` — total sent / total generated
  - `testOverallAcceptanceRateZeroWhenGeneratedButNoneSent` — 0.0 not nil
  - Existing StatsTests remain green
- test_plan: 3 new tests in `StatsTests.swift` using isolated `Stats(statsFileURL: nil)`.

### REP-178 — InboxViewModel: pin state persists to Preferences across re-init
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `InboxViewModel.pinThread` sets a flag that causes the thread to sort above others. Verify the pin state persists through Preferences so it survives an app relaunch. Test: pin a thread in one ViewModel instance with an injectable `UserDefaults` suite; create a second ViewModel from the same defaults; assert the thread is still marked pinned and appears at the top of the sorted list. Also pin: unpinThread removes from `pinnedIDs` and thread drops from pinned position.
- success_criteria:
  - `testPinStatePersistsThroughReInit` — pinned thread still at top after ViewModel re-init from same UserDefaults
  - `testUnpinRemovesFromPinnedSet` — unpinned thread no longer pinned after reinit
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift` using suiteName-isolated `UserDefaults`.

### REP-179 — RuleEvaluator: equal-priority rules maintain deterministic evaluation order
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; tests on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RuleEvaluator.matching(rules:context:)` sorts by priority descending. When two rules have the same priority, the output order should be deterministic (insertion order preserved, not arbitrary). Test: two rules at priority 0, inserted A then B; matching returns `[A, B]` (insertion order). Also test with priority 5 and 5: same result. This guards against a future `sort` → `stableSort` rollback. No production code changes expected if insertion order is already preserved.
- success_criteria:
  - `testEqualPriorityRulesPreserveInsertionOrder` — two rules at same priority return in insertion order
  - `testEqualPriorityDeterministicOnMultipleCalls` — calling matching() twice returns identical order
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift`; fabricate two rules with identical priority and different UUIDs.


### REP-183 — Preferences: wipeReplyAIDefaults skips firstLaunchDate and launchCount (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; tests on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift`
- scope: REP-130 and REP-115 added `firstLaunchDate` and `launchCount` as wipe-exempt keys. Verify the exemption is enforced: call `wipe()` after setting both values; assert both survive. This pins the `wipeExemptions` set as a regression guard — if the exemption list is accidentally cleared, this test fails. Also test: non-exempt keys ARE wiped (e.g. `autoPrimeEnabled` returns default after wipe). No production code changes expected.
- success_criteria:
  - `testWipePreservesFirstLaunchDate` — `firstLaunchDate` non-nil after wipe
  - `testWipePreservesLaunchCount` — `launchCount` retains value after wipe
  - `testWipeClearsNonExemptKey` — a non-exempt preference key returns default after wipe
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated `UserDefaults`.


### REP-187 — Stats: snapshot() values are JSON-serializable without throwing
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-085959
- blocker: MLX full build on fresh clone exceeded time budget; tests on wip/2026-04-23-085959-stats-session-acceptance
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.snapshot()` returns `[String: Any]`. This dictionary is passed to `JSONSerialization.data(withJSONObject:)` by `writeWeeklyLog()`. If any value type is not JSON-serializable (e.g. a `Date` object, a struct), `writeWeeklyLog` will silently fail or crash at the `try?` call site. Pin the contract: `JSONSerialization.isValidJSONObject(snapshot())` returns `true` for a freshly-initialized Stats instance; also for one with non-zero counters. No production code changes expected if the snapshot already uses only numbers/strings.
- success_criteria:
  - `testSnapshotIsValidJSONObject` — `JSONSerialization.isValidJSONObject(snapshot())` returns true
  - `testSnapshotWithCountersIsValidJSON` — snapshot with non-zero counters also passes JSON validation
  - Existing StatsTests remain green
- test_plan: 2 new tests in `StatsTests.swift` using isolated `Stats(statsFileURL: nil)` with incremented counters.



### REP-190 — InboxViewModel: thread sort stability — same-timestamp threads don't swap order
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: When two threads share the same `lastMessageDate`, the sort should be stable (threads don't arbitrarily swap positions between syncs). Test: add threads A and B with identical timestamps; sync multiple times; assert A always appears before B (using thread IDs as tiebreaker or creation order). Unstable sort is user-visible as jumping rows in the thread list during live sync.
- success_criteria:
  - `testEqualTimestampThreadsSortStably` — threads with same timestamp don't reorder across syncs
  - `testEqualTimestampSortUsesIdAsSecondaryKey` — tiebreaker is thread ID (deterministic)
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; use `StaticMockChannel` with two threads sharing a timestamp.


### REP-193 — IMessageSender: 4096-char boundary — 4096 succeeds, 4097 throws
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-064 added a 4096-char message length guard in `IMessageSender.send()`. Pin the boundary: a 4096-char ASCII message sends (no throw); a 4097-char message throws `SenderError.messageTooLong`. Also: a 4096-char message composed of multi-byte Unicode chars (emoji) uses Swift `String.count` (char count), not byte count — verify a 10-emoji string that is >4096 bytes but <4096 chars passes. Uses the injectable `executeHook` seam — no real AppleScript.
- success_criteria:
  - `testMessageAtExactLimitSucceeds` — 4096-char ASCII message sends without throw
  - `testMessageOverLimitThrows` — 4097-char message throws `messageTooLong`
  - `testMultiByteCharsUseCharCount` — 10-emoji string (>4096 bytes, <4096 chars) passes
  - Existing IMessageSenderTests remain green
- test_plan: 3 new tests in `IMessageSenderTests.swift` using dry-run hook.

### REP-194 — Preferences: threadLimit clamped to valid range [1, 200]
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: `pref.inbox.threadLimit` is used as a SQL LIMIT clause. If stored as 0, negative, or an unreasonably large value, the query produces no results or hangs on very large result sets. Add a computed getter that clamps the raw stored value to `max(1, min(200, rawValue))`. The setter writes the raw value as-is (clamping happens at read time). Tests: raw value -1 → getter returns 1; raw value 0 → getter returns 1; raw value 201 → getter returns 200; raw value 50 → getter returns 50; raw value 200 → getter returns 200.
- success_criteria:
  - `Preferences.threadLimit` getter clamps raw value to [1, 200]
  - `testThreadLimitClampsNegativeToOne` — -1 → 1
  - `testThreadLimitClampsZeroToOne` — 0 → 1
  - `testThreadLimitClampsOverMaxToMax` — 201 → 200
  - `testThreadLimitPassesThroughValidValue` — 50 → 50
  - Existing PreferencesTests remain green
- test_plan: 4 new tests in `PreferencesTests.swift` using injected `UserDefaults`.

### REP-195 — DraftEngine: dismiss on an unprimed thread is a silent no-op
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine.dismiss(threadID:tone:)` transitions a `.ready` draft to `.idle` and clears the `DraftStore` entry. If called on a `threadID` that was never primed (no cache entry at all), the call should silently return — no crash, no state change, no `DraftStore` delete attempted on a non-existent file. Tests: fresh engine, call `dismiss("never-primed-id", tone: .casual)`; assert no crash; assert state for that thread is `.idle`. Also test dismiss after prime → ready succeeds as usual.
- success_criteria:
  - `testDismissOnUnprimedThreadIsNoop` — no crash, state remains `.idle`
  - `testDismissAfterPrimeTransitionsToIdle` — normal dismiss path still works
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; first test requires no prior prime calls.

### REP-196 — SearchIndex: repeated search with unchanged index returns identical order
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: FTS5 BM25 ranking is deterministic for a fixed index state. Pin the contract: index 3 threads with different relevance levels for the query "hello"; search once → get order [A, B, C]; search again without any writes → get identical [A, B, C]. A third search after a no-op `upsert` of an unrelated thread also returns [A, B, C]. Unstable ordering would cause visible jump in ⌘K palette results.
- success_criteria:
  - `testRepeatedSearchReturnsSameOrder` — two identical searches on unchanged index return same order
  - `testSearchOrderStableAfterUnrelatedUpsert` — upsert of different thread doesn't reorder prior results
  - Existing SearchIndexTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift` using in-memory FTS5 with 3 seeded threads.


### REP-198 — IMessageChannel: threads with no messages are excluded from recentThreads
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-135355
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: `recentThreads(limit:)` joins `chat` and `message` tables. A chat with zero associated messages (draft group, invite pending) should not appear in the result. Test with in-memory SQLite fixture: one thread with 3 messages, one thread with 0 messages. Assert: only the thread with messages appears in the returned list. Also assert: the returned thread's `messageCount` equals 3 (not 0).
- success_criteria:
  - `testEmptyThreadExcludedFromRecentThreads` — thread with 0 messages not returned
  - `testThreadWithMessagesIncluded` — thread with messages returns with correct messageCount
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests in `IMessageChannelTests.swift` using in-memory SQLite fixture.


### REP-205 — SearchIndex: delete() removes thread from all subsequent queries (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-230824
- blocker: tests complete on wip/2026-04-23-230824-telegram-channel-tests (+58 LOC, 3 tests); MLX fresh-clone build time exceeded 13-min budget; human should run `swift test` and merge if green
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Index threads A ("hello world"), B ("hello swift"), C ("goodbye world"). Call `delete(threadID: B)`. Run 3 queries: "hello" (previously returned A+B → should now return only A); "swift" (previously returned B → should return empty); "goodbye" (should still return C unchanged). Guards against FTS5 soft-delete / rowid-reuse scenarios where a deleted thread resurfaces.
- success_criteria:
  - `testDeleteRemovesThreadFromSingleTermSearch` — "swift" returns empty after deleting B
  - `testDeleteDoesNotAffectOtherMatchingThreads` — "hello" still returns A after deleting B
  - `testDeleteDoesNotAffectUnrelatedThread` — "goodbye" still returns C
  - Existing SearchIndexTests remain green
- test_plan: 3 new tests in `SearchIndexTests.swift` using in-memory FTS5; set up 3 threads with known content.

### REP-206 — PromptBuilder: oldest messages dropped first when budget exceeded (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-23-230824
- blocker: tests complete on wip/2026-04-23-230824-telegram-channel-tests (+36 LOC, 2 tests); MLX fresh-clone build time exceeded 13-min budget; human should run `swift test` and merge if green
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: Build a list of 5 messages where combined length exceeds the 2000-char budget. Verify drop-oldest semantics: `message[0]` (oldest, first in array) must not appear in the built prompt; `message[4]` (newest) must appear. Also test: with exactly 2000 chars of messages (at budget boundary), all 5 messages survive. This pins the truncation direction so a future refactor can't accidentally flip to drop-newest.
- success_criteria:
  - `testOldestMessagesDroppedWhenOverBudget` — message[0] absent, message[4] present when over budget
  - `testAllMessagesPreservedAtExactBudget` — 2000-char total keeps all messages
  - Existing PromptBuilderTests remain green
- test_plan: 2 new tests in `PromptBuilderTests.swift`; fabricate messages with known lengths using String(repeating:).

### REP-207 — Preferences: autoPrime and autoApplyOnSync default to false in fresh suite (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Pin the safety defaults for `autoPrimeEnabled` and `autoApplyOnSync`. A fresh `Preferences` instance on an isolated `UserDefaults` suite (no prior writes) must return `false` for both. These flags control auto-send behavior: if they accidentally default to `true`, the app would auto-send replies to every incoming message without user confirmation. Regression guard against a config change that treats absence-as-true.
- success_criteria:
  - `testAutoPrimeDefaultsToFalse` — fresh suite → `autoPrimeEnabled == false`
  - `testAutoApplyOnSyncDefaultsToFalse` — fresh suite → `autoApplyOnSync == false`
  - Existing PreferencesTests remain green
- test_plan: 2 new tests in `PreferencesTests.swift` using suiteName-isolated `UserDefaults`; do not write any value before reading.

### REP-208 — SmartRule: double-negation `not(not(pred))` evaluates identically to pred (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-143143
- blocker: code complete on wip/2026-04-24-143143-prefs-channels-negation-concurrent (+8 tests: 3 REP-231, 3 REP-208, 2 REP-220); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: Verify predicate composition correctness: `not(not(senderIs("Alice")))` must match when `senderIs("Alice")` matches, and must not match when it doesn't. Test with two base predicates (a matching and a non-matching context). Also test: `not(not(not(pred)))` inverts correctly (equals `not(pred)`). Guards the `not` composition against a double-negation cancellation bug in the evaluator.
- success_criteria:
  - `testDoubleNegationMatchesWhenBaseMatches` — `not(not(senderIs("Alice")))` matches context with sender "Alice"
  - `testDoubleNegationMissesWhenBaseMisses` — same predicate misses context with sender "Bob"
  - `testTripleNegationInvertsBase` — `not(not(not(pred)))` equals `not(pred)` result
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift`; construct `RuleContext` directly with controlled sender field.

### REP-209 — InboxViewModel: unread count cleared to zero after selectThread (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-152614
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-076 wired mark-as-read on thread select. Pin the unread-clear contract: start with a thread at `unread: 3`; call `viewModel.selectThread(thread)`; assert `thread.unread == 0`. Also assert: the thread's position in `viewModel.threads` is unchanged after the unread update (no re-sort triggered by the unread change alone). Uses `StaticMockChannel` with a seeded thread.
- success_criteria:
  - `testSelectThreadClearsUnreadCount` — `thread.unread == 0` after selectThread
  - `testSelectThreadDoesNotResortList` — thread index in `threads` unchanged after unread clear
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; seed a thread with `unread: 3` via the mock channel fixture.


### REP-212 — InboxViewModel: `selectThread` seeds `userEdits` from DraftStore when stored draft exists (integration test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-066 ships `DraftStore` and its scope explicitly states "InboxViewModel.selectThread seeds `userEdits` from the store before the LLM re-primes, so the composer is populated immediately on app open." There is no integration test pinning this end-to-end path. Test: write a draft string to an injected temp `DraftStore` for thread ID "T1"; construct an `InboxViewModel` with that DraftStore injected; call `selectThread` with a thread whose ID is "T1"; assert `viewModel.userEdits == <stored string>` before the LLM prime completes. Also: a thread with no stored draft leaves `userEdits` empty on select.
- success_criteria:
  - `testSelectThreadSeedsUserEditsFromDraftStore` — stored draft string appears in `userEdits` after selectThread
  - `testSelectThreadWithNoStoredDraftLeavesUserEditsEmpty` — no stored draft → empty userEdits
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; inject `DraftStore(directoryURL: tempDir)` into ViewModel; write draft before constructing ViewModel.

### REP-213 — Stats: `rulesMatchedCount` increments by matched-rule count, not once per evaluation call (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/StatsTests.swift`
- scope: `Stats.rulesMatchedCount` is incremented in `InboxViewModel` at rule-evaluation time. Pin the per-match semantics: if 3 rules match a single thread evaluation, `rulesMatchedCount` must grow by 3 (not 1). If 0 rules match, the counter is unchanged. Uses `Stats(statsFileURL: nil)` with injected mock rule evaluator results. Guards against an implementation that calls `increment(.rulesMatchedCount)` once per `matching()` call regardless of match count.
- success_criteria:
  - `testRulesMatchedCountIncrementsPerMatchedRule` — 3 matching rules → count +3
  - `testRulesMatchedCountUnchangedOnZeroMatches` — 0 matching rules → count unchanged
  - Existing StatsTests remain green
- test_plan: 2 new tests in `StatsTests.swift`; use isolated `Stats` instance and direct counter manipulation.

### REP-214 — InboxViewModel: failed send preserves `userEdits` and surfaces `sendError` (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: The 2026-04-22-1603 review noted "error surfaced + `userEdits` preserved on failure" as shipped behavior for `InboxViewModel.send()`. Pin this with a regression test: use a throwing mock sender (via injectable `IMessageSender` seam) that always throws `SenderError.messageTooLong`. Call `send(thread:)`. Assert: (1) `viewModel.userEdits` retains its pre-send value; (2) a non-nil `sendError` is surfaced on the ViewModel. Also test the success path: successful send clears userEdits (optimistic clear, REP-046 scope). The throwing path is the regression guard.
- success_criteria:
  - `testFailedSendPreservesUserEdits` — `userEdits` unchanged after throwing send
  - `testFailedSendSurfacesSendError` — `sendError` non-nil after throwing send
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests using injectable `executeHook` seam that throws `messageTooLong`; no real AppleScript.

### REP-215 — SmartRule: `validateRegex` rejects invalid patterns and accepts valid ones (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-031 shipped `SmartRule.validateRegex(_:)` + `RulesStore.addValidating(_:)` + `RuleValidationError.invalidRegex`. These are correctness gates but coverage may be thin. Pin 4 boundary cases: (1) `"[invalid"` throws `.invalidRegex`; (2) `"^hello.*$"` is accepted (no throw); (3) `""` (empty pattern) is accepted — matches everything, which is intentional for "catch-all" rules; (4) `"(?P<name>x)"` (Python named group, unsupported in ICU) throws `.invalidRegex`. Guards the regex validation gate against silent bypass.
- success_criteria:
  - `testInvalidRegexThrowsAtCreation` — `"[invalid"` → `.invalidRegex` from `addValidating`
  - `testValidRegexAccepted` — `"^hello.*$"` → no throw
  - `testEmptyPatternAccepted` — `""` → no throw
  - `testUnsupportedRegexSyntaxThrows` — unsupported ICU syntax → `.invalidRegex`
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift` using isolated `RulesStore` with injected `UserDefaults`.

### REP-216 — DraftEngine: `regenerate(threadID:tone:)` for same tone reaches `.ready` again (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: REP-203 tests tone-change eviction on `regenerate`. This is the same-tone complement: prime thread X with `.casual` → wait for `.ready`. Call `regenerate(threadID: X, tone: .casual)`. Assert engine transitions back through `.priming` then reaches `.ready` again (new draft, same tone). A `StubLLMService` with a configurable second chunk set can verify the draft content differs from the first prime. Guards against a shortcut where `regenerate` no-ops when the tone hasn't changed.
- success_criteria:
  - `testRegenerateSameToneTransitionsThroughPriming` — engine enters `.priming` on regenerate call
  - `testRegenerateSameToneReachesReady` — engine reaches `.ready` after regenerate completes
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; configure `StubLLMService` with distinct first/second stream content; use `waitUntil` helper.

### REP-210 — IMessageSender: combined newline + backslash escaping in AppleScript literal (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-174 fixed `\n → \\n` escaping. Add a combined boundary test: a message containing `"line one\nline two\nbackslash: \\"` produces an AppleScript string literal where `\n` is escaped to `\\n` and `\\` is escaped to `\\\\`. Also: a message containing a tab character `\t` passes through unchanged (tabs are legal in AppleScript string literals). Uses the injectable `executeHook` seam to capture the constructed AppleScript string without executing it.
- success_criteria:
  - `testNewlineAndBackslashBothEscapedInAppleScript` — `\n` → `\\n`, `\\` → `\\\\` in AppleScript literal
  - `testTabCharacterPassesThroughUnescaped` — tab in message text passes unescaped
  - Existing IMessageSenderTests remain green
- test_plan: 2 new tests in `IMessageSenderTests.swift`; use `executeHook` seam to capture AppleScript string for assertion rather than executing.

### REP-229 — AppleScript thread listing: `tell Messages to get every chat` fallback when FDA unavailable
- priority: P0
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: null
- blocker: Implementation complete on wip/2026-04-23-191507-appleScript-fallback (REP-236, +228 LOC, 4 tests). Worker must NOT re-implement — check if REP-236's wip branch merged first; if so, mark this done. If not merged, this task is waiting on human swift test + merge (REP-254).
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift` (or new `Sources/ReplyAI/Channels/AppleScriptMessageReader.swift`), `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: **Pivot-aligned (alt message-source).** Add `AppleScriptMessageReader.recentChats() -> [MessageThread]` that executes `tell application "Messages" to get every chat` via `NSAppleScript`. Returns a `[MessageThread]` with display name, chat GUID, and a placeholder `previewText` (AppleScript can retrieve `every text chat` with `name` and `id` but not full message history — that's OK for the thread list). No FDA required — uses Automation permission. `IMessageChannel.recentThreads()` uses this as a fallback when `openReadOnly()` fails with `authorizationDenied`. Tests use injectable AppleScript executor (same seam as `IMessageSender`).
- success_criteria:
  - `AppleScriptMessageReader.recentChats() -> [MessageThread]` implemented with injectable executor
  - `IMessageChannel.recentThreads()` calls `AppleScriptMessageReader` when `openReadOnly()` returns `.authorizationDenied`
  - `testAppleScriptFallbackPopulatesThreadsWhenFDADenied` — mock channel returns `authorizationDenied`; fallback executor returns chat list; `recentThreads()` returns non-empty
  - `testAppleScriptFallbackExecutorIsInjectable` — custom executor captures AppleScript string for assertion
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests; injectable executor captures and asserts on the AppleScript source string without executing real AppleScript.

### REP-230 — LocalhostOAuthListener: injectable loopback handler for Slack OAuth
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-24-042000
- files_to_touch: `Sources/ReplyAI/Channels/LocalhostOAuthListener.swift` (new), `Tests/ReplyAITests/LocalhostOAuthListenerTests.swift` (new)
- scope: **Pivot-aligned (Slack first).** Building block for REP-010 (Slack OAuth). Extract the loopback listener into a standalone `LocalhostOAuthListener` that: (1) binds an `NWListener` on `127.0.0.1:4242`; (2) resolves a `code` query parameter from the first incoming callback URL; (3) calls a completion handler with `code: String` and shuts down the listener. Injectable port and timeout (`default: 120s`). Tests verify: valid callback URL returns the `code`; timeout fires completion with `OAuthError.timeout`; double-start is a no-op. No Slack-specific logic here — just the reusable plumbing.
- success_criteria:
  - `LocalhostOAuthListener(port:timeout:)` type in new file
  - `start(completion: (Result<String, OAuthError>) -> Void)` and `stop()` methods
  - `testValidCallbackURLExtractsCode` — mock NW connection delivering `/?code=abc123`  → completion called with `"abc123"`
  - `testTimeoutFiresWithOAuthError` — no callback within timeout fires `.timeout`
  - `testDoubleStartIsNoop` — second `start()` while running is safe
  - Existing tests remain green
- test_plan: 3 new tests in `LocalhostOAuthListenerTests.swift`; use an injectable `NWListener` factory or connect a real listener to localhost in a test.

### REP-231 — Preferences: per-channel enable/disable keys (iMessage, Slack, demo)
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-143143
- blocker: code complete on wip/2026-04-24-143143-prefs-channels-negation-concurrent (+8 tests: 3 REP-231, 3 REP-208, 2 REP-220); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: **Pivot-aligned (channel architecture).** Add three Preferences keys: `pref.channels.iMessageEnabled: Bool` (default `true`), `pref.channels.slackEnabled: Bool` (default `false`), `pref.channels.demoModeActive: Bool` (alias of `Preferences.demoModeActive` from REP-228, or consolidate here). These are the channel-level on/off switches that `InboxViewModel.syncFromIMessage` and future `SlackChannel.recentThreads` will check before attempting a sync. Tests: default values; round-trip through UserDefaults; wipe behavior (channels.* keys are NOT wipe-exempt — privacy reset clears channel tokens).
- success_criteria:
  - `pref.channels.iMessageEnabled`, `pref.channels.slackEnabled` Preferences keys
  - Default values correct (`iMessage=true`, `slack=false`)
  - Neither key is wipe-exempt (both cleared on `wipe()`)
  - `testIMessageEnabledDefaultsToTrue`, `testSlackEnabledDefaultsToFalse`, `testChannelKeysClearedOnWipe`
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated `UserDefaults`.

### REP-218 — InboxViewModel: archiveThread removes thread from SearchIndex (integration test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-063 shipped `SearchIndex.delete(threadID:)` and wired it in `InboxViewModel.archive(_:)`. Add an integration test verifying the full pipeline: seed a thread into an injectable `SearchIndex` and the ViewModel; call `archive(thread)`; assert `searchIndex.search("query matching thread")` returns empty. Also assert thread absent from `viewModel.threads` after archive. Guards against future refactors that break the archive→index-purge path.
- success_criteria:
  - `testArchiveThreadRemovesFromSearchIndex` — searching for archived thread returns no results
  - `testArchiveThreadRemovedFromViewModelThreads` — thread absent from `threads` after archive
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift`; inject temp-directory `SearchIndex` and `StaticMockChannel`.

### REP-219 — ContactsResolver: cache hit within TTL skips CNContactStore re-query
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: REP-074 added injectable `ttl`. Pin the positive cache-hit path: resolve a handle once (store query count = 1); call `name(for:)` again within the TTL window; assert store query count remains 1 (no second query). Complement to REP-185 which tests TTL expiry. Guards against a future change that accidentally bypasses the cache on every call.
- success_criteria:
  - `testCacheHitWithinTTLSkipsStoreQuery` — second call within TTL does not increment mock store call count
  - Existing ContactsResolverTests remain green
- test_plan: 1 new test in `ContactsResolverTests.swift` using `MockContactsStore` with call counter; `ttl=9999`.

### REP-220 — RulesStore: concurrent add + remove does not corrupt rules array
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-143143
- blocker: code complete on wip/2026-04-24-143143-prefs-channels-negation-concurrent (+8 tests: 3 REP-231, 3 REP-208, 2 REP-220); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore` uses `Locked<T>` for thread-safety. Pin correctness under concurrent writes: `DispatchQueue.concurrentPerform(iterations: 50)` alternately calls `add(_:)` and `remove(ruleID:)` on the same store. After completion, assert: no crash, `rules.count ≥ 0`, no duplicate IDs. Guards against a race where a `Locked<T>` scope is held across an add while a concurrent remove modifies a different index.
- success_criteria:
  - `testConcurrentAddRemoveNoCrash` — 50 concurrent add+remove operations complete without crash
  - `testConcurrentAddRemoveNoDuplicateIDs` — no duplicate UUIDs in `rules` after stress
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift` using isolated `RulesStore` with injected `UserDefaults` suite.

### REP-221 — IMessageChannel: text=NULL message falls back to attributedBody decoder
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: The SQL query selects both `message.text` and `message.attributedBody`. When `text` is NULL, `AttributedBodyDecoder.extractText` is called on the raw blob. Add an in-memory SQLite fixture: one message row with `text = NULL` and a hand-crafted minimal typedstream `attributedBody` blob; call `messages(forThreadID:limit:)`; assert the returned message body matches the decoded string (not nil, not "[deleted]"). Verifies the fallback path is exercised, not just the SQL filter.
- success_criteria:
  - `testNullTextFallsBackToAttributedBodyDecoder` — message with null text returns decoded attributedBody content
  - `testNullTextNullBlobProducesPlaceholder` — both null → "[deleted]" placeholder
  - Existing IMessageChannelTests remain green
- test_plan: 2 new tests using in-memory SQLite with attributedBody blob fixtures from `AttributedBodyDecoderTests`.

### REP-222 — UserVoiceProfile: data model + Preferences key + PromptBuilder injection
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: The `ob-voice` screen is a UI mock; full LoRA training is out of scope. Add the data layer: `pref.voice.exampleMessages: [String]` (UserDefaults key, defaults to `[]`, max 20 entries enforced at setter, each entry max 500 chars — truncated at setter). `PromptBuilder.buildPrompt(...)` gains optional `voiceExamples: [String]` parameter; when non-empty, inserts a "Style examples from the user's prior messages:" section above the conversation history. Tests: examples appear in built prompt; empty examples → no section header; >20 examples clamped to 20; entry >500 chars truncated at setter.
- success_criteria:
  - `pref.voice.exampleMessages` key with 20-entry cap and 500-char per-entry truncation
  - `PromptBuilder.buildPrompt` injects voice examples when non-empty
  - `testVoiceExamplesInjectedIntoPrompt` — examples appear between system and history in output
  - `testEmptyVoiceExamplesProduceNoHeader` — no section header when list is empty
  - `testVoiceExamplesCapEnforcedAtTwenty` — setter clamps list to 20 entries
  - `testVoiceExampleTruncatedAtFiveHundredChars` — long entry truncated at setter
- test_plan: 4 new tests in `PromptBuilderTests.swift` + 2 in `PreferencesTests.swift`.

### REP-223 — Stats: per-channel indexed-count reset on SearchIndex.clear() (integration)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-165 ships `SearchIndex.clear()` which calls `Stats.resetIndexedCounters()`. Add an integration test: seed an iMessage indexed count of 5 into a shared `Stats` instance via mock increments; call `searchIndex.clear()` (with the same `Stats` instance injected); assert `stats.indexedMessageCount(for: .iMessage) == 0`. Also assert non-index counters (rules fired, drafts generated) are unchanged by clear(). Guards the Stats→SearchIndex contract.
- success_criteria:
  - `testClearResetsStatsIndexedCount` — indexed count returns 0 after clear()
  - `testClearDoesNotAffectOtherStatsCounters` — rules/drafts counters unchanged by clear()
  - Existing SearchIndexTests and StatsTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift` using in-memory `SearchIndex` with injected `Stats` instance.

### REP-224 — InboxViewModel: bulkMarkAllRead() sets unread=0 for all loaded threads
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-143143
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Add `bulkMarkAllRead()` to `InboxViewModel` that iterates `threads` and sets `unread = 0` for each. Useful for a "Mark all read" menu action (UI wiring is separate, human-reviewed). Tests: start with 3 threads each with `unread > 0`; call `bulkMarkAllRead()`; assert all three have `unread == 0`; thread count unchanged.
- success_criteria:
  - `InboxViewModel.bulkMarkAllRead()` implemented
  - `testBulkMarkAllReadClearsAllUnreadCounts` — all threads have `unread == 0` after call
  - `testBulkMarkAllReadPreservesThreadCount` — thread array count unchanged
  - Existing InboxViewModelTests remain green
- test_plan: 2 new tests in `InboxViewModelTests.swift` using `StaticMockChannel` seeded with 3 threads with `unread > 0`.

### REP-225 — SearchIndex: snippet column pinned to message body, not thread_name (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Worker-111853 notes `snippet(messages_fts, 3, '«', '»', '…', 8)` uses column 3 (message body text). Pin with a test: index a thread where the thread name contains the search term "alpha" but the message body does not; search "alpha"; assert snippet does NOT contain "alpha" (because snippet comes from the message body column, not thread_name). Then index a thread where the message body contains "beta"; search "beta"; assert snippet contains `«beta»`. Guards against schema migration that shifts column indices.
- success_criteria:
  - `testSnippetExtractsFromMessageBodyNotThreadName` — thread-name match does not produce snippet
  - `testSnippetContainsBoldMarkerAroundMatchedTerm` — body match produces `«term»` in snippet
  - Existing SearchIndexTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift` using in-memory FTS5 with distinct thread_name and body content.

### REP-226 — SmartRule: `messageCount(atLeast:)` predicate — match threads with ≥N messages
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Sources/ReplyAI/Screens/Surfaces/SfcRulesView.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: Add `case messageCount(atLeast: Int)` to `RulePredicate`. `RuleContext` gains `messageCount: Int` (from `MessageThread.messages.count`). `RuleEvaluator` evaluates: `context.messageCount >= atLeast`. Codable discriminator: `"messageCountAtLeast"`. `SfcRulesView.humanize` gets a new case string. Useful for rules like "if thread has ≥10 messages, use detailed tone". Tests: context.messageCount=5, predicate atLeast=3 → true; atLeast=5 → true; atLeast=6 → false; Codable round-trip preserves the threshold; atLeast=0 → vacuous-true (always matches).
- success_criteria:
  - `RulePredicate.messageCount(atLeast:)` case added and Codable
  - `RuleContext.messageCount: Int` field populated from thread
  - `RuleEvaluator` evaluates `context.messageCount >= atLeast`
  - `SfcRulesView.humanize` updated
  - `testMessageCountAtLeastMatchesWhenAboveThreshold`, `testMessageCountAtLeastMissesWhenBelowThreshold`, `testMessageCountAtLeastZeroIsVacuousTrue`, `testMessageCountAtLeastCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: 4 new tests in `RulesTests.swift`; construct `RuleContext` directly with controlled `messageCount`.

### REP-227 — IMessageChannel: Message.messageType field exposes tapback/receipt at model layer
- priority: P2
- effort: M
- ui_sensitive: false
- status: deprioritized
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/IMessageChannel.swift`, `Sources/ReplyAI/Models/MessageThread.swift`, `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: Tapbacks (`associated_message_type 2000–2005`) and delivery receipts are currently filtered at the SQL level by the thread-preview query. Expose `messageType: MessageType` on `Message` where `MessageType` is an enum: `.standard`, `.tapback`, `.deliveryReceipt`, `.unknown(Int)`. The SQL query for `messages(forThreadID:)` adds the `associated_message_type` column. Tapbacks and receipts are still filtered from thread previews (existing behavior preserved) but are now available to callers who want to show reaction summaries or sync status. Tests: standard message has `.standard` type; a row with `associated_message_type = 2000` has `.tapback`; a row with `associated_message_type = 2002` (read receipt) has `.deliveryReceipt`.
- success_criteria:
  - `MessageType` enum with `.standard`, `.tapback`, `.deliveryReceipt`, `.unknown(Int)` cases
  - `Message.messageType` field populated from SQL
  - `testStandardMessageTypeIsStandard`, `testTapbackMessageTypeIsTapback`, `testDeliveryReceiptTypeIsDeliveryReceipt`, `testUnknownAssociatedTypeIsPreserved`
  - Existing IMessageChannelTests and thread-preview filter remain green
- test_plan: 4 new tests in `IMessageChannelTests.swift` using in-memory SQLite fixture with varied `associated_message_type` values.

### REP-240 — AppleScriptMessageReader: `messagesForChat(chatGUID:limit:) -> [Message]`
- priority: P1
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/AppleScriptMessageReader.swift` (extends REP-236), `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: **Pivot-aligned (alt message-source, no FDA).** Extend `AppleScriptMessageReader` (from REP-236) to fetch messages for a specific chat: `messagesForChat(chatGUID: String, limit: Int) -> [Message]`. AppleScript: `tell application "Messages" to get (items 1 through <limit> of messages of first chat whose id is "<guid>")`. Parses `content`, `sender`, `date` fields from each message. Returns `[Message]` in chronological order (newest last). Injectable executor preserves testability. Tests: mock executor returns 3-message list → `[Message]` with correct bodies; `limit` parameter limits result count; empty chat → empty array; AppleScript returns error → throws `ChannelError.generalError`.
- success_criteria:
  - `AppleScriptMessageReader.messagesForChat(chatGUID:limit:) -> [Message]` implemented
  - Injectable executor seam (same as REP-236)
  - `testMessagesForChatParsesBodyCorrectly` — message body from AppleScript output
  - `testMessagesForChatRespectsLimit` — limit=2 with 3 available → 2 returned
  - `testMessagesForChatEmptyResultIsEmpty` — empty message list → []
  - `testMessagesForChatErrorPropagates` — executor throws → ChannelError surfaced
  - Existing tests remain green
- test_plan: 4 new tests in `IMessageChannelTests.swift`; inject mock executor; no real AppleScript.

### REP-241 — UNNotificationContentParser: structured parser for iMessage notification payloads
- priority: P1
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-163229
- blocker: code complete on wip/2026-04-24-163229-un-notification-parser (+42 LOC source, +96 LOC tests, 7 tests); MLX fresh-clone build time exceeded 13-min budget (REP-254); human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Channels/UNNotificationContentParser.swift` (new), `Tests/ReplyAITests/UNNotificationContentParserTests.swift` (new)
- scope: **Pivot-aligned (alt message-source, no FDA).** Extract notification payload parsing from `NotificationCoordinator` (REP-235) into a dedicated testable type. `UNNotificationContentParser.parse(_ content: UNNotificationContent) -> ParsedMessageNotification?` where `ParsedMessageNotification` has `senderHandle: String`, `preview: String`, and optional `chatGUID: String?`. Tries `content.userInfo["CKSenderID"]` first, then `content.userInfo["sender"]`, then `content.title` as sender handle. Uses `content.body` as preview. Returns nil if neither sender key is present. Tests: full payload → all fields; missing CKSenderID falls back to sender key; both missing → nil; body-only notification (no userInfo keys) → nil; chatGUID present in userInfo → populated; chatGUID absent → nil.
- success_criteria:
  - `UNNotificationContentParser.parse(_:) -> ParsedMessageNotification?` static func
  - `ParsedMessageNotification` struct with `senderHandle`, `preview`, `chatGUID?` fields
  - `testFullPayloadParsesAllFields` — all userInfo keys present → all fields populated
  - `testMissingCKSenderIDFallsBackToSenderKey` — fallback key resolution
  - `testBothSenderKeysMissingReturnsNil` — nil when no sender recoverable
  - `testChatGUIDPresentAndAbsent` — both cases tested
  - Existing tests remain green
- test_plan: 4 new tests in `UNNotificationContentParserTests.swift`; construct mock `UNNotificationContent` via `UNMutableNotificationContent`.

### REP-242 — SlackChannel: `recentThreads()` with real `conversations.list` API call
- priority: P2
- effort: M
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Channels/SlackChannel.swift` (extends REP-234), `Tests/ReplyAITests/SlackChannelTests.swift`
- scope: **Pivot-aligned (first real Slack data fetch).** Implement real `recentThreads(limit:)` in `SlackChannel` using `SlackHTTPClient` (REP-237 prereq). Call `GET api/conversations.list?types=im&exclude_archived=true&limit=<limit>`. Parse the JSON response (`channels[]` array, each with `id`, `name`, `is_im: true`, `latest.text`) into `[MessageThread]`. Set `channel: .slack` on each. Returns `ChannelError.authorizationDenied` if no token; `ChannelError.networkError` on HTTP failure. Injectable `SlackHTTPClient`. Tests: mock client returning sample IM list JSON → threads created with correct fields; empty channels array → empty result; missing `latest` → previewText is empty string; HTTP error → `ChannelError.networkError`; no token → `authorizationDenied` (existing test from REP-234, unchanged).
- success_criteria:
  - `SlackChannel.recentThreads(limit:)` calls `conversations.list` when token present
  - Threads created with `channel: .slack`, `displayName`, `previewText` from `latest.text`
  - `testSlackRecentThreadsParsesIMListResponse` — sample JSON → correct `[MessageThread]`
  - `testSlackRecentThreadsEmptyChannelsReturnsEmpty` — empty channels array → []
  - `testSlackRecentThreadsMissingLatestUsesEmptyPreview` — missing latest → empty previewText
  - `testSlackRecentThreadsHTTPErrorThrowsNetworkError` — HTTP failure → `networkError`
  - Existing SlackChannelTests remain green (REP-234)
- test_plan: 4 new tests in `SlackChannelTests.swift`; mock `SlackHTTPClient` returns configured JSON Data.

### REP-243 — Channel enum: add `.telegram`, `.whatsapp`, `.teams`, `.sms` cases
- priority: P2
- effort: S
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-031929
- blocker: code complete on wip/2026-04-24-031929-channel-stubs (Channel.swift +16 LOC: displayName/iconName props, 4 ChannelTests, bundled with REP-260/261/264); MLX build time exceeded budget; human should run `swift test` and merge if green
- files_to_touch: `Sources/ReplyAI/Models/Channel.swift` (or wherever `Channel` is defined), `Tests/ReplyAITests/ChannelTests.swift` (new or extend)
- scope: **Pivot-aligned (channel architecture scaffolding).** `Channel` enum currently has only cases used in the codebase (`.iMessage`, `.slack`). Add `.telegram`, `.whatsapp`, `.teams`, `.sms` as future-channel stubs. Each case needs `displayName: String` and `iconName: String` properties. Add `CaseIterable` conformance and `Codable` (raw `String` value). `ChannelDot` and any exhaustive `switch` over `Channel` must be updated (no behavior change — add placeholder colors for new cases). Tests: `Channel.allCases` count matches expected; each case decodes from its `rawValue` string; `displayName` is non-empty for every case.
- success_criteria:
  - `.telegram`, `.whatsapp`, `.teams`, `.sms` cases added
  - `CaseIterable` and `Codable` conformance
  - `displayName` and `iconName` properties for all cases
  - `testAllCasesDecodable` — every case round-trips through `Codable`
  - `testDisplayNameNonEmpty` — all cases have non-empty `displayName`
  - `testCaseIterableCount` — `allCases.count` matches expected (pins against accidental omission)
  - Existing tests remain green (no behavior change in iMessage/Slack paths)
- test_plan: 3 new tests in `ChannelTests.swift`; no mocking needed — pure enum conformance.

### REP-244 — InboxViewModel: `syncAllChannels()` merges results from all registered ChannelServices
- priority: P0
- effort: M
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-170301
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: **Pivot P0: the multi-channel aggregation layer that makes alternative sources (AppleScript, Slack, notification-captured) appear alongside iMessage without FDA.** Without this, each channel must be queried independently and there is no unified thread list. Add `registeredChannels: [any ChannelService]` array on `InboxViewModel` (injectable for tests, defaults to `[IMessageChannel()]`). Add `syncAllChannels() async -> [MessageThread]` that concurrently calls `recentThreads(limit: Preferences.threadLimit)` on each channel, merges results deduped by `threadID`, sorts by `lastMessageDate` descending. One channel throwing does not block others — log error and continue. Tests: two channels each returning 2 threads → merged 4 sorted threads; duplicate threadID from two channels → deduplicated (first channel wins); one channel throws → others still sync; empty `registeredChannels` → empty result.
- success_criteria:
  - `InboxViewModel.registeredChannels: [any ChannelService]` injectable property
  - `syncAllChannels() async -> [MessageThread]` — concurrent fetch, dedupe, sort
  - `testSyncAllChannelsMergesResults` — 2 channels × 2 threads = 4 merged
  - `testSyncAllChannelsDeduplicatesByThreadID` — duplicate ID → deduplicated
  - `testSyncAllChannelsOneThrowsOtherStillSyncs` — partial failure handled
  - `testSyncAllChannelsEmptyListReturnsEmpty` — no channels → empty
  - Existing InboxViewModelTests remain green
- test_plan: 4 new tests in `InboxViewModelTests.swift`; inject `[StaticMockChannel, AnotherStaticMockChannel]` as `registeredChannels`.

### REP-245 — InboxViewModel: `filterByChannel(_ channel: Channel?)` view-level filter
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Add `filterByChannel(_ channel: Channel?)` to `InboxViewModel`. When non-nil, sets `activeChannelFilter: Channel?` which causes `threads` computed property to return only threads matching that channel. When nil, returns all threads. Filter is view-level — underlying `_threads` array is unchanged. Tests: filter for `.iMessage` returns only iMessage threads; filter for `.slack` returns only Slack threads; nil filter returns all; setting filter does not mutate `_threads`; empty result when no threads match filter.
- success_criteria:
  - `InboxViewModel.activeChannelFilter: Channel?` property
  - `threads` computed property filters by `activeChannelFilter` when non-nil
  - `testFilterByChannelIMessage` — iMessage filter shows only iMessage threads
  - `testFilterByChannelSlack` — Slack filter shows only Slack threads
  - `testFilterByChannelNilShowsAll` — nil filter shows all threads
  - `testFilterByChannelDoesNotMutateUnderlying` — `_threads` unchanged after filter
  - Existing InboxViewModelTests remain green
- test_plan: 4 new tests in `InboxViewModelTests.swift`; seed mixed-channel threads via `StaticMockChannel`.

### REP-246 — InboxViewModel: `totalUnreadCount: Int` computed property
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-152614
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Add `totalUnreadCount: Int` to `InboxViewModel` that sums `thread.unread` across all threads. Useful for the MenuBar badge (REP-044) and the sidebar header. Clamped to ≥0 (guard against hypothetical negative unread). Tests: no threads → 0; 3 threads with unread 2, 0, 5 → 7; all unread=0 → 0; single thread unread=1 → 1.
- success_criteria:
  - `InboxViewModel.totalUnreadCount: Int` computed property
  - `testTotalUnreadCountSumsCorrectly` — 2+0+5 → 7
  - `testTotalUnreadCountZeroWhenAllRead` — all-zero threads → 0
  - `testTotalUnreadCountNoThreadsIsZero` — empty thread list → 0
  - Existing InboxViewModelTests remain green
- test_plan: 3 new tests in `InboxViewModelTests.swift` using `StaticMockChannel` with seeded threads.

### REP-247 — InboxViewModel: `ViewState` enum for loading/populated/demo/error states
- priority: P0
- effort: M
- ui_sensitive: false
- status: blocked
- claimed_by: worker-2026-04-24-113000
- blocker: TWO competing implementations exist — `wip/worker-2026-04-24-113000-viewstate` (REP-247 only, 531 tests) and `wip/2026-04-24-120000-viewstate-slacktokenstore` (REP-247+274 bundled). Human should pick one via REP-275.
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Replace implicit thread-count-based state detection with explicit `ViewState` enum: `case loading, populated, empty(EmptyReason), demo, error(Error)` where `EmptyReason: Equatable { case noMessages, noPermissions }`. `InboxViewModel.viewState: ViewState` is `@Published`. Transitions: on init → `.loading`; sync returns threads → `.populated`; sync returns [] with demo mode active → `.demo`; sync returns [] without demo → `.empty(.noMessages)`; sync throws `authorizationDenied` → `.empty(.noPermissions)`; sync throws other → `.error(error)`. Tests: each state transition tested with mock channel; `.loading` → `.populated` on sync; `.loading` → `.demo` when demoMode; `.empty(.noPermissions)` on auth-denied sync.
- success_criteria:
  - `ViewState` enum (nested in `InboxViewModel`) with 5 cases
  - `InboxViewModel.viewState: ViewState` published property
  - `testViewStateTransitionsToPopulated` — sync returns threads → `.populated`
  - `testViewStateTransitionsToDemoOnEmptySync` — empty sync + demo mode → `.demo`
  - `testViewStateTransitionsToEmptyNoPermissions` — auth-denied → `.empty(.noPermissions)`
  - `testViewStateTransitionsToEmptyNoMessages` — empty sync, no demo → `.empty(.noMessages)`
  - Existing InboxViewModelTests remain green
- test_plan: 4 new tests in `InboxViewModelTests.swift` using injected mock channels.

### REP-248 — InboxViewModel: `bulkArchiveRead()` archives all threads with unread=0
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-152614
- files_to_touch: `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: Add `bulkArchiveRead()` to `InboxViewModel` that calls `archive(_:)` on every thread where `thread.unread == 0`. Useful for a "Clear read" menu action (UI wiring is separate). Complements `bulkMarkAllRead()` (REP-224). Tests: 3 threads with unread 0 and 1 with unread 3 → 3 archived, 1 remains; all threads unread=0 → all archived, `threads` empty; no threads with unread=0 → no archives triggered, `threads` unchanged.
- success_criteria:
  - `InboxViewModel.bulkArchiveRead()` implemented
  - `testBulkArchiveReadArchivesZeroUnreadThreads` — 3 read + 1 unread → only 3 archived
  - `testBulkArchiveReadAllRead` — all unread=0 → `threads` empty after call
  - `testBulkArchiveReadNoReadThreadsIsNoop` — all unread>0 → `threads` unchanged
  - Existing InboxViewModelTests remain green
- test_plan: 3 new tests in `InboxViewModelTests.swift` using `StaticMockChannel` with mixed-unread threads.

### REP-249 — ContactsResolver: concurrent same-handle resolve returns consistent result
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-152614
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: Pin cache-and-lock correctness under real concurrency: call `name(for: "alice@example.com")` 10 times concurrently via `DispatchQueue.concurrentPerform(iterations: 10)`; assert result is consistent (all 10 results equal the resolved name); assert mock store queried exactly once (not 10 times). Complements REP-219 (single cache-hit test) with concurrent-load correctness. Guards `NSLock`-guarded cache against TOCTOU under actual parallel reads.
- success_criteria:
  - `testConcurrentSameHandleResolvesConsistently` — 10 concurrent resolves → all same result
  - `testConcurrentSameHandleQueriesStoreOnce` — mock store called exactly once
  - Existing ContactsResolverTests remain green
- test_plan: 2 new tests using `MockContactsStore` with call counter and `DispatchQueue.concurrentPerform`.

### REP-250 — DraftEngine: `invalidate(threadID:)` mid-prime transitions to idle, not priming
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftEngine.invalidate(threadID:)` (from REP-054 / watcher-refire path) should cancel any in-flight prime task for that thread and transition to `.idle`. Pin the contract: start priming thread X (slow `StubLLMService` with delay); immediately call `invalidate(threadID: X)`; assert state is `.idle` (not `.priming`). Also assert no subsequent `.ready` transition arrives (task was cancelled). Guards against a zombie prime that completes after invalidation and incorrectly flips state to `.ready`.
- success_criteria:
  - `testInvalidateMidPrimeTransitionsToIdle` — invalidate during prime → state `.idle`
  - `testInvalidateMidPrimeCancelsPrimingTask` — no `.ready` after invalidation
  - Existing DraftEngineTests remain green
- test_plan: 2 new tests in `DraftEngineTests.swift`; use a `DelayedStubLLMService` (inject delay > test window) + `waitUntil` helper.

### REP-251 — RulesStore: compound predicate export + import round-trip (complex tree)
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: Pin Codable correctness for deeply nested predicates: `and([senderIs("A"), or([textMatchesRegex("^hi"), not(senderUnknown)])])`. Export via `RulesStore.exportRules(to:)`; import via `importRules(from:)`; assert the re-imported rule's predicate tree equals the original (using `Equatable` or matching string descriptions). Also test: `or([])` round-trips as vacuous-false (or empty or); `and([not(hasUnread)])` round-trips correctly. Guards the `kind`-discriminator Codable path for every compound wrapper.
- success_criteria:
  - `testCompoundPredicateRoundTrip` — deeply nested and/or/not survives export+import unchanged
  - `testOrEmptyPredicateRoundTrip` — `or([])` encodes and decodes without crash
  - `testAndNotPredicateRoundTrip` — `and([not(...)])` round-trips correctly
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift`; compare predicate description strings or add `Equatable` to predicate in tests.

### REP-252 — SearchIndex: BM25 ranking — higher-term-frequency thread ranks first
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: FTS5 BM25 ranking should promote threads where the query term appears more frequently. Test: index thread A with message body "hello hello hello" and thread B with "hello"; search "hello"; assert A ranks before B (first in result array). Also test: after adding a 3rd thread C ("hello hello hello hello hello"), C ranks above A. Guards against FTS5 config changes (e.g. `rank = 'bm25(0, 0, 1)'` parameter change) that break expected ranking semantics.
- success_criteria:
  - `testBM25RanksHigherFrequencyFirst` — 3× "hello" thread before 1× "hello" thread
  - `testBM25RankingIsMonotonic` — 5× > 3× > 1× in result order
  - Existing SearchIndexTests remain green
- test_plan: 2 new tests in `SearchIndexTests.swift`; use in-memory FTS5 with threads having controlled term frequencies.

### REP-253 — AGENTS.md: update "What's still stubbed" and "What's done" sections
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-24-042000
- files_to_touch: `AGENTS.md`
- scope: **Docs-only — auto-merge eligible.** Update `AGENTS.md` to reflect current automation state: (1) Remove `UNNotification inline reply` from "What's still stubbed" — resolved via REP-072 / commit `bbedd1a`. (2) Update Slack status in "What's still stubbed" to note REP-233/234 (KeychainHelper + SlackChannel stub) are shipped and next steps are REP-230/237/242. (3) `AppleScriptMessageReader` — note wip/2026-04-23-191507-appleScript-fallback has complete implementation; pending human merge. (4) Add `NotificationCoordinator requestPermissionIfNeeded` stub to "What's still stubbed" (REP-255 wip pending merge). (5) Run `grep -c "func test" Tests/ReplyAITests/*.swift | awk -F: '{s+=$2} END {print s}'` to get current test count and update the repo layout header. Planner has already updated 502→510 but the wip branches add more. Worker should not run `swift test` — docs-only, just grep and update text.
- success_criteria:
  - `UNNotification inline reply` removed from "What's still stubbed" section
  - Slack stub status updated to reflect REP-233/234 progress
  - `AppleScriptMessageReader` added to "What's still stubbed"
  - Test count in header verified by grep and updated if stale
  - No architecture or gotchas sections modified (planner ban)
- test_plan: N/A (docs-only). Worker verifies via `grep -c "func test" Tests/ReplyAITests/*.swift` before committing.

### REP-258 — AccessibilityAPIReader: read Messages.app conversation list via NSAccessibilityElement
- priority: P2
- effort: M
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-161734
- files_to_touch: `Sources/ReplyAI/Channels/AccessibilityAPIReader.swift` (new), `Tests/ReplyAITests/AccessibilityAPIReaderTests.swift` (new)
- scope: **Pivot-aligned (alt message-source, no FDA required — uses Accessibility permission).** `AccessibilityAPIReader.conversationNames() -> [String]` walks the `AXUIElement` hierarchy of the `com.apple.MobileSMS` process to find conversation names listed in the sidebar. Injectable `AXUIElementFactory` protocol for test isolation (default uses real `AXUIElementCreateApplication`). Returns `[]` gracefully when Accessibility permission not granted (check `AXIsProcessTrusted()` before walking). Tests: mock element tree returns 3 conversation names → `[String]` with correct values; Accessibility not trusted → returns `[]` without crash; empty sidebar → `[]`; injectable factory captures the target PID for assertion.
- success_criteria:
  - `AccessibilityAPIReader.conversationNames() -> [String]` with injectable `AXUIElementFactory`
  - Returns `[]` when `AXIsProcessTrusted()` is false (no crash, no permission dialog)
  - `testAccessibilityReaderReturnsConversationNames` — mock element tree → correct names
  - `testAccessibilityReaderReturnsEmptyWhenNotTrusted` — not trusted → `[]`
  - `testAccessibilityReaderReturnsEmptyOnEmptySidebar` — empty element tree → `[]`
  - Existing tests remain green
- test_plan: 3 new tests in `AccessibilityAPIReaderTests.swift`; mock `AXUIElementFactory` returning synthesized element trees with known `kAXTitleAttribute` values.

### REP-259 — Onboarding: "Limited mode" — graceful flow when all permissions denied
- priority: P1
- effort: M
- ui_sensitive: true
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Screens/Onboarding/` (existing screens), `Sources/ReplyAI/Inbox/InboxViewModel.swift`
- scope: **Pivot-aligned (UX — app must be useful with zero permissions).** When the user completes onboarding without granting FDA, Notifications, or Contacts, the app currently shows a broken or empty state. Add a "Limited mode" path: if `Preferences.demoModeActive == true` after onboarding, the onboarding completion screen shows a "Continue in Limited Mode" CTA instead of the primary "Set up iMessage" path. Tapping it sets `Preferences.hasCompletedOnboarding = true` and opens the inbox in demo mode. A dismissable banner in the inbox ("You're in Limited Mode — grant permissions to see real conversations") points to Settings. This is UI-sensitive; worker pushes to `wip/` branch for human copy + layout review. Prereq: REP-228 (demo mode fixtures) should be merged before this ships.
- success_criteria:
  - `wip/` branch with onboarding changes
  - "Continue in Limited Mode" CTA visible on permission-denied onboarding state
  - `Preferences.hasCompletedOnboarding: Bool` key (if not already present) set on CTA tap
  - Dismissable "Limited Mode" banner in inbox when `demoModeActive == true`
  - Human reviews copy, CTA placement, and banner before merge
- test_plan: Non-UI logic (setting `hasCompletedOnboarding`, checking `demoModeActive` for banner) extractable for unit tests in `InboxViewModelTests.swift`; human validates onboarding UX.

### REP-268 — Preferences: `inbox.lastSyncDate: Date?` key — persist timestamp of last successful sync
- priority: P2
- effort: S
- ui_sensitive: false
- status: open
- claimed_by: null
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/Inbox/InboxViewModel.swift`, `Tests/ReplyAITests/PreferencesTests.swift`, `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: InboxViewModel has no persistent record of when threads were last refreshed. Add `Preferences.inbox.lastSyncDate: Date?` (nil if never synced). `InboxViewModel.syncFromIMessage()` sets this to `Date()` on any successful sync returning ≥1 thread; `syncAllChannels()` (REP-244) will do the same. `wipe()` clears this key. Useful for a "Last synced N min ago" footer in SidebarView (UI wiring is separate). Tests: nil on fresh Preferences; set after successful sync returning threads; NOT updated when sync returns empty; cleared by wipe().
- success_criteria:
  - `Preferences.inbox.lastSyncDate: Date?` key implemented
  - `InboxViewModel.syncFromIMessage()` sets key on sync returning ≥1 thread
  - `testLastSyncDateNilBeforeFirstSync` — nil on fresh isolated UserDefaults
  - `testLastSyncDateUpdatedAfterSuccessfulSync` — non-nil after sync returns threads
  - `testLastSyncDateNotUpdatedOnEmptySync` — nil preserved when sync returns empty
  - `testLastSyncDateClearedOnWipe` — wipe() resets to nil
  - Existing PreferencesTests and InboxViewModelTests remain green
- test_plan: 2 new tests in `PreferencesTests.swift` (nil/round-trip via isolated UserDefaults) + 2 in `InboxViewModelTests.swift` (sync path via `StaticMockChannel`).

### REP-269 — IMessageSender: injectable `retryDelay: TimeInterval` for -1708 backoff — removes hardcoded sleep from test paths
- priority: P2
- effort: S
- ui_sensitive: false
- status: in_progress
- claimed_by: worker-2026-04-24-161734
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-064 added -1708 error retry with a hardcoded sleep between attempts. This makes tests slow — each retry cycle pays real wall-clock time. Add `retryDelay: TimeInterval` to `IMessageSender.init(retryDelay: TimeInterval = 0.5)` and use `Thread.sleep(forTimeInterval: retryDelay)` in the retry path. Tests pass `retryDelay: 0.0` to run without sleep. No behavior change in production. Existing retry tests that construct `IMessageSender()` without an explicit `retryDelay` continue to use the 0.5s default; update the tests that exercise the retry path to use `retryDelay: 0` for speed.
- success_criteria:
  - `IMessageSender.init(retryDelay: TimeInterval = 0.5)` constructor parameter added
  - Retry path uses injected delay
  - `testRetryDelayZeroCompletesInstantly` — sender with `retryDelay: 0` completes retry in <100ms wall time
  - Existing IMessageSenderTests remain green (retry tests updated to use `retryDelay: 0`)
- test_plan: 1 new test in `IMessageSenderTests.swift`; update existing retry-path tests to use `retryDelay: 0`; no behavior change for production code.


## Done / archived

### REP-265 — InboxViewModel: wire MessagesAppActivationObserver to trigger re-sync when Messages becomes active
- status: done
- claimed_by: worker-2026-04-24-102657
- scope: InboxViewModel accepts injectable `MessagesAppActivationObserver?`. `handleMessagesActivation()` triggers `syncFromIMessage()` with 5-second debounce. 3 new tests in InboxViewModelTests. Bundled with REP-239 in commit `9a6c3d1`, 521→527 tests.

### REP-239 — MessagesAppActivationObserver: notify when Messages.app becomes frontmost
- status: done
- claimed_by: worker-2026-04-24-102657
- scope: New `MessagesAppActivationObserver` watching `NSWorkspace.didActivateApplicationNotification` for `com.apple.MobileSMS`. Injectable NSWorkspace + NotificationCenter. 600ms debounce. 3 new tests. Commit `9a6c3d1`, 521→527 tests.

### REP-271 — AGENTS.md + worker.prompt: document MLX build-time budget workaround and wip-branch protocol
- status: done
- claimed_by: worker-2026-04-24-110000
- scope: Docs-only. Added MLX cold-build warning to AGENTS.md Gotchas and to `.automation/worker.prompt` step 8. Documents that workers must check `.build/` freshness before running `swift test` and must push to `wip/` if the build cache is absent or stale. Resolves the protocol ambiguity that produced 10+ unnecessary wip branches. No code changes.

### REP-263 — NotificationCoordinator: extract chatGUID from userInfo for thread deduplication
- status: done
- claimed_by: worker-2026-04-24-060000
- scope: `handleIncomingNotification` gains `chatGUID: String?` extracted from `content.userInfo["CKChatIdentifier"]` (fallback `"CKChatGUID"`). `InboxViewModel.applyIncomingNotification` matches by chatGUID when non-nil, updating existing thread's `previewText` and unread count instead of appending a duplicate. nil/unknown GUID falls back to senderHandle creation (backward-compatible). Commit `31534e1`. 516→521 tests (+5).

### REP-230 — LocalhostOAuthListener: injectable loopback handler for Slack OAuth
- status: done
- claimed_by: worker-2026-04-24-042000
- scope: New `LocalhostOAuthListener` in `Sources/ReplyAI/Channels/LocalhostOAuthListener.swift`. Binds `NWListener` on `127.0.0.1` (port 0 for tests, 4242 default), resolves `code` query param from first GET callback, fires completion exactly once. `isRunning` flag guards double-start. `actualPort` + `onReady` callback for test synchronization. `OAuthError.timeout` and `OAuthError.listenerFailed`. 3 new tests in `LocalhostOAuthListenerTests.swift`. 513→516 tests.

### REP-253 — AGENTS.md: update "What's still stubbed" and "What's done" sections
- status: done
- claimed_by: worker-2026-04-24-042000
- scope: Docs-only. Updated test count 513→516. Fixed REP-235 commit hash TBD→`b2af590`. Updated Slack "still stubbed" note to reflect REP-233/234 shipped and REP-230 in progress. Added `NotificationCoordinator requestPermissionIfNeeded` stub note (REP-255 on wip branch). Bundled with REP-230 commit.

### REP-235 — NotificationCoordinator: passive capture of incoming message metadata without FDA
- status: done
- claimed_by: worker-2026-04-24-015900
- scope: Added `onIncomingMessage` callback to `NotificationCoordinator`, `userNotificationCenter(_:willPresent:)` delegate, and `handleIncomingNotification(categoryID:senderHandle:preview:)` extracted method. Added `applyIncomingNotification(senderHandle:preview:)` + `chatDBAvailable` to `InboxViewModel`. 3 new tests in `NotificationCoordinatorTests.swift`. 502→513 tests.

### REP-234 — SlackChannel: ChannelService conformance stub with Keychain token gate
- status: done
- claimed_by: worker-2026-04-23-171932
- scope: `SlackChannel: ChannelService` in `Sources/ReplyAI/Channels/SlackChannel.swift`. Throws `authorizationDenied` when no Keychain token present; returns `[]` when token present. `channel` property returns `.slack`. 3 new tests in `SlackChannelTests.swift`. Commit `c001d7e`, 502→510 tests.

### REP-233 — KeychainHelper: generic set/get/delete wrapper for channel OAuth tokens
- status: done
- claimed_by: worker-2026-04-23-171932
- scope: `KeychainHelper(service:)` in `Sources/ReplyAI/Channels/KeychainHelper.swift`. `set(value:for:)`, `get(key:)`, `delete(key:)` methods using `kSecClassGenericPassword`. Injectable `service:` for test isolation. 5 new tests in `KeychainHelperTests.swift`. Commit `c001d7e`, bundled with REP-234.

### REP-211 — AGENTS.md: correct stale SHA `05e7035` → `4035c5a` (docs-only)
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: SHA `05e7035` corrected to `4035c5a` (REP-098/099/101/103/104/109/114 batch). `git cat-file -e 4035c5a` verified. Docs-only commit.

### REP-204 — IMessageChannel: recentThreads limit boundary (under-limit and over-limit)
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: 2 tests in `IMessageChannelTests.swift`: `testRecentThreadsLimitOneLimitsToOne` (limit 1 → 1 result), `testRecentThreadsLimitExceedsAvailableReturnsAll` (limit 10 with 5 threads → 5 results).

### REP-203 — DraftEngine: regenerate on different tone evicts original tone's cache entry
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: 2 tests in `DraftEngineTests.swift`: `testRegenerateOnToneChangeEvictsOldToneCache`, `testRegenerateOnToneChangeReachesReadyForNewTone`. Uses `StubLLMService` + `waitUntil`.

### REP-202 — SmartRule: unknown predicate discriminator decodes gracefully without crash
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: 2 tests in `RulesTests.swift`: `testUnknownPredicateKindDoesNotCrash`, `testKnownPredicateKindDecodesAdjacentToUnknown`. Forward-compatibility guard.

### REP-197 — PromptBuilder: all tones produce distinct non-empty system instructions
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: 2 tests in `PromptBuilderTests.swift` via `Tone.allCases` CaseIterable: `testAllTonesProduceNonEmptySystemInstruction`, `testToneSystemInstructionsAreDistinct`.

### REP-192 — RulesStore: 100-rule cap boundary — 100th add succeeds, 101st throws
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: 3 tests in `RulesTests.swift`: `testHundredthRuleAddSucceeds`, `testHundredAndFirstRuleThrowsTooManyRules`, `testStoreCountUnchangedAfterFailedAdd`.

### REP-191 — DraftStore: concurrent read+write does not corrupt draft file
- status: done
- claimed_by: worker-2026-04-23-135355
- scope: 2 tests in `DraftStoreTests.swift`: `testConcurrentReadWriteNoCrash`, `testConcurrentReadWriteNoEmptyResult`. `DispatchQueue.concurrentPerform` with injected temp directory.

### REP-067 — SearchIndex: FTS5 snippet extraction for search results
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: `SearchResult` type with `threadID` and `snippet: String?` fields. `search(query:)` returns `[SearchResult]`. FTS5 `snippet()` wired on message body column (col 3) with `«»` markers and 8-token context window. Worker note: used col 3 (message body) rather than col 1 (thread_name) for semantic correctness. 4 tests in `SearchIndexSnippetTests`.

### REP-169 — DraftEngine: N-concurrent-thread primes don't leak in-flight tasks (stress test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: 2 tests in `DraftEngineTests`: `testConcurrentPrimesOnDistinctThreadsAllReachReady` and `testNoPrimingStateLeaksAfterConcurrentPrimes`. 10 threads primed concurrently via `DispatchQueue.concurrentPerform`; all reach `.ready`.

### REP-188 — RulesStore: rules persisted in insertion order, not sort order
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: 1 test `testDiskRoundTripPreservesInsertionOrder` in `RulesTests`: add A (priority 0) then B (priority 5), export+import, assert A before B.

### REP-189 — DraftEngine: LLM stream error transitions state to `.idle`, not stuck in `.priming`
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-111853
- scope: 2 tests in `DraftEngineTests`: `testPrimeErrorLeavesEngineInIdleNotErrorState` and `testPrimeSucceedsAfterPreviousError`. Uses `ThrowingStubLLMService` then `StubLLMService` in sequence.

### REP-199 — InboxViewModelAutoPrimeTests: fix non-deterministic crashes under Swift 6 + macOS 26.3
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: `BlockingMockChannel` mutable fields migrated to `Locked<T>` backing stores; `InboxViewModelAutoPrimeTests`, `InboxViewModelThreadSelectionTests`, `InboxViewModelReselectTests` gain isolated `RulesStore` + `SearchIndex` per test. Eliminates TOCTOU data race and cross-test SharedState interference under Swift 6 strict-concurrency.
- test_plan: Targeted test-class runs confirm 0 crashes; 493 tests total (grep-verified).

### REP-201 — AGENTS.md: correct stale commit SHA `904b0e7` → `7512321` in done-log
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326
- files_to_touch: `AGENTS.md`
- scope: SHA `904b0e7` (non-existent) replaced with `7512321` (verified valid) for worker-2026-04-23-020741 contract-tests batch. Test count updated 463 → 493 (grep-accurate).
- test_plan: N/A (docs-only).

### REP-165 — SearchIndex: `clear()` method to wipe and rebuild
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Sources/ReplyAI/Search/SearchIndex.swift`, `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Add `clear()` to `SearchIndex` that executes `DELETE FROM thread_search` and resets the per-channel indexed-message counter in `Stats` to zero. Tests: upsert 3 threads, call `clear()`, search returns empty; upsert again after clear → searchable; concurrent `clear()` + `upsert()` does not crash.
- test_plan: 3 new tests in `SearchIndexTests.swift` using in-memory `SearchIndex`.

### REP-176 — DraftStore: 7-day prune threshold removes old files and preserves recent ones (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: `DraftStore.init()` prunes draft files older than 7 days. Tests: file aged 8 days deleted on init; file aged 6 days survives init.
- test_plan: 2 new tests in `DraftStoreTests.swift` using setAttributes modificationDate.

### REP-180 — PromptBuilder: system prompt precedes all conversation history in output
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: Pin contract: system instruction appears before first message line in buildPrompt output. Tests: `testSystemPromptPrecedesConversationHistory`, `testAllMessagesFollowSystemBlock`.
- test_plan: 2 new tests in `PromptBuilderTests.swift` using fabricated messages and `.casual` tone.

### REP-181 — IMessageSender: -1708 retry count capped, not infinite
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: REP-064 added -1708 retry. Pin retry cap: all-failing hook throws after ≤ maxRetry+1 calls; one-failure hook succeeds after 2 calls.
- test_plan: 2 new tests using call-counting hook closures; no real AppleScript.

### REP-182 — DraftEngine: empty LLM stream produces `.idle` not stuck `.priming`
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: Empty stream (zero chunks, normal completion) should transition to `.idle`, not stay in `.priming`. Tests: `testEmptyLLMStreamTransitionsToIdle`, `testEmptyLLMStreamDoesNotCrash`.
- test_plan: 2 new tests using `EmptyStubLLMService` that returns a zero-yield stream.

### REP-184 — SearchIndex: 3-word query requires all 3 terms (explicit AND semantics test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: Extend AND-semantics coverage to 3-word queries. "quick lazy fox" returns empty (no thread has all 3). Guards FTS5 query from accidentally switching to OR.
- test_plan: 3 new tests in `SearchIndexTests.swift` with overlapping-term threads.

### REP-185 — ContactsResolver: TTL expiry forces re-query on next call (cache invalidation test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: ttl=0 forces store re-query on second call (count==2); ttl=9999 uses cache (count==1). Documents TTL contract.
- test_plan: 2 new tests using `MockContactsStore` with call counter.

### REP-186 — IMessageChannel: messages within a thread ordered newest-first
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-075700
- files_to_touch: `Tests/ReplyAITests/IMessageChannelTests.swift`
- scope: Pin sort order: first returned message has latest date regardless of DB insert order. Guards against SQL ORDER BY direction change.
- test_plan: 2 new tests using in-memory SQLite fixture.

### REP-079 — SmartRule: timeOfDay(start:end:) predicate for hour-range matching
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-000050
- files_to_touch: `Sources/ReplyAI/Rules/SmartRule.swift`, `Sources/ReplyAI/Rules/RuleEvaluator.swift`, `Tests/ReplyAITests/RulesTests.swift`
- scope: The current predicate DSL has 8 primitive kinds (senderIs, senderUnknown, hasAttachment, isGroupChat, textMatchesRegex, messageAgeOlderThan, hasUnread, and/or/not). Add `case timeOfDay(startHour: Int, endHour: Int)` (0–23, inclusive range, wrap-around for overnight e.g. 22–06). `RuleEvaluator` evaluates against `Calendar.current.component(.hour, from: Date())`. Inject a `DateProvider: () -> Date` for testability (same pattern as `messageAgeOlderThan`). Tests: current hour within range matches; current hour outside range doesn't; wrap-around overnight range (22–06) works correctly; Codable round-trip preserves startHour/endHour.
- success_criteria:
  - `RulePredicate.timeOfDay(startHour:endHour:)` case added and Codable
  - `RuleEvaluator` evaluates with injectable `DateProvider`
  - `testTimeOfDayWithinRangeMatches`, `testTimeOfDayOutsideRangeMismatches`, `testOvernightWrapAround`, `testTimeOfDayCodableRoundTrip`
  - Existing RulesTests remain green
- test_plan: Extend `RulesTests.swift` with 4 new cases using an injectable date closure.


### REP-133 — RulesStore: export round-trip covers all currently-shipped predicate kinds
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-000050
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: REP-035 added export/import; REP-110 adds a version wrapper. Neither test exercises the full predicate set — existing tests use a small subset of predicates. Build one `SmartRule` for each currently-shipped predicate kind: `senderIs`, `senderUnknown`, `hasAttachment`, `isGroupChat`, `textMatchesRegex`, `messageAgeOlderThan`, `hasUnread`, plus composite `and`, `or`, `not` wrappers. Export all to a temp JSON URL, import back, assert every rule round-trips with an identical predicate (equality check). This is a Codable regression test: any new predicate kind that breaks the discriminated-union encoder/decoder will fail here.
- success_criteria:
  - `testExportImportRoundTripAllPredicateKinds` — all 8+ predicate kinds survive export/import unmodified
  - Test uses a temp URL; `tearDownWithError` cleans up
  - No production code touched
- test_plan: 1 new test in `RulesTests.swift`; extend if new predicate kinds land (REP-079, REP-129) by adding their cases.



### REP-136 — AGENTS.md: consolidate duplicate test-count lines
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `AGENTS.md`
- scope: AGENTS.md currently has the test count in two places: the repo-layout code fence header (`Tests/ReplyAITests/ NNN tests`) and the Testing expectations section ("NNN XCTest cases, all green."). The reviewer flagged this duplication in the 2026-04-22 22:10 review. Remove the hard-coded number from the Testing expectations section and replace with the live-count instruction: `Run \`grep -r "func test" Tests/ | wc -l\` for the current count`. Update the repo-layout header to the current count (349). Docs-only change — no Swift source touches.
- success_criteria:
  - Repo-layout header updated to current count (349)
  - Testing expectations section uses grep instruction instead of hard-coded number
  - No source files touched
  - Reviewer no longer flags dual test-count lines
- test_plan: N/A (docs-only).


### REP-126 — SearchIndex: file-backed persistence round-trip smoke test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-041 added on-disk FTS5 persistence via `SearchIndex(databaseURL:)`, but the file-backed path only exercises the in-memory path under `swift test`. Add a round-trip test: create a `SearchIndex` with a temp file URL, index 3 threads, destroy the instance, create a new `SearchIndex` from the same URL, verify all 3 threads are still searchable. Use `tearDownWithError` to delete the temp file. Catches schema migration regressions if the FTS5 schema ever changes without a matching migration. No production code changes.
- success_criteria:
  - `testDiskBackedIndexSurvivesReinit` — threads indexed in instance A are findable after instance B opens same URL
  - `testDiskBackedEmptyReinitDoesNotCrash` — opening an existing empty db URL without prior indexing is safe
  - No production code touched
- test_plan: 2 new tests in `SearchIndexTests.swift` using `FileManager.default.temporaryDirectory` for URL injection; `tearDownWithError` removes temp file.

### REP-128 — IMessageSender: chatGUID format pre-flight validation
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Channels/IMessageSender.swift`, `Tests/ReplyAITests/IMessageSenderTests.swift`
- scope: Malformed `chatGUID` values (empty string, wrong service prefix, missing separator) produce opaque `errOSAScriptError` from AppleScript with no useful diagnostic. Add a pre-flight validation in `IMessageSender.send(text:toChatGUID:)` before constructing the AppleScript string: chatGUID must match the pattern `^iMessage;[+-];.+$`. Throw a new `SenderError.invalidChatGUID(String)` if the pattern fails. Tests use the dry-run/injectable `executeHook` seam so no AppleScript is invoked. Tests: valid 1:1 GUID passes; valid group GUID passes; empty string throws `invalidChatGUID`; wrong prefix (e.g. `"SMS;-;4155551234"`) throws; missing separator throws.
- success_criteria:
  - `SenderError.invalidChatGUID(String)` case added to `SenderError`
  - Validation runs before AppleScript construction
  - `testValidOneToOneGUIDPasses`, `testValidGroupGUIDPasses`, `testEmptyGUIDThrowsInvalid`, `testWrongPrefixThrowsInvalid`, `testMissingSeparatorThrowsInvalid`
  - Existing IMessageSenderTests remain green
- test_plan: 5 new tests in `IMessageSenderTests.swift`; no production AppleScript invocations (dry-run mode).

### REP-130 — Preferences: `pref.app.firstLaunchDate` set-once key
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Services/Preferences.swift`, `Sources/ReplyAI/App/ReplyAIApp.swift`, `Tests/ReplyAITests/PreferencesTests.swift`
- scope: Companion to `launchCount` (REP-115). Add `pref.app.firstLaunchDate: Date?` (nil = not yet set) to `Preferences`. In `ReplyAIApp.init()`, if `firstLaunchDate == nil`, set it to `Date()` — only ever written once. Key is NOT wiped by `wipe()`. Useful for upgrade banners ("You've been using ReplyAI since…"), feature gating after N days, or analytics. Tests: `testFirstLaunchDateSetOnFirstInit` — nil before first write, then non-nil; `testFirstLaunchDateNotOverwrittenOnSubsequentInit` — calling init again doesn't update the date; `testFirstLaunchDateSurvivesWipe` — date persists after `wipe()`.
- success_criteria:
  - `pref.app.firstLaunchDate: Date?` in `Preferences`
  - Set-once guard in `ReplyAIApp.init()`
  - Key excluded from `wipe()` sweep
  - `testFirstLaunchDateSetOnFirstInit`, `testFirstLaunchDateNotOverwrittenOnSubsequentInit`, `testFirstLaunchDateSurvivesWipe`
  - Existing PreferencesTests remain green
- test_plan: 3 new tests in `PreferencesTests.swift` using suiteName-isolated UserDefaults; use a fresh suite per test to avoid cross-test date pollution.

### REP-134 — InboxViewModel: archive removes thread from SearchIndex (integration test)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/InboxViewModelTests.swift`
- scope: REP-063 wired `SearchIndex.delete(threadID:)` through `InboxViewModel.archive(_:)`. There is no integration test that verifies the end-to-end path: archive a thread via the ViewModel, then confirm it is no longer searchable. Add a test using the existing `StaticMockChannel` + an in-memory `SearchIndex`. Index the thread before sync, run `archive(thread:)`, assert `searchIndex.search(query: someKnownTerm)` returns empty. Guards against future refactors accidentally removing the `delete` call.
- success_criteria:
  - `testArchiveRemovesThreadFromSearchIndex` — thread not findable after archive
  - Uses in-memory `SearchIndex` (not a mock) for realistic FTS5 behavior
  - No production code changes
- test_plan: 1 new test in `InboxViewModelTests.swift`; inject `SearchIndex(databaseURL: nil)` into the ViewModel under test.

### REP-137 — PromptBuilder: oversized system instruction guard
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Services/PromptBuilder.swift`, `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder` enforces a 2000-char message budget by dropping oldest messages first. However, if the tone system instruction itself exceeds the budget (e.g. a user pastes a 3000-char voice description), the current code may produce a prompt that overshoots the budget or silently drops all messages. Add a guard: if the system instruction length ≥ budget, truncate the instruction to `budget - 200` chars (leaving 200 chars minimum for at least the most-recent message). Tests: `testOversizedSystemInstructionTruncatedToFit` — 3000-char instruction + 1 short message produces a prompt ≤ total budget; `testOversizedSystemInstructionPreservesAtLeastOneMessage` — most-recent message still appears in output despite instruction truncation.
- success_criteria:
  - Guard added in `PromptBuilder` for system instruction overflow
  - `testOversizedSystemInstructionTruncatedToFit` — prompt within budget
  - `testOversizedSystemInstructionPreservesAtLeastOneMessage` — at least one message in output
  - Existing PromptBuilderTests remain green (short instructions unaffected)
- test_plan: 2 new tests in `PromptBuilderTests.swift` using a 3000-char fabricated tone instruction.

### REP-138 — DraftEngine: dismiss() deletes corresponding DraftStore entry
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: `DraftStore` (REP-066) persists draft text to disk when the engine reaches `.ready`. If the user explicitly dismisses a draft (⌘. → `DraftEngine.dismiss(threadID:tone:)`), the stored file should be deleted so the stale draft does not reappear on the next launch. Add `store?.delete(threadID:)` in the dismiss path (transition to `.idle`). Tests: after prime→ready→dismiss, `DraftStore.read(threadID:)` returns nil; dismiss on a thread with no stored draft is a no-op (no crash); re-prime after dismiss generates a fresh draft and writes a new store entry.
- success_criteria:
  - `DraftEngine.dismiss()` calls `store?.delete(threadID:)` on transition to `.idle`
  - `testDismissClearsStoredDraft` — `DraftStore.read` returns nil after dismiss
  - `testDismissWithNoStoredDraftIsNoop` — no crash when dismissing a thread with no stored draft
  - `testReprimingAfterDismissWritesNewEntry` — fresh draft written after dismiss+prime cycle
  - Existing DraftEngineTests remain green
- test_plan: 3 new tests in `DraftEngineTests.swift` using `DraftStore` with injected temp directory.

### REP-140 — SearchIndex: concurrent upsert+delete interleaving does not corrupt FTS5 state
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/SearchIndexTests.swift`
- scope: REP-057 added a concurrent search+upsert stress test. A concurrent upsert+delete race for the same `threadID` is not covered. Using `DispatchQueue.concurrentPerform(iterations:)`, fire 10 upserts and 10 deletes of the same thread ID concurrently. After completion, assert: no crash; the index is in a consistent state (thread findable or not — no partial row corruption); `search(query:)` returns `[threadID]` or `[]`, never throws. No production code changes expected (SQLite WAL serialization should handle this).
- success_criteria:
  - `testConcurrentUpsertDeleteNoCrash` — 10 upserts + 10 deletes of same thread complete without crash
  - `testConcurrentUpsertDeleteConsistentState` — post-race search returns array or empty, never throws
  - No production code touched
- test_plan: 2 new tests in `SearchIndexTests.swift`; use in-memory FTS5 (`SearchIndex(databaseURL: nil)`).

### REP-141 — ContactsResolver: batchResolve result has one entry per input handle, including nil
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/ContactsResolverTests.swift`
- scope: `batchResolve([String])` (REP-037) resolves handles via cache then store. Pin the mixed-case result contract: given handles `["alice@example.com", "bob@example.com", "charlie@example.com"]` where alice and charlie are resolvable and bob is not, the result dict must have exactly 3 keys — alice: non-nil, bob: nil, charlie: non-nil. Also verify that cached handles do NOT cause a second store lookup (store call count ≤ number of uncached handles). Catches any result-keyset bugs or extra store hits.
- success_criteria:
  - `testBatchResolveResultKeySetMatchesInputHandles` — result has one key per input handle
  - `testBatchResolveUnresolvableHandleMapsToNil` — unresolvable handle present as nil, not absent
  - `testBatchResolveCacheHitsDoNotInvokeStore` — cached handles bypass store lookup
  - Existing ContactsResolverTests remain green
- test_plan: 3 new tests in `ContactsResolverTests.swift` using mock `ContactsStoring` with call-count tracking.

### REP-143 — RulesStore: `rules` backing array preserves insertion order independent of priority
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RulesStore.rules` is the insertion-order backing array. `RuleEvaluator.matching` sorts by priority at evaluation time and must not affect `rules` order. Pin this invariant: adding rule A (priority 0) then rule B (priority 5) results in `rules = [A, B]`, not `[B, A]`. The UI relies on `rules` for creation-order display. Tests: rules appended not inserted by priority; persist+reload preserves file order; `update()` changes fields without reordering.
- success_criteria:
  - `testRulesArrayPreservesInsertionOrder` — lower-priority rule added first stays at `rules[0]`
  - `testLoadFromJSONPreservesFileOrder` — persist+reload order matches original
  - `testUpdateDoesNotReorderRules` — updating a rule's priority does not move it in the array
  - Existing RulesTests remain green
- test_plan: 3 new tests in `RulesTests.swift` using isolated `RulesStore` with injectable `UserDefaults`.

### REP-144 — SmartRule: unknown RuleAction `kind` decoded gracefully without crash
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/RulesTests.swift`
- scope: `RuleAction` uses a `kind` discriminator. If a future version introduces a new action and an older decoder encounters it, the app should not crash. REP-024 covers malformed-rule skipping at the `RulesStore` level; this task tests the Codable layer directly: decode JSON with `"kind": "unknown_future_action"`, assert a `DecodingError` is thrown (not a trap), and verify `RulesStore.load()` with such a JSON skips the offending rule and loads all remaining rules cleanly. Documents the forward-compatibility contract.
- success_criteria:
  - `testUnknownRuleActionKindThrowsDecodingError` — unknown kind throws `DecodingError`, not crash
  - `testRulesStoreSkipsRuleWithUnknownAction` — load with unknown-action JSON skips that rule, loads rest
  - Existing RulesTests remain green
- test_plan: 2 new tests in `RulesTests.swift` using hand-crafted JSON fixtures.

### REP-145 — PromptBuilder: empty message list produces non-empty valid prompt
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/PromptBuilderTests.swift`
- scope: `PromptBuilder.buildPrompt(messages:tone:)` is always called with at least one message in production, but a newly-created thread or a thread whose messages all failed to load could pass an empty array. Verify: empty messages + a tone → no crash, non-empty prompt string containing the tone instruction. Also pin: single-message input → prompt contains that message body. No production code changes expected.
- success_criteria:
  - `testEmptyMessagesProducesNonEmptyPrompt` — non-empty string returned, no crash
  - `testEmptyMessagesPromptContainsToneInstruction` — returned prompt includes tone text
  - `testSingleMessagePromptContainsMessageText` — single message body appears in output
  - Existing PromptBuilderTests remain green
- test_plan: 3 new tests in `PromptBuilderTests.swift` using fabricated tone and empty/single-element message arrays.

### REP-147 — DraftStore: concurrent write+read for same threadID is race-free
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-213000
- files_to_touch: `Tests/ReplyAITests/DraftStoreTests.swift`
- scope: `DraftStore.write` and `read` operate on files in a shared directory. Concurrent calls from async `DraftEngine` operations could race. Using `DispatchQueue.concurrentPerform`, fire 10 concurrent writes of different text values and 10 concurrent reads for the same `threadID`. Assert: no crash; after all operations complete, `read(threadID:)` returns a valid non-empty String; the file is not corrupted. No production code changes expected if APFS `write(to:atomically:)` is used.
- success_criteria:
  - `testConcurrentWriteReadNoCrash` — 10 concurrent writes + 10 reads complete without crash
  - `testConcurrentWriteResultIsValid` — post-race read returns a valid string, not nil or garbled
  - No production code touched
- test_plan: 2 new tests in `DraftStoreTests.swift`; injected temp directory; `tearDownWithError` cleans up.


### REP-132 — DraftEngine: rapid regenerate() calls do not spawn parallel LLM streams
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: The concurrent prime guard (REP-049) prevents two simultaneous `prime()` calls. `regenerate()` should exhibit the same serialization: if called while a draft is `.loading`, the second call should cancel the first and start fresh (or be dropped), not run two streams in parallel. Using a `StubLLMService` with a configurable delay, call `regenerate()` for the same `(threadID, tone)` twice in quick succession. Assert the engine reaches exactly one `.ready` state (not two), and the draft counter increments by 1, not 2. Tests the invariant without timing dependencies by using a slow stub.
- success_criteria:
  - `testRapidRegenerateProducesOneDraftState` — final state is `.ready` exactly once
  - `testRapidRegenerateDoesNotDoubleDraftCount` — draft acceptance count not doubled
  - No production code changes if the guard already exists (test confirms invariant); add guard if not
- test_plan: 2 new tests in `DraftEngineTests.swift` using a slow `StubLLMService` with `Task.sleep` before yielding.


### REP-131 — ChatDBWatcher: stop() idempotency test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `Tests/ReplyAITests/ChatDBWatcherTests.swift`
- scope: `ChatDBWatcher.stop()` cancels the DispatchSource. If called twice (e.g. from a `deinit` race with an explicit stop), the second cancel on an already-cancelled source must not crash. Add a test: start a watcher, call `stop()` twice in succession, assert no crash (no `preconditionFailure` or `EXC_BAD_ACCESS`). Additionally, verify the watcher's callback is NOT invoked after the first `stop()` — a spurious callback after cancellation would indicate the source was not cancelled correctly. No production code changes expected.
- success_criteria:
  - `testDoubleStopDoesNotCrash` — calling stop() twice never traps
  - `testCallbackNotFiredAfterStop` — watcher callback is silent after stop()
  - No production code touched
- test_plan: 2 new tests in `ChatDBWatcherTests.swift`; use a temp file as the watched path (existing pattern in that test file).


### REP-127 — DraftEngine: trim leading/trailing whitespace from accumulated LLM stream output
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-210000
- files_to_touch: `Sources/ReplyAI/Services/DraftEngine.swift`, `Tests/ReplyAITests/DraftEngineTests.swift`
- scope: LLMs commonly emit drafts with leading newlines (`"\n\nHello"`) or trailing whitespace (`"Hello   \n"`). When the stream accumulator transitions from `.loading` to `.ready(text:)`, apply `.trimmingCharacters(in: .whitespacesAndNewlines)` to the accumulated text before storing. Tests: `StubLLMService` configured to return a draft with leading newlines → state is `.ready("Hello")` not `.ready("\n\nHello")`; trailing whitespace draft → trimmed; whitespace-only draft → `.ready("")` without crash.
- success_criteria:
  - `DraftEngine` trims accumulated text before `.ready` transition
  - `testDraftLeadingNewlinesTrimmed` — leading whitespace removed
  - `testDraftTrailingWhitespaceTrimmed` — trailing whitespace removed
  - `testWhitespaceOnlyDraftReturnsEmptyString` — all-whitespace input yields empty `.ready` without crash
  - Existing DraftEngineTests remain green
- test_plan: 3 new tests in `DraftEngineTests.swift`; extend `StubLLMService` fixture with configurable draft text or add a second stub variant.


*(Planner moves finished items here each day. Worker never modifies this section.)*

### REP-148 — RuleEvaluator: `apply()` output contract tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-149 — Stats: `acceptanceRate(for:)` nil-vs-zero distinction
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-150 — SearchIndex: `Result` struct fields populated correctly from upsert data
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-151 — IMessageChannel: `secondsSinceReferenceDate` autodetect at exact magnitude boundary
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-152 — PromptBuilder: all-messages-from-same-sender produces valid prompt
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-153 — DraftEngine: `invalidate()` on uncached thread is idempotent
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-154 — RulesStore: `update()` with unknown UUID is a no-op
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-157 — SmartRule: empty `and([])` evaluates to vacuous true
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-158 — IMessageSender: `chatGUID(for:)` format for 1:1 vs group thread
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-160 — Stats: concurrent mixed-counter stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-161 — SmartRule: `textMatchesRegex` with anchored patterns (^ and $)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-020741

### REP-166 — RuleEvaluator: empty-rules-array edge cases (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-172 — AttributedBodyDecoder: zero-length and all-zero blobs return nil (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-173 — ChatDBWatcher: repeated stop→reinit cycles complete without crash (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-174 — IMessageSender: special-character escaping in AppleScript string construction
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-175 — RulesStore: `import()` merge-not-replace semantics (test-only)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-063646

### REP-105 — Stats: persist lifetime counters to disk across app launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-064432

### REP-139 — Stats: flushNow() for clean-shutdown counter persistence
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-064432

### REP-159 — IMessageChannel: `MessageThread.hasAttachment` from message-level SQL field
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-064432

### REP-146 — IMessageChannel: per-thread message cap applied independently across threads
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-055654

### REP-156 — ContactsResolver: `name(for:)` fallback to raw handle when store returns nil
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-055654

### REP-066 — DraftEngine: persist draft edits to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-202900

### REP-115 — Preferences: `pref.app.launchCount` key + increment on startup
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-110 — RulesStore: export format version field for schema evolution
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-108 — ContactsResolver: flush cache on CNContactStoreDidChange notification
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-117 — IMessageChannel: graceful handling of deleted/unsupported messages (NULL text + NULL attributedBody)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-201500

### REP-125 — SearchIndex: upsert replaces preview text for existing thread (no ghost terms)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-119 — SearchIndex: `search(query:limit:)` cap to prevent unbounded result sets
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-118 — DraftEngine: evict draft cache entry on thread archive
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-116 — SmartRule: `hasUnread` predicate for unread-thread matching
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-195000

### REP-124 — InboxViewModel: pinned threads sort above unpinned threads after sync
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-123 — Stats: rulesMatchedCount ≤ rulesEvaluated invariant test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-122 — IMessageChannel: date autodetect boundary test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-121 — PromptBuilder: truncation preserves most-recent message with large payload
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-120 — RulesStore: concurrent add stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-191500

### REP-114 — DraftEngine: LLM error path surfaces in DraftState
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-109 — SearchIndex: channel-filter integration test with two-channel data
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-104 — Preferences: graceful handling of unrecognized UserDefaults keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-103 — InboxViewModel: thread list sorted by recency after sync
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-101 — AGENTS.md: fix stale test-count line in Testing expectations
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-099 — SearchIndex: delete then re-insert round-trip (FTS5 tombstone check)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-098 — DraftEngine: per-(threadID,tone) cache isolation test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-174500

### REP-074 — ContactsResolver: per-handle cache TTL (30 min) for post-launch contact changes
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-095 — IMessageChannel: per-thread message-history cap
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-096 — InboxViewModel: send() success/failure state transition tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-097 — Stats: concurrent increment stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-100 — SmartRule: `not` predicate evaluation + double-negation tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-102 — SearchIndex: empty-query returns empty list
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-150000

### REP-106 — SmartRule: `messageAgeOlderThan(hours:)` predicate
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-107 — DraftEngine: explicit dismiss() state-transition tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-112 — PromptBuilder: tone system instruction distinctness test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-113 — SmartRule: `or` predicate with 3+ branches evaluation
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-163000

### REP-041 — SearchIndex: persist FTS5 index to disk between launches
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-144200

### REP-073 — PromptBuilder: most-recent-message invariant + short-thread passthrough test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-144200

### REP-032 — Stats: draft acceptance rate per tone
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120935

### REP-035 — RulesStore: export + import rules via JSON file URL
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-142600

### REP-037 — ContactsResolver: batch resolution helper for initial sync
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-141222

### REP-038 — MLXDraftService: mocked cancellation + load-progress test coverage
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120200

### REP-042 — AGENTS.md: update What's done commit log + test count post-wip-merge
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-142600

### REP-053 — InboxViewModel: archive + unarchive thread round-trip tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-054 — DraftEngine: invalidate stale draft when watcher fires new messages
- priority: P2
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-141222

### REP-058 — RulesStore: lastFiredActions observable for debug surface
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120200

### REP-061 — AttributedBodyDecoder: fuzz test with randomized malformed blobs
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-070 — Stats: per-channel messages-indexed counter
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-120200

### REP-084 — IMessageChannel: test coverage for NULL message.text + attributedBody fallback path
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-093 — IMessageSender: consolidate isDryRun into executeHook pattern
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-094 — Stats: rulesMatchedCount counter (distinct from rulesEvaluated)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-130300

### REP-080 — SearchIndex: channel TEXT column in FTS5 for per-channel filtered search
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-122448

### REP-085 — SearchIndex: prefix-match query support for ⌘K partial-word search
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-122448

### REP-092 — SearchIndex: sanitize FTS5 special-character input
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-122448

### REP-001 — persist `lastSeenRowID` across app launches
- priority: P0
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-172426

### REP-002 — SmartRule priority + conflict resolution
- priority: P0
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-172426

### REP-003 — better AttributedBodyDecoder (real typedstream parser)
- priority: P0
- effort: L
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-173600

### REP-004 — thread-list filter for `silentlyIgnore` action parity
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128

### REP-005 — observability: counters in `.automation/stats.json`
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181957

### REP-006 — IMessageSender: test AppleScript escaping against weird inputs
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128

### REP-007 — ChatDBWatcher test coverage (debounce + cancel)
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182346

### REP-008 — contextual preview: link + attachment detection
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-183617

### REP-011 — ContactsResolver: cache + access-state unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-183251

### REP-012 — RulesStore: remove / update / resetToSeeds test coverage
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-181128

### REP-013 — Preferences: factory-reset + defaults round-trip tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-183849

### REP-014 — IMessageChannel: SQL query + date-autodetect unit tests
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182949

### REP-015 — SearchIndex: incremental upsert path for watcher events
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-182615

### REP-018 — SmartRule: isGroupChat + hasAttachment predicates
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-222600

### REP-019 — ContactsResolver: E.164 phone number normalization before cache lookup
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-222600

### REP-020 — IMessageChannel: filter reaction + delivery-status rows from thread preview
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-222600

### REP-021 — IMessageChannel: configurable thread-list pagination
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-223700

### REP-022 — InboxViewModel: concurrent sync guard
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-025439

### REP-023 — InboxViewModel: rule re-evaluation when RulesStore changes
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-043231

### REP-024 — RulesStore: validate + skip malformed rules on load
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-21-025439

### REP-025 — IMessageSender: AppleScript execution timeout
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-013926

### REP-026 — DraftEngine: extract + test prompt template construction
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055650

### REP-027 — SearchIndex: multi-word AND query support
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-020653

### REP-028 — UNNotification: register inline reply action on launch
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-032627

### REP-029 — IMessageChannel: SQLITE_BUSY graceful retry
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-030 — Preferences: pref.inbox.threadLimit setting
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633

### REP-031 — SmartRule: textMatchesRegex pattern validation at creation time
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633

### REP-033 — SearchIndex: add BM25 ranking tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-034 — DraftEngine: draft cache eviction for idle entries
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-042232

### REP-036 — IMessageChannel: Message.isRead from chat.db is_read column
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-039 — Preferences: pref.drafts.autoPrime toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-111201

### REP-040 — IMessageSender: dry-run mode for test harness
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-061633

### REP-049 — DraftEngine: concurrent prime guard
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-011918

### REP-050 — Extract `Locked<T>` generic wrapper to consolidate NSLock pattern
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-040356

### REP-051 — IMessageChannel: preserve sqlite3 result code in ChannelError
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-011918

### REP-052 — ChatDBWatcher: FSEvents error recovery with restart backoff
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-041448

### REP-055 — IMessageChannel: map message.date_delivered to Message.deliveredAt
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-055942

### REP-056 — Stats: weekly aggregate file writer
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-042232

### REP-057 — SearchIndex: concurrent search + upsert stress test
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-042232

### REP-059 — IMessageSender: retry once on errOSAScriptError (-1708)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-063 — SearchIndex: delete(threadID:) for archived thread cleanup
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

### REP-064 — IMessageSender: 4096-char message length guard
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-065 — RuleEvaluator: senderIs case-insensitive matching
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

### REP-068 — IMessageChannel: project cache_has_attachments to Message.hasAttachment
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-054016

### REP-069 — RulesStore: 100-rule hard cap with graceful rejection
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-071 — InboxViewModel: thread selection model tests
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-111201

### REP-072 — InboxViewModel: consume pending UNNotification inline reply
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-064413

### REP-076 — InboxViewModel: mark thread as read on selection
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-077 — IMessageChannel: SQLITE_NOTADB graceful error for corrupted chat.db
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-078 — NotificationCoordinator: test coverage for handleNotificationResponse
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-065225

### REP-081 — Preferences: pref.rules.autoApplyOnSync toggle
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-22-111201

### REP-142 — InboxViewModel: watcher-driven sync updates existing thread previewText
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-155 — InboxViewModel: re-selecting same thread does not double-prime
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-167 — Preferences: all AppStorage key strings are distinct (regression guard)
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-168 — InboxViewModel: isSyncing flag transitions during syncFromIMessage
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-171 — Stats: snapshot() dictionary contains all expected counter keys
- priority: P2
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-025721

### REP-199 — InboxViewModelAutoPrimeTests: fix non-deterministic crashes under Swift 6 + macOS 26.3
- priority: P1
- effort: M
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326

### REP-201 — AGENTS.md: correct stale test count 463 → 493 in header
- priority: P1
- effort: S
- ui_sensitive: false
- status: done
- claimed_by: worker-2026-04-23-091326

---

## Decomposed (archive)

### REP-500 — extract MLX to separate SPM target so test compile doesn't link MLX (structural unblock for wip queue)
- priority: P0
- effort: L
- ui_sensitive: false
- status: decomposed
- claimed_by: architect-2026-04-24
- decomposed_into: [REP-501, REP-502, REP-503, REP-504, REP-505]
- files_to_touch:
  - `Package.swift` (restructure: 2 library targets + 1 executable + 1 test target)
  - `Sources/ReplyAI/Services/MLXDraftService.swift` → `Sources/ReplyAIMLX/MLXDraftService.swift` (MOVE)
  - `Sources/ReplyAI/App/ReplyAIApp.swift` → `Sources/ReplyAIApp/ReplyAIApp.swift` (MOVE — the @main file)
  - All remaining files under `Sources/ReplyAI/**` → `Sources/ReplyAICore/**` (preserve subdirectory structure: Theme/, Components/, Channels/, Rules/, Services/, Inbox/, MenuBar/, Screens/, Resources/, Fixtures/, Models/)
  - `Sources/ReplyAIApp/ReplyAIApp.swift` gains `import ReplyAICore` + `import ReplyAIMLX`
  - `Sources/ReplyAIMLX/MLXDraftService.swift` gains `import ReplyAICore` (for `LLMService` + `DraftChunk`)
  - `Tests/ReplyAITests/*.swift` imports change from `@testable import ReplyAI` → `@testable import ReplyAICore`
  - `scripts/build.sh` path references change `Sources/ReplyAI/Resources/*` → `Sources/ReplyAICore/Resources/*`
- scope: **Structural root-cause fix for the wip-queue drain bottleneck.** The MLX C++ dependency (via `mlx-swift-lm`) adds 45–90 min of cold compile time to `swift test`, far beyond the 13-min worker budget. As of 2026-04-24 this is the root cause of 20+ stranded wip branches awaiting manual human verification (see REP-254). REP-254 is addressing the symptom via caching and the new replyai-merger. This task addresses the **cause**: tests should never link MLX because they already stub `LLMService`.

  **Target structure after this change:**
  - `ReplyAICore` (library target): everything currently in `Sources/ReplyAI/` EXCEPT `Services/MLXDraftService.swift` and `App/ReplyAIApp.swift`. Depends on `swift-huggingface` + `swift-transformers` only. **No MLX dependency.**
  - `ReplyAIMLX` (library target): only `Services/MLXDraftService.swift`. Depends on `ReplyAICore` + `mlx-swift-lm` (all three products: MLXLLM, MLXLMCommon, MLXHuggingFace).
  - `ReplyAI` (executable target): only `App/ReplyAIApp.swift` + `@main`. Depends on `ReplyAICore` + `ReplyAIMLX`. Production app links everything.
  - `ReplyAITests` (testTarget): depends **only** on `ReplyAICore`. Never imports MLX. Uses the existing `StubLLMService` for draft tests.

  **Files under `Sources/ReplyAI/` move to `Sources/ReplyAICore/` with original relative paths preserved.** The only exceptions:
  - `Sources/ReplyAI/Services/MLXDraftService.swift` → `Sources/ReplyAIMLX/MLXDraftService.swift`
  - `Sources/ReplyAI/App/ReplyAIApp.swift` → `Sources/ReplyAIApp/ReplyAIApp.swift`

  **`scripts/build.sh`:** update any `Sources/ReplyAI/Resources/*` refs to `Sources/ReplyAICore/Resources/*`. Verify the final `.app` bundle still lands the resources and entitlements identically.

  **Import work:** within ReplyAICore, all files are in the same target so no import changes needed. `ReplyAIApp.swift` must `import ReplyAICore` + `import ReplyAIMLX`. `MLXDraftService.swift` must `import ReplyAICore` (for `LLMService` and `DraftChunk`). Test files change `@testable import ReplyAI` → `@testable import ReplyAICore`.

  **Validation order:** (1) `swift package show-dependencies` after: confirm `ReplyAITests` does NOT resolve `mlx-swift-lm`. (2) `time swift test` from a fresh clone: target <10 min. (3) `./scripts/build.sh debug`: produces launchable `.app`. (4) Launch `.app`, enable MLX toggle in Settings, verify draft generation still works (MLX path intact in production).

  **Expected time:** L-effort, probably 2–4 worker fires even on warm cache. First fire: do the file moves + Package.swift rewrite, probably timeout, push to wip. Second fire: fix build errors surfaced by the move. Third fire: fix test compile errors. Merge via merger once green. Reviewer highlights this in the 2026-04-24 16:10 UTC window as the "larger task... L, P1... would unblock everything downstream."

- success_criteria:
  - `swift test` runs in under 5 minutes on warm cache, under 10 minutes on cold cache (previously 45–90 min cold)
  - All existing tests pass — zero regressions in test count (baseline 527+ as of 2026-04-24)
  - `./scripts/build.sh debug` succeeds and produces a launchable `.app`
  - The produced `.app` functions identically — MLX draft generation works in Settings toggle, AppleScript send works, all channels work
  - `swift package show-dependencies --target ReplyAITests` does NOT include `mlx-swift-lm`
- test_plan:
  - Baseline: before any change, run `time swift test` on a cold clone, record build time
  - After change: `time swift test` on cold clone (same machine), confirm <10 min
  - `grep -rh "^\s*func test" Tests/ReplyAITests/ | wc -l` before/after — must be equal or higher
  - Manual app launch with MLX enabled in Settings, verify `MLXDraftService.draft(...)` stream produces tokens
  - `swift package show-dependencies --target ReplyAITests 2>&1 | grep mlx` must return empty

