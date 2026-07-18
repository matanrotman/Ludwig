# Workspace Backup to Google Drive

## Background — why this exists
On 2026-07-16 we proved end-to-end that **AppFlowy Cloud sync is silently dead for this app and every source-built AppFlowy**: the official `beta.appflowy.cloud` server blocks the old realtime protocol (`/ws/v1`) at its edge with `426 "Please upgrade to latest client"`, while AppFlowy's official binaries ship a *private* newer client (`client_api::v2::actor` — a module absent from the public source that the release tags build). Verified with a Rust probe using the app's exact websocket stack and a valid token; final proof was fetching a page from the cloud that has **146 blocks locally and 1 empty paragraph in the cloud**. Pages reach the server as empty shells over HTTP; the typed content rides the blocked channel. **Nothing the user has written has ever reached the cloud.** Full evidence trail: STATUS.md → "Cloud sync".

So: the cloud is not a backup, cannot be made one locally, and the user's writing exists only on this Mac. This feature is the replacement safety net.

## Goal
**Phase 1 (this spec): automatic off-site backup.** The app periodically snapshots the workspace and places the snapshot in the user's Google Drive. If the Mac dies, the user restores from Drive.

**Phase 2 (future, separate spec): multi-device sync** using the same Drive folder as a "mailbox" of CRDT update files that a second machine merges. Phase 1 must not preclude this, and its folder layout should leave room for it. Phase 2 only becomes relevant when a second device actually exists.

## Decisions from the scoping interview (2026-07-16)
- **Backup now, sync later** — phase 1 is backup-only, designed not to block phase 2.
- **Own "Backup" settings section** — NOT inside Cloud settings. Cloud settings means "which server does the app talk to" and switching it re-logins/swaps data folders; backup must not touch that machinery.
- **Full data-folder archive** per snapshot (compressed copy of the active workspace, ~6MB today). Perfect restores; not human-readable in Drive.
- **Every 30 min while running (only if something changed) + always on quit.** Retention: last 50 snapshots + daily thinning beyond that. Worst-case loss ≈ 30 minutes.
- **In-app restore button** (user accepted the +1 session of careful work). Safeguards required: automatic pre-restore snapshot of the current state, and a typed confirmation ("restore" or the snapshot date) before anything is replaced.
- **Auth approach: none.** Google Drive for desktop is installed, running, and signed in on this Mac (`~/Library/CloudStorage/GoogleDrive-matan.rotman@gmail.com`). The app writes snapshot zips into a folder inside that mount; Google's own client uploads them. No OAuth code, no Google console setup, no secrets anywhere near the repo. The setting is really "backup destination folder," defaulting to the Drive mount — so Dropbox/iCloud users get the same feature free, and other forkers need only "install Google Drive."

## What's in scope (Phase 1)
1. A background backup service in the app: change detection → zip the active workspace data folder → atomic write into the destination folder (write to temp name, rename when complete — sync clients only see finished files).
2. "Backup" settings page: destination folder picker (default: detected Drive mount), interval, on/off, "last backup" status line, snapshot list, Restore… flow with the two safeguards above.
3. Retention pruning (50 recent + dailies), done client-side on the local mount.
4. Consistency: never zip a live database mid-write. Investigate the app's existing `BACKUP_COLLab_DB` event (`flowy_user::services::db`, seen 30× in logs — the app already has an internal snapshot mechanism) and prefer building on it; otherwise snapshot at quiet points (on quit is naturally safe; the 30-min tick must flush/pause writes or use the internal mechanism).
5. A short RESTORE.md + in-repo setup doc for other fork users.

## Out of scope (Phase 1)
- Any realtime or multi-device sync (Phase 2).
- Talking to any Google API directly. No OAuth, no tokens, no network code.
- Backing up the stale caches (`data_beta*`) — only the active workspace folder.
- Mobile.

## Multi-user readiness (added 2026-07-17; corrected against the code 2026-07-18 — see CLAUDE.md "Designing for other users")
**Headline (verified by reading the code, not assumed): other people can already use this feature.** The initial assumption that "only I can use it" was wrong — the design already generalizes. What's macOS-specific is the *auto-detect convenience*, not the feature.

**Already works for others (don't undo these seams):**
- **Auto-detect isn't pinned to me.** `drive_mount_detector.dart` scans for *any* `GoogleDrive-*` mount under `~/Library/CloudStorage/` (and legacy `~/Google Drive`), so any macOS user with Drive installed gets their own account detected. It even handles localized "My Drive" folder names by falling back to the mount's first writable child.
- **A manual folder picker already exists** — `backup_bloc.dart:80` `pickDestination()` → `getDirectoryPath()`, with `useAutoDetectedDestination()` to revert. This is the universal escape hatch: a user with **no Google Drive at all** points it at Dropbox, iCloud, or a plain folder. The feature is really "back up to a folder," with Drive detection as a convenience layer on top — provider-agnostic by design.
- **It fails soft.** No `HOME` → null; no mount found → `detect()` returns null → the service idles with a "no destination" status. No crash, no guessing. (Checked specifically for a latent force-unwrap; there isn't one.)
- The workspace path is resolved via `WorkspacePathResolver`, not a hardcoded `data_dev_beta.appflowy.cloud` — so it doesn't assume my specific debug/cloud workspace.

**Who can use it today:** macOS + Google Drive → auto-detected. macOS + any other sync service or plain folder → manual picker. Windows/Linux desktop → manual picker works (the service is gated to desktop generally, `backup_task.dart:38`), but auto-detect finds nothing.

**Personal-only-for-now (isolated, named here so a future edit is bounded):**
- **macOS-only path logic.** `drive_mount_detector.dart` knows only macOS's `~/Library/CloudStorage` layout; `backup_service.dart:301` reads `Platform.environment['HOME']` (unset on Windows, which uses `%USERPROFILE%`). A Windows/Linux user gets no auto-detected default (they can still pick a folder manually, but the "Google Drive detected" convenience is macOS-only). A general version needs per-OS mount/home resolution behind the same detector interface.
- **Google-Drive-flavored labels** ("Google Drive detected" badge, "My Drive"). The mechanism is generic; only the wording is Drive-specific. A general version would say "cloud sync folder detected" or lean entirely on the folder picker.
- **`RESTORE.md` is written for my macOS setup** (paths, `unzip`, Finder "Free up space"). Fine as-is for me; a multi-user version needs OS-neutral or per-OS restore instructions.

**Bottom line:** the architecture is already multi-user-friendly (detect-or-pick a folder, provider-agnostic upload, graceful degradation). **For the macOS-first distribution target this feature needs ZERO changes.** The remaining work to serve Windows/Linux fully is polish, not a rewrite: cross-platform mount/home resolution + de-Google-ify the labels + OS-neutral restore docs — and none of it blocks anyone, because the manual picker always works. Not scheduled — flagged only.

## Files / interfaces involved
**Built (Stages 1–2):** `frontend/appflowy_flutter/lib/shared/backup/` (`backup_service.dart`, `snapshot_engine.dart`, `change_detector.dart`, `retention_pruner.dart`, `drive_mount_detector.dart`, `workspace_path_resolver.dart`, `backup_settings.dart`, `snapshot_manifest.dart`, `snapshot_repository.dart`); `frontend/appflowy_flutter/lib/startup/tasks/backup_task.dart`; tests in `frontend/appflowy_flutter/test/unit_test/backup/`. Core touches so far: `lib/startup/startup.dart`, `lib/startup/deps_resolver.dart`, `lib/startup/tasks/prelude.dart`, `lib/core/config/kv_keys.dart` (all marked `// [fork:backup]`).

**Remaining (Stages 3–4):** see the detailed plan above — new settings page under `lib/workspace/presentation/settings/pages/backup/`, `backup_bloc.dart`, `restore_service.dart`, `restore_flow.dart`, `RESTORE.md`; core touches to `settings_dialog_bloc.dart`, `settings_dialog.dart`, `settings_menu.dart`, `frontend/resources/translations/en-US.json`.

Not used: `BACKUP_COLLAB_DB` (Rust) — investigated, not Dart-triggerable, decision was to stay Dart-only for Phase 1 (see "Open questions" above). The active workspace folder is resolved via `WorkspacePathResolver`, already built — no need to hardcode `data_dev_beta.appflowy.cloud` anywhere.

## Open questions — resolved by investigation 2026-07-16
- **`BACKUP_COLLAB_DB` is not Dart-triggerable.** It's the tracing span of `UserManager::prepare_backup` (`flowy-user/src/user_manager/manager.rs:556-566`), fired internally once per sign-in/day. It zips only `collab_db` into `collab_db_history/collab_db_YYYYMMDD.zip` via `CollabDBZipBackup` (`flowy-user/src/services/db.rs:166-209`), validating the DB first. Real zips exist on disk daily since 07-12 (~350KB each) — a useful *extra* safety layer that our snapshots will simply include, but not a mechanism we can invoke on demand without a new Rust event. **Decision: Phase 1 stays Dart-only** — zip the whole live workspace folder (crash-consistent copy: RocksDB and SQLite both keep write-ahead logs and are designed to recover exactly this state), mitigated by (a) retention depth — a bad snapshot never stands alone, (b) the on-quit snapshot being taken at natural quiescence, and (c) restore-time validation. If restore drills ever surface a torn snapshot in practice, escalate to a small Rust "backup now" event that reuses `CollabDBZipBackup` — the seam is already identified.
- **Change detection:** recursive latest-mtime walk of the workspace folder (~6MB, trivially fast), compared to the last snapshot's recorded high-water mark. No app-event hooking needed.
- **Drive mode / local readability & quit-time budget:** verified during Stage 5's end-to-end checks (explicit checklist items below).

## Phase 1 execution plan (agreed 2026-07-16)

**Stage 1 — backup engine.** ✅ **DONE** (Session 1, see Session Log). `lib/shared/backup/`: `backup_service.dart`, `snapshot_engine.dart`, `change_detector.dart`, `retention_pruner.dart`, `drive_mount_detector.dart`, `workspace_path_resolver.dart`, `backup_settings.dart`, `snapshot_manifest.dart`, `snapshot_repository.dart`. 38 unit tests, all green.

**Stage 2 — scheduling.** ✅ **DONE** (Session 1). `lib/startup/tasks/backup_task.dart` — 30-min timer, `AppLifecycleListener(onExitRequested:)` quit hook (5s cap), 60s catch-up. Live-verified against the real Google Drive mount.

**Stage 3 — Backup settings page.** ⬅ **START HERE for Session 2.** Not built. See "Stage 3 — detailed plan" below.

**Stage 4 — restore + docs.** ✅ **DONE** (Session 3, see Session Log). `restore_service.dart`, `restore_flow.dart`, `RESTORE.md`; Restore… buttons live; 16 new tests (14 state-machine + 2 real-FS rehearsal); gate passed.

**Stage 5 — verification drills.** ◐ **PARTIALLY RUN** (Session 3): (b) and (h) pass, manual-restore route proven against a real snapshot; (a-web), (c), (d), (e), (f), (g) need the user at the machine — see Session Log for exact state.

**Session split:** Session 1 = Stages 1–2 (done). Session 2 = Stage 3. Session 3 = Stages 4–5.

---

### Stage 3 — detailed plan (Session 2 starts here)

**New files:**
- `lib/workspace/presentation/settings/pages/backup/settings_backup_view.dart` — page scaffold: `SettingsBody` → `SettingsCategory("Automatic backup")` (toggle; destination row modeled on the `_CurrentPath` clickable/copyable row in `settings_manage_data_view.dart:335-454`, with a "Google Drive detected ✓" badge when auto-detected vs a manual-pick label; interval dropdown {15,30,60}; "Back up now" button; "Last backup: …" status line reading `BackupService.status` `ValueNotifier`) + `SettingsCategory("Snapshots")` (list from `SnapshotRepository.list()`, size + date per row, a "Restore…" button per row — wire that button in Stage 4, disabled/TODO for now). `BlocProvider` created in `build()` (pattern: `settings_shortcuts_view.dart:44-46`).
- `lib/shared/backup/backup_bloc.dart` — plain bloc (no freezed, mirror `ShortcutsCubit`'s style): load settings + status + snapshot list on open; events for toggle enabled, pick destination (`getIt<FilePickerService>().getDirectoryPath()`, pattern `settings_manage_data_view.dart:312`), change interval, "back up now" (`BackupService.backupNow(trigger: BackupTrigger.manual)`), refresh. On any settings change, call `BackupService.settingsChanged()` (already implemented) so the running timer re-arms.

**Core touches (each ≤ a few lines, mark `// [fork:backup]` like Stage 1–2's):**
1. `lib/workspace/application/settings/settings_dialog_bloc.dart:14-29` — add `backup,` to the `SettingsPage` enum.
2. `lib/workspace/presentation/settings/settings_dialog.dart:127-187` — add `case SettingsPage.backup: return const SettingsBackupView();` (exhaustive switch, compiler forces this).
3. `lib/workspace/presentation/settings/widgets/settings_menu.dart:50-149` — one `SettingsMenuElement(page: SettingsPage.backup, label: LocaleKeys.settings_backupPage_menuLabel.tr(), icon: ...)` after the Manage Data entry; reuse an existing `FlowySvgs` glyph, don't add a new asset.
4. `frontend/resources/translations/en-US.json` (NOT `assets/translations/` — codegen wipes and re-copies that) — new `settings.backupPage.*` block (menuLabel, title, description, toggle label, destination row labels incl. "Google Drive detected", interval label + 3 option strings, "Back up now", last-backup variants incl. never-run/running/succeeded/failed, snapshots section header, empty-state text). Then run `cargo make code_generation` (wraps `dart run easy_localization:generate` twice — text + `LocaleKeys`) to regenerate `lib/generated/locale_keys.g.dart`.

**Gate before moving to Stage 4:** toggle/destination/interval persist across an app restart; "Back up now" produces a snapshot and the list updates; Drive auto-detect badge shows correctly; `flutter analyze` clean; `flutter build macos --debug` + the standard dock-app content check (`kernel_blob.bin` strings for `IntegrationTestWidgetsFlutterBinding`=0, `runAppFlowy`>0).

### Stage 4 — detailed plan

**New files:**
- `lib/shared/backup/restore_service.dart` — the state machine below.
- `lib/workspace/presentation/settings/pages/backup/restore_flow.dart` — typed-confirmation dialog via `showCustomConfirmDialog` (`lib/workspace/presentation/widgets/dialogs.dart:586`) whose `builder` hosts a `TextField` gate (confirm button disabled until the input exactly matches the keyword `restore` — this exact "type to confirm" pattern does not exist anywhere else in the codebase, base ideas from `NavigatorTextFieldDialog` `dialogs.dart:75`); a progress dialog reflecting `RestoreService`'s phase; a completion dialog ("Restore complete — Restart AppFlowy") whose button pops the settings dialog and calls `runAppFlowy()`.
- `RESTORE.md` (repo root) — manual restore when the app won't even launch: find the newest zip in `My Drive/AppFlowy Backups/snapshots/` (or the web UI if the mount is gone), unzip, read `manifest.json` for `sourceFolderName`, copy `data/**` over `~/Library/Application Support/com.appflowy.appflowy.flutter/<sourceFolderName>` (app must be quit first). Plus a short "setting this up on a fresh machine / other forks" section: install Google Drive for desktop → the app auto-detects `My Drive/AppFlowy Backups` → done; anyone using Dropbox/iCloud instead can point the destination picker at their own synced folder.

**Restore state machine** (the only code in this feature that can destroy data — the most care goes here):

`idle → confirmed → preRestoreSnapshot → extracting → validating → swapping → awaitingRelaunch | failed(phase, error)`

1. User picks a snapshot from the Stage-3 list → typed-confirmation dialog (keyword `restore`, shows the snapshot's date) → no mutation happens before step 6.
2. `BackupService.pause()` (already implemented — cancels the timer, awaits any in-flight run, sets `isPaused`).
3. Trim `.pre-restore-*` dirs beyond the newest 2 (housekeeping done at the START of a restore, never at the end — so a failure never destroys the fallback).
4. Pre-restore snapshot: `BackupService.backupNow(trigger: BackupTrigger.preRestore)` — must succeed or abort the whole restore.
5. Extract the picked zip via `extractSnapshot()` (already implemented in `snapshot_engine.dart`) into `<parent-of-workspace>/<workspaceFolderName>.restore-staging-<ts>`. A corrupt zip throws HERE (ZipDecoder's `verify: true`) — live data untouched.
6. Validate the staging folder: `manifest.formatVersion` is `SnapshotManifest.currentFormatVersion` or known-supported; at least one `*/collab_db` directory exists; nonzero files extracted. If the manifest's `appVersion` is newer than `ApplicationInfo.applicationVersion`, show an extra confirmation (older app opening a newer snapshot's format is the risky direction).
7. Swap: rename the live workspace dir → `<name>.pre-restore-<ts>`; rename the staging dir → the live name (this is why staging must be created with the exact final name it needs — see `WorkspacePathResolver`, which already excludes `.pre-restore-`/`.restore-staging-` names from candidacy). If the second rename fails, rename the first one back (single-rename rollback) — the pre-restore dir is **never deleted by the same run**, so at every failure point the live folder is either untouched or already restored.
8. Show the "Restart AppFlowy" dialog → `runAppFlowy()` (precedent: `settings_manage_data_view.dart:55` after a data-location change; `lib/startup/startup.dart:92-97` disposes the SDK + `getIt` and re-resolves everything, including a fresh `WorkspacePathResolver.resolve()` call that will find the just-restored folder). Any writes the Rust backend makes into the renamed-away pre-restore folder between swap and restart are harmless — it's abandoned, not deleted.
9. `BackupService.resume()` (already implemented); the high-water mark is naturally stale after a restore, so the next scheduled tick snapshots the restored state correctly.

**Tests:** `test/unit_test/backup/restore_service_test.dart` — happy path (MemoryFileSystem, engine calls faked/injected); rename-#2-fails → rollback leaves live folder byte-identical to before; corrupt zip → validation never reached, live untouched; manifest from a future format version → refused with a clear error.

**Gate before moving to Stage 5:** all restore-service unit tests green; a restore rehearsed against a **scratch** data folder (never the live one — 2026-07-13 incident rule) round-trips correctly end to end including the relaunch.

### Stage 5 — drill checklist (what unit tests can't cover)

Run these against the real app and record results in this file's Session Log:
- (a) edit a scratch page → a snapshot appears in the Drive folder **and** shows as uploaded in Google Drive's **web** UI (proves it left the machine, not just the local mount).
- (b) `.tmp` dot-file behavior on the Drive mount is sane (no stuck partial uploads).
- (c) unzip a snapshot that Drive's streaming mode had evicted locally (forces a re-download) — confirms restore still works when Drive hasn't cached the file.
- (d) Cmd+Q with pending changes → snapshot completes, quit stays fast (already measured at 0.3s in Session 1 for the no-change case — re-measure for the changed case).
- (e) `kill -9` mid-session → relaunch → app comes up clean → the 60s catch-up snapshot fires.
- (f) **full restore drill on a scratch data folder only** — both safeguards demonstrably fire (pre-restore snapshot exists afterward; the typed-confirmation gate actually blocks a wrong keyword).
- (g) seed >50 snapshots in the real destination → pruning matches the Stage-1 unit-tested policy against real files, not just `MemoryFileSystem`.
- (h) confirm `My Drive` (not a differently-named localized folder) is what this Mac's mount actually uses — already true here, but `DriveMountDetector`'s fallback path has no live test yet.

### Locked engineering decisions (context for whoever resumes — don't re-derive these)
| Decision | Choice | Why |
|---|---|---|
| Quit hook | `AppLifecycleListener(onExitRequested:)`, zero core-file changes | `macos/Runner/AppDelegate.swift` returns `false` from `applicationShouldTerminateAfterLastWindowClosed` (window-close hides, doesn't quit); Cmd+Q is the only real quit and flows through Flutter's cancellable-exit protocol. `setPreventClose` was rejected — it changes the global close path and doesn't even fire on Cmd+Q. |
| Zip off-thread | `Isolate.run` over plain path strings — first isolate use in `lib/` | Existing zips (`share_log_files.dart:15`) run on the UI thread and jank; ours runs mid-session and on quit. |
| Atomic write | `.{finalName}.tmp` inside `snapshots/`, `flush: true`, then same-dir rename | Same-directory rename is atomic on APFS and the Drive mount. |
| Zip contents | File entries only, **no explicit directory entries** | Found live in Session 1: the `archive` package's directory entries make Info-ZIP's `unzip -t` report "invalid compressed data to inflate" — would have broken the manual-restore path in RESTORE.md. Regression-tested (`snapshot_engine_test.dart`: runs the real system `unzip -t`). |
| Destination layout | `<Drive mount>/My Drive/AppFlowy Backups/snapshots/*.zip`, auto-created on first use | Found live in Session 1: auto-detect originally wrote an unbranded `snapshots/` folder at the Drive root; moved under a named `AppFlowy Backups/` folder. Manual destinations still must pre-exist (typo protection). |
| Naming | `AppFlowy-backup-v<appVersion>-<yyyyMMdd-HHmmss>.zip` (+ `AppFlowy-prerestore-…`) | Sortable, greppable, version-stamped. |
| Change signal | Max mtime over files+dirs, plus count; excludes `log.*` and `LOG`/`LOG.old.*` basenames only (never `*.log` suffix — RocksDB WALs like `000004.log` carry typed content and must count) | App/RocksDB info logs churn even while idle and would defeat change detection otherwise; verified both directions in `change_detector_test.dart`. |
| Live-folder resolution | Mirrors Rust's `make_user_data_folder` preference order (`flowy-core/src/config.rs:109-165`) with existence checks, not blind re-derivation; glob fallback; restore-artifact names excluded from candidacy | Dart doesn't own this logic natively — see `workspace_path_resolver.dart`. |

### Useful seams already located (don't re-explore)
- Settings page scaffold: `SettingsBody` → `SettingsCategory` → `SingleSettingAction` (`lib/workspace/presentation/settings/shared/`). `BlocProvider` created inside the page's `build()`.
- Folder picker: `getIt<FilePickerService>().getDirectoryPath()` — interface in `packages/flowy_infra/lib/file_picker/file_picker_service.dart`, registered in `deps_resolver.dart`.
- Confirm dialogs: `lib/workspace/presentation/widgets/dialogs.dart` — `showConfirmDialog` (:515), `showCustomConfirmDialog` (:586, the one with a `builder` — use this for typed confirmation), `NavigatorTextFieldDialog` (:75, a text-input dialog base).
- `KVKeys.backupSettings` / `KVKeys.backupState` already exist (`lib/core/config/kv_keys.dart`); `BackupSettingsStore` in `backup_settings.dart` already reads/writes them.
- `BackupService` (`lib/shared/backup/backup_service.dart`) already exposes everything Stage 3/4 need: `status` (`ValueNotifier<BackupStatus>`), `backupNow(trigger:)`, `pause()`/`resume()`, `settingsChanged()`, `isPaused`. No changes needed to this file for Stage 3; Stage 4's `RestoreService` calls into it but doesn't modify it.

## How we'll know it's done (verification)
1. Type in a scratch page → within 30 min (or on quit) a new zip appears in the Drive folder **and** shows "uploaded" in Drive's web UI (checked from the browser — proves it left the machine).
2. Kill the app mid-session → relaunch → no corruption, next snapshot fine.
3. Full restore drill on a disposable copy: restore a snapshot into a scratch data folder, launch the app against it, confirm pages open. (Never against the live folder in testing — same incident rule as always.)
4. Retention: seed >50 fake snapshots, confirm pruning keeps 50 + dailies and deletes nothing else.
5. The two restore safeguards demonstrably fire (pre-restore snapshot exists; typed confirmation required).

## Sign-off
**Execution plan presented 2026-07-16 after the user asked to "make a plan to execute" — treating plan approval as the sign-off gate. Code starts only after the user approves the plan above.**

## Session Log
- **2026-07-18 — multi-user readiness review, no code.** Part of the "position this fork for other users" session. User's assumption going in was "no one but me can use the backup feature"; **reading the code disproved it.** Verified: `drive_mount_detector.dart` scans for any `GoogleDrive-*` mount (not the user's account) and handles localized "My Drive" names; a manual folder picker already exists (`backup_bloc.dart:80` `pickDestination()` + `useAutoDetectedDestination()`), making the feature work for non-Drive and non-macOS users; the resolve path fails soft (`backup_service.dart:301` null-`HOME` guard → `detect()` → null → "no destination" idle, no crash — checked specifically for a latent force-unwrap, none found). Conclusion: **zero changes needed for the macOS-first distribution target**; Windows/Linux auto-detect + de-Google-ified labels + OS-neutral `RESTORE.md` are polish, flagged not scheduled. Added the "Multi-user readiness" section above and corrected STATUS.md, which had understated the feature. No behavior changed.
- **2026-07-16 — spec written from scoping interview; no code.** Root-cause investigation that motivated this lives in STATUS.md ("Cloud sync") and the session log there. Interview decisions recorded above.
- **2026-07-16 (later) — open questions resolved by code investigation; Phase 1 execution plan added.** Key finding: the app already makes daily internal `collab_db` zips (`CollabDBZipBackup`, fired at sign-in — real zips on disk since 07-12), but it isn't Dart-triggerable, so Phase 1 zips the whole workspace folder Dart-side with crash-consistent semantics + retention depth + restore validation as the mitigation stack. Escalation path to a Rust "backup now" event identified if drills ever surface a torn snapshot.
- **2026-07-16 (Session 1 of the build) — Stages 1+2 BUILT and live-verified.** Engine (`lib/shared/backup/`: service, isolate zip engine, change detector, retention pruner, Drive-mount detector, workspace resolver, settings store, snapshot repository) + scheduling (`lib/startup/tasks/backup_task.dart`: 30-min timer, `AppLifecycleListener(onExitRequested)` quit hook w/ 5s cap, 60s catch-up). 38 unit tests green, analyzer clean. Core touches: `startup.dart`, `deps_resolver.dart`, `kv_keys.dart`, `tasks/prelude.dart` (~8 lines total, marked `[fork:backup]`).
  **Live gates passed in the real dock app:** catch-up snapshot of the real workspace (109 files) landed in a scratch destination ~60s after launch; graceful quit ran the change check and exited in **0.3s** (state record proved the run: `noChanges` 24s after catch-up); positive quit path also proven (change marker reset → quit produced a full snapshot); no `.tmp` orphans.
  **Two real bugs found by the live run, both fixed + regression-tested:** (1) the archive package's explicit directory entries make Info-ZIP's `unzip -t` report corruption — snapshots now contain file entries only, and a unit test runs the system `unzip -t` against every engine build; (2) auto-detected destination initially pointed at `My Drive/snapshots` (unbranded, at Drive root) — now `My Drive/AppFlowy Backups/`, auto-created on first use (manual picks still must-exist).
  **Backups are LIVE against the user's real Google Drive as of this session** (default-on, auto-detect). Session-2 work: settings page (Stage 3). Session-3: restore + drills (Stages 4–5).
  Known gap, non-blocking: Dart-side `Log.info` lines don't reach the workspace log files (observability only — verification used the persisted state record instead; worth a look during Stage 3).
- **2026-07-16 (Session 2 of the build) — Stage 3 (Backup settings page) BUILT.** New: `lib/shared/backup/backup_bloc.dart` (plain `Cubit`, no freezed — mirrors `ShortcutsCubit`'s hand-rolled style; forwards `BackupService.status`'s `ValueNotifier` into bloc state, persists settings edits via `BackupSettingsStore`, calls `BackupService.settingsChanged()` so a running timer re-arms without a restart) and `lib/workspace/presentation/settings/pages/backup/settings_backup_view.dart` (toggle, destination row with a "Google Drive detected ✓" badge + folder picker, interval dropdown {15,30,60}, "Back up now" button, last-backup status line, snapshot list with size+date). Four core touches, all marked `[fork:backup]`: `SettingsPage.backup` enum case, the settings dialog's switch, a new `SettingsMenu` entry (reused the existing unused `cloud_mode_m` icon rather than adding an asset), and a new `settings.backupPage.*` block in `en-US.json` + regenerated `locale_keys.g.dart`.
  **Restore is intentionally not wired up yet** — each snapshot row's "Restore…" button is a disabled placeholder; Stage 4 replaces it with the real flow.
  **Verified:** `flutter analyze` clean on every touched/new file (7 pre-existing analyzer infos elsewhere belong to the unrelated parallel floating-toolbar session); all 38 pre-existing backup unit tests still pass unmodified; `flutter build macos --debug` succeeded and was confirmed a real (non-test) app build containing the new code by checking `kernel_blob.bin` contents (`IntegrationTestWidgetsFlutterBinding` refs = 0, `runAppFlowy` refs > 0, `settings.backupPage` string present).
  **Not yet done this session:** no widget test written for the new page; not manually clicked through in the running app (analyzer + unit tests + content-verified build only — the user should open Settings → Backup and try it). Not committed as of session end — see STATUS.md.
- **2026-07-16 (Session 3 of the build) — Stage 4 (guarded restore + RESTORE.md) BUILT, gate PASSED; Stage 5 drills partially run.**
  New: `lib/shared/backup/restore_service.dart` (the state machine: idle → confirmed → preRestoreSnapshot → extracting → validating → swapping → awaitingRelaunch | failed; every effect injected so the machine unit-tests on a MemoryFileSystem; `RestoreService.production()` wires the real engine/BackupService/resolver), `lib/workspace/presentation/settings/pages/backup/restore_flow.dart` (typed-confirmation dialog — keyword `restore`, destructive confirm button stays disabled until it matches, ConfirmPopup's Enter-listener disabled so Enter can't bypass the gate; progress dialog mirroring the service's phases; success state → "Restart AppFlowy" → `runAppFlowy()`; failure states in plain language with the raw detail underneath), `RESTORE.md` (repo root: in-app route, fully manual route for a dead app / fresh machine, rollback-failed recovery, fresh-machine setup incl. non-Drive folders), `test/unit_test/backup/restore_service_test.dart` (14 tests) and `test/unit_test/backup/restore_rehearsal_test.dart` (2 real-filesystem end-to-end rehearsals). Stage-3's disabled Restore… buttons now start the real flow. Zero core-file touches this stage (translations block + regenerated `locale_keys.g.dart` only).
  **One deliberate deviation from this spec's step order, tested and documented in the code:** the pre-restore snapshot is taken BEFORE `BackupService.pause()`, not after — a paused service refuses every run *including forced ones* (`_run`'s first check), and this spec forbids modifying `backup_service.dart`. Safety is unchanged (pause() still awaits in-flight runs and completes before any mutation). Also handled: if the pre-restore `backupNow` coalesces with an in-flight periodic run it can return `noChanges` without writing a prerestore zip — the service retries once (the retry is guaranteed to be our own forced run).
  **Gate evidence:** analyzer clean on all new/touched files; 54/54 backup tests green; scratch-folder rehearsal round-trips end-to-end on a real filesystem (real zips via the isolate engine, real APFS renames, both safety nets verified byte-for-byte, `WorkspacePathResolver` post-restore resolves the restored folder — the relaunch's resolution step); `flutter build macos --debug` shipped to the dock app and verified by CONTENTS (test-binding refs 0, `runAppFlowy` 31, restore strings 55, `RestoreService` 12). NOTE: the shipped build also carries the parallel floating-toolbar session's uncommitted round-3 changes that were in the tree.
  **Stage 5 drills run from the shell (all against the REAL Drive mount, read-only or scratch-only):**
  - (b) ✅ PASS — 0 `.tmp` orphans in the real snapshots folder after a full day of live operation.
  - (h) ✅ PASS — the mount really is English `My Drive` (`~/Library/CloudStorage/GoogleDrive-matan.rotman@gmail.com/My Drive`); the localized-name fallback stays unit-test-only by nature on this Mac.
  - (a) ◐ local half PASS — snapshots appear on the ~30-min change-gated cadence (9 today, incl. one that landed mid-session at 15:25); the **web-UI "uploaded" check still needs the user's browser**.
  - BONUS ✅ — RESTORE.md's manual route rehearsed against the newest REAL snapshot into scratch: system `unzip -t` clean, manifest correct (`sourceFolderName` = `data_dev_beta.appflowy.cloud`, formatVersion 1, 0 skipped), 120 files extracted = exactly the live folder's 120, `collab_db` present. Extracted copy scrubbed from scratch afterwards.
  - (c) not runnable yet — no snapshot has been evicted to cloud-only (all 9 fully materialized; feature is a day old). Needs Drive's "Free up space" (GUI) on one snapshot, or natural aging.
  - (d), (e), (f) need the user at the machine (live app quit/kill/GUI-restore). (f) is the big one: full in-app restore drill against a scratch data folder, both safeguards witnessed.
  - (g) automatable but touches the user's real Drive (seeding ~50 tiny grammar-valid zips that later prune) — left for the user's explicit go-ahead.
  **Committed at session end: `08066e099`.**
