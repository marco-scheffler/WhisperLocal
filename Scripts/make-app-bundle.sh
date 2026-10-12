#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP="$ROOT/WhisperLocal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$ROOT/.build/release/WhisperLocal" "$APP/Contents/MacOS/WhisperLocal"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Classic Mac OS-era marker that some Gatekeeper heuristics still look for to
# distinguish "an .app bundle" from "a directory with a binary inside".
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

ENTITLEMENTS="$ROOT/Resources/WhisperLocal.entitlements"

# Signing strategy, in priority order:
#   1. SIGN_IDENTITY env override (e.g. for release.sh) — hardened runtime
#      + entitlements, ready for notarization.
#   2. Developer ID Application certificate in keychain — same as 1.
#   3. Self-signed "WhisperLocal Dev" — stable identity for local dev so TCC
#      permissions persist across rebuilds. No hardened runtime.
#   4. Ad-hoc — last resort. TCC will re-prompt on every rebuild.

DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' \
    | head -1 | tr -d '"' || true)

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "Signing for notarization with: $SIGN_IDENTITY"
    codesign --force \
        --sign "$SIGN_IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        "$APP"
elif [ -n "$DEV_ID" ]; then
    echo "Signing with Developer ID (hardened runtime): $DEV_ID"
    codesign --force \
        --sign "$DEV_ID" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        "$APP"
elif security find-certificate -c "WhisperLocal Dev" >/dev/null 2>&1; then
    echo "Signing with self-signed dev identity: WhisperLocal Dev"
    if ! codesign --force --sign "WhisperLocal Dev" "$APP" 2>&1; then
        echo "Codesign failed; falling back to ad-hoc." >&2
        codesign --force --sign - "$APP"
    fi
else
    echo "No signing identity found; using ad-hoc."
    echo "Hint: run ./Scripts/create-dev-cert.sh for stable TCC permissions."
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
echo "Run: open '$APP'"
