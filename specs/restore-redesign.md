# Restore, redesigned — pick what you lost, keep what you have

*Status: scoped 2026-07-26 (session 13), awaiting sign-off. Replaces the restore half of
`specs/google-drive-backup.md`, which stays the authoritative document for the backup/snapshot
engine itself.*

## Background

The backup side of this fork is finished and proven: snapshots land in Google Drive every 30
minutes when something changed, plus on quit, with a tiered retention ladder. The restore side is
where it stops being good.

**What exists today is a wholesale swap.** `RestoreService` takes a snapshot zip, extracts it to a
staging folder, renames the live data folder away, renames the staged one in, and relaunches. It is
carefully built — nothing is mutated before a pre-restore snapshot succeeds, the swap is two
renames with a single-rename rollback, and drill (f) verified both safeguards on real data. It is
also, as a *product*, the wrong shape for almost every real situation:

- **It is all-or-nothing.** To recover one page deleted this morning, you throw away everything
  written since the snapshot. The most common recovery need is the one it serves worst.
- **It is a one-way door.** The pre-restore snapshot makes it survivable, not painless.
- **It shows you filenames, not your work.** `AppFlowy-backup-v0.11.4-20260726-030817.zip` tells
  you nothing about whether the page you want is inside it.

The user's direction, recorded before this session and confirmed during the interview: a
**read-only tree of spaces → folders → pages with checkboxes**; tick what you want; the app
**merges** it into the existing workspace, recreating containing spaces and folders as needed.
Never a wholesale swap by default. **Never a Markdown round-trip** — that is what lost highlights,
RTL direction and table widths last time it was tried, and it is a hard prohibition, not a
preference.

### What Google Docs gets right, and what doesn't transfer

Docs groups versions under collapsible date headings, chunks nearby edits so the list stays
readable, previews a version read-only before you commit, and files the current state into history
when you restore — so restoring is never destructive.

Two of those are being stolen deliberately: **preview before committing** (D5) and **restore is
never a one-way door** (D1). Snapshot chunking we get free — snapshots are already every 30
minutes when changed.

**What does not transfer, and is worth stating so nobody re-derives it later:** Docs shows the
history of *one document you are already inside*. This shows a *whole workspace at a point in
time*, and you pick pieces out. That makes browse-and-tick right for "what did I lose?", but it
means the common Docs move — "this page was better yesterday" — arrives as a whole-workspace trip.
A per-page version history would be a different feature, and is explicitly not this one.

## Goals

1. **Recovering one page costs you nothing else.** No lost work, no cleanup you didn't choose.
2. **You can tell what you're recovering before you recover it** — by structure, and by reading it.
3. **The thing you most often need — "a page is gone" — is the fastest path through the UI**, not
   the same hunt as everything else.
4. **The dangerous step never runs beside a live editor.**
5. **The existing whole-workspace swap survives** for the disaster case it is genuinely right for.

## Non-goals / out of scope

- **Per-page version history** (the Docs model). Different feature, different data shape.
- **Databases, boards, calendars and their rows.** Visible in the tree, not tickable — see D4 and
  the phased plan. A database view owns a database whose rows and fields live elsewhere in the
  data; copying one correctly is its own problem, and half-right produces a *broken* board rather
  than a missing one.
- **Restoring settings, shortcuts, or workspace configuration.** Those are what the Advanced full
  restore is for.
- **Editing anything in the snapshot browser.** It is read-only, with no admin affordances — no
  rename, no delete, no move. Stated because it is easy to drift into "while we're here…".
- **Changing the backup/snapshot engine.** Unchanged; `specs/google-drive-backup.md` still owns it.
- **The trash screen redesign.** Adjacent and coming, but separate (`specs/delete-and-trash.md`).

## Decisions (user, session 13)

| # | Question | Decision |
|---|---|---|
| D1 | A restored page's live counterpart still exists | **Restore alongside as a dated copy. The live page is never touched.** Nothing you currently have can be lost by a restore — which is the entire point of the feature. |
| D2 | Where does a restored page land? | **Back where it came from**, recreating the containing space/folder only if it is gone. The workspace ends up looking the way it should; the dated name does the work of telling copies apart. |
| D3 | Picking a point in time | **A list of days; a day expands to every time there is a snapshot that day.** "It was fine on Thursday" is how the need actually arrives, with times as the escape hatch for same-day mistakes. |
| D4 | What is tickable | **Documents only.** Other view types render in the tree, greyed, with an honest "not yet" — visible so the structure still makes sense, un-tickable so nothing lands broken. |
| D5 | Preview | **Yes — read-only preview beside the tree.** Click a page, read that snapshot's version of it before deciding. The single most valuable thing Docs does. |
| D6 | Pages missing from the live workspace | **Marked, plus a "only show what's missing" filter.** Turns the primary use case from a whole-workspace hunt into a short list. |
| D7 | Ticking a container | **Cascades to everything inside, with a partial (dash) state** when only some descendants are selected. Standard file-picker behaviour. |
| D8 | Not running against a live app | **Browse and preview in the running app; the merge itself happens on relaunch**, before anything opens. Comfortable browsing, and the write step never races a live editor. |
| D9 | The existing wholesale swap | **Kept, demoted behind "Advanced".** It is proven, and it is the only route that recovers what the tree cannot show. |
| D10 | Naming a restored copy | **`Name (restored 26 Jul)`** — says what it is and where it came from, and stays distinct across two restores from different days. |
| D11 | Where it lives | **Settings → Backup**, where restore already is. Opens into a full-window browser. |

### Standing requirements (not open to re-litigation)

- **Never a Markdown round-trip.** Content moves as encoded collab, or it does not move.
- **The legacy Workspace/Private fallback UI must never render in this fork.** See below.

## ⚠️ The finding that de-risks this: most of the hard part already exists

The obvious fear with a selective restore is the machinery underneath — opening a snapshot's
database without making it live, walking its folder, and copying documents into the running
workspace. **AppFlowy already does exactly this**, for its "import from another AppFlowy data
folder" feature:

`flowy-user/src/services/data_import/appflowy_data_import.rs` opens a *second* `CollabKVDB` from
an arbitrary data folder (`CollabKVDB::open(collab_db_path)`), reads that folder's session and
workspace, walks its views, and writes them into the live workspace — copying each object's
**encoded collab** (not Markdown) and remapping every id through an `OldToNewIdMap`. It is wired
as `ImportedSource::ExternalFolder`, and it is shipped, exercised code.

A snapshot is precisely an AppFlowy data folder in a zip: `data/<uid>/collab_db/…`. So the
primitive this feature needs — *read another workspace, copy real content out of it* — is not new
work. What is missing is:

1. **Selectivity.** Import takes everything; we need only the ticked views.
2. **Placement.** Import drops everything under one container view; we need "back where it came
   from, recreating containers as needed" (D2).
3. **Read-only browsing and preview** before any of it (D5, D6).

That reframes the risk. The scary part is largely solved; the work is mostly *shaping* it. **This
must be verified against the real code before Phase 2 is committed to** — the read above is from
reading, not running.

### The legacy Workspace/Private UI — root cause found

`SpaceBloc.shouldShowUpgradeDialog` (`space_bloc.dart:738`) returns true whenever the folder has
views that sit outside any space — the pre-spaces layout. The sidebar then renders `SpaceMigration`
(`sidebar.dart:501`). During startup and restore there is a transient window where views have
loaded and spaces have not, so the banner flashes up.

**In this fork spaces always exist** — Temporary is guaranteed by `specs/temp-space.md`, and
`capture-and-structure.md` decision 1 makes a space a top-level folder. The pre-spaces layout is
therefore unreachable, and this path is dead weight that only ever fires as a false positive.
**Hard-off it in this fork** rather than suppressing it during restore: a transient-state guard
would still be a guard against a state that cannot legitimately occur.

## Files and interfaces likely involved

**Rust — the read-only snapshot reader (new, but built on existing parts):**
- New module, likely `flowy-folder` or a new `flowy-backup` crate: open a snapshot's extracted
  `collab_db` read-only, return its view tree, and fetch one document's encoded collab.
- Reuse: `CollabKVDB::open`, and the traversal patterns in
  `flowy-user/src/services/data_import/appflowy_data_import.rs`.
- New events: list snapshot views, get one snapshot document, merge a selection.

**Rust — the merge:**
- Modelled on `appflowy_data_import.rs`'s import, narrowed to a supplied id list and given a
  destination resolver implementing D2.
- Must go through the same encoded-collab copy path — never a serialise/parse round-trip.

**Dart:**
- New: a full-window snapshot browser (tree + checkboxes + preview pane + missing filter).
- New: a merge plan written to disk at Restore, executed on next launch (D8).
- Touched: `settings/pages/backup/` — the selective route becomes primary, `restore_flow.dart`
  moves behind "Advanced".
- Touched: `space_bloc.dart` / `sidebar.dart` — hard-off the legacy migration path.
- Unchanged: `restore_service.dart`, `backup_service.dart`, `RESTORE.md`.

## Phased plan

**Phase 0 — prove the primitive. ✅ DONE 2026-07-26, and it holds.** See "Phase 0 result" below.

**Phase 1 — browse, read-only. ✅ DONE 2026-07-26.** Day/time picker (D3), the tree (D4), missing-page
marking and filter (D6). No merging, nothing writable. See the session log.

**Phase 2 — preview (D5). ✅ BUILT 2026-07-26 (session 15), not yet looked at in the app.** A
selected page's snapshot content renders read-only beside the tree, in the real editor. See the
session log for the media-block finding.

**Phase 3 — the merge.** Ticking, the destination resolver (D2), dated-copy naming (D10), the
write-plan-and-relaunch flow (D8). The only phase that writes.

**Phase 4 — the surrounds.** Demote the old restore behind Advanced (D9); hard-off the legacy
Workspace/Private path.

**Phase 5 — live verification with the user**, against real snapshots, restoring into a scratch
space first.

## Phase 0 result — the primitive holds (2026-07-26)

Run against a **copy** of a real snapshot (`AppFlowy-backup-v0.11.4-20260726-030817.zip`) unpacked
into a scratch directory. The live data folder was never opened, resolved or written to.

| Claim | Result |
|---|---|
| A snapshot carries a readable session | ✅ uid + workspace id read from its `cache.db` |
| Its `collab_db` opens read-only, in-process | ✅ opened alongside everything else running |
| The folder loads and the view tree is walkable | ✅ **97 views**, correct hierarchy, Hebrew names intact |
| Documents yield real content | ✅ **82 of 82 documents loaded with content — 0 empty, 0 failures** |
| Content is collab, not Markdown | ✅ deltas with inline attributes (`{"attributes":{"bold":true},"insert":"לשנים"}`) |

The richest page read back was `RECOVERED-מעבר-על-דוח-קלוד` — **the very page lost in the session-12
incident** — at 121KB with its formatting intact. The feature can demonstrably read the thing that
motivated it.

**Per-page settings survive too, and via a different route worth knowing.** Direction, theme,
margins and the fork's own space/folder/temporary flags live in `View.extra` on the *folder* side,
not in the document collab — so they arrive with the tree rather than with the content. Of 97 views,
37 carry extra: `text_direction` on 10, `is_folder` on 10, `is_space` on 8, `theme_mode` on 3,
`margin` on 1, `is_temporary` on 1.

**What Phase 0 did NOT prove, stated plainly.** Highlight (`bg_color`), text colour (`font_color`)
and font size appear in **0** of the 82 pages — they are simply unused in the current content, so
their fidelity is **untested, not disproven**. Table widths *are* present (7 pages) and survive.
Proving the highlight/colour case needs a purpose-built page, which belongs to the Phase 3
acceptance test, not here.

**Consequence for the plan:** the largest unknown is closed. Phases 1–3 are shaping an existing
primitive rather than inventing one, and no phase needs to invent snapshot reading.

## How we'll know it's done

- A page deleted from the live workspace can be found via the missing-only filter, previewed,
  ticked, and restored — and **nothing else in the workspace changed**.
- Restoring a page whose live counterpart still exists leaves the live one **byte-identical**, with
  the restored copy beside it named `… (restored 26 Jul)`.
- A page restored from a space that has since been deleted recreates that space and lands in it.
- Restored content keeps highlights, RTL direction and table widths — the three things the Markdown
  round-trip destroyed. This is the acceptance test that matters most.
- Non-document views appear in the tree and cannot be ticked.
- The merge does not run while the app is live; it runs on relaunch, before anything opens.
- The legacy Workspace/Private UI does not render, at any point, including mid-restore.
- The Advanced full restore still works, and drill (f)'s safeguards still fire.

## Multi-user readiness

Almost entirely general — snapshot reading and merging carry no personal assumptions, and the
backup destination is already user-configurable (`specs/google-drive-backup.md` → "Multi-user
readiness"). Two things to watch:

- **The relaunch step (D8) is platform-shaped.** Quitting and re-executing is macOS-flavoured; the
  *plan file* it depends on is portable. Keep the plan/execute split clean so another platform
  changes only the relaunch mechanism.
- **Hard-offing the legacy migration path is fork-specific and correct only because this fork
  guarantees spaces exist.** Anyone lifting this code without Temporary would be removing a guard
  they still need. Name it in the code comment, not just here.

## Open questions

1. **Does the merge need the pre-restore snapshot?** Phase 3 never deletes, so the case for one is
   weaker than for the swap — but "never deletes" is an argument, not a proof, and this is the
   feature where being wrong is expensive. Lean yes; decide before Phase 3.
2. **How far back does the day list go?** Retention keeps monthly snapshots for a year, so the
   list is long and uneven — dense for recent days, sparse for old months. Needs a design pass.
3. **What does "missing" mean for a page that was moved rather than deleted?** It exists live, at a
   different path. Probably "present", not "missing" — but the tree should likely say where it went.
4. ~~**Preview fidelity.**~~ **ANSWERED (user, session 14): the real editor, read-only.** The
   preview shows the page pixel-for-pixel as it looks live — colours, RTL, tables, callouts — at
   the cost of mounting a second editor instance inside the dialog. Phase 2 starts here rather
   than re-opening the question. Non-negotiable consequence: read-only must be enforced so nothing
   can be typed into a backup.
5. ~~**Does the pre-migration snapshot bug touch this?**~~ **PARTLY ADDRESSED (session 14).** The
   root cause is still unknown, but the reason it was *invisible* is fixed: the migration's
   `takeSnapshot` discarded `backupNow`'s result, and `backupNow` reports refusals by returning
   them rather than throwing — so "snapshot taken" and "snapshot silently skipped" were
   indistinguishable. It now logs the outcome. The next workspace that migrates says why.

## Session Log

### 2026-07-26 (session 13) — scoped

Interviewed and scoped in one pass; eleven decisions taken (table above). Grounded in the existing
code first: confirmed today's restore is a wholesale folder swap, located the legacy
Workspace/Private root cause (`shouldShowUpgradeDialog`), and inspected a real snapshot's contents.

The session's most useful find was `appflowy_data_import.rs` — AppFlowy already opens a second
`CollabKVDB` and copies views and documents (as encoded collab, with id remapping) out of an
arbitrary data folder. That is the primitive this feature needed most, and it removes the largest
unknown. Phase 0 exists specifically to verify that by running it rather than trusting the read.

Not yet built.

### 2026-07-26 (session 13) — Phase 0 run, primitive confirmed

Wrote a scratch probe (`event-integration-test/tests/folder/local_test/zz_phase0_snapshot_reader.rs`,
`#[ignore]`d, pointed at a snapshot via `LUDWIG_SNAPSHOT_ZIP`) and ran it against a copy of a real
snapshot. Results in "Phase 0 result" above. Two things the probe corrected along the way, both
worth keeping:

1. **A space is a Document-layout view with no document collab.** The first version picked
   "Temporary" as its sample page and reported a failure to load — which was correct behaviour
   being read as a bug. Spaces are excluded via `space_info().is_some()`. Any future snapshot
   reader must do the same, or it will report phantom failures on every space.
2. **Testing formatting fidelity on one page under-tests it** — a page may simply not use the
   attribute. The probe now counts, across all 82 documents, how many carry each attribute, which
   is what surfaced that highlights and text colour are unused in the current content and therefore
   untested rather than proven.

The probe is scratch and should be deleted or promoted before this feature ships; its
`collab-integrate` / `collab-plugins` / `flowy-sqlite` dev-dependencies on `event-integration-test`
go with it if deleted.

### 2026-07-26 (session 13) — Phase 1 built

**Rust: a new `flowy-snapshot` crate.** Its own crate rather than code inside `flowy-folder`, so
the feature stays out of upstream's files (CLAUDE.md, "Fork maintenance"). The only shared-core
touch is one line in `flowy-core/src/module.rs`, plus the dependency and the `dart` feature entry.
Modelled on `flowy-date`: a **stateless** plugin, because every call carries the snapshot path it
should read, so there is no manager to own and nothing to keep in sync with the live workspace.

One event, `ReadSnapshotTree`: extract → open `collab_db` read-only → return the view tree.
Extraction is cached per snapshot (expanding a day must not re-unzip) and **skips
`collab_db_history`**, which is the majority of a snapshot's bytes and useless for browsing. Zip
entries go through `enclosed_name`, so a crafted archive cannot write outside the scratch dir.

**Dart.** `snapshot_browse_model.dart` holds the real logic and is deliberately Flutter-free:
grouping by day, building the tree, marking what the live workspace no longer has, and the
missing-only filter — which keeps containers on the path, so a recovered page still appears inside
the space and folder it belongs to instead of floating at the root. The browser puts days on the
left (the two most recent expanded by default, since same-day mistakes are the common case) and
the tree on the right. Settings → Backup gains **"Find something you lost"** *above* the existing
snapshot list: browsing is the everyday route, the whole-workspace swap is the disaster case.

**Two honesty notes, both in the code:**
- `GetAllViews` **excludes trashed views**, so a page sitting in the trash currently reads as
  "missing". It over-reports rather than under-reports, but the shorter route for such a page is
  the trash. Revisit with the trash redesign.
- If the live workspace can't be read, the browser **says so and marks nothing missing**. An empty
  live set would flag the entire snapshot as lost — a far more alarming lie than admitting the
  comparison failed.

**Tests.** 13 Dart model tests (day grouping, tree building, cycle safety, missing detection, the
filter keeping containers, what is tickable). 3 Rust event tests, of which the two always-on ones
assert that a missing path and a non-snapshot file are **clean errors rather than an empty tree** —
an empty tree would read as "your backup contains nothing", the worst lie this feature could tell.
The Phase 0 scratch probe is deleted, replaced by an `#[ignore]`d end-to-end test against a real
snapshot (97 views, 8 spaces, 10 folders).

**Still to verify with the user:** the browser has not been opened in the real app yet — that is
the first item next session.

### 2026-07-26 (session 14) — the browser was opened for the first time; six defects fixed

**It rendered, and the core flow was sound.** Days group as Today/Yesterday/weekday with counts, the
two most recent expand by default, picking a time loads that snapshot's tree, missing pages are
badged, databases read "not yet restorable", and the filter keeps ancestors for context. The tree
genuinely reloads per snapshot — verified by finding a page created overnight present in the 03:08
backup and absent from the previous evening's 22:18.

**Six defects, all fixed and re-verified live:**

1. **Hover painted a solid accent-blue block** over day headers and time rows, swallowing their own
   text. **The reusable finding: AppFlowy's `ThemeData.hoverColor` is `hoverBG2`, which in the dark
   theme is `darkMain1` — the full-strength accent.** Nothing else in the app shows this because the
   app's own rows hover through `FlowyHover` with explicit colours; **any new UI built from stock
   Material widgets inherits it**. Fixed with a scoped `Theme` override at the browser's root
   (`_flatHoverTheme`), documented there as the trap it is.
2. **Selection read quieter than hover** — the open backup had blue text, the hovered row a blue
   fill. Reversed: selection carries `themeSelect`, hover stays quiet.
3. **A raw Material `Switch`** instead of the app's own `Toggle`, so it read grey while the
   identical control three rows above it was blue.
4. **No way out but clicking outside.** Added a close ×.
5. **The tree pane never said which backup it was showing** — collapse its day group and the answer
   was off-screen. Now headed "Backup from Today at 03:08".
6. **No scroll affordance** on either list — 58 backups, and the bottom edge read as "that's all".

**Two honesty notes.**
- **Escape closes no dialog anywhere in this app** — not Settings either, verified separately. So it
  is pre-existing, not something the browser introduced. A `HardwareKeyboard` hook was added for the
  browser (a focus-based `CallbackShortcuts` demonstrably does not fire here), but it is
  **UNVERIFIED**: synthetic keystrokes stopped reaching the window mid-session, the documented
  session-10 tooling wall. **Needs the user's physical keyboard.**
- Of the two new widget tests, **only the close-button one is a proof**. The escape test passes with
  the fix reverted, because the bare test wrapper has none of the global shortcut layer that eats the
  key. It is labelled a guard in the file.

**Open question 4 (preview fidelity) ANSWERED by the user: the real editor, read-only.** Phase 2
starts there. Open question 5 partly addressed — see the pre-migration note in that section.

### 2026-07-26 (session 15) — Phase 2 BUILT: the read-only preview

Click a page in the tree and that backup's version of it opens beside the tree, rendered by the
**real editor**, read-only. Built, analyzer-clean, not yet looked at in the app.

**The Rust side: one new event, `ReadSnapshotDocument`.** It returns `flowy_document`'s own
`DocumentDataPB` — the *same payload a live document open returns* — rather than raw encoded collab.
That is what makes "the real editor" cheap: the preview is handed exactly what the live editor is
built from, so there is no second document model to drift. Cross-crate PB reuse has precedent
(`flowy-search`'s `result.rs` uses `flowy_folder`'s `ViewIconPB`). `read_tree` and the new
`read_document` now share one `open_snapshot` door, so "never touches the live workspace" is stated
once instead of per caller.

**Read-only is enforced three ways, and the third is the one that matters.** `editable: false` on
the editor and the block builders; **no** character or command shortcut events at all, so no
keystroke can mutate the document independently of that flag; and — the real property — **nothing is
wired to write.** There is no `DocumentBloc`, no document service, no save path, and no write
counterpart to the event anywhere in the plugin. A preview cannot be saved because there is nothing
to save it with.

**⚠️ The finding worth keeping: media blocks cannot be previewed, and that is CORRECTNESS, not a
shortcut.** Image, multi-image, file, sub-page and AI-writer components read
`DocumentBloc.state.userProfilePB` or the live document id **at build time**, so a preview containing
an image would simply crash — and providing a `DocumentBloc` would mean opening the live page, which
is the one thing this screen must never do. **But even if they built, they would lie:** a local image
is stored as a path into the *live* data folder, so rendering it would show you **today's picture
inside yesterday's backup** — the most misleading thing this screen could do. They are replaced with
a named placeholder ("An image was here.") that reports the block's presence rather than hiding it,
because a block missing from a preview reads as "this backup doesn't have it".

Also needed: the preview provides its own `SharedEditorContext` (sub-page blocks ask it whether they
are in a database row); the live page creates one per document and the preview must not reach for
the open page's.

**Known edge, deliberately left:** tapping an inline **page mention** inside a preview reads
`DocumentBloc` in its tap handler. It renders fine and the read is on tap, not build, so the failure
is an unhandled async error logged to the console — nothing visible, nothing lost. Worth fixing
alongside Phase 3, where mentions matter for the merge.

**Other decisions taken while building:**
- Per-page **direction travels with the folder entry, not the document**, so the preview parses the
  snapshot row's raw `extra` for `page_text_direction`. Without it every Hebrew page in a backup
  would preview LTR and look corrupted.
- The preview clears when you **switch backups**. Leaving yesterday's page beside today's tree is
  the single confusion this screen exists to prevent.
- A **late result is dropped** if you clicked another page meanwhile — otherwise the slow page's
  content paints under the fast page's name. **Proven failing-then-passing.**
- A page that can't be read fails the **preview only**, never the tree: the rest of the backup is
  still browsable.
- The dialog grew from a fixed 900×620 to `min(1120, 92% of the window) × min(700, 88%)`, because a
  third pane left prose about 360pt wide. The tree keeps the full pane until a preview opens.
- Hover was checked against the standing trap: the new rows use `InkWell` under the browser's
  existing `_flatHoverTheme`, and the close button is `FlowyIconButton` with an explicit hover
  colour — no stock Material widget is left to inherit the full accent.

**Tests: 6 new, in `snapshot_preview_test.dart`,** covering the ways a preview can lie about what
you are looking at. **A render smoke test was attempted and deliberately abandoned** — mounting the
preview headlessly drags in the whole app startup (`AFThemeExtension` → appearance cubits → a
GetIt-registered `KeyValueStorage`), each fix revealing the next. That is the same judgment session 7
recorded about `ViewAddButton`: the test would have proved the fake, not the app. **Do not retry it;
the rendering is a live check**, which is also what CLAUDE.md requires for anything visual.

**Phase 2 is unverified in the app.** What to look at first: an ordinary page, then a Hebrew one
(direction), then one with an image (the placeholder), then click between two pages quickly.

**✅ ESCAPE IS VERIFIED (user, session 15, physical keyboard).** Escape closes the browser. This was
session 14's one unverified item — synthetic keystrokes had stopped reaching the window, so it could
only ever be settled on real hardware. The `HardwareKeyboard` hook in `snapshot_browser_view.dart` is
therefore **proven**, and the honesty note above stands unchanged: its widget test remains a *guard*,
not a proof, because the bare test wrapper has none of the global shortcut layer that eats the key.

Worth carrying forward: **Escape still closes no other dialog in this app** (Settings included). The
browser is the exception, and it is one only because it installs its own hook.

**⏸ PHASE 2 IS BUILT BUT STILL UNSEEN — the user deferred looking at it to the next session.**
Nothing about it has been judged by eye. Two things to drive, in this order:

1. **The preview itself.** An ordinary page first, then a **Hebrew** one (direction is parsed from
   the snapshot row's `extra`, and getting it wrong makes every Hebrew page in a backup look
   corrupted), then one **containing an image** (must read "An image was here.", never a picture —
   a rendered local path would be showing *today's* image inside an old backup), then **click
   quickly between two pages** (the late-result guard).
2. **Hover states**, since the tree rows became clickable this session. The standing trap:
   `ThemeData.hoverColor` is the full accent in dark mode. The rows sit under the browser's
   `_flatHoverTheme` and the close button carries an explicit hover colour, so this is a
   confirmation, not a suspicion — but it has bitten this exact dialog before.
