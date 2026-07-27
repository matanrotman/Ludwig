#!/usr/bin/env bash
#
# Build a distributable Ludwig for macOS (Apple Silicon).
#
#   ./frontend/scripts/ludwig/build_release.sh
#
# `specs/distribution.md` Phase 3. This exists because the release path is NOT
# the debug path: `flutter build macos --debug` only relinks a prebuilt Rust
# library, while a release build recompiles the Rust core AND regenerates the
# protobuf bindings. Every failure below was hit for real on 2026-07-27, and
# each check is here so the next person does not rediscover it.
#
# Environment:
#   LUDWIG_SIGN_IDENTITY   Code-signing identity to use. Defaults to a
#                          self-signed cert named "Ludwig Self-Signed" if one
#                          exists. Set to "-" to force ad-hoc (not advised:
#                          macOS ties permission grants to the code hash, so
#                          every ad-hoc rebuild makes the app look brand new
#                          and silently drops microphone/Documents access).
#   LUDWIG_SKIP_BUILD=1    Only sign and verify whatever is already built.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FRONTEND="$REPO_ROOT/frontend"
PROFILE="production-mac-arm64"
APP_NAME="Ludwig"
BUNDLE_ID="app.ludwig.desktop"
APP_PATH="$FRONTEND/appflowy_flutter/build/macos/Build/Products/Release/$APP_NAME.app"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. PATH. The release build shells out to tools a login shell has but a
#    non-interactive one does not. `protoc-gen-dart` living only in
#    ~/.pub-cache/bin is the one that actually broke the build.
# ---------------------------------------------------------------------------
export PATH="$HOME/flutter/bin:$HOME/.cargo/bin:$HOME/.pub-cache/bin:/opt/homebrew/bin:$PATH"

bold "Checking toolchain"
for tool in flutter cargo cargo-make protoc protoc-gen-dart; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not found on PATH.
  protoc-gen-dart: dart pub global activate protoc_plugin
  protoc:          brew install protobuf
  cargo-make:      cargo install cargo-make"
done
ok "flutter, cargo, cargo-make, protoc, protoc-gen-dart"

# ---------------------------------------------------------------------------
# 2. Stale-path guard. `flowy-codegen` resolves its template directory from
#    env!("CARGO_MANIFEST_DIR"), which is baked in AT COMPILE TIME. Move or
#    rename the checkout and every cached copy still points at the old
#    location, so the build panics with a path that no longer exists. Debug
#    builds never notice, because they don't re-run codegen.
# ---------------------------------------------------------------------------
bold "Checking for stale build caches"
TARGET="$FRONTEND/rust-lib/target"
STALE=0
# Check the BUILD SCRIPT BINARIES, not the rlib. They are what actually panics,
# and they demonstrably carry the baked path; the rlib does not always expose it
# to `strings`, which made an earlier version of this check fire on every run.
if [ -d "$TARGET/release/build" ]; then
  while IFS= read -r script_bin; do
    baked=$(strings "$script_bin" 2>/dev/null \
            | grep -o '/[^ ]*/rust-lib/build-tool/flowy-codegen' | head -1 || true)
    if [ -n "$baked" ] && [ "$baked" != "$FRONTEND/rust-lib/build-tool/flowy-codegen" ]; then
      printf '  %s\n    baked: %s\n' "$(basename "$(dirname "$script_bin")")" "$baked"
      STALE=1
      break
    fi
  done < <(find "$TARGET/release/build" -name build-script-build 2>/dev/null)
fi
if [ "$STALE" = "1" ]; then
  printf '  Cached flowy-codegen was compiled for a different checkout path.\n'
  printf '  Clearing it and every build script that linked it.\n'
  rm -f "$TARGET"/release/deps/libflowy_codegen-*.rlib \
        "$TARGET"/release/deps/libflowy_codegen-*.rmeta \
        "$TARGET"/release/deps/flowy_codegen-*.d
  rm -rf "$TARGET"/release/.fingerprint/flowy-codegen-* \
         "$TARGET"/release/build/flowy-* \
         "$TARGET"/release/build/dart-ffi-*
  ok "stale caches cleared"
else
  ok "no stale caches"
fi

# ---------------------------------------------------------------------------
# 3. Build. `appflowy` = release Rust core -> codegen -> flutter release ->
#    copy to product/. Slow: the Rust core is compiled from scratch.
# ---------------------------------------------------------------------------
if [ "${LUDWIG_SKIP_BUILD:-0}" != "1" ]; then
  bold "Building $APP_NAME (release, arm64) — the Rust core takes a while"
  ( cd "$FRONTEND" && cargo make --profile "$PROFILE" appflowy )
  ok "build finished"
fi

[ -d "$APP_PATH" ] || fail "expected $APP_PATH, which is missing.
  If the build reported success, check PRODUCT_NAME in frontend/Makefile.toml
  matches the Xcode project — a mismatch copies nothing, silently."

# ---------------------------------------------------------------------------
# 4. Verify it is the real app, by CONTENTS. A timestamp proves nothing here:
#    Flutter copies cached artifacts and preserves their mtime.
# ---------------------------------------------------------------------------
bold "Verifying the bundle"
# A release build is AOT-compiled: the Dart code lives in App.framework's binary,
# and there is NO kernel_blob.bin (that is the debug layout). Checking for the
# wrong one made this script reject a perfectly good release build.
DART_BIN="$APP_PATH/Contents/Frameworks/App.framework/Versions/A/App"
[ -f "$DART_BIN" ] || fail "no compiled Dart binary at App.framework/Versions/A/App"

test_refs=$(strings "$DART_BIN" | grep -c IntegrationTestWidgetsFlutterBinding || true)
app_refs=$(strings "$DART_BIN" | grep -c runAppFlowy || true)
[ "$test_refs" = "0" ] || fail "bundle contains $test_refs test-binding refs — this is a TEST build"
[ "$app_refs" -gt 0 ] || fail "bundle has no runAppFlowy — not the real app"
ok "not a test build ($test_refs test refs, $app_refs app refs)"

# Ludwig's own assets, as a check that the rebrand actually shipped. Do NOT add
# `LudwigServerPolicy` here: it is a compile-time const, so release AOT folds it
# away and greps to 0 in a correct build.
ASSETS="$APP_PATH/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/images"
for asset in ludwig_logo.png ludwig_launch_splash.jpg; do
  [ -f "$ASSETS/$asset" ] || fail "$asset missing from the bundle — the rebrand did not ship"
done
ok "Ludwig branding assets present"

actual_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
[ "$actual_id" = "$BUNDLE_ID" ] || fail "bundle id is $actual_id, expected $BUNDLE_ID"
ok "bundle id $actual_id"

# ---------------------------------------------------------------------------
# 5. Sign. Self-signed (specs/distribution.md D6). This does NOT get past
#    Gatekeeper on a downloader's Mac — they still need right-click -> Open the
#    first time — but it keeps the code hash stable across rebuilds, so granted
#    permissions survive an update instead of silently resetting.
# ---------------------------------------------------------------------------
bold "Signing"
IDENTITY="${LUDWIG_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  # NOTE: match against `find-identity` WITHOUT `-p codesigning`. A self-signed
  # root is reported as CSSMERR_TP_NOT_TRUSTED and omitted from the codesigning
  # policy list, even though `codesign` signs with it perfectly well (verified
  # 2026-07-27). Trust affects *verification* on someone else's Mac — and
  # Gatekeeper rejects self-signed there regardless — not our ability to sign.
  # So do NOT "fix" this by asking anyone to trust the certificate.
  if security find-identity 2>/dev/null | grep -q "Ludwig Self-Signed"; then
    IDENTITY="Ludwig Self-Signed"
  else
    IDENTITY="-"
  fi
fi

if [ "$IDENTITY" = "-" ]; then
  printf '\033[33m⚠ No "Ludwig Self-Signed" identity found — leaving the build ad-hoc signed.\033[0m\n'
  printf '  Create one once, in Keychain Access:\n'
  printf '    Keychain Access → Certificate Assistant → Create a Certificate…\n'
  printf '    Name: Ludwig Self-Signed   Identity Type: Self Signed Root\n'
  printf '    Certificate Type: Code Signing\n'
  printf '  Then re-run this script. Until then every rebuild resets macOS permissions.\n'
else
  # --deep is deprecated for signing but still the practical way to cover the
  # embedded frameworks Flutter ships.
  #
  # Deliberately NOT `--options runtime`. The hardened runtime enforces library
  # validation — every loaded library must be signed by the same team — and a
  # self-signed certificate has no team, so Flutter's embedded frameworks can
  # fail to load at launch. Hardened runtime is a prerequisite for
  # *notarization*, which this build does not do (D6: self-signed).
  codesign --force --deep --sign "$IDENTITY" "$APP_PATH"
  ok "signed with: $IDENTITY"
fi

codesign --verify --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/  /'
sig=$(codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "^Signature" || echo "Signature=unknown")
ok "$sig"

# ---------------------------------------------------------------------------
# 6. Report. AGPL: the release must point at the exact source it was built
#    from, so print it rather than trusting anyone to remember.
# ---------------------------------------------------------------------------
bold "Done"
commit=$(cd "$REPO_ROOT" && git rev-parse HEAD)
dirty=$(cd "$REPO_ROOT" && git status --porcelain | wc -l | tr -d ' ')
printf '  app          %s\n' "$APP_PATH"
printf '  size         %s\n' "$(du -sh "$APP_PATH" | cut -f1)"
printf '  source       %s%s\n' "$commit" "$([ "$dirty" != "0" ] && echo "  ⚠ $dirty uncommitted change(s) — the release would not match any commit")"
printf '  license      AGPL-3.0 (LICENSE at the repo root; AppFlowy attributed in the copyright string)\n'
