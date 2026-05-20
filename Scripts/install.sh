#!/usr/bin/env bash
# Build the app and install it into /Applications.
# Run again any time you change source code.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/make-app-bundle.sh"

TARGET="/Applications/WhisperLocal.app"

# Stop any running instance so we can replace the binary cleanly.
killall WhisperLocal 2>/dev/null || true
sleep 0.3

echo "Installing to $TARGET"
rm -rf "$TARGET"
cp -R "$ROOT/WhisperLocal.app" "$TARGET"

# Codesign survives the copy because the signature lives inside the bundle,
# but re-verify to make sure /Applications/WhisperLocal.app is well-formed.
codesign --verify --verbose=1 "$TARGET" 2>&1 | tail -3

echo ""
echo "Installed."
echo "Launch:  open '$TARGET'"
echo "Enable Launch at login: open the app → menu bar icon → Settings → Startup."
