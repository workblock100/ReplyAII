# Contributing to ReplyAI

This file is the fast-path for any new contributor — human or agent — landing on the repo. It tells you how to clone, build, test, and ship a change without re-reading 400 lines of `AGENTS.md` or the autopilot SKILL.

For deeper context on architecture, the 2026-04-23 strategic pivot, and per-area gotchas, read [AGENTS.md](AGENTS.md). For release/distribution flow, see [RELEASE.md](RELEASE.md). For the autopilot's full operating contract, see [`~/.claude/scheduled-tasks/replyai-autopilot/SKILL.md`](https://github.com/workblock100/ReplyAII) (path on Elijah's local machine; not committed to the repo).

## TL;DR

```bash
git clone https://github.com/workblock100/ReplyAII.git ReplyAI
cd ReplyAI
./scripts/verify.sh                # one-command gate: 3-skip Swift test + build + UI smoke
./scripts/build.sh debug open      # build + bundle + launch the app
```

If `verify.sh` passes, your change is mergeable to `main`. If it doesn't, fix it before opening a PR or branch.

## Build

Two paths share the same sources. Pick whichever fits.

**SwiftPM + bundler (no Xcode required):**

```bash
./scripts/build.sh debug          # bundles at build/ReplyAI.app, ad-hoc signed
./scripts/build.sh release open   # release build + launch
```

The script wraps `swift build -c <config> --product ReplyAI` and bundles into a launchable `.app`. Output lives at `build/ReplyAI.app` and is ad-hoc codesigned for local Gatekeeper.

**XcodeGen + Xcode:**

```bash
xcodegen generate
open ReplyAI.xcodeproj    # ⌘R
```

`xcodegen` lives at `~/.local/bin/xcodegen`; install from source or release binary if missing.

## The test gate

`swift test` (plain) **does not work** on this repo. It hangs intermittently because of an actor-deadlock pattern between `ContactsResolverTests`, `InboxViewModelTests`, and `InboxViewModelIsSyncingTests` that's tracked at `REP-ALERT-260506-2010` in [BACKLOG.md](BACKLOG.md).

Use one of these two forms — both are equivalent:

```bash
./scripts/verify.sh
# OR
swift test \
    --skip ContactsResolverTests \
    --skip InboxViewModelIsSyncingTests \
    --skip InboxViewModelTests
```

`verify.sh` is the canonical one-stop gate: it runs the 3-skip Swift test invocation, then `./scripts/build.sh`, then `./scripts/smoke-ui.swift` against the bundled app (the AX-driven first-run smoke). Pass `--clean-stale` if a previous run left ghost `xctest` / `swift-build` processes.

### Why the carve-outs exist

| Skipped suite | Why |
|---|---|
| `ContactsResolverTests` | Headless test runners lack Contacts access. Loading the test bundle eagerly resolves `Contacts.framework` symbols, surfacing 21 spurious `NSXPCStore` / `AddressBook-v22.abcddb` failures from the Address Book daemon. The suite already calls `XCTSkipIf(...)` in `setUpWithError` when access isn't authorized, but the symbol-load failures fire before `setUpWithError` runs. |
| `InboxViewModelIsSyncingTests` | Hangs intermittently on warm cache because of cross-suite actor-state leakage from a previous test class. In isolation (`--filter ReplyAITests.InboxViewModelIsSyncingTests`), the cases pass in 0.01s. |
| `InboxViewModelTests` | Same root cause as above — the deadlock boundary moves between fires depending on the Address Book daemon's XPC retry timing. |

All three carve-outs go away once the structural fix on `REP-ALERT-260506-2010` lands. Until then, the 3-skip form is reliable.

## Branch strategy

- **`main`** is always shippable. Every commit on `main` passes `verify.sh` at the time of merge.
- **`wip/<topic>-YYYY-MM-DD-HHMMSS`** is for work-in-progress and any UI-sensitive change. Anything that touches `Theme.*`, view bodies, layout, or rendered copy must land on a `wip/*` branch first — Elijah (or whoever's reviewing) eyeballs the rendered output before fast-forward-merging into `main`.
- Merge `wip/*` into `main` only with `git merge --ff-only`. The autopilot and merger agents both enforce this.
- Never `--force-push` to `main`. Never `git reset --hard` on a published branch. The autopilot will refuse to do either.

## Commit format

Short, lower-cased, present-tense subject. Body explains the **why**, not the what. Trailer attributes the author when run by an automated agent:

```
plain-words-summary-of-the-change

Why this change matters in 2-4 sentences. What problem did it solve,
what tradeoffs were considered, what's deliberately out of scope.

Co-Authored-By: ReplyAI Autopilot <automation@replyai.co>
```

Human contributors should drop the trailer. Reuse the autopilot's trailer only when committing on behalf of an automated fire.

## Style

- Swift 6 strict concurrency. Mark anything that crosses async boundaries `Sendable`.
- ViewModels are `@Observable @MainActor`.
- Tests use `XCTest`, not `swift-testing`.
- No `#Preview { ... }` macros — they break SwiftPM compilation.
- Comments default to none. When you add one, it should explain **why**, not **what** — a future reader will understand what the code does from the code itself.

## Where things are

| Path | What |
|---|---|
| `Sources/ReplyAI/` | App-shell code (SwiftUI views, view models, scenes) |
| `Sources/ReplyAICore/` | Reusable core (models, services, persistence) |
| `Sources/ReplyAIMLX/` | MLX-backed on-device LLM (separate target so MLX symbols don't load unless `pref.model.useMLX = true`) |
| `Tests/ReplyAITests/` | XCTest suites |
| `scripts/` | `build.sh`, `verify.sh`, `smoke-ui.swift`, `create-dmg.sh`, `notarize.sh` |
| `BACKLOG.md` | All tracked tickets (REP-NNN format) |
| `AGENTS.md` | Architecture, pivot, gotchas, priority queue |
| `RELEASE.md` | Shipping checklist + what's blocked on Elijah specifically |
| `.automation/logs/` | Autopilot fire logs (one per fire, append-only) |

## Pre-flight checks before opening a PR

1. `./scripts/verify.sh` passes locally.
2. The change is on a `wip/*` branch if it touches UI; otherwise either `wip/*` or directly on `main` is fine (the autopilot defaults to `wip/*` for anything non-trivial).
3. The commit message explains the why, not just the what.
4. If the change closes a `REP-NNN`, update the entry's `status` and `done_on` in `BACKLOG.md`.
5. If the change introduces a new gotcha or violates an existing assumption, update `AGENTS.md` so the next contributor doesn't re-discover it.

## Reporting issues

Use the BACKLOG. Open a new `### REP-NNN — <title>` block at the bottom of the appropriate priority section, with `status: open`, `effort: S|M|L`, and a scope of 2–4 sentences. The autopilot will pick it up on its next fire if dependencies are met and it's not flagged `ui_sensitive` (those go to a `wip/*` for human review).
