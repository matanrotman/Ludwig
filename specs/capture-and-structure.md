# Capture and Structure — the shared model

**Status:** decisions agreed 2026-07-25 (session 12). Not a build spec — it has no phases and no code.
**Governs:** `specs/temp-space.md` and `specs/folder.md`, and any future feature that touches where content lives.

## Why this file exists

Ludwig's product thesis is one sentence: **you should be able to dump a thought without deciding
where it goes, and give it structure later.** That sentence on its own is a slogan. This file exists
because the 2026-07-25 interview turned it into seven decisions that *both* the Temporary-space work
and the folder work must obey — and if each spec re-derived them independently they would drift apart.

**The test this file has to keep passing:** every section below must be a decision another spec
depends on. The moment this reads as description rather than constraint, delete it and fold whatever
survives into the two build specs. It is not here to be inspiring.

## The seven decisions

### 1. Everything is a page. Some pages are containers. The top-level containers are called spaces.

There is **one** container concept, not two. A folder is not a new kind of object that happens to
resemble a space — a space *is* a folder that lives at the top level.

This came out of the code, not from theory. A space is already created as a
`ViewLayoutPB.Document` view ([space_bloc.dart:132](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart:132))
and marked as a space only by `is_space` in `View.extra`
([view_ext.dart:47](frontend/appflowy_flutter/lib/workspace/application/view/view_ext.dart:47)).
Views already nest arbitrarily. So the machinery for "a document that contains other documents and
renders as a collapsible sidebar row" is already built and half-used.

**Consequences that bind both specs:**
- A folder is marked by a flag in `View.extra`, exactly as `is_space` does it. No new backend entity,
  no protobuf change, no Rust change.
- A folder reuses the space widgets' *anatomy* (icon, collapse arrow, `+`, `…`, drop target) rather
  than growing a parallel set.
- Anything true of a space's storage is true of a folder's, which is why a folder can hold writing.
- If a rule has to differ between a space and a folder, that difference is a deliberate exception and
  gets written down as one — not discovered in the widget tree.

### 2. Containers are explicit. They are never emergent.

Nesting a page under another page does **not** turn the parent into a container. You create a folder
on purpose, with a command that says so.

**Why:** the alternative (any page with children becomes a folder) means a page you wrote as a page
silently restructures itself — grows a contents section, changes its sidebar row — the moment you drag
something under it, and reverts when you drag it out. Structure appearing behind your back is the
opposite of the thesis, which is about structure you apply *deliberately*, later.

Deferred, not rejected: **converting** a page into a folder and back (`Turn into folder`). It fits
"structure later" well and is worth having, but it is not needed for the first version and it is
strictly additive.

### 3. Capture requires no destination decision.

Starting a new page must not ask, imply, or depend on where it belongs. The top-level **New Page
always lands in Temporary**, regardless of what is open or which space was last touched.

**⚠️ This deliberately supersedes a decision from session 6**, which made New Page target the space
you were currently in (`state.currentSpace`,
[space_bloc.dart:80](frontend/appflowy_flutter/lib/workspace/application/sidebar/space/space_bloc.dart:80)).
That was the right call under the old model and is the wrong call under this one. It is reversed with
the user's explicit sign-off; it is not an oversight, and it should not be quietly reverted later by
someone reading the session-6 notes.

Deciding a destination up front is still fully supported — that is what the `+` on a specific space or
folder is for, and creating a page inside a container remains the fast path when you already know.

### 4. The staging area is deliberately flat.

Temporary holds loose pages only. No folders inside it, at any depth.

**Why:** the instant you can organise *inside* the inbox, you will organise there instead of filing,
and the staging area quietly becomes a second permanent home. Keeping the pile a literal pile is what
creates the pressure to file. This is a rule with a purpose, not a limitation to be relaxed on a whim —
if a future session wants to allow folders in Temporary, it should argue against this paragraph first.

### 5. The size of the pile must be visible.

Temporary carries a quiet count of what is sitting in it unfiled. Without it, "structure later"
degrades into "never" with nothing in the interface to notice.

Constraint: a count, not a warning. No red, no badge language borrowed from notifications, no nagging
copy. It reports; it does not scold.

### 6. Structure is applied by moving, using mechanisms that already exist.

Filing a page is a **move**, and both move paths already ship:
- drag in the sidebar (built in session 11 — `space_drop_target.dart`)
- **Move to** in the page's `…` menu (`ViewMoreActionType.moveTo` → `move_to/move_page_menu.dart`)

Neither spec may invent a third filing gesture. Their only obligation is that folders appear as valid
destinations in the existing picker and as valid drop targets.

Deferred: a dedicated triage screen (a list of everything in Temporary with a picker per row). It is a
genuinely good idea for processing a backlog in one sitting, and it is out of scope until the basics
are lived with.

### 7. Navigation surfaces do not duplicate management.

A folder's contents list is for **going somewhere**, not for administering the folder. Reordering,
renaming, deleting and creating stay in the sidebar, where all of it already works.

**Why:** a second management surface is a second implementation to keep correct, a second place for
bugs, and a second set of states that can disagree with the sidebar. This is the standing reason to
say no to "…but you could also drag to reorder right there."

## Deferred, but part of the model: the ephemeral pad

**Scoped 2026-07-26 — see `specs/ephemeral-pad.md`, which is now the authoritative document for
this. The section below is kept as the original framing and the reasoning for why it belongs to
this model; the open questions it lists were answered in that spec's interview.**

**⚠️ Note for decision 3 above:** the ephemeral pad's D8 changes the top New Page button from
"creates a page in Temporary" to "opens the pad". That is a refinement of decision 3, not a
reversal — it removes the act of creation, which is the direction decision 3 was already going.

The app should always open on an **open, ephemeral writing pad that is "nothing"** — not a page, not a
row in the sidebar, not a file. Only when something is typed or pasted into it does it *become* a page,
at which point it lands in Temporary. In the user's words: *"from chaos and nothing into context and
structure"* — the experience has to allow spontaneity.

This is the logical completion of decision 3. That decision removed the *destination* choice from
capture; this removes the act of creation itself. Today you still have to decide to make a page.

Why it needs its own spec rather than a quick build — the open questions are real and mostly about
state, not UI:
- **What "nothing" means concretely.** No view at all (a pure in-memory buffer), or a real view that is
  hidden from the sidebar until it has content? The first is truer to the idea; the second is far easier
  because the editor is built around a `ViewPB`.
- **What counts as "something typed".** First keystroke? First non-whitespace character? A paste? An
  image drop? A title but no body?
- **What survives a crash or a force-quit** before the pad has become a page. An in-memory buffer would
  lose it — which may be acceptable for a scratchpad, but it must be a decision, not an accident.
- **What happens to an untouched pad** when you navigate away and come back, and whether there is ever
  more than one.
- **How it interacts with the tab system**, session restore ("reopen the page I had open"), and the
  existing `MenuSharedState.latestOpenView`.
- **Naming.** An untitled page in Temporary is already the fallback; does the pad become "Untitled", or
  get a name from its first line the way Apple Notes does?

Nothing in Phases 1–5 of `specs/temp-space.md` blocks this or assumes its absence.

## What this model is explicitly NOT

Naming these so they are recognised as out of scope rather than re-proposed as obvious extensions:

- **Not a property/metadata system.** A folder's top section shows what is inside it and nothing else.
  Description fields, tags, dates and per-folder properties would mean designing a property system,
  which is its own feature (and arguably already exists as databases).
- **Not tags or multi-parent membership.** A page lives in exactly one place. Cross-cutting membership
  is a different mental model and would undo the "give it context by putting it somewhere" idea.
- **Not automatic organisation.** Nothing files anything for you. AI-assisted filing suggestions are a
  plausible later feature and are deliberately not assumed by anything here.
- **Not a rethink of databases, grids, boards or calendars.** Those stay exactly as they are.

## Multi-user readiness

This model carries almost no personal assumptions — it is about a general product idea, not about this
Mac or this account. Two things to watch:

1. **The one-time General → Temporary rename** is the only part that touches existing data, and the
   decision taken (rename in place, silently) is a **personal-now** choice. Anyone installing Ludwig
   over an existing AppFlowy data folder would have a space renamed without being asked. The bounded
   multi-user upgrade is the prompt variant, already scoped in `specs/temp-space.md`.
2. **A fresh install** (nobody's existing data) has no General to rename, so Temporary has to be
   created as part of first-run workspace setup. `specs/temp-space.md` owns that.

Everything else — folders, flatness, the count, filing — is universal.

## Session Log

### 2026-07-25 (session 12) — model agreed
Interviewed over three rounds. The unified container model (decision 1) was **not** in the original
request; it fell out of noticing that spaces are already `Document` views flagged in `View.extra`, and
it converts "build a folder entity" from a backend feature into a flag plus a renderer. Decision 3 was
surfaced as a direct conflict with session 6 and reversed with explicit sign-off. Decisions 4, 5 and 7
each exist to protect the thesis from a plausible-sounding erosion, and each records the argument so a
future session has to engage with it rather than rediscover it.
