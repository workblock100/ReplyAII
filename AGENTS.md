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

Tests/ReplyAITests/                34 tests
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

- `9c86704` Smart Rules DSL + store + live UI; 34 tests green
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

- **Rule actions don't fire live**. `RuleEvaluator` classifies correctly, `InboxViewModel` doesn't call it yet. `setDefaultTone` is the lowest-friction wiring (see priority #1 below).
- **FTS5 palette search**. `PalettePopover` shows a static list. Need a SQLite FTS5 index backed by `liveMessages` + a query that debounces user input.
- **Global `⌘⇧R`**. Not wired. Needs Accessibility permission + either MASShortcut or `CGEventTapCreate` + `NSEvent.addGlobalMonitorForEvents`.
- **UNNotification inline reply**. Gallery mock exists (`sfc-notification`); real `UNNotificationAction` with `UNTextInputNotificationAction` pending.
- **Slack / WhatsApp / Teams / Telegram**. `ChannelService` protocol exists; only `IMessageChannel` conforms. Slack is next (OAuth loopback on `:4242`, Socket Mode for RTM).
- **Voice profile training**. `ob-voice` is a UI mock; no LoRA pipeline.
- **Group chat sending**. `IMessageSender.send(…)` uses `iMessage;-;<handle>` form which only works for 1:1. Group chats need the full `chat.guid` — project it in `IMessageChannel.recentThreads`.
- **Rich message decoding limits**. `AttributedBodyDecoder` is a byte-scan, not a real typedstream parser. Some messages render as `[non-text message]`. Upgrade path: port https://github.com/dgelessus/python-typedstream to Swift.
- **Model progress UI**. `MLXDraftService` emits `DraftChunk.loadProgress(fraction:message:)` but `InboxScreen` doesn't render it yet. Add a banner above the composer when the latest stream's last chunk is `.loadProgress`.

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

Pick in order. Each has a concrete starting point:

### 1. Wire rule actions live in `InboxViewModel`

Currently `RuleEvaluator` is a pure function with tests; nothing calls it from live code. Start with `setDefaultTone` since it's read-only:

- In `InboxViewModel.selectThread(_ id:)`, after updating `selectedThreadID`, compute `RuleEvaluator.defaultTone(for: rulesStore.rules, in: RuleContext.from(thread: selectedThread))` and set `activeTone` to that if non-nil.
- Hold a `@ObservationIgnored var rules: RulesStore` on `InboxViewModel` (inject via init).
- Tests: add a case to `RulesTests` that exercises the integration against a fake rules array.
- Follow-up actions (`archive`, `pin`, `markDone`) need list mutations on the thread array + persistence — larger change, do second.

### 2. FTS5 palette search

- Add `Sources/ReplyAI/Search/SearchIndex.swift` that owns a SQLite DB at `~/Library/Application Support/ReplyAI/search.db` with an FTS5 virtual table `messages_fts(thread_id, text, sender, date UNINDEXED)`.
- On successful `syncFromIMessage`, iterate each thread's live messages and `INSERT OR REPLACE INTO messages_fts` (dedup by a `(thread_id, message_rowid)` unique constraint).
- Expose `func search(_ query: String) async -> [SearchResult]` that runs `MATCH ?` with a small snippet helper.
- Rewrite `PalettePopover` to take a `SearchIndex` env value and re-query on `@State var query` change with a 120 ms debounce.
- Test the tokenizer: query `"dinner mom"` should find "dont forget sundays dinner ♥".

### 3. Global `⌘⇧R`

- Add `Sources/ReplyAI/GlobalHotkey.swift`. Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (cheapest; triggers Accessibility permission prompt).
- Hook in `ReplyAIApp.init()`, call `openWindow(id: "inbox")` when the modifier+key match.
- `NSAccessibilityUsageDescription` needs adding to `Info.plist` + `project.yml`.
- If Accessibility not granted, show a banner in the inbox.

### 4. Animation + a11y polish

- Thread-select bar: animate the `Rectangle().fill(isSelected ? accent : .clear)` with `withAnimation(Theme.Motion.std)` and `matchedGeometryEffect` across rows.
- Relative-time chip in sidebar: add a `Timer.publish(every: 10)` republisher so `"live · 12s ago"` auto-ticks.
- Reduced motion: read `@Environment(\.accessibilityReduceMotion)`, skip crossfades in `ComposerView.editableDraft` and tone-pill animations.

### 5. Slack OAuth (first non-iMessage channel)

- New `Sources/ReplyAI/Channels/SlackChannel.swift`. Port the flow from `ob-channel-detail.jsx`: spin up an `NWListener` on `127.0.0.1:4242` during auth only, open the OAuth URL via `NSWorkspace.shared.open`, stop the listener on callback.
- Store the token in Keychain (prefix `ReplyAI-`; factory reset clears by prefix — see `set-privacy`).
- Subsequent `recentThreads` hits `conversations.list` + `conversations.history`; use Socket Mode for RTM.

## Testing expectations

- **Every new feature ships with XCTest coverage.** 34 tests today. `swift test` from repo root.
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
