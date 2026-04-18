# ReplyAI

Native macOS AI-native messaging assistant. SwiftUI, macOS 14+, dark mode only for v1.

## Status

Screen inventory: **1 / 28** complete.

- [x] `app-inbox` — three-pane inbox with streaming drafts
- [ ] `app-inbox-empty` / `app-inbox-loading` / `app-offline`
- [ ] Threads (`thr-group`, `thr-media`, `thr-long`)
- [ ] Composer variants (`cmp-tones`, `cmp-custom`, `cmp-lowconf`, `cmp-nothing`)
- [ ] Surfaces (`sfc-palette`, `sfc-snooze`, `sfc-rules`, `sfc-menubar`, `sfc-notification`)
- [ ] Settings (6)
- [ ] Onboarding (9)
- [ ] Error states (3)

## Build

One-time toolchain:

```bash
# 1. Xcode 15+ from the App Store (required; Command Line Tools alone won't build GUI apps).
# 2. XcodeGen — pick one:
brew install xcodegen
# or: mint install yonaskolb/xcodegen
# or: https://github.com/yonaskolb/XcodeGen/releases
```

Generate and run:

```bash
cd ~/Code/ReplyAI
xcodegen generate
open ReplyAI.xcodeproj
# Hit ⌘R in Xcode
```

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
