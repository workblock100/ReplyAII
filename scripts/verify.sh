#!/usr/bin/env bash
# One-command local verification gate for ReplyAI.
#
# Usage:
#   ./scripts/verify.sh                 # three-skip XCTest gate + debug build + UI smoke
#   ./scripts/verify.sh release         # same gate, release bundle
#   ./scripts/verify.sh --clean-stale   # also kill stale SwiftPM/xctest workers first
set -euo pipefail

CONFIG="debug"
CLEAN_STALE=0
REPO="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
One-command local verification gate for ReplyAI.

Usage:
  ./scripts/verify.sh                 # three-skip XCTest gate + debug build + UI smoke
  ./scripts/verify.sh release         # same gate, release bundle
  ./scripts/verify.sh --clean-stale   # also kill stale SwiftPM/xctest workers first
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        debug|release)
            CONFIG="$1"
            ;;
        --clean-stale)
            CLEAN_STALE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "verify: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd "$REPO"

if [ "$CLEAN_STALE" -eq 1 ]; then
    echo "==> cleaning stale SwiftPM/xctest workers"
    pkill -9 -f xctest || true
    pkill -9 -f 'swift test' || true
    pkill -9 -f swift-frontend || true
    pkill -9 -f swift-build || true
fi

echo "==> swift test (headless gate)"
swift test \
    --skip ContactsResolverTests \
    --skip InboxViewModelIsSyncingTests \
    --skip InboxViewModelTests

echo "==> build ($CONFIG)"
"$REPO/scripts/build.sh" "$CONFIG"

echo "==> UI smoke"
"$REPO/scripts/smoke-ui.swift" "$REPO/build/ReplyAI.app"

echo
echo "✓ verify passed: three-skip XCTest gate + $CONFIG build + UI smoke"
