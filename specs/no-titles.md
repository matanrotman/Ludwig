# Titleless pages — the first line is the page

**Status: answers recorded, interview NOT done.** The user answered the three blocking questions
on 2026-07-26 (session 14) as they came up in conversation. That is not a substitute for the
scoping interview — it settles the *model*, not the scope, the phases or the edges. Do the
interview before writing code.

## Background

Today a page has a **name** and, separately, a **document**. The name is set in one place (the
title box at the top of the page, or the sidebar's double-click rename) and the writing happens
somewhere else. The user's position, arrived at independently and recorded in their own
"Things to change in Ludwig" list before this was ever discussed: *"Remove titles — we'll
implement them as styles."*

The title box is not decoration. `view.name` is read in **72 files** — the sidebar row, the
breadcrumb, search results, `@`-mentions and page links, tab labels, the backup browser's tree.
Removing the box does not remove the need for a name; it removes the only place to set one.

So the real change is: **the name comes from the document's first line**, Apple Notes style. What
looks like a title on the page is a *heading style* applied to that first line, not a separate
field.

## Why this is worth doing (not just tidying)

- **It removes a category of complexity rather than moving it.** The ephemeral pad currently needs
  a frozen appearance, header suppression and its own first-line naming (`specs/ephemeral-pad.md`,
  Phase 2). With no titles anywhere, the pad is just *a page that has no name yet* — the same as
  every other new page. The mid-keystroke header swap does not get fixed; it stops existing.
- **It matches the capture model.** `specs/capture-and-structure.md` is built on "start writing,
  file later". Asking for a name before the first sentence is the same friction as asking for a
  destination.

## The user's answers (2026-07-26, session 14)

### 1. Where does the name come from, given the sidebar rename already exists?

**The first line dictates the DRAFT name. An explicit rename sets the TRUE name.** Once a page has
been renamed deliberately, the first line no longer drives it — and if the user then edits that
first line so the two disagree, that is the user's business, not something the app should reconcile.

*Consequence to design for:* a page needs a stored "has been named deliberately" state. This is the
same shape as `View.extra` flags already used for spaces, folders and the pad — a flag, not a
guess, and never inferred by comparing the name to the first line (which would silently re-arm
itself the moment someone edited either).

### 2. What happens to pages that already have a name unrelated to their first line?

**The user converts them by hand, one at a time** — moving the title into the document as the first
line. Names are kept; the pages change. Once done, there is exactly **one kind of page: titleless.**

*Consequence:* **no migration is written and none should be.** This is deliberate — a bulk migration
would have to guess whether a name is "really" the first line, and getting that wrong rewrites the
user's own writing. Doing it by hand is slower and correct. It does mean the transition period has
two kinds of page in the wild, which the build must tolerate without special-casing.

### 3. Databases (grid, board, calendar) have a name and no first line.

**The user's position: either remove them, or turn them into components inside a page via the
ribbon. They see no reason for them to exist standalone.** Explicitly open to being argued out of it.

**Claude's counter-argument, for the interview — the conclusion is "don't remove them", but not for
the reason you'd expect:**

- The product argument is sound. Standalone databases are the strongest pull toward
  "team workspace tool", which is the direction this fork is deliberately diverging from.
- The *implementation* argument runs the other way, hard. `lib/plugins/database` is a large upstream
  subsystem. Deleting it, or rebuilding it as in-page components, means carrying an enormous
  permanent diff against upstream — which directly contradicts this project's own fork-maintenance
  rule ("isolate new functionality, keep merges low-conflict"). It would make every future upstream
  merge harder, not easier, and it is *more* work than leaving it alone, not less.
- There is also a data signal worth respecting: `specs/restore-redesign.md` D4 already treats
  databases as "not yet restorable" because they are a genuinely different data shape, not a block
  in a document. That was discovered by reading the code, not assumed.
- **Middle path worth putting to the user:** don't remove anything. Stop databases being *created*
  as top-level items, and give them the titleless treatment only where it is cheap. That buys the
  product identity change without a subsystem rewrite, and leaves the door open.

### 4. Scope

**Its own feature, its own interview, its own spec** — not folded into the pad work. The pad is
finished and verified; this would delete complexity from it, which is worth doing deliberately
rather than as a side effect.

## Known interactions (check before scoping)

- **`specs/ephemeral-pad.md`** — Phase 2's first-line naming and the frozen pad appearance both
  become unnecessary. Do not delete them speculatively; they are live and verified.
- **The ribbon's paragraph-style hierarchy** (`specs/ribbon-menu.md`, "future button designs") —
  "titles as styles" IS that feature. Scope the two together or the first one built constrains the
  second.
- **Sidebar rename** (`specs/sidebar-improvements.md` Phase 2) — becomes the "set the true name"
  action, so it gains meaning rather than losing it.
- **`specs/folder.md` Phase 2** — the folder page shows a contents list above free writing; whether
  a folder has a first-line name is the same question in a different costume.

## Open questions (for the interview, not answered)

1. Does the first line stop driving the name on the first explicit rename, or does an explicit
   rename win only until the first line changes again? (Answer 1 says the former; confirm.)
2. What names an untitled page in the sidebar before anything is typed — blank row, "Untitled", or
   nothing at all?
3. Does the first line render as a heading automatically, or is it a normal paragraph the user
   styles? This is where "titles as styles" is actually decided.
4. Links and `@`-mentions point at a page by name. If the name is a draft that keeps changing as
   the first line is edited, do existing mentions follow it?
5. Does the ⌘-search index the first line differently from the rest of the document once it is
   also the name?
