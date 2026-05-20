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

# Prefer a stable self-signed identity so macOS TCC keeps permissions across
# rebuilds. If "WhisperLocal Dev" is missing, fall back to ad-hoc (TCC will
# re-prompt on every rebuild).
IDENTITY="WhisperLocal Dev"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Signing with stable identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "Stable identity '$IDENTITY' not found; using ad-hoc signing."
    echo "Hint: create a Code-Signing self-signed cert in Keychain Access named '$IDENTITY'"
    echo "      to make macOS keep permissions across rebuilds."
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
echo "Run: open '$APP'"
