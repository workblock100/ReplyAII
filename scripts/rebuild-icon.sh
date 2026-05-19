#!/usr/bin/env bash
# Rebuild Sources/ReplyAICore/Resources/AppIcon.icns from the 10 PNGs in
# Sources/ReplyAICore/Resources/Assets.xcassets/AppIcon.appiconset/.
#
# When to run:
#   - After replacing the placeholder PNGs in the .appiconset with new art.
#   - When `file AppIcon.icns` shows only one icon type (e.g. ic12) instead
#     of the full multi-resolution set.
#
# Uses iconutil, which ships with macOS — no Homebrew dep.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/Sources/ReplyAICore/Resources/Assets.xcassets/AppIcon.appiconset"
DST="$REPO/Sources/ReplyAICore/Resources/AppIcon.icns"

[ -d "$SRC" ] || { echo "rebuild-icon: missing $SRC" >&2; exit 1; }

# iconutil requires the staging directory to end in `.iconset`. mktemp
# doesn't support trailing suffixes, so create the parent and rename.
STAGE_BASE="$(mktemp -d -t replyai-icon)"
STAGE="${STAGE_BASE}.iconset"
mv "$STAGE_BASE" "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

# iconutil expects exactly these names. The .appiconset uses the same names
# already; cp is enough.
declare -a REQUIRED_PNGS=(
    icon_16x16.png
    icon_16x16@2x.png
    icon_32x32.png
    icon_32x32@2x.png
    icon_128x128.png
    icon_128x128@2x.png
    icon_256x256.png
    icon_256x256@2x.png
    icon_512x512.png
    icon_512x512@2x.png
)

for f in "${REQUIRED_PNGS[@]}"; do
    [ -f "$SRC/$f" ] || { echo "rebuild-icon: missing $SRC/$f" >&2; exit 1; }
    cp "$SRC/$f" "$STAGE/$f"
done

echo "==> iconutil -c icns -> $DST"
iconutil -c icns -o "$DST" "$STAGE"

ICNS_TYPES="$(file -b "$DST" | sed 's/.*Mac OS X icon, //')"
echo
echo "✓ rebuilt $DST"
echo "  contents: $ICNS_TYPES"
echo "  next: ./scripts/build.sh release    # to pick up the new icon"
