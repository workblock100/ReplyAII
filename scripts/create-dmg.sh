#!/usr/bin/env bash
# Wrap build/ReplyAI.app into a distributable DMG.
#
# Usage:
#   ./scripts/create-dmg.sh                # uses build/ReplyAI.app, writes build/ReplyAI.dmg
#   ./scripts/create-dmg.sh --output PATH  # custom .dmg destination
#   ./scripts/create-dmg.sh --volname NAME # DMG volume label (default: "ReplyAI")
#
# Uses hdiutil (ships with macOS — no Homebrew dep). Idempotent: overwrites
# any existing .dmg at the destination. Works against ad-hoc-signed bundles
# (closed-beta distribution) and Developer-ID-signed + notarized bundles
# (public distribution); notarization is a separate step in scripts/notarize.sh.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/build/ReplyAI.app"
OUT="$REPO/build/ReplyAI.dmg"
VOLNAME="ReplyAI"

usage() {
    sed -n '2,12p' "$0"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            shift; OUT="$1"
            ;;
        --volname)
            shift; VOLNAME="$1"
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)
            echo "create-dmg: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ ! -d "$APP" ]; then
    echo "create-dmg: missing $APP" >&2
    echo "create-dmg: run ./scripts/build.sh release first" >&2
    exit 1
fi

# Verify the bundle is signed before we ship it. Ad-hoc is fine for closed
# beta; Developer ID is what notarize.sh expects. Either way an unsigned
# bundle is a misconfigure and we refuse to wrap it.
if ! codesign --verify --no-strict "$APP" 2>/dev/null; then
    echo "create-dmg: $APP is unsigned or signature is broken" >&2
    echo "create-dmg: re-run ./scripts/build.sh to re-sign, or sign explicitly" >&2
    exit 1
fi

STAGE="$(mktemp -d -t replyai-dmg)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> staging $APP -> $STAGE"
# Use ditto rather than cp -R: preserves extended attributes (xattr) and
# resource forks that codesign + Gatekeeper inspect on the destination.
ditto "$APP" "$STAGE/$(basename "$APP")"

# Symlink to /Applications so the user can drag-install. This is the
# convention every well-known macOS DMG uses; Finder shows it as a folder
# shortcut inside the mounted volume.
ln -s /Applications "$STAGE/Applications"

if [ -e "$OUT" ]; then
    echo "==> removing existing $OUT"
    rm -f "$OUT"
fi

echo "==> hdiutil create $OUT"
# UDZO = zlib-compressed, read-only — the standard distribution format.
# Quiet output unless something fails; hdiutil is noisy by default.
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -quiet \
    "$OUT"

echo "==> verify"
hdiutil verify -quiet "$OUT"

SIZE_BYTES="$(stat -f%z "$OUT")"
SIZE_MB="$(( SIZE_BYTES / 1024 / 1024 ))"

echo
echo "✓ created $OUT  (${SIZE_MB} MB)"
echo "  next: ./scripts/notarize.sh   # only after Developer ID signing"
echo "  beta: share the .dmg directly via Dropbox / iCloud / GitHub Releases"
