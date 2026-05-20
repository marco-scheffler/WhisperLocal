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
# rebuilds. Detection is tricky: `find-identity -v` doesn't list self-signed
# code-signing certs reliably, but `codesign` accepts them. Check for the
# certificate by name instead.
IDENTITY="WhisperLocal Dev"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "Signing with stable identity: $IDENTITY"
    if ! codesign --force --deep --sign "$IDENTITY" "$APP" 2>&1; then
        echo "Codesign with '$IDENTITY' failed; falling back to ad-hoc." >&2
        codesign --force --deep --sign - "$APP"
    fi
else
    echo "Stable identity '$IDENTITY' not found; using ad-hoc signing."
    echo "Hint: run ./Scripts/create-dev-cert.sh to make TCC permissions stick."
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
echo "Run: open '$APP'"
