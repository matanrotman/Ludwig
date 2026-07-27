# Becoming Ludwig — the steps only you can do

Everything in the app itself is already done: it builds as **Ludwig.app**, carries the bundle id
`app.ludwig.desktop`, wears your icon, and calls itself Ludwig everywhere in the interface.

What's left are four things that live outside the codebase. **Do them in order.** Each one has a
backup step before it and a way back afterwards.

> **The rule for this whole document: never `mv` anything you haven't copied first.**
> Every rename below is written as *copy, verify, then remove the original* — slower, and the
> difference between a bad afternoon and a lost project.

---

## Part 0 — Back up first. Do not skip this.

Run these three. They take about a minute and they are what makes everything below reversible.

```bash
mkdir -p ~/Desktop/Ludwig_rename_backup && cd ~/Desktop/Ludwig_rename_backup && ditto ~/Library/Application\ Support/com.appflowy.appflowy.flutter/data_dev_beta.appflowy.cloud ./data_ORIGINAL && du -sh ./data_ORIGINAL
```

```bash
cp ~/Library/Preferences/com.appflowy.appflowy.flutter.plist ~/Desktop/Ludwig_rename_backup/prefs_ORIGINAL.plist && ls -lh ~/Desktop/Ludwig_rename_backup/
```

```bash
ditto ~/.claude/projects/-Users-matanrotman-Projects-AppFlowy ~/Desktop/Ludwig_rename_backup/claude_history_ORIGINAL && du -sh ~/Desktop/Ludwig_rename_backup/claude_history_ORIGINAL
```

**Check before continuing:** the first should print about **17M**, the third about **291M**. If
either is wildly smaller, stop and say so — something didn't copy.

A copy of your writing already exists in Google Drive as well (62 snapshots), so this is your
*second* net, not your only one.

---

## Part 1 — Rename the GitHub repository

This keeps every commit, every issue, the fork link to AppFlowy-IO, and both open pull requests.
GitHub leaves a redirect behind, so nothing breaks the moment you do it.

1. Go to **https://github.com/matanrotman/AppFlowy/settings**
2. The **Repository name** field is at the top, under "General".
3. Change `AppFlowy` to **`Ludwig`** and press **Rename**.

That's the whole thing. **Do not** use "Transfer ownership" or "Delete this repository", which sit
lower on the same page.

Then point your local checkout at the new name — the redirect works, but relying on it is the kind
of quiet dependency that bites later:

```bash
cd ~/Projects/AppFlowy && git remote set-url origin https://github.com/matanrotman/Ludwig.git && git remote -v
```

**Verify:** `git ls-remote origin HEAD` should print a commit hash, not an error.

**If you want to undo it:** rename it back on the same settings page. GitHub redirects both ways.

### What NOT to rename

Leave **`matanrotman/appflowy-editor`** exactly as it is. Your app depends on it by URL in
`pubspec.yaml`, and renaming it would put a build dependency behind a redirect — this project has
already lost time twice to that pin drifting. It also *is* appflowy-editor with your patches, so
the name is honest.

---

## Part 2 — Rename the project folder

**Claude Code must be closed for this.** Renaming the folder underneath a running session
invalidates its working directory.

1. Quit Claude Code entirely.
2. Close any editor or Terminal tab sitting inside `~/Projects/AppFlowy`.
3. Run this — it copies, verifies, and only then removes the original:

```bash
cd ~/Projects && ditto AppFlowy Ludwig && echo "--- file counts (must match) ---" && find AppFlowy -type f | wc -l && find Ludwig -type f | wc -l
```

**Only if those two numbers match**, remove the old one:

```bash
rm -rf ~/Projects/AppFlowy && ls -d ~/Projects/*
```

> The copy takes a while — the Rust build directory is large. That's expected.

**If anything looks wrong before you delete:** `~/Projects/AppFlowy` is still there, untouched.
Just `rm -rf ~/Projects/Ludwig` and you're back where you started.

### Three small things afterwards

**Added 2026-07-27, after this bit us for real.** The Rust build cache also remembers the old path,
and unlike the two below it is *not* harmless — it breaks the release build with a confusing panic
about a file that does not exist. `flowy-codegen` bakes its own location in at compile time
(`env!("CARGO_MANIFEST_DIR")`), and every crate's build script statically links that stale copy.
**Debug builds never notice**, because they only relink a prebuilt library and never re-run code
generation — so the breakage stays hidden until the first release build, possibly weeks later.

```bash
cd ~/Projects/Ludwig/frontend/rust-lib && rm -f target/release/deps/libflowy_codegen-*.rlib target/release/deps/libflowy_codegen-*.rmeta target/release/deps/flowy_codegen-*.d && rm -rf target/release/.fingerprint/flowy-codegen-* target/release/build/flowy-* target/release/build/dart-ffi-* && echo done
```

`frontend/scripts/ludwig/build_release.sh` now detects and clears this automatically, so you only
need the command above if you are building by hand.

Flutter regenerates one file with an absolute path in it; harmless, but this clears it:

```bash
cd ~/Projects/Ludwig/frontend/appflowy_flutter && rm -f ios/Flutter/flutter_export_environment.sh && echo done
```

About six saved permissions in `.claude/settings.local.json` refer to the old path and will simply
stop matching — Claude Code will ask again the first time. To fix them in one go:

```bash
cd ~/Projects/Ludwig && sed -i '' 's|/Users/matanrotman/Projects/AppFlowy|/Users/matanrotman/Projects/Ludwig|g' .claude/settings.local.json && echo done
```

---

## Part 3 — Carry your Claude Code history across

Claude Code names its history folder after the project path, so the rename orphans 17 sessions
(291MB) plus the memory files. This moves them to the new name.

**Still with Claude Code closed:**

```bash
cd ~/.claude/projects && ditto -Users-matanrotman-Projects-AppFlowy -Users-matanrotman-Projects-Ludwig && ls -d -Users-matanrotman-Projects-*
```

**Verify both exist and are the same size:**

```bash
du -sh ~/.claude/projects/-Users-matanrotman-Projects-AppFlowy ~/.claude/projects/-Users-matanrotman-Projects-Ludwig
```

Now open Claude Code in `~/Projects/Ludwig` and check that your past sessions are listed. **Only
once you've seen them** remove the old folder:

```bash
rm -rf ~/.claude/projects/-Users-matanrotman-Projects-AppFlowy && echo removed
```

If the history *doesn't* show up, leave both folders alone and tell me — the copy on your Desktop
from Part 0 is a third copy regardless.

---

## Part 4 — Put Ludwig in your Dock

The old Dock tile pointed at `…/Debug/AppFlowy.app`, which no longer exists — the app builds as
`Ludwig.app` now. The dead icon is expected, not a broken build.

1. Drag the old AppFlowy tile off the Dock (it'll puff away).
2. Open this folder:

```bash
open ~/Projects/Ludwig/frontend/appflowy_flutter/build/macos/Build/Products/Debug/
```

3. Drag **Ludwig.app** onto your Dock.

> Use `~/Projects/AppFlowy/...` instead if you haven't done Part 2 yet.

**This is still the debug build**, deliberately — it's the one that opens your real data folder,
and it's what every verification rule in `STATUS.md` refers to. Don't switch to a release build.

---

## Part 5 — Check it worked

Open Ludwig and confirm:

- [ ] The Dock and menu bar say **Ludwig**, with your icon
- [ ] **All your pages and spaces are there** (this is the one that matters)
- [ ] The sidebar is on the **right**
- [ ] The **ribbon** is present
- [ ] Settings → Backup still lists your existing snapshots — **all ~62 of them**, not just new ones

If pages are missing, **stop and don't type anything**. It almost certainly means the app is
looking at the wrong data folder, which is recoverable in seconds — your writing is in three places
(`~/Desktop/Ludwig_rename_backup/data_ORIGINAL`, the original folder, and Google Drive). Nothing is
lost; it's just pointing at the wrong shelf.

If the snapshot list looks short, that's the backup-prefix compatibility — tell me, it's a one-line
fix and there's a test covering it.

---

## What you can throw away, and when

| Keep | Until |
|---|---|
| `~/Desktop/Ludwig_rename_backup/` | you've used Ludwig happily for a few days |
| `~/Library/Application Support/com.appflowy.appflowy.flutter/` | same — this is the pre-rename data folder |
| `~/Desktop/Ludwig_INVESTIGATION_backup_*` | whenever you like; today's data-loss bug is fixed |
| `~/Desktop/Ludwig_phase1_preflight/` | after Part 5 passes — it holds your original settings and the old app icon |

There is no hurry on any of them.
