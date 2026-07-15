# Project Status

*The current snapshot only — replace sections when they change, don't append to them. Detailed history lives in each feature's spec, under its own "Session Log."*

**Last updated:** 2026-07-15 (round 2 — editor merge investigated and deliberately deferred; fork hygiene done)

## Active feature
RTL/LTR support (`specs/rtl-support.md`). Phase 1 (sidebar) done and signed off. Phase 2 (document-content direction) is in good shape: auto-detect direction, bidi, block-insert menu direction, icon-margin gap, and now the **empty-line cursor** are all done.

## The editor-fork merge is deferred on purpose — don't restart it from the "36 behind" number
The fork-sync check will keep reporting the editor fork as **36 behind / 10 ahead**. That is true and
still the wrong target to chase. `AppFlowy-IO/AppFlowy` pins `appflowy_editor` at `470c4e7`, which is
**byte-identical to our merge base** — against the upstream that actually matters we are **0 behind**,
and those 36 commits belong to a package the app doesn't follow. 35 of them sit at/after a Flutter
≥3.32 bump (upstream CI runs 3.38.5) while the app, AppFlowy-IO's CI and this machine are all on
3.27.4, so `pub get` fails before anything compiles. It is a Flutter migration of all of AppFlowy, not
an editor merge, and it would land us on an untested AppFlowy 0.11.4 + editor 6.1.0 while *increasing*
what we maintain. **Trigger to revisit: when AppFlowy-IO bumps its own editor pin past `470c4e7`.**
Full reasoning, the landmines, and the convergent-conflict finding: `specs/rtl-support.md` →
"Editor fork — upstream merge".

## How to verify anything here (read this first — these rules are why the loop broke)
**Several "still broken" bugs turned out to be already fixed — the user was testing a STALE dock app** (found 2026-07-15 r1). The floating toolbar was the clearest case: it worked in a fresh build and was broken only in the installed app, which predated the fix. That explained the multi-session loop: **the fixes were real but never reached the app being tested in.** Everything below exists to stop that recurring — treat it as standing procedure, not history.
1. **Verify against the REAL macOS render path, never headless `flutter test`.** Run `flutter test integration_test/desktop/document/<file>.dart -d macos`. Plain `flutter test` forces a fixed-width fake font (Ahem) that collapses RTL glyph geometry, so RTL caret/position bugs are invisible to it — this is why prior headless "fixes" went green while the app stayed broken. (It gets worse: even on the real target, `editorState.selectionRects()` mis-reports the caret for the shrink-wrapped empty RTL block — measure the actual rendered `Cursor` widget's global rect instead.)
2. **The user's dock app IS the DEBUG build — verified from the Dock plist, don't re-guess this.**
   `~/Library/Preferences/com.apple.dock` → the AppFlowy tile points at
   `…/frontend/appflowy_flutter/build/macos/Build/Products/Debug/AppFlowy.app`.
   So: their real pages live in `…/com.appflowy.appflowy.flutter/**data_dev_beta.appflowy.cloud**` (debug + AppFlowy Cloud), **not** `data_beta.appflowy.cloud` (that's a stale release-build cache — a *different* local cache of the same cloud workspace `612287731153768448`).
   **To ship a fix to the user's daily app: `flutter build macos --debug`** — it rebuilds *in place* at the exact path the dock icon already points to. No release build, no `/Applications` copy, no dock changes needed. (A release build was tried on 2026-07-15 r1 and was the wrong target: it opened `data_beta`, so recent pages looked "missing." Nothing was lost.)
   Data-dir map: debug → `data_dev*`; release → `data*`; integration tests → their own sandbox (see the hazard below).
   Note for debug bundles: the Dart code is `Contents/Frameworks/App.framework/Resources/flutter_assets/kernel_blob.bin`. **Do NOT judge a rebuild by its timestamp** (corrected 2026-07-15 r2 — the earlier advice here was wrong): Flutter copies the cached artifact and *preserves its mtime*, so a successful rebuild can legitimately show an old time. A verified-correct restore on 2026-07-15 r2 read `09:26` — hours stale, and fine. Check **contents**, not time:
   ```
   KB=build/macos/Build/Products/Debug/AppFlowy.app/Contents/Frameworks/App.framework/Resources/flutter_assets/kernel_blob.bin
   strings "$KB" | grep -c IntegrationTestWidgetsFlutterBinding   # want 0 (non-zero = it's a TEST build)
   strings "$KB" | grep -c runAppFlowy                            # want >0 (the real app)
   ```
   (Grepping the blob for a *test filename* is a false-positive detector — it matches a code comment in `appflowy_rich_text.dart` that references the test file.)
3. **⚠️ HAZARD — `flutter test integration_test/... -d macos` OVERWRITES the dock app with a TEST build.** (Found 2026-07-15 r2.) The run rebuilds *in place* at `build/macos/Build/Products/Debug/AppFlowy.app` — the exact path the Dock tile points at — using the test as the Dart entrypoint. Verified: afterwards the bundle carried **14** `IntegrationTestWidgetsFlutterBinding` refs. Clicking the dock icon then launches the test harness, not AppFlowy. This is silent, and is very likely a *second* cause of the "blank window / looks broken" reports previously blamed only on the pref below.
   **Always re-run `flutter build macos --debug` after any `-d macos` integration test**, then verify by contents as above.
4. **⚠️ HAZARD — integration tests pollute the user's REAL app preferences.** `initializeAppFlowy()` → `mockApplicationDataStorage()` writes
   `flutter.io.appflowy.appflowy_flutter.path_location` into `~/Library/Preferences/com.appflowy.appflowy.flutter.plist`, which is **shared by every build (same bundle id)**. The user's app then opens an empty integration-test sandbox under `~/Library/Caches/appflowy_integration_test/…` and shows a **blank window** — which looks exactly like a broken build. Their data is fine; the app is just looking in the wrong folder.
   **After ANY integration-test run, clear it before the user opens their app:**
   ```
   defaults delete com.appflowy.appflowy.flutter flutter.io.appflowy.appflowy_flutter.path_location
   ```
   (Also note `syncDefaultTextDirection(...)` in tests writes `kDocumentAppearanceDefaultTextDirection` to those same real prefs — it happened to match the user's existing `rtl`, but don't rely on that.)

## Bug status
- **Empty-line cursor ("creating a new line has a very far cursor") — FIXED, confirmed live by the user.** Root cause was the user's setting **`kDocumentAppearanceDefaultTextDirection = rtl`** (document default direction RTL). That made every empty line RTL while showing the LTR English "Type '/'…" placeholder, and two stacked bugs stranded the caret/text far left:
  1. The empty-line caret resolved to logical offset 0 of the LTR placeholder run (its *left* end). The old "correction" was a permanent no-op (it read `_renderParagraph.size.width`, a real 0.0 for empty text, before the placeholder width in a `??` chain). Fixed by SETTING the caret dx to the placeholder paragraph's own (right-aligned) width — the RTL start.
  2. Typing then "jumped left" because the invisible placeholder was kept full-width, inflating the right-aligned RTL block so real text rendered a placeholder-width left of the content edge. Fixed by collapsing the placeholder to an empty span (keeps line height, takes no width) when the line has text.
  Both fixes are in the editor fork's `appflowy_rich_text.dart`. Committed: fork `ba6c4fcb`, app `6ff1967c4`, pin resynced (no drift). Real-target regression test: `integration_test/desktop/document/document_rtl_empty_caret_test.dart`.
- **Floating selection toolbar — WORKING in current code; earlier "broken" was the stale dock app.** User confirmed it works in a fresh build. No new code needed. (The debounce-split fix from a prior session was real; it just never reached the user's stale app.)
- **Mid-character cursor in embedded dates — DEFERRED to next session** (user's choice). Deterministic repro is already encoded in the fork's `caret_bidi_test.dart` skipped test. Blocker is an *oracle* — the user needs to look at the one anomalous boundary (right after the comma in an embedded date like `20.4.26,`) and say what "correct" is. Plan next time: capture a real-render screenshot of that spot, get the user's judgment, then fix to match.

## Where things stand
- Repo forked (`origin` = matanrotman/AppFlowy), `upstream` = AppFlowy-IO/AppFlowy.
- **Fork-sync (checked 2026-07-15 r2, end of session):** app `main` **0 behind** `upstream/main` — that's the number that matters. (The "ahead" count is ~26 and climbs with every commit here, so don't treat any figure written down as current; the session-start fork-sync check is authoritative.) Editor fork branch `rtl-direction-aware-selection-menu` **36 behind, 10 ahead** of `AppFlowy-IO/appflowy-editor` (tagged 6.1.0; our pin reports 5.2.0) — see the "deferred on purpose" section at the top before acting on that number. Pin ↔ pushed-HEAD: **in sync** (`ba6c4fcb`).
- **Editor fork upstream merge — deferred indefinitely, on evidence.** Not "risky to fold into a bug-fix session" (the old reason) — it's the wrong move until AppFlowy-IO moves first. See the top section.
- **⚠️ The RTL caret regression test is intermittently unreliable — 1 hang in 3 runs (2026-07-15 r2).** When it runs it is *deterministic*: two passing runs produced bit-identical geometry (`emptyCaret=1174.0 typedCaret=1164.7 diff=9.3`, threshold 999.0 of a 1332px editor). But one run in between **hung for 61 minutes** and failed having never reached the measurement. Root cause **unknown** — the run's output was destroyed by grepping it, so there's no log (see the process rule below). Ruled out: it is not the `setUpAll` guard (present in the passing runs), not the removed `foundation.dart` import (the *later* passing run has it removed), and not a geometry regression (no `RTLDIAG` line = it never measured).
  **How to read a failure:** if there's no `RTLDIAG` line, the test didn't measure anything — treat it as a flake, re-run, and don't conclude the caret regressed. A real regression shows `RTLDIAG` with bad numbers. **Never pipe a test run through `grep`** — capture full output to a file (`… -d macos > run.log 2>&1`) and grep the *file*, or the next failure is undiagnosable too. Worth a proper diagnosis session before leaning on this test as a safety net.
  **Lead for that diagnosis — deliberately left in place:** `~/Library/Caches/appflowy_integration_test` has **52** accumulated run dirs (14M). It's the prime suspect for the hang, so it was *not* cleaned at session end: wiping it would destroy the repro and probably mask the flake. It is test cache only — the real data is `~/Library/Application Support/com.appflowy.appflowy.flutter/data_dev_beta.appflowy.cloud`, a different tree entirely — so it's safe to clear once the diagnosis is done (or if the flake ever blocks real work).
- **Upstream toolbar PR prepared, NOT sent** (awaiting review). Branch `fix/floating-toolbar-debounce-race` in the **editor fork**, off `upstream/main`, commit **`7299f9d4`** — local-only; `git ls-remote` confirms it exists on no remote. **The commit message is the PR body** (durable — don't go looking for the scratchpad draft, that was session-temp). Can't be compiled locally (upstream needs Flutter ≥3.32); verified by inspection only — parses, `dart format`-clean, no dangling `_debounceKey`. If accepted, `floating_toolbar.dart` leaves the fork for good.
  **To send it** (user authorised this on 2026-07-15 r2; the push was blocked by a permission classifier still reading the earlier "prepare, don't send" decision):
  ```
  cd ~/Projects/appflowy-editor-fork
  git push -u origin fix/floating-toolbar-debounce-race
  gh pr create --repo AppFlowy-IO/appflowy-editor --base main \
    --head matanrotman:fix/floating-toolbar-debounce-race
  ```
- **The user's dock app now runs the fixed code with their real data — confirmed live by the user** ("everything's back", cursor fix works). Done by rebuilding the debug app in place (`flutter build macos --debug`), which is what the dock icon points at.
- **Data backup taken 2026-07-15** at `~/Desktop/AppFlowy_data_backup_backup_20260715_0925` (6.2M — all four data folders) before touching anything. **Keep it until the cloud-sync question (Next step #1) is settled** — if recent work is local-only, this backup is currently the only second copy.
- **Incident history (still governs live testing):** a 2026-07-13 live-drag test corrupted a real user document. Rule since: all live typing/selecting/dragging happens in a disposable scratch page, never in existing content.
- Local build confirmed working: `flutter run -d macos` and `flutter build macos --debug` (the dock app). A release build also compiles, but it is **not** the user's app — see rule 2 above.
- Toolchain (unchanged): Rust rustup w/ pinned 1.85 + stable default; `cargo-make` + `duckscript_cli` (`duck`); **Flutter 3.27.4** git-cloned at `~/flutter` (not Homebrew); CocoaPods/sqlite3/protobuf via Homebrew.
- Rust core (dev): `cargo make --profile development-mac-arm64 appflowy-core-dev-macos` (from `frontend/`). Release core: `cargo make --profile production-mac-arm64 appflowy-core-release`.
- Code generation before `flutter run`: `cargo make code_generation` (from `frontend/`).

## Next step
1. **Cloud sync — investigate (user asked for this, 2026-07-15).** The user's real workspace (`data_dev_beta.appflowy.cloud`, debug build) holds their current pages, but the release-build cache of *the same cloud workspace* (`data_beta.appflowy.cloud`, workspace id `612287731153768448`) was noticeably sparser — which suggests recent work may be **local-only and not fully pushed to AppFlowy Cloud**. Nothing was lost and this is unrelated to the RTL bugs, but it means the cloud copy may not be a reliable backup. Worth checking: is sync actually running/succeeding for this workspace; does the account show the same content on another client/the web; are there pending/failed sync ops. Do this **before** deleting the safety backup below.
2. **Mid-character cursor bug** — capture a real-render screenshot of the caret right after the comma in an embedded date, get the user's judgment on correct placement, fix to match, un-skip the `caret_bidi_test.dart` case.
3. **Send the upstream toolbar PR** — user already authorised it 2026-07-15 r2; the push was blocked by a permission classifier and never went out. Commit `7299f9d4` on `fix/floating-toolbar-debounce-race` in the editor fork is ready, and its commit message is the PR body. Exact commands in "Where things stand" above. Accepting it removes one file from every future merge.
4. **Automate the three footguns** — now clearly worth it, since they're the recurring cause of "the app looks broken". A single wrapper script for real-target tests would do all of it: run the test → `flutter build macos --debug` (restore the dock app from the test build) → `defaults delete … path_location` → verify by contents (`grep -c IntegrationTestWidgetsFlutterBinding` = 0). Doing these by hand has failed before.
5. **Editor-fork upstream merge — do NOT schedule.** Deferred indefinitely; see the top section for the trigger. Listed here only so its absence isn't read as an oversight.

## Open questions
- Sharing-scope badge / workspace icon in the content-pane toolbar — user deferred (out of scope for now).
- `specs/tables.md` (RTL table paste) — written spec, untouched, not scheduled.

## Local build quick-reference
Run from `~/Projects/AppFlowy/frontend`, with `~/flutter/bin`, `~/.cargo/bin`, `~/.pub-cache/bin` on PATH:
```
# Dev run (debug; uses the user's real data_dev* workspace):
cargo make --profile development-mac-arm64 appflowy-core-dev-macos
cargo make code_generation
cd appflowy_flutter && flutter run -d macos

# ⭐ SHIP A FIX TO THE USER'S DOCK APP (this is the one that matters):
#    rebuilds in place at exactly the path the dock icon points to.
cd appflowy_flutter && flutter build macos --debug
#    verify it took by CONTENTS — NOT by timestamp. Flutter preserves the cached
#    artifact's mtime, so a correct rebuild can legitimately show an OLD time.
KB=build/macos/Build/Products/Debug/AppFlowy.app/Contents/Frameworks/App.framework/Resources/flutter_assets/kernel_blob.bin
strings "$KB" | grep -c IntegrationTestWidgetsFlutterBinding   # want 0 (non-zero = TEST build)
strings "$KB" | grep -c runAppFlowy                            # want >0 (the real app)

# Real-target regression test (the ONLY trustworthy way to check RTL geometry):
flutter test integration_test/desktop/document/document_rtl_empty_caret_test.dart -d macos

# ⚠️ ALWAYS run BOTH of these afterwards — the test run leaves the dock app broken in
#    two independent ways, and each looks identical to "the build is broken":
flutter build macos --debug   # 1. the test run replaced the dock app with a TEST build
defaults delete com.appflowy.appflowy.flutter flutter.io.appflowy.appflowy_flutter.path_location
                              # 2. it also pointed the app at an empty test sandbox
# Then verify by CONTENTS (not timestamp — see rule 2 above for why):
KB=build/macos/Build/Products/Debug/AppFlowy.app/Contents/Frameworks/App.framework/Resources/flutter_assets/kernel_blob.bin
strings "$KB" | grep -c IntegrationTestWidgetsFlutterBinding   # want 0
strings "$KB" | grep -c runAppFlowy                            # want >0

# Release build: NOT what the user runs. It targets the data* workspace, which is
# a different (stale) cache — building it made pages look "missing". Avoid unless
# genuinely packaging a release.
```
