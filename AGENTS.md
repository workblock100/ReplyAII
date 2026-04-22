# AGENTS.md — ReplyAI handoff

Read this before you touch anything. It's the shortest path to productive edits without asking the human redundant questions.

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

Tests/ReplyAITests/                189 tests
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

189 XCTest cases, all green.

## What's still stubbed
- **Global `⌘⇧R`**. Not wired. Needs Accessibility permission + either MASShortcut or `CGEventTapCreate` + `NSEvent.addGlobalMonitorForEvents`.
- **UNNotification inline reply**. `NotificationCoordinator` registered (`UNTextInputNotificationAction`, "REPLY" category) and wired to `InboxViewModel.pendingNotificationReply` (REP-028, commit `9810196`). Reply consumption in `InboxViewModel` pending (REP-063).
- **Slack / WhatsApp / Teams / Telegram**. `ChannelService` protocol exists; only `IMessageChannel` conforms. Slack is next (OAuth loopback on `:4242`, Socket Mode for RTM).
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
- **macOS 26.4 SDK on this machine.** Deployment target is 14.0 but some new SDK features leak through (`consuming` parameters in swift-transformers API, etc.).

## Priority queue

Pick in order. Each has a concrete starting point.

### 1. Global `⌘⇧R`

- Add `Sources/ReplyAI/GlobalHotkey.swift`. Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (cheapest; triggers Accessibility permission prompt).
- Hook in `ReplyAIApp.init()`, call `openWindow(id: "inbox")` when the modifier+key match.
- `NSAccessibilityUsageDescription` needs adding to `Info.plist` + `project.yml`.
- If Accessibility not granted, show a banner in the inbox.

### 2. Animation + a11y polish

- Thread-select bar: animate the `Rectangle().fill(isSelected ? accent : .clear)` with `withAnimation(Theme.Motion.std)` and `matchedGeometryEffect` across rows.
- Relative-time chip in sidebar: add a `Timer.publish(every: 10)` republisher so `"live · 12s ago"` auto-ticks.
- Reduced motion: read `@Environment(\.accessibilityReduceMotion)`, skip crossfades in `ComposerView.editableDraft` and tone-pill animations.

### 3. Slack OAuth (first non-iMessage channel)

- New `Sources/ReplyAI/Channels/SlackChannel.swift`. Port the flow from `ob-channel-detail.jsx`: spin up an `NWListener` on `127.0.0.1:4242` during auth only, open the OAuth URL via `NSWorkspace.shared.open`, stop the listener on callback.
- Store the token in Keychain (prefix `ReplyAI-`; factory reset clears by prefix — see `set-privacy`).
- Subsequent `recentThreads` hits `conversations.list` + `conversations.history`; use Socket Mode for RTM.

### 4. Better AttributedBodyDecoder

- Current scanner misses nested `NSMutableAttributedString` payloads and returns nil for some rich-text messages.
- Port https://github.com/dgelessus/python-typedstream to Swift (it's well-documented) or vendor a minimal parser covering class-ref / length / UTF-8 blob extraction for `NSString` + `NSAttributedString`.
- Test against a corpus of real `attributedBody` blobs harvested from chat.db (sanitized — no real content in the repo).

## Testing expectations

- **Every new feature ships with XCTest coverage.** 60 tests today. `swift test` from repo root.
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
- Every commit includes `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`; if you're Codex, sub in your own trailer.
- Never force-push. Never `git amend` after pushing. Separate commits per logical change.

## When you're stuck

1. Read the design reference for the affected screen.
2. Read the existing tests — they document expected behavior better than the code.
3. `git log -p <file>` to see why something is the way it is.
4. Ask the human. Don't guess on anything user-visible.

Good luck. Ship it.
