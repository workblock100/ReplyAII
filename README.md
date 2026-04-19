# ReplyAI

Native macOS AI-native messaging assistant. SwiftUI, macOS 14+, dark mode only for v1.

## Status

Screen inventory: **28 / 28** complete.

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

- `InterTight-Regular.ttf`, `-Medium.ttf`, `-SemiBold.ttf`, `-Bold.ttf`
- `InstrumentSerif-Italic.ttf`
- `JetBrainsMono-Regular.ttf`, `-Medium.ttf`

All OFL-licensed. Until installed, Theme.Font falls back to the system font silently — visible but not pixel-perfect.

## Architecture

```
Sources/ReplyAI/
├── App/              # @main entry
├── Theme/            # Theme.Color / .Font / .Radius / .Space / .Motion
├── Models/           # Channel, MessageThread, Message, Folder, Tone
├── Fixtures/         # THREADS/DRAFTS seed from reply-app.jsx
├── Services/         # LLMService protocol + StubLLMService + DraftEngine
├── Components/       # Avatar, ChannelDot, MiniButton, Caret, SectionLabel, KbdChip
└── Inbox/
    ├── InboxScreen.swift
    ├── InboxViewModel.swift
    ├── Sidebar/
    ├── ThreadList/
    ├── Thread/
    └── Composer/
```

### LLM plumbing

`LLMService` is a `Sendable` protocol that returns an `AsyncThrowingStream<DraftChunk, Error>`. `DraftChunk` is one of `.text(String)`, `.confidence(Double)`, `.done`.

`StubLLMService` emits tokens from the hard-coded `Fixtures.drafts` table with 22–58ms inter-token delay and a 180ms cold-start. The shape matches what an MLX-backed service will emit, so swapping is one file.

`DraftEngine` is an `@Observable @MainActor` cache keyed on `(threadID, tone)`. Sub-views read state from it via `.environment(engine)` + `@Environment(DraftEngine.self)`. `prime` kicks off generation on first view; `regenerate` busts the cache for one (thread, tone) pair.

### Keyboard map (wired)

| Key    | Action                             |
| ------ | ---------------------------------- |
| `⌘↵`  | Advance to next thread (send stub) |
| `⌘J`  | Regenerate current draft           |
| `⌘/`  | Cycle tone                         |
| `⌘.`  | Dismiss current draft              |

## Not yet wired

- Channel integrations (iMessage `chat.db`, Slack OAuth, WhatsApp pair) — locked until UI is done.
- Real MLX model — `StubLLMService` stays swapped in.
- FTS5 search — no store yet.
- `NSStatusItem` popover, `UNNotification` inline reply.
