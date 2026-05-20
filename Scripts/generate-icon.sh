#!/usr/bin/env bash
# Renders the WhisperLocal app icon and produces Resources/AppIcon.icns.
# Idempotent — re-run any time the icon design changes.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PNG="$(mktemp -t whisperlocal-icon).png"
ICONSET="$(mktemp -d -t whisperlocal-iconset).iconset"
trap "rm -rf $PNG $ICONSET" EXIT

echo "Rendering 1024×1024 source PNG..."
swift Scripts/GenerateIcon.swift "$PNG"

echo "Generating iconset..."
mkdir -p "$ICONSET"
# macOS expects these specific filenames and sizes inside .iconset.
sips -z 16 16     "$PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp                "$PNG"             "$ICONSET/icon_512x512@2x.png"

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"

# Also export a PNG for the GitHub README (which can't render .icns).
mkdir -p "$ROOT/docs"
sips -z 256 256 "$PNG" --out "$ROOT/docs/icon.png" >/dev/null
echo "Wrote $ROOT/docs/icon.png"
