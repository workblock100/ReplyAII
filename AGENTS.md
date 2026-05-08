# AGENTS.md — ReplyAI handoff

Read this before you touch anything. It's the shortest path to productive edits without asking the human redundant questions.

## Strategic direction (2026-04-23 pivot)

**ReplyAI's `chat.db` + Full Disk Access read path is unreliable in practice.** Even with FDA granted by the user, the integration hits intermittent disconnections and silent failures we can't consistently fix. The product direction has pivoted: **stop chasing FDA. Find practical alternatives.**

New priorities for the autonomous agents (planner, worker, reviewer):

1. **Alternative message-source architectures** — AppleScript via `tell application "Messages"` (uses Automation permission, not FDA), Accessibility API reading of the Messages.app window, UNNotification passive capture of incoming messages, Shortcuts.app export flows that a user triggers manually, or hybrids of the above. None require FDA.
2. **Non-iMessage channels as first-class citizens** — Slack (OAuth + Socket Mode is clean and already partially specced), WhatsApp via hosted WebView, Telegram Bot API, Teams via Graph API, SMS relay from iPhone via CloudKit. The app should be valuable to a user with iMessage integration completely disabled.
3. **UX and practicality polish (channel-agnostic)** — onboarding that handles every permission-denied state gracefully, error states that tell the user what to do, a fixture-driven demo mode so the app is usable with zero permissions granted, keyboard shortcut refinement, composer and draft polish, MenuBar popover quality, Smart Rules UI clarity, Settings → per-channel enable/disable.

**Deprioritized** (existing code stays as reference, but don't invest new cycles):
- `AttributedBodyDecoder` rich-text parsing improvements
- `ChatDBWatcher` refinements and reinit cycles
- New `chat.db` SQL queries or optimizations
- FDA prompt flow tweaks
- Any task whose "done" state assumes the user granted FDA and `chat.db` reads work

Existing tests and defensive internals already shipped against the chat.db path stay — they're not wasted. The pivot is about where new effort goes. The iMessage code path isn't being deleted; it's being flanked with alternatives so the product is usable whether or not FDA works for a given user.

## What ReplyAI is

Native macOS app (SwiftUI, macOS 14+) that unifies iMessage + Slack + WhatsApp + Teams + SMS + Telegram into a single keyboard-first inbox and drafts replies in the user's voice via an on-device LLM. Dark-only v1. Keyboard-first (`⌘↵` send, `⌘J` regen, `⌘/` tone, `⌘.` dismiss, `⌘K` palette, `⌘⇧R` global).

- **Repo root**: `~/Code/ReplyAI`
- **Design references** (read-only, source of truth for pixels/copy): `~/ReplyAI_work/design_handoff_replyai/` — `prototype.html` + `components/*.jsx` + `README.md`
- **Build output**: `~/Code/ReplyAI/build/ReplyAI.app`
- **User data** (Preferences, rules): `~/Library/Application Support/ReplyAI/`
- **Model cache** (MLX weights when enabled): `~/Library/Caches/huggingface/hub/`

## Build & run

SwiftPM builds without Xcode. Xcode is installed at `/Applications/Xcode.app` and `xcode-select` points at it. Either path works.

```bash
# SwiftPM path (fastest iteration):
cd ~/Code/ReplyAI
./scripts/build.sh debug open   # compile, bundle, codesign, launch
./scripts/build.sh release      # release build, doesn't launch
swift test                      # run the XCTest suite

# Xcode path:
xcodegen generate && open ReplyAI.xcodeproj
# then ⌘R inside Xcode
```

The bundler script (`scripts/build.sh`) substitutes `$(VAR)` placeholders in `Info.plist` at bundle time and applies the entitlements at ad-hoc codesign time. Do not bypass it — macOS will refuse to launch a bundle where entitlements don't match the signature.

## Running app expectations

- PID will show up under `ps aux | grep ReplyAI/build`. Stable at ~130–150 MB idle; spikes on sync.
- Two windows: the prototype gallery (default) and "inbox" (secondary, opened via menu-bar "Open inbox" or `⌘⇧O` from gallery).
- Menu-bar `R` icon (`MenuBarExtra`) with waiting-threads popover.
- Crash logs: `~/Library/Logs/DiagnosticReports/ReplyAI-*.ips`.

## Repo layout

```
Sources/ReplyAI/
├── App/ReplyAIApp.swift           @main + Scene graph (WindowGroup × 2 + MenuBarExtra)
├── Theme/Theme.swift              Color / Font / Radius / Space / Motion tokens
├── Models/                        Channel, MessageThread, Message, Folder, Tone
├── Fixtures/Fixtures.swift        Seed threads/drafts from reply-app.jsx
├── Components/                    Avatar, Card, Caret, ChannelDot, InboxFrame,
│                                  KbdChip, KbdKey, MiniButton, PillToggle,
│                                  PrimaryButton + GhostButton, SectionLabel
├── Channels/
│   ├── ChannelService.swift       Protocol + ChannelError
│   ├── IMessageChannel.swift      chat.db reader (SQLite3 direct), contacts injection
│   ├── ContactsResolver.swift     CNContactStore, NSLock-guarded cache, @unchecked Sendable
│   ├── AttributedBodyDecoder.swift Best-effort typedstream scanner for rich messages
│   ├── ChatDBWatcher.swift        DispatchSource.makeFileSystemObjectSource + 600ms debounce
│   └── IMessageSender.swift       NSAppleScript → Messages.app (`tell application "Messages"`)
├── Rules/
│   ├── SmartRule.swift            Predicate + Action DSL, hand-written Codable w/ "kind" discriminator
│   ├── RuleEvaluator.swift        Pure-func evaluator + defaultTone extraction
│   └── RulesStore.swift           @Observable @MainActor, atomic JSON writes
├── Services/
│   ├── LLMService.swift           Protocol returning AsyncThrowingStream<DraftChunk>
│   ├── StubLLMService.swift       Fake streams from Fixtures.drafts / genericAcknowledgment
│   ├── MLXDraftService.swift      mlx-swift-lm 3.x via #huggingFaceLoadModelContainer macro
│   ├── DraftEngine.swift          Per-(threadID, tone) cache + prime/regenerate/dismiss
│   └── Preferences.swift          @AppStorage keys + defaults + wipe
├── Inbox/
│   ├── InboxScreen.swift          Root of the real inbox window
│   ├── InboxViewModel.swift       @Observable @MainActor: threads, sync, edits, send, rules-ish
│   ├── FDABanner.swift            Full Disk Access deep-link banner
│   ├── SendConfirmSheet.swift     Two-button sheet before AppleScript send
│   ├── Sidebar/SidebarView.swift  + sync chip footer
│   ├── ThreadList/ThreadListView.swift + ThreadRow.swift
│   ├── Thread/                    ThreadDetailView, MessageBubble, ContextCard
│   └── Composer/                  ComposerView (editable TextEditor), TonePills
├── MenuBar/MenuBarContent.swift   Real popover (counterpart to sfc-menubar mock)
├── Screens/                       All 34 gallery screens + router
│   ├── ScreenID.swift             + ScreenInventory + ScreenMeta
│   ├── ScreenRouter.swift         switch (ScreenID) -> View
│   ├── AppPrototypeView.swift     Gallery shell (sidebar + top bar + content + footer)
│   ├── _Placeholders.swift        Empty (all 34 screens now real)
│   ├── Onboarding/ (9)            Share OnboardingStage
│   ├── MainApp/ (3)               Inbox variants (empty/loading/offline) over InboxFrame
│   ├── Threads/ (3)               thr-group, thr-media (typed-stream image/voice), thr-long
│   ├── Composer/ (3)              cmp-custom, cmp-lowconf, cmp-nothing
│   ├── Surfaces/ (5)              Palette (extracted into reusable PalettePopover), Snooze,
│   │                              Rules (wired to RulesStore), Menubar, Notification
│   ├── Settings/ (6 + shell)      SetModelView has the MLX toggle + progress reporter
│   └── Errors/ (3)
└── Resources/
    ├── Info.plist                 with $(VAR) placeholders substituted by scripts/build.sh
    ├── ReplyAI.entitlements       SANDBOX IS OFF (FDA requires this)
    ├── Assets.xcassets/
    └── Fonts/                     Inter Tight, Instrument Serif, JetBrains Mono

Tests/ReplyAITests/                ~1888 tests as of 2026-05-08-1410 (1852 pass under the autopilot's three-skip workaround — `--skip ContactsResolverTests --skip InboxViewModelIsSyncingTests --skip InboxViewModelTests` — in ~17s warm; the other ~36 live in those three skipped suites, see gotcha #243). Plus 2 always-skipped in headless: `GlobalHotkeyContractTests` AppKit-touching cases gated behind `RUN_APPKIT_TOUCHING_TESTS=1`; opt-in to exercise locally.
```

## Architecture patterns

- **`@Observable @MainActor` view models** (InboxViewModel, RulesStore). Sub-views take `@Bindable var model` to get bindings.
- **`@Observable` services (DraftEngine)** injected via `.environment(engine)` + `@Environment(DraftEngine.self)`.
- **`LLMService` protocol** is `Sendable` and returns `AsyncThrowingStream<DraftChunk>` synchronously — no `async` on `draft(...)`. Bridge to async work inside the stream's task. This is the MLX-vs-stub swap point.
- **Thread-safe resolvers** (`ContactsResolver`): `@unchecked Sendable`, `NSLock`-guarded cache, sync wrappers (`synced { … }`) so async callers don't hold the lock across an await.
- **Per-weight PostScript-name font lookup** in `Theme.Font` — SwiftUI's `.weight()` modifier on `.custom(...)` is unreliable; we resolve to `InterTight-Medium` / `-SemiBold` / `-Bold` by name.
- **Entitlements applied at codesign time** in `scripts/build.sh`, NOT embedded in the bundle. Changing `Resources/ReplyAI.entitlements` requires a rebuild through the script, not just a recompile.

## What's done

Commits (newest first; run `git log` for detail):

- `e5074e2` AccessibilityAPIReader (AX-based alt message source, injectable seams, 6 tests) + IMessageSender.retryDelay injectable (removes hardcoded 0.5s sleep, 1 new test + 3 updated) — REP-258+269 (now landed on main; the original wip branch was reabsorbed when REP-501-style consolidation merged through)
- `8cf5a15` per-channel Preferences keys + not(not(pred)) guard + concurrent add+remove tests — REP-231+208+220 (landed on main)
- `ce76f2a` SlackSocketClient: WebSocket wrapper for Socket Mode, injectable seams, 5 tests — REP-267 (landed on main; see Sources/ReplyAI/Channels/SlackSocketClient.swift + SlackSocketClientTests)
- `6ae9022` Thread-list cache for cold-launch resilience — REP-278 (landed on main)
- `ea6fc52` ViewState enum + 4 transition tests — REP-247 (landed on main; see also `a819f59` ViewState + SlackTokenStore consolidation)
- `08f2e4b` AGENTS.md + worker.prompt: MLX cold-build warning and wip-branch protocol documented (REP-271, worker-2026-04-24-110000, 527 tests unchanged)
- `9a6c3d1` MessagesAppActivationObserver (NSWorkspace activation watcher, 600ms debounce, injectable seams) + InboxViewModel activation re-sync wiring (5s debounce, weak capture, handleMessagesActivation) (REP-239, REP-265, worker-2026-04-24-102657, 521→527 tests)
- `31534e1` NotificationCoordinator/InboxViewModel: chatGUID extraction from `CKChatIdentifier`/`CKChatGUID` userInfo keys, thread deduplication in applyIncomingNotification (REP-263, worker-2026-04-24-060000, 516→521 tests)
- `fbba843` LocalhostOAuthListener: NWListener-backed loopback HTTP server for OAuth callbacks, `actualPort`/`onReady` test hooks, `OAuthError` enum + 3 new tests; AGENTS.md sync (REP-230, REP-253, worker-2026-04-24-042000, 513→516 tests)
- `b2af590` NotificationCoordinator passive incoming-message capture via willPresent + InboxViewModel applyIncomingNotification (REP-235, worker-2026-04-24-015900, 510→513 tests)
- `c001d7e` KeychainHelper set/get/delete Keychain wrapper + SlackChannel ChannelService stub with token gate (REP-233, REP-234, worker-2026-04-23-171932, 502→510 tests)
- `43d735b` FTS5 snippet extraction (SearchResult type + snippet() col-3 wiring), concurrent-prime stress test, insertion-order disk round-trip, error→idle state transition (REP-067, REP-169, REP-188, REP-189, worker-2026-04-23-111853, 493→502 tests)
- `c8c3a04` InboxViewModelAutoPrimeTests data-race fix via Locked<T> migration + AGENTS.md test count 463→493 (REP-199, REP-201, worker-2026-04-23-091326)
- `1f170b0` SearchIndex.clear(), DraftEngine empty-stream idle fix, +18 contract tests (REP-165,176,180,181,182,184,185,186, worker-2026-04-23-075700)
- `c99f235` per-thread cap contract tests, ContactsResolver handle fallback (REP-146,156, worker-2026-04-23-055654)
- `0102852` Stats lifetime persistence + flushNow() + thread hasAttachment tests (REP-105,139,159, worker-2026-04-23-064432)
- `f40ed9d` isSyncing flag + sync upsert/merge + double-prime guard + key uniqueness + snapshot keys (REP-142,155,167,168,171, worker-2026-04-23-025721)
- `42b518c` AppleScript newline escaping, empty-rules-array boundary, zero-blob decoder, watcher reinit cycles, import merge semantics (REP-166,172,173,174,175, worker-2026-04-23-063646)
- `7512321` apply() contract, acceptanceRate nil/zero, SearchIndex.Result fields, secondsSince boundary, same-sender prompt, invalidate-uncached, update-unknown-UUID, and([]) vacuous-true, chatGUID format, concurrent mixed-counter, anchored regex (REP-148,149,150,151,152,153,154,157,158,160,161, worker-2026-04-23-020741)
- `6d80f9d` timeOfDay predicate, export round-trip test for all predicate kinds (REP-079, REP-133, worker-2026-04-23-000050)
- `7132176` chatGUID validation, firstLaunchDate pref, oversized-prompt guard, dismiss→store delete, disk index round-trip, concurrent race tests (REP-126, REP-128, REP-130, REP-134, REP-137, REP-138, REP-140, REP-141, REP-143, REP-144, REP-145, REP-147, worker-2026-04-22-213000)
- `79fc909` DraftStore: persist completed draft edits to disk between launches (REP-066, worker-2026-04-22-202900)
- `e33be0d` ContactsResolver cache flush, RulesExport version, launchCount pref, NULL-msg placeholder (REP-108, REP-110, REP-115, REP-117, worker-2026-04-22-201500)
- `7181beb` hasUnread predicate, archive→dismiss eviction, search cap 50, upsert ghost-term tests (REP-116, REP-118, REP-119, REP-125, worker-2026-04-22-195000)
- `f5ae41d` concurrent-add stress test, PromptBuilder large-payload, date-boundary, stats-invariant, pinned-sort fix + test (REP-120, REP-121, REP-122, REP-123, REP-124, worker-2026-04-22-191500)
- `4035c5a` cache isolation, delete-reinsert, channel-filter, error-path, ordering, pref-unrecognized, AGENTS.md count (REP-098, REP-099, REP-101, REP-103, REP-104, REP-109, REP-114, worker-2026-04-22-174500)
- `80035e18d6f16e8197320222262df7771182e31b` messageAgeOlderThan predicate, not/or/dismiss/concurrent/tone-distinctness tests (REP-097, REP-100, REP-106, REP-107, REP-112, REP-113, worker-2026-04-22-163000)
- `9879312` ContactsResolver TTL, IMessageChannel message cap, send-state tests, SearchIndex empty-query test (REP-074, REP-095, REP-096, REP-102, worker-2026-04-22-150000)
- `7196e9d` SearchIndex disk persistence + PromptBuilder truncate invariants (REP-041, REP-073, worker-2026-04-22-144200)
- `a5bd7a4` RulesStore: export/import rules via JSON file URL; AGENTS.md sync (REP-035, REP-042, worker-2026-04-22-142600)
- `eaa0b39` fuzz coverage, archive persistence, isDryRun→executeHook, rulesMatchedCount counter (REP-053, REP-061, REP-084, REP-093, REP-094, worker-2026-04-22-130300)
- `fa4d009` DraftEngine: invalidate stale draft on watcher refire; ContactsResolver: batch resolve (REP-054, REP-037, worker-2026-04-22-141222)
- `038826e` per-tone draft counters + acceptance rate on Stats (REP-032, worker-2026-04-22-120935)
- `6a629a2` SearchIndex: channel column filter, FTS5 sanitizer, prefix-match tests (REP-080, REP-085, REP-092, worker-2026-04-22-122448)
- `c114189` per-channel index counter, lastFiredActions debug surface, load-progress + cancellation tests (REP-070, REP-058, REP-038, worker-2026-04-22-120200)
- `874f483` autoPrime + autoApplyOnSync preference flags, InboxViewModel thread-selection test coverage (REP-039, REP-071, REP-081, worker-2026-04-22-111201)
- `7667f22` message length guard, IMessageSender -1708 retry, RulesStore 100-rule cap, mark-as-read on select, SQLITE_NOTADB graceful error, NotificationCoordinator test coverage (REP-059, REP-064, REP-069, REP-076, REP-077, REP-078, worker-2026-04-22-065225)
- `bbedd1a` InboxViewModel: consume pending UNNotification inline reply (REP-072, worker-2026-04-22-064413)
- `3169995` preference keys threadLimit/autoPrime, SmartRule regex validation, IMessageSender dry-run mode (REP-030, REP-031, REP-040, worker-2026-04-22-061633)
- `90e21f6` SQLITE_BUSY retry, isRead/deliveredAt fields, BM25 ranking tests (REP-029, REP-036, REP-055, REP-033, worker-2026-04-22-055942)
- `ec9e723` SearchIndex.delete, senderIs case-insensitive, cache_has_attachments projection (REP-063, REP-065, REP-068, worker-2026-04-22-054016)
- `ea37669` DraftEngine eviction, Stats weekly log, SearchIndex concurrency test (REP-034, REP-056, REP-057, worker-2026-04-22-042232)
- `8988959` ChatDBWatcher: FSEvents error recovery with restart backoff (REP-052, worker-2026-04-22-041448)
- `a7204d2` Locked<T>: extract shared thread-safe value box (REP-050, worker-2026-04-22-040356)
- `9810196` NotificationCoordinator: UNNotification inline reply + category registration (REP-028, worker-2026-04-22-032627)
- `881d8f0` SearchIndex: explicit AND semantics for multi-word queries (REP-027, worker-2026-04-22-020653)
- `9717756` extract PromptBuilder + test coverage (REP-026, worker-2026-04-22-055650)
- `5fedafc` rule re-evaluation on RulesStore change (REP-023, worker-2026-04-22-043231)
- `aa34006` AppleScript send timeout + injectable executor (REP-025, worker-2026-04-22-013926)
- `1df1fce` concurrent prime guard + databaseError result code (REP-049, REP-051, worker-2026-04-22-011918)
- `76850a9` concurrent sync guard + malformed-rule skipping (REP-022, REP-024, worker-2026-04-21-025439)
- `8e9d0d2` IMessageChannel thread-list pagination tests + ChannelService default overload (REP-021, worker-2026-04-21-223700)
- `04e4e1e` isGroupChat/hasAttachment predicates, E.164 normalization, tapback + delivery-receipt filtering (REP-018/019/020, worker-2026-04-21-222600)
- `eca3692` Preferences: injectable `UserDefaults` + register/wipe test coverage (REP-013, worker-2026-04-21-183849)
- `b7c8f8b` Sidebar preview: link + attachment collapsing in `IMessagePreview` (REP-008, worker-2026-04-21-183617)
- `d0b72e1` `ContactsStoring` protocol extraction + full ContactsResolver test coverage (REP-011, worker-2026-04-21-183251)
- `1e8c57e` `IMessageChannel.recentThreads` injectable `dbPathOverride` + in-memory SQLite test coverage (REP-014, worker-2026-04-21-182949)
- `687c5a3` SearchIndex: incremental FTS upsert path for watcher-driven syncs (REP-015, worker-2026-04-21-182615)
- `525870e` ChatDBWatcher: debounce + stop coverage (REP-007, worker-2026-04-21-182346)
- `5097de5` Observability: persistent counters for rules/drafts/indexed messages (REP-005, worker-2026-04-21-181957)
- `1a0f7ba` `silentlyIgnore` parity + AppleScript escape hardening + RulesStore coverage (REP-004/006/012, worker-2026-04-21-181128)
- `e760a12` Real typedstream parser (0x2B tag scan) in AttributedBodyDecoder (REP-003, worker-2026-04-21-173600)
- `753d8803` persist lastSeenRowID across launches; SmartRule priority field + conflict resolution (worker-2026-04-21-172426)
- `33424cc` Automation scaffolding (planner/worker/reviewer cron agents + BACKLOG.md seed)
- `10fce3d` Group chat sending (chat.guid projected + used verbatim by IMessageSender)
- `2d9110d` Incoming-message rule actions (archive / markDone / silentlyIgnore) fire on watcher refire
- `82f544e` Thread list: pinned threads float top + inline pin indicator
- `5f2a746` ⌘K palette: real FTS5 search over live threads
- `151217c` Rules fire on thread select + initial sync (setDefaultTone + pin)
- `52d30f8` AGENTS.md for Codex
- `9c86704` Smart Rules DSL + store + live UI
- `f06b7ce` Model-load progress banner above the inbox
- `28e2e74` MLX take 2: on-device drafts behind Settings toggle
- `584ef3d` Composer: edit the draft before sending
- `ab54a5d` Send via AppleScript + confirm sheet
- `7a37b8e` Live iMessage updates (ChatDBWatcher) + sync chip
- `6f0dc51` Fix: crash in syncFromIMessage on cooperative executor (MainActor.assumeIsolated)
- `b54f011` Contacts name resolution + attributedBody decoder + sane draft fallbacks
- `075910a` Wire iMessage: chat.db read + FDA banner
- `ff12137` Escape hatch out of the gallery
- `db1c40c` MenuBarExtra + ⌘K palette overlay + persisted settings + test suite
- `1a9fab9` All 34 screens translated
- `df72480` Build without Xcode — SPM + .app bundler

## What's still stubbed
- ~~**Global `⌘⇧R`**.~~ Resolved (REP-009). Shipped via `Sources/ReplyAI/Services/GlobalHotkey.swift` (Carbon `RegisterEventHotKey` rather than `NSEvent.addGlobalMonitorForEvents` — works without Accessibility permission). `ReplyAIApp` retains the `GlobalHotkey()` for the process lifetime; `ReplyAIWindowSummoner.summon()` brings the inbox forward via fast-path window-title match or notification fallback. Pinned by `GlobalHotkeyContractTests` (3 cases, 2 gated behind `RUN_APPKIT_TOUCHING_TESTS=1`). Surfaced through ObShortcutsView, ObDoneView, SetShortcutsView, SfcMenubarView copy.
- ~~**UNNotification inline reply.**~~ Resolved: `InboxViewModel` observes `pendingNotificationReply` via `NotificationCoordinator` callback, looks up the thread by ID, calls `IMessageSender.send(text:toChatGUID:)`, then clears the pending state. Unknown thread IDs are logged and discarded without crash (REP-072, commit `bbedd1a`). Test coverage: 2 cases in `InboxViewModelTests.swift`.
- **Slack / WhatsApp / Teams / Telegram**. `ChannelService` protocol exists. `SlackChannel` shipped (REP-233/234, commit `c001d7e`) and now sends/receives via `SlackHTTPClient` (REP-237/238, commit `e26e72a`); `LocalhostOAuthListener` (REP-230, `fbba843`) + `SlackOAuthFlow` (REP-272, `c975e51`) wire the auth flow; `SlackSocketClient` (REP-267, `7c62474`) handles Socket Mode receive. WhatsApp/Teams/Telegram remain stub channels that throw `authorizationDenied`.
- ~~**AppleScript message-source fallback.**~~ Resolved: `AppleScriptMessageReader.recentChats()` (REP-236, commit `cf3d379`) and `messagesForChat()` (REP-240, commit `07f4b16`) — `IMessageChannel` falls through to AppleScript when FDA returns `authorizationDenied`. No FDA required; uses Automation permission.
- ~~**NotificationCoordinator `requestPermissionIfNeeded`.**~~ Resolved: authorization request on startup (REP-255, commit `949e7a3`).
- ~~**Thread-list cache (REP-278).**~~ Resolved: `Preferences.lastThreadsCacheURL`, `InboxViewModel.saveThreadCache/loadThreadCache` for cold-launch resilience (commit `cfe50f8`).
- **Voice profile training**. `ob-voice` is a UI mock; no LoRA pipeline.
- ~~**Rich message decoding limits.**~~ Resolved: `AttributedBodyDecoder` now does a real typedstream 0x2B tag scan (REP-003, commit `e760a12`). Hand-crafted hex fixtures cover nested `NSMutableAttributedString`, UTF-8 emoji, malformed blobs.
- ~~**FTS5 watcher updates.**~~ Resolved: `SearchIndex` now has an incremental upsert path keyed by `(thread_id, message_rowid)` for watcher-driven syncs (REP-015, commit `687c5a3`). Full rebuild is still the fallback for first-boot / settings changes.
- ~~**Global vs per-rule tone priority.**~~ Resolved: `SmartRule.priority: Int` (default 0, higher wins). `RuleEvaluator.matching` sorts by priority DESC before returning; `defaultTone` gets highest-priority tone automatically.

## Gotchas (read once, save hours)

- **Sandbox MUST stay OFF.** TCC's Full Disk Access only exposes to non-sandboxed bundles, and we need FDA to read `~/Library/Messages/chat.db`. If you re-add `com.apple.security.app-sandbox`, iMessage sync will silently start failing with "authorization denied" after rebuild.
- **Cooperative executor traps.** Don't call `MainActor.assumeIsolated` from code that runs inside a non-MainActor `async` context (e.g. inside `IMessageChannel.recentThreads`, which runs on a cooperative QoS queue). That's what commit `6f0dc51` fixed. Prefer thread-safe types (`@unchecked Sendable` + `NSLock`) over actor bridging when the API surface is synchronous.
- **`#Preview` macros don't work in SwiftPM builds without Xcode.** They need a plugin that only exists in Xcode-driven builds. All `#Preview` blocks were stripped. If you add them back, the SwiftPM build will fail with "plugin for module 'PreviewsMacros' not found". Use Xcode canvas for previews or skip them.
- **Info.plist has literal `$(VAR)` placeholders.** `scripts/build.sh` substitutes `$(DEVELOPMENT_LANGUAGE)`, `$(EXECUTABLE_NAME)`, `$(PRODUCT_BUNDLE_IDENTIFIER)`, `$(PRODUCT_NAME)` before copying into the .app. Don't remove that sed block.
- **`ATSApplicationFontsPath` auto-registers fonts at launch.** Fonts must sit directly under `Contents/Resources/Fonts/` in the bundle; the SPM resource bundle at `Contents/Resources/ReplyAI_ReplyAI.bundle/Fonts/` does NOT count. The bundler script copies .ttf files to both paths.
- **`chat.db` uses Apple reference dates** — either seconds since 2001-01-01 on older macOS, or nanoseconds on modern. `IMessageChannel.secondsSinceReferenceDate(appleDate:)` autodetects by magnitude. Don't assume one or the other.
- **Rich messages (newer iOS)** store text in `message.attributedBody` (typedstream NSAttributedString), not `message.text`. The query selects both; `AttributedBodyDecoder` falls back when `text` is NULL.
- **`chat.chat_identifier` is the projected ID, not the guid.** Group chat sends via AppleScript need the full `chat.guid` (`iMessage;+;chat1234567890`). 1:1 chats we synthesize `iMessage;-;<chat_identifier>` which works.
- **First MLX draft takes ~60–120s** — downloads ~2 GB + compiles Metal kernels. UI must show progress (see stubbed work above).
- **MLX runtime exit bug — emergency `defaults write` workaround.** Per REP-ALERT-260504-1650 (open as of 2026-05-05), the bundled `.app` exits ~1s after launch when `pref.model.useMLX = true` because dynamic library loading of `MLXLLM` / `MLXHuggingFace` / `Tokenizers` on the launch path triggers a clean exit. The workaround on a stuck install is `defaults write co.replyai.mac pref.model.useMLX -bool false` followed by relaunch. Smoke-launch checks should set this flag before opening the `.app` to verify main is otherwise healthy. The structural fix is REP-501→REP-505 (SPM target split so MLX symbols only load when the user explicitly opts in); a behavioral default flip alone does not help existing users with persisted `useMLX=1`.
- **MLX fresh-clone C++ compile exceeds the 13-min worker budget (~45–90 min on a cold machine).** Do NOT attempt `swift test` from a clean repo — it will time out. Before running tests, check whether `.build/` exists and is less than 6 hours old (`find .build -maxdepth 0 -mmin -360`). If `.build/` is absent or stale AND the task requires `swift test`, **push to `wip/`** with a note that the MLX build time exceeded the budget — merging unverified code to `main` is banned. Workers on a hot machine (`.build/` present, <6h old) can run `swift build && swift test` incrementally (~9 min). Also check `SWIFTPM_BUILD_PATH` in the environment — if it points at an existing cache, that path applies instead of `.build/`.
- **macOS 26.4 SDK on this machine.** Deployment target is 14.0 but some new SDK features leak through (`consuming` parameters in swift-transformers API, etc.).
- **Loopback HTTP roundtrip tests are timing-flaky — don't write `conn.receive` after `conn.send` against the in-process listener.** 2026-05-07-0811 fire added `testSuccessResponseBodyIsExactlyOK` to pin LocalhostOAuthListener's `"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n…OK"` ack, then immediately had to remove it: the listener's per-connection `connection.cancel()` in the `defer` runs before `.idempotent` send semantics flush bytes onto the loopback, so a second `NWConnection` doing `receive(...)` from the test harness fires its callback with `data == nil` ~50ms after open, asserting against `""` and failing 4 of 4 expectations. The failure is timing-only — passed on first run, failed on next run, no source change. **Pattern to avoid**: do not write a roundtrip test that `conn.send`s a request to the listener and then `conn.receive`s the response in the test process. **Pattern that works for the same intent**: expose the response template at package level (e.g. an internal `static let okResponseTemplate: String` on `LocalhostOAuthListener`) and assert with `XCTAssertEqual` against the literal — deterministic, no NW timing. Sibling pins that DON'T do a roundtrip (request-line shape, duplicate-`code` precedence, no-code timeout path) are stable.
- **Channel keychain service names are NOT uniform — do not "normalize" them.** `SMSChannel.keychainService = "ReplyAI-SMS"`, `TeamsChannel = "ReplyAI-Teams"`, `WhatsAppChannel = "ReplyAI-WhatsApp"`, but `TelegramChannel = "co.replyai.telegram"` (reverse-DNS). The Telegram divergence is intentional and pinned by `ChannelStubKeychainContractTests` (shipped on main as of `c1e1084`, 2026-05-05). Renaming any of these orphans every authorized user's token — keychain identity is the service+account literal. If a refactor proposes "consistency," reject it; the right fix is a documented one-time migration that reads the OLD service first, copies to the NEW, and deletes the OLD. None of that exists today, so leave the literals as-is.
- **Present-but-empty strings are a recurring bug class.** Several recent fires (2026-05-06 → 2026-05-07) have hammered on the same shape: a Swift `??` chain falls back only on `nil`, so `Some("")` passes through verbatim. The bugs hit chatGUID matching, sender attribution, OAuth token storage, OAuth callback codes, Keychain wildcard prefixes, draft-file paths, search-index thread IDs, and OAuth form-body URL-encoding. When auditing new code that does `userInfo[key] as? String ?? fallback` or `String.hasPrefix(prefix)` or `someID == ""`-style equality, ask whether `Some("")` should be treated as `nil` (filter to nil and let the next fallback run) or whether it should explicitly throw / no-op. The pattern that keeps bugs out: `let normalized = (raw?.isEmpty == false) ? raw : nil`. The companion test pattern is to write a regression-pin even when current Foundation behavior is "surprising-but-safe" (e.g. `String.range(of: "")` returns nil, `localizedCaseInsensitiveContains("")` returns false) — pinning the surprising-but-safe makes a future "consistency fix" refactor surface as a deliberate change rather than silent drift. Empty-pattern regex (`textMatchesRegex("")` / `threadNameMatchesRegex("")`) is in this class too — passes validation but `NSRegularExpression(pattern: "")` throws, so the evaluator's `try?` short-circuits to `nil` → false at runtime. The historical "catch-all rule" doc-comment was wrong; corrected on 2026-05-07.
- **`swift test` full-suite hangs intermittently on Contacts XPC even with `--skip ContactsResolverTests`.** Symptoms: xctest CPU drops to 0%, total CPU time stays under 10s, system log spams `CoreData: error: Failed to create NSXPCConnection` against `AddressBook-v22.abcddb`. The XCTSkipIf in `ContactsResolverTests.setUpWithError()` no-ops the suite when Contacts auth isn't granted, but the framework is loaded eagerly when the test bundle initializes — that load itself can hang on the system AddressBook daemon for reasons that are not deterministic. Observed 2026-05-05-0411 fire: full suite passed in 14.5s at the start of the fire, then hung indefinitely on subsequent runs in the same fire. **2026-05-05-0611 update — hang is at *some* InboxViewModel class boundary, not a specific class.** Three runs in this fire reproduced the hang with progressively narrower skips: default `--skip ContactsResolverTests` hung after `InboxViewModelBulkFilterTests` and before `InboxViewModelChatGUIDDeduplicationTests`. Adding `--skip InboxViewModelChatGUIDDeduplicationTests` did NOT clear the hang — it just shifted to after `InboxViewModelDraftStoreSeedTests`, the next InboxViewModel-based class alphabetically. Conclusion: the hang fires at *whichever* InboxViewModel test class runs first after the Contacts framework's lazy XPC handshake exhausts its retry budget — narrowing the skip list just moves the boundary. **2026-05-06-2010 update** — same pattern still active; this fire's `swift test --skip ContactsResolverTests` got 589 cases through (deeper than 2026-05-05 runs) before hanging at `InboxViewModelIsSyncingTests.testIsSyncingFalseAfterSuccess` (`Tests/ReplyAITests/InboxViewModelTests.swift:1193`). The "deeper" data point reinforces that the boundary is non-deterministic — depends on the AddressBook daemon's handshake retry timing on each run. Tracking the hang separately as `REP-ALERT-260506-2010` for a structural fix attempt. Workers should not chase narrower skip lists; just `--filter` the specific change. **Workaround**: when full suite hangs, run targeted `--filter <SuiteName>` to verify your change in isolation, then leave the branch on `wip/` rather than merging unverified to main; a future fire usually clears the hang. NB: `tccutil reset Contacts` from the autopilot runner returns `tccutil: Failed to reset Contacts` (it lacks the TCC privilege required for the reset), so don't bother invoking it — only a user-shell `tccutil reset Contacts` (or fully running tests via Xcode with a granted Contacts permission) can clear the daemon state. **2026-05-06-2210 update — VALIDATED WORKAROUND**: `swift test --skip ContactsResolverTests --skip InboxViewModelIsSyncingTests` completes the full suite in ~13s with 1311 tests passing, 0 failures, 2 skipped. Reproduced this fire. Future fires can use this two-flag form as the autopilot merge gate while the structural fix lives as a separate investigation (REP-ALERT-260506-2010). The IsSyncing suite passes 3/3 in 11ms when run via `--filter InboxViewModelIsSyncingTests` alone, confirming the test logic is sound — it's the class-boundary daemon state, not the test. **2026-05-07-0210 update — boundary moved one suite over, third skip required**: the two-flag form started hanging at `InboxViewModelTests.testConcurrentSyncCallsDoNotOverlap` (the next InboxViewModel suite alphabetically after IsSyncing). Current validated form: `swift test --skip ContactsResolverTests --skip InboxViewModelIsSyncingTests --skip InboxViewModelTests` — completes in ~13s with 1390 tests passing, 0 failures, 2 skipped. `swift test --filter ReplyAITests.InboxViewModelTests` runs that suite's 3 cases in 0.01s in isolation, same pattern as IsSyncing. Expect the list to keep growing one suite per fire until the structural fix lands; future fires should add `--skip` for whichever InboxViewModel suite hangs next rather than chasing the boundary.

## Priority queue

Pick in order. Each has a concrete starting point.

### 1. ~~Global `⌘⇧R`~~ — SHIPPED (REP-009)

Implementation chose Carbon `RegisterEventHotKey` over `NSEvent.addGlobalMonitorForEvents`, sidestepping the Accessibility permission prompt entirely. See `Sources/ReplyAI/Services/GlobalHotkey.swift` and `ReplyAIWindowSummoner` (same file). Remaining polish: tighten the fallback notification path when no inbox window exists at hotkey-fire time (currently posts `replyAIRequestSummonInbox`; consumer is `RootView.task`).

### 2. Animation + a11y polish

- Thread-select bar: animate the `Rectangle().fill(isSelected ? accent : .clear)` with `withAnimation(Theme.Motion.std)` and `matchedGeometryEffect` across rows. Awaiting merge — REP-082 wip branch `wip/autopilot-polish-2026-05-06-183151-rep082-thread-selection-bar` (1 commit, +55/-5) wires a `@Namespace selectionNamespace` on ThreadListView, threads it through to ThreadRow's accent bar via `matchedGeometryEffect(id: "thread-selection-bar")`, and gates the slide on `@Environment(\.accessibilityReduceMotion)` so reduce-motion users still get a snap. Default-arg params on ThreadRow keep existing call sites compiling.
- ~~Relative-time chip in sidebar: add a `Timer.publish(every: 10)` republisher so `"live · 12s ago"` auto-ticks.~~ Resolved (REP-047): `SidebarView.syncChip` is wrapped in `TimelineView(.periodic(from: Date(), by: 10))` so the relative-time string auto-advances every 10 s without a republisher.
- ~~Reduced motion: read `@Environment(\.accessibilityReduceMotion)`, skip crossfades in `ComposerView.editableDraft` and tone-pill animations.~~ Awaiting merge — REP-083 wip branch `wip/autopilot-polish-2026-05-06-181549-reducemotion` (4 commits, re-cut from main 2026-05-06 18:15 after the 14:11 branch rotted vs main) gates 13 `withAnimation` sites across PillToggle, TonePills, ThreadListView, InboxScreen, and SidebarView. `ComposerView.editableDraft` has no animation modifiers in current main (refactored out), so nothing left to gate there.

### 3. ~~Slack OAuth~~ — SHIPPED (REP-010, REP-272, REP-273, REP-274)

The end-to-end OAuth + send/receive surface has shipped. `Sources/ReplyAI/Channels/SlackChannel.swift` conforms to `ChannelService`; `SlackOAuthFlow` drives `LocalhostOAuthListener` on `127.0.0.1:4242` and exchanges via `oauth.v2.access`; `SlackTokenStore` persists `(token, workspaceName)` in Keychain; Settings → Channels (`SetChannelsView.swift`) renders the Connect/Disconnect UX. `SlackHTTPClient` covers `conversations.list` + `conversations.history`; `SlackSocketClient` handles Socket Mode receive. Remaining polish: multi-workspace (currently single-token) and Socket Mode error-state UI.

### 4. Better AttributedBodyDecoder

- Current scanner misses nested `NSMutableAttributedString` payloads and returns nil for some rich-text messages.
- Port https://github.com/dgelessus/python-typedstream to Swift (it's well-documented) or vendor a minimal parser covering class-ref / length / UTF-8 blob extraction for `NSString` + `NSAttributedString`.
- Test against a corpus of real `attributedBody` blobs harvested from chat.db (sanitized — no real content in the repo).

## Testing expectations

- **Every new feature ships with XCTest coverage.** Run `grep -r "func test" Tests/ | wc -l` for the current count (kept current in the repo layout header above). `swift test` from repo root.
- **Pure Swift (models, evaluators, parsers) gets unit tests.** View code gets ad-hoc visual checking.
- **Async tests**: use the `waitUntil(timeout:_:)` helper pattern in `DraftEngineTests` rather than arbitrary sleeps.
- **Never add `#Preview` blocks** — they break the SwiftPM path.

## External dependencies

Pinned in `Package.swift`:

- `mlx-swift-lm` from 3.31.0 — on-device LLM inference. Provides `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace` (macros).
- `swift-huggingface` from 0.9.0 — `HubClient` (macro expansion target).
- `swift-transformers` from 1.3.0 — `Tokenizers`, `Hub`, `AutoTokenizer` (macro expansion target).
- No CocoaPods, no Carthage, no third-party UI frameworks.

## Design references — how to use them

- **Read `~/ReplyAI_work/design_handoff_replyai/README.md`** for the full spec (tokens, inventory, interactions).
- **Before editing any screen, re-open its JSX reference** at `design_handoff_replyai/design_reference/components/*.jsx`. Match spacing, radii, colors, copy exactly.
- **When ambiguous, ask the human.** Don't guess.
- Design HTML: `design_handoff_replyai/design_reference/prototype.html` — opens in any browser; sidebar steps through all 34 screens.

## Commit style

- Present tense, lowercase first letter, terse noun-phrase title.
- Body explains the *why*, not the *what* — readers can `git diff` for the what.
- **Automation commits** (planner, worker, merger, reviewer) use the fixed trailer `Co-Authored-By: ReplyAI Automation <automation@replyai.co>` regardless of underlying model. Do not substitute model-specific names — that just creates drift flags every time Anthropic rotates the provisioned model.
- **Human-driven commits** include `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`; if you're Codex, sub in your own trailer.
- Never force-push. Never `git amend` after pushing. Separate commits per logical change.

## When you're stuck

1. Read the design reference for the affected screen.
2. Read the existing tests — they document expected behavior better than the code.
3. `git log -p <file>` to see why something is the way it is.
4. Ask the human. Don't guess on anything user-visible.

Good luck. Ship it.
