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

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run: open '$APP'"
