#!/usr/bin/env bash
#
# Package the built Ludwig.app as a drag-to-Applications disk image.
#
#   ./frontend/scripts/ludwig/make_dmg.sh
#
# Run build_release.sh first — this only packages what that produced, so that
# signing and verification happen exactly once, in one place.
#
# Uses hdiutil, which ships with macOS. `create-dmg` would allow a styled
# window with a background image; it is a Homebrew dependency and a prettier
# window is not worth adding one for v1. The result is still the familiar
# "drag the app onto Applications" layout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="Ludwig"
APP_PATH="$REPO_ROOT/frontend/appflowy_flutter/build/macos/Build/Products/Release/$APP_NAME.app"
DIST="$REPO_ROOT/dist"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

[ -d "$APP_PATH" ] || fail "no built app at $APP_PATH — run build_release.sh first"

# Refuse to package something unsigned or broken: the .dmg is the artefact
# people actually download, so this is the last place to catch it.
bold "Checking the app"
codesign --verify --deep "$APP_PATH" 2>/dev/null \
  || fail "the app fails signature verification — do not ship it"
authority=$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep "^Authority" | head -1 || true)
[ -n "$authority" ] || fail "the app is ad-hoc signed (no authority) — run build_release.sh to sign it"
ok "${authority}"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
commit=$(cd "$REPO_ROOT" && git rev-parse --short HEAD)
DMG="$DIST/$APP_NAME-$version-macos-arm64.dmg"

bold "Staging"
# ditto, never cp -R: cp -R corrupts a bundle's code signature.
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
ok "app + Applications shortcut"

bold "Building the disk image"
mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null
ok "$(basename "$DMG")"

# Verify the image mounts and the app inside it still passes signature checks —
# a corrupted copy is the failure mode that only shows up on someone else's Mac.
bold "Verifying the image"
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "the disk image failed verification"
mountpoint=$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
if [ -n "$mountpoint" ]; then
  codesign --verify --deep "$mountpoint/$APP_NAME.app" 2>/dev/null \
    && ok "signature intact inside the image" \
    || { hdiutil detach "$mountpoint" >/dev/null 2>&1; fail "signature broken inside the image"; }
  hdiutil detach "$mountpoint" >/dev/null 2>&1
fi

bold "Done"
printf '  image    %s\n' "$DMG"
printf '  size     %s\n' "$(du -sh "$DMG" | cut -f1)"
printf '  version  %s\n' "$version"
printf '  source   %s%s\n' "$commit" \
  "$([ "$(cd "$REPO_ROOT" && git status --porcelain | wc -l | tr -d ' ')" != "0" ] \
     && echo "  ⚠ uncommitted changes — this image does not match any commit")"
printf '\n  Note: recipients must right-click → Open the first time (self-signed).\n'
