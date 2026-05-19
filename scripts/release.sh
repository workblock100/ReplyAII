#!/usr/bin/env bash
# Release orchestrator — chains build.sh release + (notarize.sh) + create-dmg.sh.
#
# Usage:
#   ./scripts/release.sh                # alias for `beta`
#   ./scripts/release.sh beta           # ad-hoc-signed build + DMG (no notarization)
#   ./scripts/release.sh public         # Developer-ID build + notarize + DMG
#
# `beta` is ship-able today: produces a closed-beta DMG that opens with
# right-click → Open → confirm Gatekeeper on a stock machine. `public`
# requires Elijah's Apple Developer Program enrollment + the env vars or
# keychain profile that scripts/notarize.sh consumes; see RELEASE.md.
set -euo pipefail

MODE="${1:-beta}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

usage() {
    sed -n '2,12p' "$0"
}

case "$MODE" in
    beta|public) ;;
    -h|--help) usage; exit 0 ;;
    *)
        echo "release: unknown mode: $MODE (expected: beta | public)" >&2
        usage >&2
        exit 2
        ;;
esac

# --- step 1: release-config build + ad-hoc/Developer-ID signing ---------------
echo "==> step 1/3: build (release)"
./scripts/build.sh release

# --- step 2 (public only): notarize via xcrun notarytool + staple -------------
if [ "$MODE" = "public" ]; then
    echo "==> step 2/3: notarize (Developer ID required)"
    ./scripts/notarize.sh
else
    echo "==> step 2/3: skip notarization (mode = beta)"
fi

# --- step 3: wrap into DMG ----------------------------------------------------
echo "==> step 3/3: create-dmg"
./scripts/create-dmg.sh

echo
echo "✓ release ($MODE) complete: $REPO/build/ReplyAI.dmg"
if [ "$MODE" = "beta" ]; then
    echo "  distribution: closed beta — share via Dropbox / iCloud / GitHub Releases"
    echo "  recipients: right-click → Open → confirm Gatekeeper (one-time per machine)"
else
    echo "  distribution: public — DMG is notarized + stapled, no Gatekeeper friction"
fi
