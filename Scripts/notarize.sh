#!/usr/bin/env bash
# Submit a built .app to Apple's notarization service and staple the ticket.
#
# Prerequisites (one-time setup — see README):
#   1. Apple Developer Program membership ($99/year)
#   2. "Developer ID Application" certificate installed in your keychain
#   3. Stored credentials profile named "whisperlocal-notarize", created via:
#        xcrun notarytool store-credentials whisperlocal-notarize \
#            --apple-id "you@example.com" \
#            --team-id "ABCDE12345" \
#            --password "abcd-efgh-ijkl-mnop"   # app-specific password
#
# Usage:
#   ./Scripts/notarize.sh                          # notarize ./WhisperLocal.app
#   ./Scripts/notarize.sh /path/to/WhisperLocal.app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/WhisperLocal.app}"
PROFILE="${NOTARYTOOL_PROFILE:-whisperlocal-notarize}"

if [ ! -d "$APP" ]; then
    echo "App bundle not found: $APP" >&2
    echo "Run ./Scripts/make-app-bundle.sh first." >&2
    exit 1
fi

# Verify the app was signed with a Developer ID Application certificate
# (hardened runtime + timestamp). Notarization requires this — self-signed
# or ad-hoc signatures are rejected by Apple.
echo "Verifying signature..."
SIG=$(codesign -dvv "$APP" 2>&1)
if ! echo "$SIG" | grep -q "Developer ID Application"; then
    echo "$SIG" >&2
    echo "" >&2
    echo "ERROR: app is not signed with a Developer ID Application certificate." >&2
    echo "       Notarization will be rejected by Apple." >&2
    echo "" >&2
    echo "Make sure a 'Developer ID Application: ...' identity is in your" >&2
    echo "keychain and re-run ./Scripts/make-app-bundle.sh." >&2
    exit 2
fi

ZIP="$(mktemp -t whisperlocal-notarize).zip"
trap "rm -f $ZIP" EXIT

echo "Zipping for upload..."
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notarization service (this can take a few minutes)..."
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$PROFILE" \
    --wait

echo "Stapling the notarization ticket onto the bundle..."
xcrun stapler staple "$APP"

echo "Verifying notarized signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" 2>&1 | tail -3

echo ""
echo "Done. $APP is notarized and stapled."
