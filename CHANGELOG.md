# CHANGELOG

ReplyAI release notes. Versioning follows [SemVer](https://semver.org) once the v1.0 line ships; pre-v1 cuts use the date as a secondary disambiguator. Each entry summarises the user-facing impact, not the implementation detail — see commit history for the code-level diff.

## Unreleased

Work-in-progress on `main` since the last tagged release.

### Distribution + tooling

- **One-command release orchestrator** (`scripts/release.sh`): chains `build.sh release` → optional `notarize.sh` → `create-dmg.sh` into one invocation. `./scripts/release.sh beta` is ship-able today (closed-beta DMG); `./scripts/release.sh public` runs the same chain with Apple notarization in the middle once Elijah's Developer Program enrollment is live.
- **DMG creation** (`scripts/create-dmg.sh`): produces a UDZO-compressed `build/ReplyAI.dmg` with the conventional `/Applications` drag-install symlink. Pure macOS-built-in tools, no Homebrew dependency.
- **Apple notarization helper** (`scripts/notarize.sh`): validates Developer ID signing, accepts env-var or stored-keychain-profile credentials, submits via `xcrun notarytool`, waits, staples the ticket, runs a final `spctl --assess`.
- **App icon regeneration** (`scripts/rebuild-icon.sh`): rebuilds `AppIcon.icns` from the 10-PNG `.appiconset` via `iconutil`. Makes the placeholder-→-final-icon swap a one-command operation when the real design lands.

### UX polish

- **Brand identity consolidation**: extracted the brand glyph `R` and standalone `ReplyAI` wordmark to `Sources/ReplyAICore/BrandStrings.swift`. 13 view sites updated. Drift-enumeration test (`testNoInlineBrandLiterals`) walks the source tree and fails fast if any future view reintroduces inline brand literals.
- **Per-view UI string pin tests** (REP-UI-STR-HOIST-001, 5 views complete): `MenuBarContent`, `SidebarView`, `WelcomeGate`, `FDABanner`, and `ObDoneView` now expose nested `Strings` enums with literal-fidelity pin tests + shape invariants (sentence count, character-length caps, terminal-punctuation rules). A copy-edit on any high-traffic surface now lands in PR review with a named test, not as a silent SwiftUI-body diff.

### Reliability

- **AX-driven UI smoke** (`scripts/smoke-ui.swift` + `scripts/verify.sh`): single-command gate that combines the 3-skip XCTest run, debug build, and end-to-end UI smoke (onboarding → open-inbox → thread selection → composer → all 3 tone pills). Replaces an XCUITest target that SwiftPM doesn't natively support; closes REP-XCUI-001 by alternative.

### Documentation

- **Contributor onboarding** (`CONTRIBUTING.md`): fast-path doc covering the 3-skip Swift test gate (with explicit rationale per suite), branch strategy, commit format, and where to find architecture / release / per-area gotchas in the larger docs.
- **Responsible-disclosure policy** (`SECURITY.md`): how to report vulnerabilities without opening a public issue; in-scope / out-of-scope; default 90-day coordinated-disclosure window.
- **Release docs** (`RELEASE.md`): technical shipping checklist + explicit list of what's blocked on Elijah-side (Developer Program enrollment, App Store Connect, billing backend, pricing decision, real app icon).
- **AGENTS.md staleness sweep**: marked the MLX runtime-exit gotcha as RESOLVED (was 14-day stale), refreshed the priority-queue note to point at current BACKLOG state.

## 0.1.0 — pre-launch (target, not yet tagged)

The first cut intended for closed-beta hand-off. Tag will land once Elijah signs off on the launch-ready state. State at this point:

- 34 / 34 screens complete (Welcome / Onboarding / Inbox / Composer / Threads / Settings / Surfaces / Errors)
- iMessage `chat.db` + AppleScript fallback + UNNotification capture
- Slack OAuth + Socket Mode + send/receive via HTTP client
- Demo-mode fixture threads + Limited Mode banner (zero-permission users)
- MLX 4-bit on-device reply path (gated behind `pref.model.useMLX`, default off)
- Voice-profile few-shot capture (20-entry FIFO, exact-duplicate de-dup)
- 9 wired keyboard shortcuts (⌘↵ / ⌘J / ⌘/ / ⌘. / ⌘K / ⌘⇧O / ⌘⇧R / ⌘R / ⌘⇧S)
- 2027 passing tests under the 3-skip gate; ~16s on warm cache

## How tags get cut

```bash
git tag -a v0.1.0 -m "ReplyAI v0.1.0 — closed-beta cut"
git push origin v0.1.0
./scripts/release.sh beta            # builds + DMGs the tagged commit
```

(After Developer Program enrollment, replace `beta` with `public` to produce a notarized DMG.)
