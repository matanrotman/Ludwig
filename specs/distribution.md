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
**Scoping interview DONE (session 17). PHASE 1 DONE (sessions 17–18) — the app is Ludwig and it is
the user's daily build. Phase 2 (the fresh-install path) is next.**
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

**✅ ALL TEN RESTORED AND VERIFIED (session 18)** — but six of them were missed on the first pass
and only found by diffing the domains a session later. Marked below with how they were resolved.

- [x] `flutter.featureFlag = {"ribbonMenu":true}` — **the ribbon vanishes without this**, and it
      did: **missed in Phase 1, the ribbon was genuinely off for ~1.5 hours of real use.** Restored.
- [x] `flutter.sidebarDockSide = right` — sidebar jumps to the left. Restored in Phase 1.
- [x] `flutter.kCloudType = 2` + `flutter.kAppFlowyCloudBaseURL` — see the landmine above. Restored
      in Phase 1, which is why the pages showed up at all.
- [x] `flutter.backupSettings` (enabled, 30 min) — **missed in Phase 1**; backups ran on defaults,
      which happen to match. `flutter.backupState` survived and is *newer* than the dump, so it was
      deliberately left alone (a lost high-water mark only forces one full snapshot).
- [x] `flutter.expandedViews` — ~130 pages' collapse state. **Missed in Phase 1**, and restored by
      **merge, not overwrite**: the new domain had already learned 19 entries that are newer than
      the dump (110 + 19 = 111).
- [x] `flutter.lastOpenedSpaceId`, `flutter.ribbonActiveTab`, `flutter.ribbonCollapsed` — **missed
      in Phase 1.** Restored.
- [x] `flutter.windowSize` / `windowPosition` / `windowMaximized` — restored in Phase 1.
- [x] `flutter.kRecentIcons` — recently-used emoji and icons. **Missed in Phase 1.** Restored.
- [x] `flutter.kDocumentAppearanceDefaultTextDirection` — **`auto`**. **Missed in Phase 1.**
      Restored, and `STATUS.md`'s stale `rtl` claim corrected in the same pass.

Phase 1 dumps the whole plist to a file before touching anything, so this is a restore, not a
reconstruction. **The dump is at `~/Desktop/Ludwig_phase1_preflight/prefs_ORIGINAL.plist`** (plus a
readable `.xml` twin, the original icon set, and a data copy).

**Two procedural lessons, both earned:**
1. **Write these with the app quit, and verify by reading the plist FILE, not `defaults read`.**
   macOS's preferences daemon caches a running app's domain and rewrites it from that cache on
   exit — so a write during a live session can vanish, and a read-back through the daemon only
   proves the daemon agrees with itself.
2. **Tick this list against the domain, not against the app's appearance.** Ludwig looked entirely
   correct with six of these missing, because the four load-bearing ones had been restored.
   Everything else fails as "quietly behaves like a fresh install."

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

### Phase 1 — Be Ludwig ✅ DONE (built session 17, closed out session 18)
Nothing ships. Ends with the user's daily app named Ludwig, wearing their icon, holding all their
writing, behaving exactly as before.

1. ✅ **Pre-flight.** Forced Drive snapshot, **verified on disk by contents, not by its label**. Dump
   the preferences plist to a keepsake file. → `~/Desktop/Ludwig_phase1_preflight/`
2. ✅ **Rename.** `PRODUCT_NAME`, bundle id, copyright. `appName` in `en-US.json` + `he.json`.
   **The trap: `project.pbxproj` overrides `AppInfo.xcconfig` and wins silently.**
3. ✅ **Snapshot-prefix compatibility.** Regex accepts both prefixes; writer emits `Ludwig-`; tests
   cover an old-prefix name, a refused foreign prefix, and the writer never emitting the old one.
4. ✅ **Icon.** All 25 sizes. **The source PNG had no alpha and white corners** — masked to an
   Apple-style superellipse and the mark enlarged first.
5. ✅ **Build** and **verify by contents**: test-binding refs 0, `runAppFlowy` 31.
6. ✅ **Migrate data.** Copied (not moved) into `~/Library/Application Support/app.ludwig.desktop/`.
   Original untouched.
7. ✅ **Restore preferences** from the checklist above — **four in session 17, the remaining six in
   session 18** after a domain diff found them missing. See the checklist for which.
8. ✅ **Verify live** (user, session 18, after the preference restore): **ribbon back**, sidebar on
   the right, **backup shows all snapshots** — including the 62 old `AppFlowy-`-prefixed ones, which
   is the reader-accepts-both-prefixes fix proving itself against real data rather than a test.
9. ✅ **Update `STATUS.md`'s verification rules** to the new app name and paths (session 18).

**Not in Phase 1:** the local-only default, removing the cloud switch, the release build, signing,
GitHub Releases, the other ~40 locale files, Windows/Linux, the app's own font bundling.

### Phase 2 — The fresh-install path ✅ DONE (session 18)
Make a clean launch correct for someone who is not me.
- ✅ **`kCloudType = 2` was already set** for this install — restored in session 18's preference
  sweep, before the flip existed. The landmine was defused by accident rather than by plan, and
  verified before any code changed.
- ✅ **Fresh-install default flipped to `AuthenticatorType.local`**
  ([`cloud_env.dart`](../frontend/appflowy_flutter/lib/env/cloud_env.dart)). **Two branches, not
  one** — the spec only knew about the null branch; reading the function turned up a second one that
  resolves an *unrecognised* stored value to AppFlowy Cloud. A damaged preferences file could
  therefore put a downloaded build on someone else's server. Both now resolve to local.
- ✅ **Server switcher hidden in EVERY build, the user's own included** — their explicit choice over
  the narrower "release builds only". Reasoning: a control present for the person testing and absent
  for everyone else means the shipped path is the one nobody exercises.
- ✅ **Policy lives in a sidecar**, [`ludwig_server_policy.dart`](../frontend/appflowy_flutter/lib/env/ludwig_server_policy.dart),
  so each of the two core files carries a one-line change and future upstream merges stay cheap.
- ✅ **5 unit tests, proven failing-then-passing** by flipping the policy off (3 failed with exactly
  the upstream behaviour: `appflowyCloud`, stored `'2'`). **Stated limitation, written into the test
  file:** the fresh-install branch is guarded by `!integrationMode().isUnitTest` so a test cannot
  write real preferences — that branch is unreachable from a unit test *by design*, and is proven
  only by the drill below.

**The drill — a real fresh install, simulated on the live machine and fully reverted.** Preferences
backed up, backups disabled for the duration (otherwise the run would push a near-empty snapshot
into the Drive history and muddle the restore browser), `kCloudType` deleted, app launched.

| Claim | Evidence |
|---|---|
| Fresh install resolves to local | `kCloudType` written as **`0`** within ~10s |
| No sign-in wall | "Welcome to Ludwig" + a single **Quick Start** button — no email, no third-party buttons |
| Uses the bare local folder | Welcome screen showed `…/app.ludwig.desktop/**data_dev**` |
| No cloud contact | log says `authenticator: Local`; **0** `appflowy.cloud` hits, **0** websocket attempts |
| Switcher gone | Settings → Cloud Settings shows only the local view |
| Writing survives a restart | workspace persisted (1 → 35 files); relaunch went **straight in**, no Welcome screen |
| Real writing untouched | `data_dev_beta.appflowy.cloud` **356 files before and after**; snapshots held at 63 |

Afterwards the preference domain was restored from the backup and diffed against it: **21 keys, none
missing, none changed.**

**✅ Both drill findings were FIXED the same session (see the session log). The updater is off with
a placeholder seam for Ludwig's own feed, the welcome logo and launch splash are Ludwig's, and
Cloud Settings is gone from Settings.** The original findings, kept because the reasoning matters:

**⚠️ Two findings from the drill, neither of them anticipated:**

1. **🔴 A downloaded Ludwig would tell every user to install AppFlowy over it.** The fresh install
   showed a "New Version Available" toast, and Settings → Account & App read: *"New Version (0.13.0)
   Available! Current version: 0.11.4 (**Official build**) → 0.13.0"* with an **Update** button. The
   updater is checking **AppFlowy's** releases, calling our build an "Official build", and offering
   an upgrade path that replaces Ludwig with AppFlowy. **This is a Phase 3/4 blocker** — shipping
   with it means every downloaded copy invites its own destruction. It also silently contacts
   AppFlowy's servers on launch, which contradicts the local-only promise this very phase
   establishes. Decide: point it at Ludwig's own releases, or remove it for v1 (no updater is
   already the plan — see Phase 4).
2. **The in-app logo is still AppFlowy's.** "Welcome to **Ludwig**" sits under AppFlowy's petal
   mark. Phase 1 changed the *app icon*; this is a separate bundled asset (`FlowyLogoTitle`).
   Cosmetic, but it is the first thing a new user sees.

**Also worth a decision (not a bug):** with the switcher hidden and local mode active, **Settings →
Cloud Settings is a near-empty page** — a "Restart" button and a sentence about changes taking
effect, for changes that can no longer be made. Consider hiding the whole row when the switcher is
off.

**Left behind deliberately:** the drill's throwaway workspace (35 files, 548K) in
`~/Library/Application Support/app.ludwig.desktop/data_dev`. Harmless — nothing reads it while
`kCloudType = 2` — but it means a future local-mode launch would find a stale drill workspace rather
than a clean slate. Safe to delete.

### Phase 3 — The release build
- `flutter build macos --release` as a **genuinely new target** — `STATUS.md` warns it opens a
  different data dir and it has never been validated for this fork.
- Signing decision (D6 comes due here).
- A repeatable build script.
- AGPL: license preserved, release links the exact source commit, AppFlowy attributed.

### Phase 4 — Publish
GitHub Releases on `matanrotman/Ludwig`, release notes, README, the pitch. Manual re-download for
updates — no updater in v1.

**The GitHub page itself is a Phase 4 deliverable** (user, session 18). The repo is *already* named
**Ludwig**, which makes the mismatch worse rather than better — everything around the name still
sells AppFlowy. Surveyed session 18:

- **Repo description** is AppFlowy's marketing copy verbatim ("Bring projects, wikis, and teams
  together with AI… The leading open source Notion alternative").
- **Homepage link** points at `appflowy.com`.
- **`README.md` (157 lines) is AppFlowy's landing page**: the title links to appflowy.com, the
  tagline is "The Open Source Alternative To Notion", and the badge/nav rows push AppFlowy's
  Discord, Forum, Reddit and Twitter.
- **⚠️ The sharpest problem: the README advertises features Ludwig has deliberately removed.** Its
  five hero screenshots are the **Kanban board, Grid databases, Sites, AI and Templates** — and
  Grid, Board, Calendar and AI Chat were retired from the UI on purpose
  (`specs/retire-non-core-surfaces.md`). Someone downloading on the strength of that page would find
  the opposite app. That is a correctness problem, not a branding one.

**What replaces it is the pitch** (open question 5, still unanswered): the reason to download Ludwig
rather than AppFlowy. `specs/product-direction.md` is the source — digital paper, the on-the-go
version of a thing, RTL that actually works, local backup you own. **Not** a feature-comparison
table; the whole point is that Ludwig does less.

**Attribution stays.** Removing AppFlowy's marketing is not the same as hiding the lineage — AGPL
obligations hold, the fork relationship is public, and the release must link the exact source commit
and credit AppFlowy plainly. The goal is an honest Ludwig page, not a scrubbed one.

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
5. **What's the pitch?** Which features are the reason to download Ludwig. Shapes Phase 4 — and now
   blocks the README rewrite, since the pitch is what replaces AppFlowy's marketing copy.

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
- **2026-07-27 (session 18c) — THE FOUR APPFLOWY LEFTOVERS THE DRILL EXPOSED, ALL FIXED.**
  User's instruction: kill the update invite (keeping a placeholder for Ludwig's own), change the
  welcome logo, hide Cloud Settings. A fourth was found while doing it.
  1. **Auto-update off** — `lib/env/ludwig_update_policy.dart`. `AutoUpdateTask` returns early, so
     no network call, no listener, and **no blocking "Update required to continue" dialog** — that
     one could have locked a Ludwig user out of their own writing until they installed AppFlowy.
     Belt-and-braces, the gate also sits on `ApplicationInfo.isUpdateAvailable`, **the single
     property both update surfaces read** (sidebar banner + Settings row), so one edit covers both
     and no future code path can surface a prompt. The placeholder the user asked for is
     `feedUrl`, with a runtime `assert` pairing it to `checkForUpdates`: turning checks on without
     a Ludwig feed would silently fall back to *AppFlowy's* feed, which is the exact bug being
     fixed — so it fails loudly rather than trusting a future reader.
  2. **Welcome logo** — upstream's `AFLogo` drew AppFlowy's petal mark, untouched by Phase 1 (which
     changed the app *icon*). Now the icon's artwork with the white removed. Built three candidates
     and let the user look: the icon tile, a naive background-removal (rejected — the white trapped
     *inside* the loops survived as blobs), and the line-art. **Line-art won because it reads
     identically on light and dark**, and the welcome screen follows the theme.
  3. **Launch splash** — found while chasing the logo, not asked for: upstream's desktop splash is a
     full-screen AppFlowy advert, *"Making it possible for anyone to create apps"*, shown at **every**
     launch rather than just the first. Replaced with Ludwig's mark on the app's dark background.
     The AppFlowy file is left in the repo unused so an upstream merge touching it is a no-op.
  4. **Cloud Settings row removed** + "(Official build)" dropped from the version strings — it meant
     "an official *AppFlowy* release" and read as a claim about Ludwig.
  **8 tests, proven failing-then-passing** (3 fail with the update gate removed). The behavioural
  one sets a real newer version and asserts nothing offers it.
  **⚠️ The method note that nearly cost a wrong conclusion.** First verification showed *both* the
  Cloud row and the update prompt still present, and the obvious reading was "the code does not
  work". It was a **stale app**: the user had reopened Ludwig at 16:28, the build finished at 16:44,
  and `open` merely re-activated the running instance. Caught by comparing the process start time
  with the kernel blob's — after confirming the *bundle* did contain the new symbols. **When a
  change appears not to work, check what is actually running before you touch the code.** This is
  the same trap `STATUS.md`'s verification rules were written for, in a new disguise.
  **Verified live after a real restart:** Cloud Settings absent, "Ludwig is up to date!" with no
  Update button, the welcome screen showing Ludwig's mark. **Not seen by eye: the splash** — the app
  loads in under three seconds, so it is verified by the asset being bundled and the code pointing
  at it, nothing more.
  **Also checked, because a count moved:** the real data folder read 335 files where the drill had
  recorded 356. It is AppFlowy's own `log.sync.*` rotation, not loss — `collab_db` 5.2M plus an
  8.7M history copy, 318 files in the workspace, folder still 18M.
- **2026-07-27 (session 18b) — PHASE 2 BUILT AND DRILLED.** Local-first fresh install, switcher
  hidden everywhere, 5 tests proven failing-then-passing, and a real simulated fresh install on the
  live machine that was fully reverted afterwards (21 preference keys, none missing, none changed).
  Full evidence table under "Phase 2" above.
  **The two things worth carrying forward, neither of them the work that was planned:**
  (1) **The spec knew about one branch; the code had two.** `getAuthenticatorType()` also resolves
  an *unrecognised* stored value to AppFlowy Cloud, so a damaged preferences file could put a
  downloaded build on someone else's server. Found by reading the whole function rather than
  jumping to the line the spec named.
  (2) **🔴 The drill found a shipping blocker the spec never imagined: a fresh Ludwig offers to
  update itself into AppFlowy.** "New Version (0.13.0) Available… Current version: 0.11.4 (Official
  build)", with a working Update button pointed at AppFlowy's releases. **This would never have
  surfaced from tests** — it only appears on a genuinely clean launch, which is exactly what the
  drill was for and exactly what a unit test cannot reach. It is now the top item in the queue.
  **Method note worth keeping:** synthetic typing could not be driven into the editor during the
  drill (a known limitation in this project, recorded in `STATUS.md`). Rather than treat that as a
  finding, persistence was proven a different way — the workspace the app created for itself *is* a
  write, and it survived a quit-and-relaunch with the app going straight in rather than back to the
  Welcome screen. **Prove the claim, not the tooling.**
- **2026-07-27 (session 18) — PHASE 1 CLOSED OUT: the six unrestored preferences, and the docs.**
  No app code. Phase 1 had been built and committed but its last two steps (7 and 9) were never
  finished, and the gap was invisible because the app *looked* right.
  **Step 7 — six of the ten preferences on the recovery checklist above had never been written to
  the new domain.** Found by diffing `defaults export app.ludwig.desktop` against the pre-flight
  dump, not by noticing a symptom. The consequential one is
  **`flutter.featureFlag = {"ribbonMenu":true}` — the entire ribbon was switched off in Ludwig**,
  exactly as the checklist predicted in bold, and it had been that way for the ~1.5 hours the app
  had been in use. Also missing: `kDocumentAppearanceDefaultTextDirection`, `backupSettings`,
  `lastOpenedSpaceId`, `ribbonActiveTab`/`ribbonCollapsed`, `kRecentIcons`. Restored from
  `prefs_ORIGINAL.plist` with the app quit, then verified in the **on-disk plist read directly**,
  bypassing the preferences daemon's cache — a `defaults read` alone would only prove the daemon
  agreed with itself. All ten checklist items now present.
  **`expandedViews` was MERGED, not overwritten** — the new domain had already learned 19 entries
  since the rename and those are newer than the dump; 110 + 19 = 111 (so 18 of the 19 already
  existed). Blind restore would have been a small, silent regression.
  **The lesson worth keeping: a rename's damage is measured against the checklist, not against the
  app's appearance.** Everything user-visible looked correct — pages present, sidebar on the right,
  Hebrew intact, backups running under the new name — because the four *load-bearing* preferences
  had been restored. The six that were missed are all "the app quietly behaves like a fresh
  install," which is indistinguishable from working unless you go looking. This is precisely why
  the checklist was written during the interview; it earned its place.
  **Step 9 — `STATUS.md`'s verification rules were rewritten to the Ludwig identity.** They still
  named `Debug/AppFlowy.app`, the old bundle id and the old data path in five places, including the
  two hazard rules and the `defaults delete` command that undoes integration-test pollution. Also
  corrected there: **the document text-direction default is `auto`, not `rtl`** as several older
  notes claim, and a warning that **three stale copies of the same writing now exist** (the kept
  pre-rename folder, an old release-build cache, and the bare `data_dev` that is Phase 2's landmine)
  so no future session restores from the wrong one. Recorded a detail found while editing: the
  `path_location` pref KEY is still `io.appflowy.appflowy_flutter…` because it is a hardcoded Dart
  constant (`kv_keys.dart:4`), independent of the bundle id — only the domain moved. Renaming it
  would orphan existing values for no gain.
  **✅ VERIFIED LIVE by the user the same session, which closes Phase 1 entirely:** ribbon back,
  sidebar on the right, backup showing all snapshots. That last one is the strongest of the three —
  it means the both-prefixes reader is resolving the 62 pre-rename `AppFlowy-` snapshots against
  real data, not just in its unit test.
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
