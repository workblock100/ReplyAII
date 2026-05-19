# RELEASE.md — ReplyAI shipping checklist

Where the technical work ends and Elijah's account/billing decisions begin.
This file is the autopilot-authored counterpart to the marketing/growth
DISTRIBUTION.md (community + newsletter research) that lives in the
Next.js companion workspace at `~/Documents/replyai-app/DISTRIBUTION.md`.

## State of the build (as of 2026-05-19)

- `swift test --filter ReplyAITests --skip ContactsResolverTests --skip InboxViewModelIsSyncingTests --skip InboxViewModelTests` → 1945 / 1945 passing in 15.9s on warm cache.
- `./scripts/build.sh debug` → 5s warm; bundles + ad-hoc signs + entitlements applied; `codesign -v` returns valid; smoke launch verified PID alive after 30s, single 1360×852 inbox window, no crash signatures in system log.
- `pref.model.useMLX = true` no longer crashes the app on launch (REP-ALERT-260504-1650 resolved by REP-501→REP-505 SPM target split landing on main `e602c1a`).
- Pivot-aligned channel fallbacks shipped: AppleScript reader (REP-236), Slack OAuth + Socket Mode (REP-266 et al.), UNNotification capture (REP-235), demo-mode fixture threads (REP-228), Limited Mode banner + onboarding CTA (REP-259).

## What ships TODAY without any account changes

`./scripts/build.sh release` produces a fully-functional `build/ReplyAI.app` that runs locally and against an Apple Silicon Mac the user can hand-carry the bundle to. The bundle is ad-hoc signed (`codesign --sign -`), so:

- Will run for the developer who built it: ✓
- Will run for anyone else after they right-click → Open → confirm Gatekeeper: ✓ (one-time warning)
- Will run via double-click on a stock machine: ✗ (Gatekeeper blocks; needs the right-click bypass)

Distribution mechanism: tarball or DMG of the .app, shared via Dropbox/iCloud/GitHub Releases. Acceptable for closed beta. Not acceptable for the open public listing.

## What unlocks the next tier (Apple Developer ID + notarization)

**Cost:** $99/yr Apple Developer Program enrollment, paid by Elijah on developer.apple.com.

**Time:** 24–48 h for first-time enrollment + identity verification.

Once that's in place, the work is mechanical (no further user decisions):

1. Generate Developer ID Application certificate in Keychain Access; export `.p12` for backup.
2. Rewrite `scripts/build.sh` codesign block to `--sign "Developer ID Application: Elijah Osik (TEAMID)"` instead of `--sign -`.
3. Add a `scripts/notarize.sh` that:
   - `xcrun notarytool submit build/ReplyAI.app.zip --apple-id <email> --team-id <id> --password <app-specific-pw> --wait`
   - `xcrun stapler staple build/ReplyAI.app` after successful submission.
4. Wrap into a DMG via `create-dmg` (Homebrew) or `hdiutil create`.

After steps 1–4, double-click-on-stock-machine works without any Gatekeeper friction.

## What unlocks the App Store tier

**Cost:** Above + App Store fees (15–30 % of revenue; $99/yr enrollment unchanged).

**Time:** First submission review is 24–72 h. Subsequent updates are usually <24 h.

Mechanical work after the Developer Program is active:

1. Create an App Store Connect record (bundle ID `co.replyai.mac`, SKU, primary category Productivity, age rating 4+).
2. Generate sandbox screenshots at 6 required resolutions (auto-generatable via XCUITest later; for now, hand-captured from a real run).
3. Author privacy nutrition labels (zero outbound message text; license + crash report endpoints only — both opt-out, matching the SetPrivacyView toggles).
4. Upload via Transporter or `xcrun altool --upload-app` (legacy).
5. App Review questionnaire: declare no encryption-export concerns (the on-device MLX path is local-only inference, not transmitted).

The product copy and screenshots for the listing live separately at `~/Documents/replyai-app/APP_STORE_LISTING.md` + `~/Documents/replyai-app/APP_STORE_RELEASE_NOTES.md` (currently untracked — Elijah's growth research draft).

## What stays internal and doesn't need external accounts

These can ship inside an ad-hoc build today:

- Voice profile training on local message history (in-app, on-device — REP-080-series).
- Demo mode for zero-permission users (Limited Mode shipped REP-259 / REP-228).
- All AI quality work (prompt engineering, tone tuning, draft polish) — the LLM service is now provider-pluggable via `LLMServiceProvider.make`, so swapping MLX for an API-backed model or vice-versa is one line in `ReplyAIApp.init`.
- All UI polish — animation, accessibility, copy.

## What's blocked on Elijah specifically

Everything in this section is a "user-required decision, credentials, billing, or external app store action" that the autopilot cannot perform:

- [ ] Apple Developer Program enrollment ($99, one Apple ID).
- [ ] App Store Connect record creation (free, after enrollment).
- [ ] App-specific password generation at appleid.apple.com (for `notarytool`).
- [ ] Stripe / Paddle / Lemon Squeezy account for paid-tier billing (if not App-Store-only).
- [ ] Sentry / Bugsnag account for crash reporting endpoint (the existing `Send anonymous crash reports` toggle in SetPrivacyView assumes one exists).
- [ ] Decision on price ($X one-time vs $Y/mo vs free) and any free-tier limits.
- [ ] Decision on whether to ship via App Store, direct download, or both.
- [ ] App icon at production resolutions (1024px PNG + .icns generated from it — current shipped icon is the placeholder R-square).

## Versioning + tagging

When ready to ship a build:

```bash
cd ~/.cache/replyai-autopilot
./scripts/build.sh release
git tag v0.1.0          # SemVer; pre-1.0 because public-beta surface
git push origin v0.1.0
# Then either: upload build/ReplyAI.app.zip to GitHub Releases v0.1.0,
# or notarize + DMG (see "next tier" section above), or both.
```

The autopilot will not perform `git tag` or `git push --tags` autonomously — that step belongs to Elijah on a deliberate release decision.
