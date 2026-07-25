# Temporary — the default landing space

**Status:** ALL 5 PHASES BUILT 2026-07-25 (session 12). Phases 1, 2 and 4 live-verified; Phase 3's
migration ran successfully on the user's real data. One open bug: the pre-migration snapshot did not fire.
**Governed by:** `specs/capture-and-structure.md` — read it first; the decisions there are binding here.
**Sibling:** `specs/folder.md`.

## Background

Ludwig's thesis is that starting a page must not require deciding where it belongs. Today it does:
the top-level **New Page** button puts the page in whatever space you are currently in (a deliberate
session-6 decision), so every capture is also a filing decision, however small.

Temporary is the answer: one permanent staging space that everything unallocated falls into, so the
decision can be deferred to a moment when you actually know.

Plain-language version of what a "space" is, since it matters below: in AppFlowy a space is the
top-level grouping in the sidebar — your workspace holds several spaces, each space holds pages. Under
the hood a space is just an ordinary document page carrying a flag (`is_space`) in a free-form
`extra` field, which is why turning one into something special is cheap.

## Goals

1. A space named **Temporary** exists, is always present, and cannot be deleted.
2. It always sorts **first** in the sidebar.
3. **Every page created without a stated destination lands in it** — specifically, the top-level
   New Page button, unconditionally.
4. It carries a **quiet count** of how many pages are sitting in it.
5. It is **flat** — no folders inside it, ever.
6. It uses the user's own icon (asset supplied by the user; they are working on it).
7. The user's existing default space becomes Temporary **in place**, losing nothing.

## Non-goals / out of scope

- **No triage screen.** Processing the pile in one sitting is a good idea and belongs to a later spec.
- **No aging behaviour.** Nothing expires, warns, auto-archives or auto-files based on how long a page
  has sat in Temporary. Not now, and not assumed by anything built here.
- **No change to how any other space behaves.** Temporary is one exception, precisely defined below;
  everything else keeps session 6's behaviour exactly.
- **No new filing gesture** (decision 6 of the model): drag and the existing **Move to** are it.
- **No rethink of the sidebar's other sections** (Favorites, the retired-but-kept upstream widgets).

## What "special" means, precisely

Exceptions to normal space behaviour, exhaustively — anything not on this list is unchanged:

| Behaviour | Temporary | Other spaces |
|---|---|---|
| Can be deleted | **No** (action hidden or disabled with a reason) | Yes |
| Sort position | **Always first**, not reorderable | User order |
| Target of top-level New Page | **Always** | Never |
| Can contain folders | **No** | Yes |
| Shows an unfiled count | **Yes** | No |
| Can be renamed | **No** (user decision, 2026-07-25) | Yes |
| Collapsible, `+`, `…`, drop target, icon | Same as any space | — |

## Identification — do NOT match on the name

The user's space is currently called **General**, but that string appears nowhere in the code: a fresh
install creates a space named `Shared`
([space_bloc.dart:604](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart:604)),
and "General" is simply what this user's own space ended up called.

So:
- Temporary is identified by a **flag in `View.extra`** (e.g. `is_temporary: true`), in the same style as
  `is_space` — never by its display name, which the user may change and which differs per install.
- The **migration** identifies its target by **role** — the workspace's default/first space — never by
  matching "General". Matching the literal string would be exactly the kind of hardcoded personal value
  `CLAUDE.md` forbids: it would silently no-op for every other person.

## Migration — the one part that touches real data

**Decision: rename in place, keeping all contents.** The existing default space becomes Temporary; its
pages do not move; only its name, icon and flag change.

Consequence the user has accepted: whatever is in the space today — including the junk test pages still
awaiting deletion (STATUS "Next step" item 1) — is now sitting in Temporary. Which is arguably accurate.

**Precedent to copy, and a name to avoid colliding with:** upstream already ships a migration from the
pre-spaces sidebar model — `SpaceMigration` widget + `SpaceEvent.migrate()`
([space_migration.dart](frontend/appflowy_flutter/lib/workspace/presentation/home/menu/sidebar/space/space_migration.dart),
[space_bloc.dart:344](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart:344)).
Ours is a different migration and must not reuse that event or read as the same thing.

Safety rules, non-negotiable (this touches the only fully-proven copy of the user's writing):
- Take a Google Drive snapshot immediately before the first run that migrates (the backup feature is
  live and already snapshots on a schedule — force one, don't assume).
  - **⚠️ OPEN BUG, found 2026-07-25 by inspecting the real Drive folder: this did NOT fire.** All 47
    snapshots carry `quit` / `catchUp` / `preRestore` triggers; there is **no `preMigration` snapshot**.
    The migration itself succeeded (the user confirmed the rename), because a failed snapshot is
    deliberately non-blocking — so the guard silently did nothing rather than failing loudly.
    **Ruled out:** the forced-run gate (`isForced` includes `preMigration`) and the change detector
    (also bypassed when forced). **Prime suspect:** timing — the migration runs inside
    `SpaceEvent.initial`, early in startup, likely before `BackupService` can resolve a workspace or
    destination, so `_run` returns `workspaceNotFound` / `noDestination` and logs. **Needs the app log
    to confirm.** Practically moot for this user (the migration is done and idempotent, and snapshots
    from 17:39/17:40/17:44 bracket it), but it must be **fixed or removed** before anyone else migrates —
    a guard that quietly no-ops is worse than no guard, because it reads as protection.
- The migration must be **idempotent** and must run at most once (a marker, not a name check).
- If no default space can be identified, it must **fail soft**: create Temporary fresh, touch nothing.

## Fresh installs (someone else downloads Ludwig)

There is no space to rename, so Temporary must be **created** as part of first-run workspace setup —
the same path that creates `Shared` today. First run should produce Temporary plus whatever starter
space upstream already makes.

## Multi-user readiness

- **The silent rename is a personal-now choice.** Someone installing Ludwig on top of an existing
  AppFlowy data folder would find a space renamed without being asked. The bounded upgrade is the
  variant already considered in the interview: ask once, then rename. **Isolate the rename behind a
  single function so switching to the prompt is a small, known edit** — not archaeology.
- Everything else here is universal: no macOS assumption, no account assumption, no path assumption.
- The **icon is a user-supplied asset**; ship a sensible built-in default so a fresh install isn't
  missing an icon.

## Files and interfaces likely involved

Sidecar-first, per the standing fork-maintenance rule. Realistically this one *must* touch shared core
in a few named places, because it changes existing behaviour rather than adding a surface:

**New (sidecar):**
- a small module owning the Temporary flag, identification, the count, and the migration.

**Core files that must change (each a small, named edit):**
- [view_ext.dart](frontend/appflowy_flutter/lib/workspace/application/view/view_ext.dart) — one new
  `View.extra` key, alongside `isSpaceKey`.
- [space_bloc.dart](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart)
  — sort-first; delete guard; the migration hook; **and the New Page destination change** (currently
  `state.currentSpace`, [line 80](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart:80)).
- [sidebar_new_page_button.dart](frontend/appflowy_flutter/lib/workspace/presentation/home/menu/sidebar/shared/sidebar_new_page_button.dart)
  — the capture path that must now always mean Temporary.
- [sidebar_space_list.dart](frontend/appflowy_flutter/lib/workspace/presentation/home/menu/sidebar/space/sidebar_space_list.dart)
  — ordering.
- `sidebar_space_header.dart` — the count.
- `space_more_popup.dart` / `space_action_type.dart` — suppress Delete.
- First-run space creation (`_createSpace` callers around
  [space_bloc.dart:603](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart:603)).

## Phased plan

**Phase 1 — the space itself. ✅ BUILT + live-verified 2026-07-25.** The flag, identification,
always-first ordering, rename + delete guards. **Writes nothing to the user's data:** the name is
rendered, and identity falls back to "the first space" until Phase 3 writes the flag (the *bridge*,
documented on `TemporarySpace`). Space creation was deliberately *not* included — see Phase 3.

**Phase 2 — capture routing. ✅ BUILT + live-verified 2026-07-25.** New Page always targets Temporary
(the session-6 reversal). The phase that delivers the actual thesis and the one that feels different
day to day.

**Phase 3 — the migration. ✅ BUILT 2026-07-25, awaiting the user's next app launch.** Adopts the
first space: sets its stored name to the canonical `Temporary` and merges the flag into its `extra`,
after a forced `preMigration` backup snapshot. Held to its own phase deliberately: it is the only step
that touches real data. Three properties, each unit-tested — **idempotent** (the flag *is* the marker;
no separate "done" pref that could disagree with the data), **merging** (`extra` also carries
`is_space`, icon, colour, permission, creator — replacing it would strip the space's identity), and
**fail-soft** (no spaces / failed write / malformed `extra` all leave the workspace untouched and stay
retryable). A failed snapshot deliberately does *not* abort, or the feature would never activate for
anyone without a backup destination configured.
  - **Follow-up, deliberately deferred:** on a genuinely fresh install the migration adopts whatever
    starter space upstream creates (`Shared`), so a new user gets Temporary and *nothing to file into*.
    Acceptable for now — they can create spaces — but a first-run that produces Temporary **plus** a
    real space would be better. Needs its own small pass.

**Phase 4 — the unfiled count.** Quiet, on the header. Last because it is pure polish and its design
(what exactly is counted — direct children only? nested? untitled only?) benefits from having lived
with phases 1–3.

**Phase 5 — flatness enforcement. ✅ DONE 2026-07-25, via folder Phase 1.** `canContainFolders` was
written and tested here in Phase 1 but had nothing to enforce against until folders existed;
`PageFolder.canCreateFolderIn` now delegates to it, so "New folder" never appears anywhere inside
Temporary — including on an unmigrated workspace, where the *fallback* Temporary (the first space) is
protected too.

## How we'll know it's done

- Temporary is present, first, undeletable; Delete either absent or disabled with a stated reason.
- The top New Page button lands in Temporary from every starting point tried: with a space open, with
  a page open in another space, with nothing open.
- The `+` on another space still puts the page in **that** space (session 6 behaviour preserved).
- Drag and **Move to** both still move a page out of Temporary into a space or folder.
- The existing space's pages are all still present after migration, count matched before and after.
- Running the app twice does not migrate twice.
- The count matches what is actually in Temporary, and updates on create/move/delete.
- Verified in the **real dock app** (`flutter build macos --debug`, content-verified), not headless —
  and with the user's real settings, per the standing verification rules.

## Open questions

1. ~~Can Temporary be renamed?~~ **RESOLVED 2026-07-25: no.** Neither renamable nor deletable — it is a
   fixed part of the furniture, like Mail's Inbox. (Identification still keys on the flag, not the name;
   the name being fixed is a *rule*, not the mechanism.)
2. **What exactly does the count count?** Direct children only, or everything nested underneath?
   Temporary is flat, so those are the same today — but pages can have child pages regardless of
   folders, so it needs an answer. Leaning: **direct children**.
3. **Where does the count sit visually**, and does it show at all when zero? Leaning: **hidden at zero.**
4. **Does Temporary participate in the ⌘O "switch to next space" cycle?** (Note: that shortcut currently
   makes a macOS beep — upstream, deliberately unfixed.)
5. **Icon asset** — pending from the user.

## Session Log

### 2026-07-25 (session 12) — scoped
Interviewed in three rounds; every question answered with the recommended option. Two findings changed
the shape of the spec: (a) **"General" is not a code-produced name** — a fresh install makes `Shared` —
so identification and migration must key on *role*, not the string, or the feature silently does nothing
for every other user; (b) upstream already has a `SpaceMigration` / `SpaceEvent.migrate()` pair for the
pre-spaces model, which is a good precedent and a naming collision to avoid. The New-Page-always-Temporary
decision knowingly reverses session 6 and is recorded as such in `specs/capture-and-structure.md`
decision 3 so it is not read later as a regression.

## Session Log

### 2026-07-25 (session 12) — all five phases built
Phases 1 and 2 (mechanism, guards, ordering, New Page routing) shipped writing **nothing** to the user's
data: the name is rendered and identity falls back to "first space" until Phase 3 writes the flag. That
bridge is what made the work verifiable in the real app at zero risk, and it is documented on
`TemporarySpace` with instructions to delete it. Live-verified "works well".

Phase 3's migration ran on real data and the rename landed. Phase 4's count needed its own `ViewBloc`,
because the obvious source (`SpaceState.spaces[].childViews`) is a snapshot that goes stale, and the one
the page list uses only exists while a space is expanded — the opposite of when the count matters.
Its first version was 12pt `hintColor` after the name's `Expanded`, which put it at the far edge and read
as too faint; the user asked for `(n)` at the name's own weight, adjacent to it.

Phase 5 arrived free with folder Phase 1: `canContainFolders` had been written and tested here with
nothing to enforce against.

**The finding worth carrying forward:** "General" is not a name the code produces (a fresh install makes
`Shared`), so identification and migration key on *role*. Matching the string would have silently no-oped
for every other user — the exact failure mode `CLAUDE.md` warns about.
