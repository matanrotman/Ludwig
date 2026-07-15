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

## Open questions (to resolve during build, not blockers)
- Does `BACKUP_COLLAB_DB` produce a complete, consistent copy we can zip directly? (Best case: yes, we reuse it wholesale.)
- Change detection: cheapest reliable signal for "something changed since last snapshot" (folder mtime walk vs. hooking the app's own edit events).
- Drive "streaming" vs "mirroring" mode behavior for files we *write* (upload happens either way; verify the written file also remains locally readable for the snapshot list).
- Quit-time snapshot: how late in shutdown can we run and still finish the zip (6MB ≈ fast, but verify).

## How we'll know it's done (verification)
1. Type in a scratch page → within 30 min (or on quit) a new zip appears in the Drive folder **and** shows "uploaded" in Drive's web UI (checked from the browser — proves it left the machine).
2. Kill the app mid-session → relaunch → no corruption, next snapshot fine.
3. Full restore drill on a disposable copy: restore a snapshot into a scratch data folder, launch the app against it, confirm pages open. (Never against the live folder in testing — same incident rule as always.)
4. Retention: seed >50 fake snapshots, confirm pruning keeps 50 + dailies and deletes nothing else.
5. The two restore safeguards demonstrably fire (pre-restore snapshot exists; typed confirmation required).

## Sign-off
**Pending — do not start coding until the user approves this spec.** (CLAUDE.md rule.)

## Session Log
- **2026-07-16 — spec written from scoping interview; no code.** Root-cause investigation that motivated this lives in STATUS.md ("Cloud sync") and the session log there. Interview decisions recorded above. Sign-off not yet given.
