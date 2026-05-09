# ReplyAI

Native macOS AI-native messaging assistant. SwiftUI, macOS 14+, dark mode only for v1.

## Status

Screen inventory: **34 / 34** complete.

- [x] Main app: `app-inbox`, `app-inbox-empty`, `app-inbox-loading`, `app-offline`
- [x] Threads: `thr-group`, `thr-media`, `thr-long`
- [x] Composer: `cmp-tones`, `cmp-custom`, `cmp-lowconf`, `cmp-nothing`
- [x] Surfaces: `sfc-palette`, `sfc-snooze`, `sfc-rules`, `sfc-menubar`, `sfc-notification`
- [x] Settings: `set-account`, `set-voice`, `set-channels`, `set-shortcuts`, `set-privacy`, `set-model`
- [x] Onboarding: `ob-welcome`, `ob-privacy`, `ob-permissions`, `ob-channels`, `ob-channel-detail`, `ob-voice`, `ob-tone`, `ob-shortcuts`, `ob-done`
- [x] Errors: `err-disconnected`, `err-auth`, `err-model-update`

## Build

Two paths — pick whichever fits. Both share the same sources + resources.

### A) SwiftPM + bundler (no Xcode required)

```bash
cd ~/Code/ReplyAI
./scripts/build.sh debug open
```

Compiles with `swift build` (Command Line Tools' toolchain), wraps the
executable into `build/ReplyAI.app`, ad-hoc codesigns, and launches.

### B) XcodeGen + Xcode

```bash
cd ~/Code/ReplyAI
xcodegen generate
open ReplyAI.xcodeproj      # ⌘R in Xcode
```

XcodeGen lives at `~/.local/bin/xcodegen`. Install from source or release
binary if it's missing.

## Fonts

Drop the files listed in [Resources/Fonts/README.md](Resources/Fonts/README.md) into that folder before building. They auto-register via `ATSApplicationFontsPath` in `Info.plist`.

Expected:

- `InterTight[wght].ttf` (single variable-weight axis file — `Theme.Font.sans(_:weight:)` calls `.weight(weight)` on `.custom("Inter Tight", …)` to interpolate)
- `InstrumentSerif-Italic.ttf`
- `JetBrainsMono-Regular.ttf`, `-Medium.ttf` (per-weight static files — `.custom("JetBrains Mono", …).weight(_:)` is unreliable on the Mono family, so these ship as separate PostScript names)

All OFL-licensed. Until installed, Theme.Font falls back to the system font silently — visible but not pixel-perfect.

## Architecture

```
Sources/ReplyAI/
├── App/              # @main entry + ReplyAIApp scene graph
├── Theme/            # Theme.Color / .Font / .Radius / .Space / .Motion tokens
├── Models/           # Channel, MessageThread, Message, Folder, Tone
├── Fixtures/         # Seed threads/drafts (gallery + demo-mode)
├── Services/         # LLMService + StubLLMService + MLXDraftService + DraftEngine + Stats + Preferences + GlobalHotkey + NotificationCoordinator + PromptBuilder + DraftStore
├── Components/       # Avatar, ChannelDot, MiniButton, Caret, SectionLabel, KbdChip, etc.
├── Channels/         # ChannelService + IMessage{Channel,Sender,Preview} + AppleScriptMessageReader + AccessibilityAPIReader + Slack{Channel,OAuthFlow,SocketClient,HTTPClient} + KeychainHelper + 4 stub channels
├── Rules/            # SmartRule + RuleEvaluator + RulesStore (JSON-backed)
├── Search/           # SearchIndex (FTS5)
├── MenuBar/          # MenuBarContent (MenuBarExtra popover)
├── Screens/          # All gallery screens (Onboarding/, Settings/, MainApp/, Threads/, Composer/, Errors/, Surfaces/) + ScreenID + ScreenInventory + AppPrototypeView
├── Inbox/            # InboxScreen + InboxViewModel + Sidebar/ + ThreadList/ + Thread/ + Composer/ + FDABanner + ModelLoadBanner + SendConfirmSheet
└── Resources/        # Fonts/, Assets.xcassets
```

### LLM plumbing

`LLMService` is a `Sendable` protocol that returns an `AsyncThrowingStream<DraftChunk, Error>`. `DraftChunk` is one of `.text(String)`, `.confidence(Double)`, `.loadProgress(fraction:message:)`, `.done`.

`StubLLMService` emits tokens from the hard-coded `Fixtures.drafts` table with 22–58ms inter-token delay and a 180ms cold-start — used by every demo / fixture / test path.

`MLXDraftService` is the on-device path: `mlx-swift-lm` + `swift-huggingface` load `mlx-community/Llama-3.2-3B-Instruct-4bit` (~2 GB) into a cached `ModelContainer` and stream tokens through `ChatSession.streamResponse(...)`. Gated behind `Preferences.useMLX` (default false until REP-501→REP-505 ships the SPM split — see "Not yet wired" below).

`DraftEngine` is an `@Observable @MainActor` cache keyed on `(threadID, tone)`. Sub-views read state from it via `.environment(engine)` + `@Environment(DraftEngine.self)`. `prime` kicks off generation on first view; `regenerate` busts the cache for one (thread, tone) pair.

### Keyboard map (wired)

| Key    | Action                             |
| ------ | ---------------------------------- |
| `⌘↵`  | Send current draft                 |
| `⌘J`  | Regenerate current draft           |
| `⌘/`  | Cycle tone                         |
| `⌘.`  | Dismiss current draft              |
| `⌘K`  | Open command palette / search       |
| `⌘⇧O` | Open inbox window from gallery     |
| `⌘⇧R` | Global summon (system-wide hotkey) |

## Not yet wired

- WhatsApp / Teams / Telegram / SMS channel integrations — stub `ChannelService` impls in `Sources/ReplyAI/Channels/{WhatsApp,Teams,Telegram,SMS}Channel.swift` throw `authorizationDenied` until a real backend lands. iMessage (`chat.db` + AppleScript fallback) and Slack (OAuth + Socket Mode) are shipped.
- Voice profile training — `ob-voice` is a UI mock; no LoRA pipeline.
- MLX runtime opt-in path is structurally fragile — `pref.model.useMLX = true` triggers an exit-on-launch (REP-ALERT-260504-1650) until the SPM split (REP-501→REP-505) lands.

(For an exhaustive ship state see [`AGENTS.md`'s "What's still stubbed"](AGENTS.md) section — this list focuses on what a contributor most likely cares about.)
