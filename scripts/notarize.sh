#!/usr/bin/env bash
# Notarize build/ReplyAI.app with Apple and staple the ticket.
#
# Usage:
#   ./scripts/notarize.sh                  # uses build/ReplyAI.app + env vars
#   ./scripts/notarize.sh --keychain-profile NAME  # uses a stored profile
#   ./scripts/notarize.sh --bundle PATH    # notarize a custom .app path
#
# Required env vars (when --keychain-profile is not used):
#   APPLE_ID                       # Apple ID email (e.g. workblock100@gmail.com)
#   APPLE_TEAM_ID                  # 10-char Team ID from developer.apple.com → Membership
#   APPLE_APP_SPECIFIC_PASSWORD    # generated at appleid.apple.com → App-Specific Passwords
#
# Or, if you've stored a notarytool profile once via
#     xcrun notarytool store-credentials "replyai" \
#         --apple-id "$APPLE_ID" \
#         --team-id "$APPLE_TEAM_ID" \
#         --password "$APPLE_APP_SPECIFIC_PASSWORD"
# pass --keychain-profile replyai and skip the env vars.
#
# Prerequisites:
#   1. Apple Developer Program enrollment ($99/yr) — completed on developer.apple.com.
#   2. Developer ID Application certificate present in login keychain.
#   3. build/ReplyAI.app signed with the Developer ID Application cert
#      (NOT ad-hoc — re-sign via scripts/build.sh after editing its codesign
#      identity from `--sign -` to `--sign "Developer ID Application: ..."`).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/build/ReplyAI.app"
KEYCHAIN_PROFILE=""

usage() {
    sed -n '2,20p' "$0"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --keychain-profile)
            shift; KEYCHAIN_PROFILE="$1"
            ;;
        --bundle)
            shift; APP="$1"
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)
            echo "notarize: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

die() {
    echo "notarize: $*" >&2
    exit 1
}

# --- 1) bundle present + signed with Developer ID -----------------------------

[ -d "$APP" ] || die "missing $APP — run ./scripts/build.sh release first"

# `codesign -dvv` writes signing info to stderr (per design). We want it on
# stdout for the grep, so swap.
SIGN_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
AUTHORITY="$(printf "%s\n" "$SIGN_INFO" | awk -F'=' '/Authority=/ {print $2; exit}')"

case "$AUTHORITY" in
    "Developer ID Application:"*)
        echo "==> signed by: $AUTHORITY"
        ;;
    "-"|"adhoc"|"")
        die "bundle is ad-hoc signed; notarization requires Developer ID Application
       1) enroll in Apple Developer Program at developer.apple.com (\$99/yr)
       2) generate Developer ID Application cert in Keychain Access
       3) edit scripts/build.sh: change --sign \"-\" to --sign \"Developer ID Application: <Your Name> (<TEAMID>)\"
       4) re-run ./scripts/build.sh release"
        ;;
    *)
        die "unexpected signing authority: $AUTHORITY
       notarization expects 'Developer ID Application:' — check scripts/build.sh"
        ;;
esac

# --- 2) credentials available -------------------------------------------------

if [ -n "$KEYCHAIN_PROFILE" ]; then
    CRED_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
    echo "==> using keychain profile: $KEYCHAIN_PROFILE"
else
    : "${APPLE_ID:?APPLE_ID env var is required (or pass --keychain-profile NAME)}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID env var is required (10-char Team ID from developer.apple.com → Membership)}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD env var is required (generated at appleid.apple.com → App-Specific Passwords)}"
    CRED_ARGS=(
        --apple-id "$APPLE_ID"
        --team-id "$APPLE_TEAM_ID"
        --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
    echo "==> using env-var credentials for $APPLE_ID"
fi

# --- 3) zip the bundle for submission ----------------------------------------

ZIP="$REPO/build/ReplyAI.app.zip"
echo "==> zipping bundle -> $ZIP"
rm -f "$ZIP"
# `ditto -ck --keepParent` preserves the .app directory structure inside the
# zip and is what Apple's docs recommend for notarytool submissions.
ditto -c -k --keepParent "$APP" "$ZIP"

# --- 4) submit + wait --------------------------------------------------------

echo "==> notarytool submit (this can take several minutes)"
SUBMIT_LOG="$(mktemp -t replyai-notarize)"
trap 'rm -f "$SUBMIT_LOG"' EXIT

if ! xcrun notarytool submit "$ZIP" "${CRED_ARGS[@]}" --wait | tee "$SUBMIT_LOG"; then
    die "notarytool submit failed — see output above"
fi

STATUS="$(awk -F': *' '/^ *status: / {print $2; exit}' "$SUBMIT_LOG")"
case "$STATUS" in
    Accepted)
        echo "==> Apple accepted the submission"
        ;;
    "")
        die "could not parse notarytool status from output"
        ;;
    *)
        SUBMISSION_ID="$(awk -F': *' '/^ *id: / {print $2; exit}' "$SUBMIT_LOG")"
        echo "notarize: submission status was '$STATUS' (not Accepted)" >&2
        echo "notarize: fetch the log with:" >&2
        echo "    xcrun notarytool log $SUBMISSION_ID ${CRED_ARGS[*]}" >&2
        exit 1
        ;;
esac

# --- 5) staple ---------------------------------------------------------------

echo "==> stapling ticket onto $APP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Final Gatekeeper assessment — what a user's Mac will do on first launch.
echo "==> spctl assessment"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

echo
echo "✓ notarized $APP"
echo "  next: ./scripts/create-dmg.sh   # wrap into a distributable .dmg"
