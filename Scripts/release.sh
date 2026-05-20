#!/usr/bin/env bash
# Full release pipeline: build → sign (Developer ID) → notarize → staple →
# zip → tag → create GitHub release with the notarized .app attached.
#
# Usage:
#   ./Scripts/release.sh v0.1.1
#
# Prerequisites:
#   - Developer ID Application certificate installed in keychain
#   - Stored credential profile "whisperlocal-notarize" (see notarize.sh)
#   - `gh` authenticated and pointing at the WhisperLocal repo

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version>     e.g. v0.1.1" >&2
    exit 1
fi

VERSION="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. Bump CFBundleShortVersionString to match the tag (without the leading v).
VERSION_NUMBER="${VERSION#v}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION_NUMBER" Resources/Info.plist

echo "==> Building and signing"
./Scripts/make-app-bundle.sh

# Verify Developer ID signing actually happened.
if ! codesign -dvv WhisperLocal.app 2>&1 | grep -q "Developer ID Application"; then
    echo "ERROR: app was not signed with a Developer ID Application certificate." >&2
    echo "       Install one and re-run." >&2
    exit 2
fi

echo "==> Notarizing"
./Scripts/notarize.sh WhisperLocal.app

echo "==> Packaging"
mkdir -p dist
DIST_ZIP="dist/WhisperLocal-${VERSION_NUMBER}.zip"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent WhisperLocal.app "$DIST_ZIP"
echo "Created $DIST_ZIP ($(du -h "$DIST_ZIP" | cut -f1))"

echo "==> Tagging $VERSION"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "Tag $VERSION already exists locally; using existing."
else
    git tag "$VERSION"
fi
git push origin "$VERSION"

echo "==> Creating GitHub release"
NOTES_FILE="$(mktemp -t release-notes).md"
cat > "$NOTES_FILE" <<EOF
WhisperLocal ${VERSION_NUMBER}

This release is signed with a Developer ID Application certificate and
notarized by Apple, so Gatekeeper opens it without warnings.

Install:
  1. Download WhisperLocal-${VERSION_NUMBER}.zip below and unzip.
  2. Move WhisperLocal.app to /Applications.
  3. Open. Grant Microphone, Accessibility, and Input Monitoring when
     prompted. Quit and relaunch once after granting.

See the README for full usage docs.
EOF
gh release create "$VERSION" "$DIST_ZIP" \
    --title "WhisperLocal ${VERSION_NUMBER}" \
    --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"
echo "Done. https://github.com/WEBER-marcoscheffler/WhisperLocal/releases/tag/${VERSION}"
