#!/usr/bin/env bash
# One-command local verification gate for ReplyAI.
#
# Usage:
#   ./scripts/verify.sh                 # three-skip XCTest gate + debug build + UI smoke
#   ./scripts/verify.sh release         # same gate, release bundle
#   ./scripts/verify.sh --clean-stale   # also kill stale SwiftPM/xctest workers first
#   ./scripts/verify.sh --verbose       # stream full command output
set -euo pipefail

CONFIG="debug"
CLEAN_STALE=0
VERBOSE=0
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG_ROOT="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_ROOT%/}/replyai-verify"

usage() {
    cat <<'EOF'
One-command local verification gate for ReplyAI.

Usage:
  ./scripts/verify.sh                 # three-skip XCTest gate + debug build + UI smoke
  ./scripts/verify.sh release         # same gate, release bundle
  ./scripts/verify.sh --clean-stale   # also kill stale SwiftPM/xctest workers first
  ./scripts/verify.sh --verbose       # stream full command output
EOF
}

run_logged() {
    local label="$1"
    local log_file="$2"
    shift 2

    echo "==> $label"
    if [ "$VERBOSE" -eq 1 ]; then
        "$@"
        return
    fi

    if "$@" >"$log_file" 2>&1; then
        local warning_count
        warning_count="$(grep -c 'warning:' "$log_file" || true)"
        awk '
            /Executed [0-9]+ tests/ { executed = $0 }
            /Build of product|Build complete|valid on disk|satisfies its Designated Requirement|smoke-ui: PASS|verify passed/ { print }
            END { if (executed != "") print executed }
        ' "$log_file" | sed 's/^/    /' || true
        if [ "$warning_count" -gt 0 ]; then
            echo "    warnings: $warning_count (see $log_file)"
        fi
        echo "    log: $log_file"
    else
        local status=$?
        echo "verify: $label failed; last 80 log lines:" >&2
        tail -80 "$log_file" >&2 || true
        exit "$status"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        debug|release)
            CONFIG="$1"
            ;;
        --clean-stale)
            CLEAN_STALE=1
            ;;
        --verbose)
            VERBOSE=1
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
mkdir -p "$LOG_DIR"

if [ "$CLEAN_STALE" -eq 1 ]; then
    echo "==> cleaning stale SwiftPM/xctest workers"
    pkill -9 -f xctest || true
    pkill -9 -f 'swift test' || true
    pkill -9 -f swift-frontend || true
    pkill -9 -f swift-build || true
fi

TEST_LOG="$LOG_DIR/swift-test.log"
BUILD_LOG="$LOG_DIR/build-$CONFIG.log"
SMOKE_LOG="$LOG_DIR/smoke-ui.log"

run_logged "swift test (headless gate)" "$TEST_LOG" swift test \
    --skip ContactsResolverTests \
    --skip InboxViewModelIsSyncingTests \
    --skip InboxViewModelTests

run_logged "build ($CONFIG)" "$BUILD_LOG" "$REPO/scripts/build.sh" "$CONFIG"

run_logged "UI smoke" "$SMOKE_LOG" "$REPO/scripts/smoke-ui.swift" "$REPO/build/ReplyAI.app"

echo
echo "✓ verify passed: three-skip XCTest gate + $CONFIG build + UI smoke"
