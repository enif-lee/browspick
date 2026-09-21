#!/bin/bash
# Browspick installer — downloads the latest GitHub release DMG and installs
# it to /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/enif-lee/browspick/main/Scripts/install.sh | bash
#
set -euo pipefail

REPO="enif-lee/browspick"
APP="Browspick.app"
DEST="/Applications"

die() { echo "✗ $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only."
[ "$(uname -m)" = "arm64" ] || die "The released build is Apple Silicon (arm64) only — build from source for Intel."
[ -w "$DEST" ] || die "$DEST is not writable for this user."

echo "▸ Fetching latest release of $REPO…"
JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" \
  || die "Could not reach the GitHub API."
TAG="$(echo "$JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
URL="$(echo "$JSON" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4)"
[ -n "$URL" ] || die "No .dmg asset found in the latest release ($TAG)."
echo "▸ Latest release: $TAG"

TMP="$(mktemp -d)"
MNT=""
cleanup() { [ -n "$MNT" ] && hdiutil detach "$MNT" -quiet 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

echo "▸ Downloading $(basename "$URL")…"
curl -fSL --progress-bar "$URL" -o "$TMP/browspick.dmg"

MNT="$(hdiutil attach -nobrowse -readonly "$TMP/browspick.dmg" | grep -o '/Volumes/.*' | head -1)"
[ -d "$MNT/$APP" ] || die "$APP not found inside the DMG."

echo "▸ Installing to $DEST…"
pkill -x Browspick 2>/dev/null || true
rm -rf "$DEST/$APP"
cp -R "$MNT/$APP" "$DEST/"
hdiutil detach "$MNT" -quiet && MNT=""

# Self-signed build — drop quarantine if present so Gatekeeper doesn't warn.
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "✔ Installed $DEST/$APP ($TAG) — launching…"
open -a "${APP%.app}"
echo "Done. Finish setup in the onboarding window (default browser + permissions)."
