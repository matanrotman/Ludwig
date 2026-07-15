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

## Files / interfaces likely involved
- New module for the backup service (new files — fork-maintenance rule: isolate, don't edit core). Likely a startup task registration (one-line touch in `frontend/appflowy_flutter/lib/startup/`) analogous to existing `auto_update_task.dart`.
- New settings page + registration in the settings dialog (`settings_dialog.dart` — one entry; the shortcuts settings page at `settings_shortcuts_view.dart` is the pattern to copy).
- Drive mount detection: `~/Library/CloudStorage/GoogleDrive-*` (macOS), with manual folder picker as override.
- The app's own data-path plumbing (`ApplicationDataStorage.getPath()`) to find the active workspace folder — the debug build's real folder is `data_dev_beta.appflowy.cloud` (see STATUS.md's data-dir map; don't hardcode).
- Possibly `BACKUP_COLLAB_DB` machinery in `flowy_user` (Rust) if we build on the internal snapshot path.

## Open questions — resolved by investigation 2026-07-16
- **`BACKUP_COLLAB_DB` is not Dart-triggerable.** It's the tracing span of `UserManager::prepare_backup` (`flowy-user/src/user_manager/manager.rs:556-566`), fired internally once per sign-in/day. It zips only `collab_db` into `collab_db_history/collab_db_YYYYMMDD.zip` via `CollabDBZipBackup` (`flowy-user/src/services/db.rs:166-209`), validating the DB first. Real zips exist on disk daily since 07-12 (~350KB each) — a useful *extra* safety layer that our snapshots will simply include, but not a mechanism we can invoke on demand without a new Rust event. **Decision: Phase 1 stays Dart-only** — zip the whole live workspace folder (crash-consistent copy: RocksDB and SQLite both keep write-ahead logs and are designed to recover exactly this state), mitigated by (a) retention depth — a bad snapshot never stands alone, (b) the on-quit snapshot being taken at natural quiescence, and (c) restore-time validation. If restore drills ever surface a torn snapshot in practice, escalate to a small Rust "backup now" event that reuses `CollabDBZipBackup` — the seam is already identified.
- **Change detection:** recursive latest-mtime walk of the workspace folder (~6MB, trivially fast), compared to the last snapshot's recorded high-water mark. No app-event hooking needed.
- **Drive mode / local readability & quit-time budget:** verified during Stage 5's end-to-end checks (explicit checklist items below).

## Phase 1 execution plan (agreed 2026-07-16)

**Stage 1 — backup engine (new files only).**
`lib/shared/backup/` : `backup_service.dart` (walk → detect change → zip to temp name → atomic rename into destination), `backup_settings.dart` (KeyValueStorage-backed: enabled, destination, interval, last-run), `drive_mount_detector.dart` (`~/Library/CloudStorage/GoogleDrive-*`, fallback `~/Google Drive`, manual override), retention pruner (last 50 + daily thinning). Unit tests for retention math, change detection, and atomic-write behavior (temp dir fixtures — no real data).

**Stage 2 — scheduling (2 one-line core touches).**
Startup task registered next to `AutoUpdateTask()` (`lib/startup/startup.dart:148` pattern) running the 30-min timer; quit hook investigated at build time (app teardown path) — **fallback if quit hooks prove unreliable: snapshot-on-next-launch covers the previous session's tail, and the 30-min timer bounds the loss either way.** Never runs in integration-test mode (same guard as AutoUpdateTask).

**Stage 3 — Backup settings page.**
New `SettingsPage.backup` enum case + page (pattern: `settings_shortcuts_view.dart`; registration in `settings_dialog.dart` + settings sidebar + `en-US.json` strings — small, flagged core touches). Contents: on/off, destination picker (Drive auto-detected, shown as "Google Drive ✓"), interval, "Last backup: …" status, snapshot list read from the destination folder.

**Stage 4 — restore + docs.**
In-app Restore… flow: pick snapshot → **automatic pre-restore snapshot of current state** → typed confirmation → unzip to a staging folder → sanity-validate (expected structure present, zip integrity) → swap folders → prompt relaunch. Plus `RESTORE.md` (manual path for when the app can't even launch) and a short setup doc for other fork users.

**Stage 5 — verification drills (the spec's "how we'll know it's done", executed).**
Type in a scratch page → snapshot appears AND Drive web UI shows it uploaded (proves it left the machine); kill the app mid-session → next snapshot fine; full restore drill against a scratch data folder (never live data); seed >50 snapshots → pruning correct; both restore safeguards demonstrably fire. Also verified here: written zips stay locally readable under Drive's streaming mode, and the on-quit zip completes within teardown.

**Estimated shape: ~3 sessions** (1: Stages 1–2, 2: Stage 3, 3: Stages 4–5). Core-file touches total: one line in `startup.dart`, the settings enum/dialog/sidebar registrations, and localization strings — everything else is new isolated files, per the fork-maintenance rule.

## How we'll know it's done (verification)
1. Type in a scratch page → within 30 min (or on quit) a new zip appears in the Drive folder **and** shows "uploaded" in Drive's web UI (checked from the browser — proves it left the machine).
2. Kill the app mid-session → relaunch → no corruption, next snapshot fine.
3. Full restore drill on a disposable copy: restore a snapshot into a scratch data folder, launch the app against it, confirm pages open. (Never against the live folder in testing — same incident rule as always.)
4. Retention: seed >50 fake snapshots, confirm pruning keeps 50 + dailies and deletes nothing else.
5. The two restore safeguards demonstrably fire (pre-restore snapshot exists; typed confirmation required).

## Sign-off
**Execution plan presented 2026-07-16 after the user asked to "make a plan to execute" — treating plan approval as the sign-off gate. Code starts only after the user approves the plan above.**

## Session Log
- **2026-07-16 — spec written from scoping interview; no code.** Root-cause investigation that motivated this lives in STATUS.md ("Cloud sync") and the session log there. Interview decisions recorded above.
- **2026-07-16 (later) — open questions resolved by code investigation; Phase 1 execution plan added.** Key finding: the app already makes daily internal `collab_db` zips (`CollabDBZipBackup`, fired at sign-in — real zips on disk since 07-12), but it isn't Dart-triggerable, so Phase 1 zips the whole workspace folder Dart-side with crash-consistent semantics + retention depth + restore validation as the mitigation stack. Escalation path to a Rust "backup now" event identified if drills ever surface a torn snapshot.
