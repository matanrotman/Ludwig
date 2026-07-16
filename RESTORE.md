# Restoring AppFlowy from a backup

This fork automatically snapshots the whole AppFlowy workspace into a synced
folder (Google Drive by default) — see `specs/google-drive-backup.md` for how
that works. This file is the **recovery manual**: how to get your data back,
even on a brand-new machine where AppFlowy won't launch or was never
installed.

Each snapshot is a plain `.zip` you can open with any unzip tool. Inside:

```
manifest.json      ← what this snapshot is (see below)
data/…             ← an exact copy of the workspace data folder
```

---

## Route 1 — the app runs: use the built-in Restore

1. Open AppFlowy → **Settings → Backup**.
2. Pick a snapshot in the **Snapshots** list → **Restore…**.
3. Type `restore` when asked (this arms the Restore button), confirm, and
   click **Restart AppFlowy** when it finishes.

Two safety nets fire automatically: a fresh snapshot of your current data is
taken *before* anything changes, and your current data folder is kept on disk
(renamed to `…pre-restore-<timestamp>`, not deleted). If anything fails
mid-way, the restore rolls itself back and tells you so.

## Route 2 — the app won't launch (or a fresh machine): manual restore

You need: the snapshot zip, and about five minutes.

**1. Get the newest snapshot zip.**
   - Mac with Google Drive installed: look in
     `Google Drive → My Drive → AppFlowy Backups → snapshots/`.
   - Any machine: open [drive.google.com](https://drive.google.com) in a
     browser → `My Drive → AppFlowy Backups → snapshots` → download the
     newest file. Names sort by date:
     `AppFlowy-backup-v<version>-<date>-<time>.zip` — the last one in the
     list is the newest. (`AppFlowy-prerestore-…` files are safety snapshots
     taken just before earlier restores; they're equally usable.)

**2. Quit AppFlowy completely** (Cmd+Q — this matters; never replace the
   data folder while the app is running).

**3. Unzip it** (double-click in Finder is fine).

**4. Read `manifest.json`** (open it with any text editor). You care about
   one field: `sourceFolderName` — the exact name of the workspace folder
   this snapshot came from, e.g. `data_dev_beta.appflowy.cloud`.

**5. Put the data where AppFlowy looks for it.** In Terminal:

   ```bash
   # The folder AppFlowy reads on this Mac (adjust <sourceFolderName>):
   TARGET="$HOME/Library/Application Support/com.appflowy.appflowy.flutter/<sourceFolderName>"

   # Park the old folder if it exists (don't delete anything):
   [ -d "$TARGET" ] && mv "$TARGET" "$TARGET.before-manual-restore"

   # Move the snapshot's data/ folder into place (adjust the unzip path):
   mv ~/Downloads/<unzipped-folder>/data "$TARGET"
   ```

   Or in Finder: rename the existing `<sourceFolderName>` folder inside
   `~/Library/Application Support/com.appflowy.appflowy.flutter/` (press
   Cmd+Shift+G in Finder and paste that path), then move the unzipped `data`
   folder there and rename it to `<sourceFolderName>`.

**6. Launch AppFlowy.** Your pages should be back. Once you've confirmed
   everything is there, the parked `…before-manual-restore` folder can be
   deleted — no rush.

## If an in-app restore ever reports "couldn't be undone automatically"

This is the one state that needs a hand. It means your data was renamed to
`<folder>.pre-restore-<timestamp>` but couldn't be renamed back — **nothing
was deleted**. The error message shows both paths. Quit AppFlowy, then in
Finder (or Terminal) rename that `…pre-restore-<timestamp>` folder back to
its original name (shown in the same message), and launch again.

---

## Setting this up on a fresh machine (or another fork)

1. Install [Google Drive for desktop](https://www.google.com/drive/download/)
   and sign in. That's the entire "setup" — no API keys, no configuration:
   AppFlowy just writes zips into the Drive folder and Google's own app
   uploads them.
2. Launch this fork of AppFlowy. It auto-detects the Drive mount and creates
   `My Drive/AppFlowy Backups/snapshots/` on the first backup (every 30
   minutes when something changed, plus on quit).
3. Check **Settings → Backup**: you should see "Google Drive detected ✓" and,
   soon after, the first snapshot in the list.

**Using Dropbox, iCloud Drive, or any other synced folder instead:** open
**Settings → Backup → Choose folder…** and pick any folder inside your synced
area (it must already exist). Everything else works identically.

**Restoring onto the fresh machine:** once snapshots exist in Drive, follow
Route 2 above — or launch the app, let it detect Drive, and use Route 1.
