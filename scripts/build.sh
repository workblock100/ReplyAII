#!/usr/bin/env bash
# Build + bundle ReplyAI into a runnable macOS .app without Xcode.
#
# Usage:
#   ./scripts/build.sh                 # debug build, bundles at build/ReplyAI.app
#   ./scripts/build.sh release         # release build
#   ./scripts/build.sh debug open      # debug + launch
#   ./scripts/build.sh release open    # release + launch
#
# Output: <repo>/build/ReplyAI.app, ad-hoc signed, launchable via `open`.
set -euo pipefail

CONFIG="${1:-debug}"
POST="${2:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/build/ReplyAI.app"

cd "$REPO"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product ReplyAI

EXE="$REPO/.build/$CONFIG/ReplyAI"
if [ ! -x "$EXE" ]; then
    echo "build failed: $EXE missing" >&2
    exit 1
fi

echo "==> bundling -> $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/Fonts"

# Executable + Info.plist (substitute Xcode build-variable placeholders the
# plist still references — they'd otherwise stay literal in our bundle).
cp "$EXE" "$APP/Contents/MacOS/ReplyAI"

/usr/bin/sed \
  -e 's/\$(DEVELOPMENT_LANGUAGE)/en/g' \
  -e 's/\$(EXECUTABLE_NAME)/ReplyAI/g' \
  -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/co.replyai.mac/g' \
  -e 's/\$(PRODUCT_NAME)/ReplyAI/g' \
  "$REPO/Sources/ReplyAI/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Fonts — auto-registered by macOS via ATSApplicationFontsPath.
for ttf in "$REPO/Sources/ReplyAI/Resources/Fonts"/*.ttf; do
    [ -e "$ttf" ] || continue
    cp "$ttf" "$APP/Contents/Resources/Fonts/"
done

# SPM resource bundle (carries anything .process() picked up, e.g. Assets.xcassets).
BUNDLE_SRC="$REPO/.build/$CONFIG/ReplyAI_ReplyAI.bundle"
if [ -d "$BUNDLE_SRC" ]; then
    cp -R "$BUNDLE_SRC" "$APP/Contents/Resources/"
fi

# Ad-hoc codesign so macOS will launch the bundle without quarantine warnings
# on this machine. (Gatekeeper is strict; ad-hoc is fine for dev.)
# The entitlements file must be applied at signing time, otherwise the
# sandbox-disabled bit isn't honored and FDA can't attach to this bundle.
echo "==> codesign (ad-hoc, entitlements)"
ENT="$REPO/Sources/ReplyAI/Resources/ReplyAI.entitlements"
codesign --force --sign - --timestamp=none --entitlements "$ENT" "$APP/Contents/MacOS/ReplyAI" >/dev/null
codesign --force --sign - --timestamp=none --entitlements "$ENT" "$APP" >/dev/null

echo "==> verify"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

if [ "$POST" = "open" ]; then
    echo "==> open"
    open "$APP"
fi

echo
echo "✓ built $APP"
echo "  launch: open $APP"
