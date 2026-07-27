# Ludwig — Rebrand and Distribution

## Goal
Two goals that share one set of decisions, which is why they share one spec:

1. **Rebrand.** The fork stops being "AppFlowy with my changes" and becomes **Ludwig** — its own
   name, its own icon, its own identity on macOS, its own data location. Starting with my machine.
2. **Distribute.** Other people **download and run Ludwig without compiling it** — **macOS only**
   (the only platform I run and can actually test). The audience is people who want what this fork
   has and upstream doesn't: RTL support, local/Drive backup, the ribbon, and what comes next.

They share a spec because the rebrand *is* the hard half of distribution. Bundle id, app name, data
location and default server are all one decision surface, and getting them wrong is expensive to
undo once anyone has downloaded a build.

## Status
**Scoping interview DONE (2026-07-27, session 17). Awaiting sign-off, then Phase 1.**
This supersedes the "placeholder, not scoped" status this file carried since 2026-07-17.

**Scope of the current work: Phase 1 only** (the user's choice) — my dock app becomes Ludwig, with
all my writing. Nothing ships to anyone. Phases 2–4 are specified below but not started.

### ⚠️ Superseded: the 2026-07-18 "no rebrand" decision
This file previously recorded a leaning decision: *"No rebrand. Keep the AppFlowy name; do NOT
start a separate product,"* with only the bundle id and data folder changing. **That is superseded**
by `specs/product-direction.md` (2026-07-26), which makes *"Rebrand and distribution"* priority #1
and names the product Ludwig, and by the user's explicit confirmation in the session-17 interview.

The old reasoning is kept in the Session Log rather than deleted — it was sound at the time and a
future session shouldn't have to rediscover why "AppFlowy (RTL build)" was ever on the table. It
lost because the product acquired an identity of its own in the intervening week.

## Decisions from the scoping interview (2026-07-27)

| # | Decision | Reasoning |
|---|---|---|
| **D1** | **Full Ludwig identity.** New name, own icon, own bundle id, own data folder, own copyright. AppFlowy credited honestly in About and README as AGPL requires, but Ludwig presents as its own product — not as a build of something else. | The product has its own philosophy, its own refusals and its own roadmap (`product-direction.md`). Calling it "AppFlowy (RTL build)" would misdescribe what it now is. |
| **D2** | **The app shows "Ludwig".** Just the word — Dock, window title, menu bar, About. No tagline, no "(beta)" in the chrome. | Cleanest, most product-like. Positioning text belongs on the release page, not in the title bar the user stares at every day. |
| **D3** | **Bundle id: `app.ludwig.desktop`.** | Product-first rather than person-first; reads correctly if Ludwig outgrows being a personal build. Slightly aspirational (implies `ludwig.app`) but nothing breaks if that domain is never registered. **Settle once — changing it later relocates everyone's data.** |
| **D4** | **A fresh download is local-only.** No sign-in, no server, everything on the downloader's disk; backup is the safety net. | Sync is *proven dead* for source-built AppFlowy (see `STATUS.md` — pages arrive as empty shells and typed content is silently dropped). Pointing a stranger at that server would quietly destroy their writing. **`AuthenticatorType.local` already exists as a first-class mode** — this is flipping a default, not building a feature. |
| **D5** | **The cloud switch is removed for downloaded builds only**, behind a debug/dev flag. I keep it on my machine; a downloader cannot reach it. | Same reasoning as D4, one layer deeper: leaving the control visible means a downloader can walk into Settings and opt themselves into silent data loss. That is a data-loss trap behind a menu item, not a preference. Cost: a build-mode branch and a deliberate divergence between my build and theirs. |
| **D6** | **Code signing: deferred to release time.** | Nothing in Phases 1–2 depends on it, and the trade-off (see "Signing" below) is easier to judge against an actual binary. |
| **D7** | **My data migrates by COPY, keeping the old folder.** Forced Drive snapshot first, copy to the new location, verify, leave the AppFlowy folder untouched as a fallback. | Slowest and safest. The old folder can be deleted whenever; a bad move cannot be undone at all. |
| **D8** | **The icon is the user's own**, supplied as a source image; I generate the 24 macOS sizes. | — |

## What actually changes — verified in the code, session 17

### App identity
| Thing | Where | Current | Becomes |
|---|---|---|---|
| Product name | `macos/Runner/Configs/AppInfo.xcconfig` | `AppFlowy` | `Ludwig` |
| Bundle id | `macos/Runner.xcodeproj/project.pbxproj` — **this overrides the xcconfig**, which still says `io.appflowy.appflowy` | `com.appflowy.appflowy.flutter` | `app.ludwig.desktop` |
| Copyright | `AppInfo.xcconfig` | `© 2025 AppFlowy.IO` | Ludwig + AppFlowy attribution |
| Icon | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` — 24 PNGs | AppFlowy logo | user's icon |
| In-app name | `assets/translations/en-US.json` `"appName"`, `he.json` | `AppFlowy` | `Ludwig` |

`en-US.json` has **40** `AppFlowy` occurrences and `he.json` **11**, but most are `AppFlowy Cloud` /
`AppFlowy AI` — cloud-specific or belonging to surfaces already retired
(`specs/retire-non-core-surfaces.md`). Only strings that name *the app* get changed. The other ~40
locale files are left alone in Phase 1; they are not languages this user reads, and a partial
rename there is no worse than the current state.

### The data folder moves by itself — and that is the risk
The path is `getApplicationSupportDirectory()` + `data_dev` (debug) / `data` (release)
([`rust_sdk.dart:73`](../frontend/appflowy_flutter/lib/startup/tasks/rust_sdk.dart)), and on macOS
that first component **is the bundle id**. So D3 relocates the data automatically, no code change.
The cost is that everything else keyed to the bundle id moves too.

**⚠️ The landmine, confirmed in Rust.** `flowy-core/src/config.rs:45` builds the folder suffix from
the cloud base URL — and **local mode gets no suffix at all**:

```
AppFlowy Cloud  →  data_dev_beta.appflowy.cloud     ← the user's real 17MB of writing
local           →  data_dev                          ← a stale 15MB folder that already exists
```

`kCloudType` lives in the **preferences plist, keyed to the bundle id** — *not* in the data folder.
So it does not survive the rename. Phase 2 flips the fresh-install default to local (D4); if that
lands after Phase 1 has wiped `kCloudType`, the user's own app resolves to **bare `data_dev`** —
which already exists, from an earlier local-mode run — and their pages look gone.

**Phase 2 must explicitly write `kCloudType = 2` for this install before the default flips.**
This is the single most valuable thing the interview found.

### Preferences lost to the bundle-id change (recovery checklist)
None of this is writing. All of it is recoverable by hand. Discovering it one item at a time over a
week is the failure mode this list exists to prevent. Dumped from the live plist, session 17:

- [ ] `flutter.featureFlag = {"ribbonMenu":true}` — **the ribbon vanishes without this**
- [ ] `flutter.sidebarDockSide = right` — sidebar jumps to the left
- [ ] `flutter.kCloudType = 2` + `flutter.kAppFlowyCloudBaseURL` — see the landmine above
- [ ] `flutter.backupSettings` (enabled, 30 min) + `flutter.backupState` (high-water mark) — a lost
      high-water mark just forces one full snapshot; harmless but confusing
- [ ] `flutter.expandedViews` — ~130 pages' collapse state
- [ ] `flutter.lastOpenedSpaceId`, `flutter.ribbonActiveTab`, `flutter.ribbonCollapsed`
- [ ] `flutter.windowSize` / `windowPosition` / `windowMaximized`
- [ ] `flutter.kRecentIcons` — recently-used emoji and icons
- [ ] `flutter.kDocumentAppearanceDefaultTextDirection` — currently **`auto`** (note: `STATUS.md`
      records this as `rtl`; it has since changed, and a couple of verification rules there assume
      the old value)

Phase 1 dumps the whole plist to a file before touching anything, so this is a restore, not a
reconstruction.

### ⚠️ Backup snapshot naming — rename this carelessly and the safety net goes blind
[`snapshot_repository.dart:47`](../frontend/appflowy_flutter/lib/shared/backup/snapshot_repository.dart)
parses snapshots with:

```
^AppFlowy-(backup|prerestore)-v(.+)-(\d{8})-(\d{6})\.zip$
```

and writes `'AppFlowy-$kindLabel-v$appVersion-$ts.zip'`. Changing the prefix to `Ludwig-` without
changing the reader makes **every existing snapshot invisible** — to the restore browser, to
"Find something you lost", and to the retention pruner. That is a real regression in the one proven
safety net.

**Required:** the regex accepts `(AppFlowy|Ludwig)`; the writer emits `Ludwig-`. Both, in the same
change, with a test covering an old-prefix name.

### ⚠️ The Dock tile breaks, and it will look like a broken build
The Dock points at `…/build/macos/Build/Products/Debug/**AppFlowy.app**`. Renaming `PRODUCT_NAME`
makes the build output **`Ludwig.app`** — a different path. The old tile becomes a dead icon.
Expect to drag the new app to the Dock once. Every verification rule in `STATUS.md` that names
`Debug/AppFlowy.app` needs updating in the same pass.

## Phased plan

### Phase 1 — Be Ludwig (the current scope)
Nothing ships. Ends with the user's daily app named Ludwig, wearing their icon, holding all their
writing, behaving exactly as before.

1. **Pre-flight.** Forced Drive snapshot, **verified on disk by contents, not by its label**. Dump
   the preferences plist to a keepsake file.
2. **Rename.** `PRODUCT_NAME`, bundle id, copyright. `appName` in `en-US.json` + `he.json`.
3. **Snapshot-prefix compatibility.** Regex accepts both prefixes; writer emits `Ludwig-`; test.
4. **Icon.** Generate the 24 sizes from the user's source image into `AppIcon.appiconset`.
5. **Build** (`flutter build macos --debug`) and **verify by contents**, per `STATUS.md`'s rules.
6. **Migrate data.** Copy (not move) `data_dev_beta.appflowy.cloud` into
   `~/Library/Application Support/app.ludwig.desktop/`. Leave the original untouched.
7. **Restore preferences** from the checklist above.
8. **Verify live:** pages all present, ribbon present, sidebar on the right, backup still finds its
   destination and its history, Hebrew pages intact.
9. **Update `STATUS.md`'s verification rules** to the new app name and paths.

**Not in Phase 1:** the local-only default, removing the cloud switch, the release build, signing,
GitHub Releases, the other ~40 locale files, Windows/Linux, the app's own font bundling.

### Phase 2 — The fresh-install path
Make a clean launch correct for someone who is not me.
- Write `kCloudType = 2` for this install **before** anything else (the landmine).
- Flip the fresh-install default from AppFlowy Cloud to `AuthenticatorType.local`
  ([`cloud_env.dart:56`](../frontend/appflowy_flutter/lib/env/cloud_env.dart) — the null branch
  currently *writes* AppFlowy Cloud as the default).
- Hide the cloud switch behind a dev flag (D5).
- Prove it in a scratch data folder: launch clean, no sign-in wall, no `beta.appflowy.cloud`, a page
  can be written and survives a restart.

### Phase 3 — The release build
- `flutter build macos --release` as a **genuinely new target** — `STATUS.md` warns it opens a
  different data dir and it has never been validated for this fork.
- Signing decision (D6 comes due here).
- A repeatable build script.
- AGPL: license preserved, release links the exact source commit, AppFlowy attributed.

### Phase 4 — Publish
GitHub Releases on `matanrotman/AppFlowy`, release notes, README, the pitch. Manual re-download for
updates — no updater in v1.

## Signing — the decision deferred by D6
| Option | Cost | Gatekeeper | Permissions survive updates? |
|---|---|---|---|
| Self-signed cert | free | ✗ right-click-Open needed | ✓ |
| Apple Developer + notarize | $99/yr | ✓ just opens | ✓ |
| Unsigned | free | ✗ hard on recent macOS | ✗ re-prompts every release |

**Why this is more than a download-time nicety** (evidence from 2026-07-19): the build is *ad-hoc*
signed, and macOS keys TCC permission grants to the code hash — which changes on every rebuild. So
every granted permission dies at the next release. This surfaced as the app re-asking for Documents
access on every launch. It will matter concretely when the microphone-dependent transcription
feature is built.

## Open questions
1. **Signing** (D6) — decide at Phase 3 against a real binary.
2. **The other ~40 locale files** — rename `appName` everywhere, or leave them? Deferred; costs
   nothing to do later, and none are languages this user reads.
3. **`RESTORE.md` and the backup docs** still say AppFlowy throughout. Update in Phase 1 or 3?
4. **Existing snapshots keep the `AppFlowy-` prefix forever.** Acceptable (the reader handles both),
   or rename them on disk? Leaning: leave them — renaming files in a proven backup set to make them
   prettier is a bad trade.
5. **What's the pitch?** Which features are the reason to download Ludwig. Shapes Phase 4.

## Out of scope (first version)
Windows and Linux builds; auto-update infrastructure; App Store / Flathub / Snap; any server the
fork hosts itself; bundling the font library (deferred to the ribbon font feature — see below).

## Note: font bundling belongs to the ribbon, not here
Settled 2026-07-27: the 113 downloaded Hebrew/Arabic families at
`~/Projects/ludwig-fonts/google_fonts_he_ar/` are **document fonts for writing, not UI fonts**.
They become important when the ribbon's font picker is built, and **should be bundled as part of any
Ludwig distribution** at that point. Deferred there by the user's decision, not forgotten.

Measured evidence for the eventual bundling argument, gathered session 17: the user's app-support
folder holds **224 TTF files / 61MB** of `google_fonts` *runtime downloads* — over three times the
size of their actual writing (17MB). An offline build cannot rely on that fetch.

The **UI** font question is closed: **Rubik**, one family genuinely covering Latin + Hebrew + Arabic
(verified by parsing the font's character map: latin=58, hebrew=47, arabic=89), selectable today
with no code. Poppins, the previous UI font, contains **zero** Hebrew and **zero** Arabic — which is
why Hebrew and English sidebar rows never looked like the same typeface.

## How we'll know it's done
**Phase 1:** the Dock launches an app called Ludwig, wearing the user's icon, with every page,
space and setting where it was — and the AppFlowy data folder still sitting untouched beside it.

**Overall:** a non-technical person follows a link, downloads Ludwig, opens it on macOS without an
insurmountable Gatekeeper wall, and it runs with its own identity — no collision with official
AppFlowy, no attempt to sync into anyone's account, no route to silent data loss. The release links
the exact source commit and preserves the AGPL license.

## Session Log
- **2026-07-27 (session 17) — SCOPING INTERVIEW DONE, no code.** Two rounds of questions, eight
  decisions (D1–D8 above). Rebrand to **Ludwig** confirmed, superseding the 2026-07-18 "no rebrand"
  leaning. Bundle id **`app.ludwig.desktop`**. Fresh downloads **local-only** with the cloud switch
  removed for downloaded builds only. Data migrates by **copy**, old folder kept. Signing deferred
  to release. Icon supplied by the user. Scope of the work: **Phase 1 only.**
  **Four findings from reading the code and the live machine, each of which changes the plan:**
  (1) **`kCloudType` lives in the bundle-id-keyed preferences plist, not the data folder**, so the
  rename drops it — and because local mode resolves to a *suffixless* data folder that already
  exists with 15MB of stale content, Phase 2's local-only default would make the user's real pages
  look gone. Phase 2 must set `kCloudType = 2` explicitly first. (2) The **backup snapshot parser is
  hardcoded to `^AppFlowy-`**; renaming the prefix without widening the regex blinds the restore
  browser and the pruner to every existing snapshot. (3) The **Dock tile breaks** because
  `PRODUCT_NAME` decides the built `.app` filename — this will look like a broken build if
  unannounced. (4) **Local-only is ~5 lines, not a feature** — `AuthenticatorType.local` already
  exists; `cloud_env.dart`'s null branch actively writes AppFlowy Cloud as the default.
  Also recorded: the **UI font question is closed (Rubik)** and font *bundling* moves to the ribbon
  font feature by the user's decision.
- **2026-07-19 — signing question sharpened by real evidence (no distribution code).** While fixing a repeating macOS Documents-permission prompt, discovered the build is ad-hoc signed and that this makes **every** TCC permission grant expire on the next rebuild. The practical upshot: stable signing is not only about Gatekeeper warnings at download time — it decides whether users keep their granted permissions across updates, and it will matter concretely when the microphone-dependent transcription feature is built. A self-signed cert may be enough for that half; notarization remains separate.
- **2026-07-18 — identity/naming direction set (no code). ⚠️ SUPERSEDED 2026-07-27, see D1.** User decided: no rebrand, no separate product. Keep the AppFlowy name with an honest qualifier ("RTL build" / "community build"); change only the bundle id + data-folder location so the build coexists with official AppFlowy. The reasoning at the time: the goal was "let people enjoy my features without compiling," not "build my own app," and AGPL does not require a rename. This lost a week later because the product acquired an identity of its own (`specs/product-direction.md`). Also this session: confirmed the backup feature is already multi-user-capable on macOS (auto-detects any Google account, manual folder picker covers non-Drive users, degrades gracefully) — no backup changes needed for a macOS distribution; details folded into `specs/google-drive-backup.md`.
- **2026-07-17 — spec created, no code.** Captured during the "position this fork for other users" session. Decided macOS-only for now. Recorded the real cross-cutting issues (bundle-id collision with official AppFlowy — verified `com.appflowy.appflowy.flutter` / product name `AppFlowy` are identical to official; AGPL-3.0 obligations — verified via `LICENSE`; Gatekeeper signing/notarization trade-off; what a downloaded build connects to; hosting on GitHub Releases; manual-update expectation). No interview run yet — this is the placeholder so the goal isn't lost and so in-flight features keep app-identity/data-location/default-server in mind.
