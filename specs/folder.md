# Folders — containers below spaces

**Status:** Phase 1 BUILT + live-verified 2026-07-25 (session 12). Phases 2-4 not started.
**Governed by:** `specs/capture-and-structure.md` — read it first; the decisions there are binding here.
**Sibling:** `specs/temp-space.md`.

## Background

Ludwig's model is capture first, structure later. Today the only structure available is *space → page*:
one level of grouping, then a flat list. Giving a captured thought its context means putting it somewhere
meaningful, and with one level there often isn't a somewhere meaningful to put it.

A folder is the missing middle: a container that lives inside a space, holds pages and other folders,
**and can itself hold writing** — so the context you are giving those pages has a place to be written down
rather than being compressed into a name.

Per decision 1 of the model, a folder is not a new kind of object. **A space is a top-level folder.**
Both are ordinary document views flagged in `View.extra`; both nest; both render as a collapsible sidebar
row. This feature mostly *finishes* a capability the codebase already half-has.

## Goals

1. **An explicit folder type** you create on purpose — never one a page becomes by accident.
2. **Behaves like a space in the sidebar**: own icon, collapse arrow, `+`, `…`, and a drop target —
   distinguished from a space by **indentation plus a lighter, smaller treatment**, not by new iconography.
3. **Nests freely** inside spaces and inside other folders, to any depth. Not inside Temporary.
4. **Opens as a real page, visually divided in two:**
   - **Top: the contents.** An auto-generated list of what is inside — first thing on the page, above
     everything. Clearly set apart so it reads as *about the contents*.
   - **Bottom: free writing.** An ordinary document body, about the container itself.
5. **Each contents row shows name, icon, and a preview of the page's first lines** — because pages dumped
   in a hurry are often untitled, and a name alone won't tell you which half-formed thought it was.
6. **The contents list is navigation only.** Click to open. Nothing else.
7. Folders are valid destinations in the existing **Move to** picker and valid **drag** targets.

## Non-goals / out of scope

- **No properties, description fields, tags or dates** in the top section. The contents list is all it
  holds (model: "what this is NOT").
- **No management from the contents list** — no reorder, rename, delete or create there. That is model
  decision 7, and it exists so there is only one place this behaviour can be wrong.
- **No converting** an existing page into a folder or back (`Turn into folder`). Deliberately deferred;
  it fits "structure later" and is strictly additive, so it can come later without rework.
- **No new filing gesture.** Drag and **Move to** already exist.
- **No change to databases, boards, grids or calendars.**
- **Not a replacement for the existing outline block** (`outline_block_component.dart`), which is a
  table of contents of *headings within one page*. Different thing; useful precedent for rendering.

## The folder page, in detail

Reading order top to bottom, because the user was specific that contents come **first**, not below:

1. **Title and icon** — as any page.
2. **Contents section.** The generated list. Visually divided from what follows — the division is what
   communicates "above this line is what's inside; below it is my writing about it." Exact treatment
   (rule, background shade, card, spacing) is a design decision, see open question 3.
3. **Free document body.** A completely normal editor: any block type, the ribbon, per-page direction
   and theme, page colour and margins — everything the user has already built applies unchanged.

An **empty folder** still shows the contents section, with a short placeholder rather than a blank gap
(see open question 4).

## ⚠️ The main technical risk: where do the previews come from?

**There is no existing snippet/preview mechanism in this codebase.** I checked: nothing in `flowy-search`,
nothing on the Flutter side. Each child page's content lives in its own collab document, so "the first
lines of each child" means reading N separate documents to draw one folder page.

Three ways to solve it, in the order I'd investigate them:

- **(a) Lazy, per visible row.** Load a snippet only for rows actually on screen, in a virtualised list,
  and cache in memory for the session. Nothing stored, nothing to keep fresh. Risk: a visible per-row
  pop-in, and it needs a cheap "read just the first block" path rather than loading whole documents.
- **(b) Store the snippet on the view.** Keep a short snippet in the child's `View.extra`, refreshed when
  the page is saved. Reads become free and instant. Costs a write path, and snippets can go stale for
  pages edited by something that doesn't run our update (or edited before the feature existed).
- **(c) Ask the Rust core.** `flowy-search` has search/embeddings machinery; there may be a cheap way to
  get a leading fragment without loading the document through the Flutter layer. **Investigate before
  choosing (a) or (b)** — if it exists, it is better than both.

**Sequencing consequence:** the contents list ships *without* previews first (Phase 2), and previews are
their own phase (Phase 3). If previews turn out to be expensive, we still have a working folder — instead
of a folder feature blocked on a performance problem.

## Naming collision to avoid in code

`lib/workspace/presentation/home/menu/sidebar/folder/` **already exists** — it holds `_section_folder.dart`
and `_folder_header.dart`, upstream's pre-spaces name for sidebar *sections*. Reusing "folder" there would
be actively confusing, and `Container` is unusable as a class prefix in Flutter.

**Resolved 2026-07-25:** "folder" stays the user-facing word; in code it is `PageFolder` in
`lib/workspace/application/view/page_folder.dart`, with the stored flag `is_folder`. The flag *read*
sits in `view_ext.dart` next to `isSpace`, both to keep the flag reads together and to avoid an import
cycle.

## Files and interfaces likely involved

**New (sidecar — the bulk of the work):**
- the folder flag, creation command, and identification helpers
- the sidebar row (wrapping/reusing the space row's anatomy at a lighter weight)
- the contents section widget, and the snippet source chosen above

**Core files that must change (small, named edits):**
- [view_ext.dart](frontend/appflowy_flutter/lib/workspace/application/view/view_ext.dart) — one new
  `View.extra` key, alongside `isSpaceKey`.
- [sidebar_space.dart](frontend/appflowy_flutter/lib/workspace/presentation/home/menu/sidebar/space/sidebar_space.dart)
  and the space row/header widgets — render folders inside a space's tree.
- `space_drop_target.dart` (built session 11) — folders as drop targets.
- [move_page_menu.dart](frontend/appflowy_flutter/lib/workspace/presentation/home/menu/sidebar/move_to/move_page_menu.dart)
  — folders as destinations.
- `view_action_type.dart` / the `…` menu — a "New folder" entry.
- The document page build path ([editor_page.dart](frontend/appflowy_flutter/lib/plugins/document/presentation/editor_page.dart))
  — render the contents section above the body when the view is a folder. **Must sit inside
  `PageThemeScope`** so it follows the page's theme, and inside the existing `PageSurface` sheet.

**Precedent worth reading first:** `outline_block_component.dart` (generated contents rendering) and
`space_icon.dart` / `space_more_popup.dart` (the row anatomy being reused).

## Phased plan

**Phase 1 — the folder exists. ✅ BUILT 2026-07-25.** Explicit "New folder" command, the flag, the
folder glyph, nesting inside spaces and inside folders, blocked inside Temporary. No page rendering yet —
clicking it just expands. Three things worth knowing about how it landed:
  - **The sidebar needed no changes for the row itself.** Folders render through the existing `ViewItem`
    page-row recursion, which already has expand/collapse, `+` and `…`. The only visual work was the
    glyph, and that slots into `ViewExtension.defaultIcon()` in `view_ext.dart` — so `view_item.dart`
    was untouched except for one parameter. A user-chosen emoji still wins over the glyph.
  - **Folders cannot be created under an ordinary page** — only in a space or another folder. This was
    always the spec's goal 3 ("nests inside spaces and inside other folders"), and making it explicit
    is what keeps `canCreateFolderIn` synchronous: no ancestor walk is needed to know whether a target
    is inside Temporary.
  - **This delivered `specs/temp-space.md` Phase 5.** The flatness rule was written and tested in
    temp-space Phase 1 as `TemporarySpace.canContainFolders` and had nothing to enforce against;
    `PageFolder.canCreateFolderIn` now delegates to it, including for the unmigrated fallback case.

**Phase 2 — the folder page.** Opens as a page: contents list on top (name + icon only), visual division,
free document body below. Navigation only.

**Phase 3 — previews.** Investigate (c), then choose (a) or (b). Add first-lines previews to the rows.
Separated so a performance problem here cannot block Phases 1–2.

**Phase 4 — filing integration polish.** Folders in the **Move to** picker, drop-target behaviour verified
at depth, and whatever the first week of real use exposes.

**Deferred to its own future work:** `Turn into folder` / `Turn into page` conversion.

## How we'll know it's done

- A folder can be created inside a space and inside another folder; at least three levels deep works.
- A folder **cannot** be created inside Temporary.
- A normal page with children stays a normal page — no contents section, no space-like row (this is the
  explicit-not-emergent guarantee, and it deserves a test).
- Sidebar: a folder is visually distinguishable from a space at a glance, and its collapse state survives
  a restart (the same quirk the session-6 space work had to handle).
- Opening a folder shows contents first, a clear division, and a fully working editor below — ribbon,
  per-page direction, per-page theme, page colour and margins all behave as on any page.
- The contents list matches reality after create / rename / move / delete of a child.
- Clicking a contents row opens that page. Nothing else in the list does anything.
- **RTL:** the contents section and its division mirror correctly on an RTL page, and follow the *page's*
  direction (not the layout's) — the trap already documented in `specs/ribbon-menu.md`.
- Folders appear in **Move to**; dragging a page onto a folder files it there.
- Verified in the **real dock app** (`flutter build macos --debug`, content-verified) with the user's real
  RTL settings — never headless, per the standing rules.

## Multi-user readiness

Universal — nothing here assumes this Mac, this account or this user's settings. Two notes:
- **Default folder icon** must exist as a shipped asset so a fresh install isn't missing one.
- **RTL is a first-class case, not an afterthought**, since RTL support is the headline draw for other
  users. The contents section is new layout code and is exactly the sort of thing that gets built LTR-first.

## Open questions

1. ~~Code naming~~ **RESOLVED 2026-07-25:** `PageFolder` in
   `lib/workspace/application/view/page_folder.dart` (logic sits with the other view concerns, not under
   `sidebar/`), stored key `is_folder`. The flag *read* lives in `view_ext.dart` next to `isSpace` — both
   to keep the flag reads together and to avoid an import cycle, since `PageFolder` needs `ViewExtKeys`.
2. **Ordering inside a container** — do folders sort above loose pages, or is it one manually-ordered list?
   Leaning: **one manual list** (matches the sidebar's existing drag-to-order behaviour, fewer surprises).
3. **The visual division** — rule, shaded band, card, or just generous spacing? Needs the user's eye, and
   it interacts with the page-colour and page-theme features already built. Worth mocking two options.
4. **Empty folder** — what the placeholder says, and whether it invites an action (which would brush
   against "navigation only").
5. **Deep nesting in the sidebar** — how far does indentation go before it stops working? Cap the visual
   indent at some depth, or let it run?
6. **Does the contents list include nested descendants**, or only direct children? Leaning: **direct
   children only** — a deep tree in the page body duplicates the sidebar.
7. **Snippet length** and whether it strips formatting/images. Depends on Phase 3's chosen source.

## Session Log

### 2026-07-25 (session 12) — scoped
Interviewed in three rounds. The user's one substantive amendment to my proposal: the contents list goes
**first on the page**, not below the writing, with an explicit visual division so the top reads as being
about the contents and the bottom as free content about the container — plus "folders behave like spaces
in the sidebar." That last phrase is what produced decision 1 of `specs/capture-and-structure.md` (a space
*is* a top-level folder), which in turn made this a flag-plus-renderer feature rather than a new backend
entity. Two findings shaped the plan: the `sidebar/folder/` directory name is already taken by upstream's
pre-spaces sections, and **no snippet/preview mechanism exists anywhere in the codebase**, which is why
previews are their own phase rather than part of the contents list.

## Session Log

### 2026-07-25 (session 12) — Phase 1 built and live-verified
Landed cheaper than scoped, for one reason worth remembering: **folders render through the existing
`ViewItem` page-row recursion, which already has expand/collapse, `+` and `…`** — so "behaves like a
space in the sidebar" was mostly free, and `view_item.dart` needed only two small edits. The `+` menu
also turned out to be a plain `PopoverActionList`, not plugin-registry-locked as first assumed (that
assumption was stated to the user and corrected).

Two clarifications became explicit while building:
- **Folders cannot be created under an ordinary page** — only in a space or another folder. Always the
  spec's goal 3, and stating it is what keeps `canCreateFolderIn` synchronous: no ancestor walk is
  needed to decide whether a target sits inside Temporary.
- **This delivered `specs/temp-space.md` Phase 5.**

Live verification passed all six checks, and produced three follow-ups (see "Open questions"): the icon
became a **filled rounded-square badge** like a space's, spaces gained a **tinted row + separators** to
stay distinguishable, and two behaviours need decisions — folder deletion currently takes its children
with it silently, and clicking a folder opens a (still empty) page rather than expanding.

### Follow-ups raised by that verification — NOT yet built
1. **⚠️ Folder deletion takes its contents with it, with no warning.** User's requested policy: when a
   folder has pages inside, **ask** — delete them too, or move them elsewhere (opening the existing
   "Move to" picker). Mitigating fact: AppFlowy deletes to **trash**, so this is recoverable rather than
   destructive; that is why it is a follow-up and not a stop-everything. Needs a small design pass (what
   the dialog says, what "move elsewhere" does with nested folders).
2. **Clicking a folder opens a page rather than expanding it.** Reported as a deviation from what was
   described. Deliberately left as-is: it is the Phase 2 target behaviour (a folder *will* have a real
   page), and expansion is available from the caret exactly as it is for any page with children.
   Changing it now and back at Phase 2 would be churn.
3. **The space/folder visual experiment needs the user's verdict** — tinted space rows at 0.12 alpha of
   the space's own icon colour, plus dividers between spaces. Explicitly exploratory ("let's try ... and
   see how that works"). The alpha and the divider are each one constant.

### Live-design round 2 — 2026-07-25 (user feedback on the first visual pass)

**Applied this session:**
- **Space icon: no filled badge.** The row already carries the space's colour as a tint; repeating it
  behind the icon said the same thing twice. `SpaceIcon` gained `showBackground` (default true, so every
  other caller is unchanged); the sidebar header passes false.
- **Dividers: a real 1px hairline** at 50% of the theme divider colour, `height: 1`, indented 8pt, with
  no padding stack around it. The first version (a `FlowyDivider` between two `VSpace(4)`) "sat too high"
  and ate vertical space.
- **Folders: the filled rounded-square badge is REVERTED and deleted.** It read as "a coloured rectangle"
  beside emoji-bearing pages. A folder now draws a plain monochrome folder glyph at full strength —
  deliberately not the 0.6 opacity pages use, so a container sits slightly forward of its contents.

**Still open — decisions needed before more folder UI is built:**

1. **Page ↔ folder conversion: UNDECIDED.** The user is explicitly on the fence. Do not build either way.
2. **Clicking a space's icon should open the icon + colour picker**, exactly as the `…` menu's "Change
   icon" does — a direct affordance rather than a menu trip. Not built.
3. **Folders must start with an icon and be able to change it**, the way spaces do — a container is never
   iconless. The default glyph is done; the open part is *which picker*: spaces are restricted to the
   **icon set (no emoji)**, and the user likes that restriction. If folders get the same restriction, it
   also protects the folder/page distinction below — an emoji on a folder would defeat it.
4. **⚠️ Folder vs. page at the same indent — the real unsolved problem.** Both can carry an icon, so
   icon-presence alone cannot carry the distinction. Proposal put to the user (three signals, none of
   them colour):
   - **a. An always-visible disclosure caret on folders**, even when empty — pages show one only when
     they have children. The strongest signal because it is *structural* ("things go inside me"), it is
     the Finder / VS Code / Notion convention, and it gives an empty folder something to show.
   - **b. Monochrome glyph vs. colourful emoji.** Pages lean on emoji; folders stay flat and
     monochrome, so the eye sorts them without reading. Only holds if folders are restricted to the icon
     set (see 3).
   - **c. Folder names in medium weight** (the weight space headers use), pages regular.
   - **d. (optional) Folders sort above pages** inside a container. Strongest grouping there is, but it
     conflicts with manual drag ordering — offered as a choice, not recommended by default.
   Recommendation: **a + b + c**, with folders restricted to icons so (b) cannot be defeated.
5. **Clicking empty sidebar space should deselect the open page**, returning to the ephemeral
   "nothing" area. **Blocked on the ephemeral pad** (`specs/capture-and-structure.md` → "the ephemeral
   pad"), which does not exist yet — there is currently nothing to return *to*. Worth building the two
   together, since this is the gesture that makes the pad reachable rather than only a launch state.
