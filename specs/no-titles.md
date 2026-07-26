# Titleless pages — the first line is the page

**Status: PHASES 1–4 BUILT AND LIVE-TESTED across two rounds on 2026-07-26 (session 15). The second
round's fixes are shipped but NOT re-tested — that is the first item next session. Phase 5 (the
one-off migration + retiring the title box) is SCOPED BUT NOT BUILT** — the user asked for it at the
end of session 15; it writes into every document in the workspace and was deliberately not fired off
at wrap-up time. See "Phase 5" below.

**The whole feature in one rule** — amended session 15 after live use:

> *A page's name comes from its first line while you are first writing it. Leaving the page freezes
> the name. After that, only an explicit rename changes it.*

The user's framing: **a page title is a window in time.** *"You can change it while you're inside for
the first time, and then it sticks."* This replaces the original "tracks until you rename it" rule —
see Q1 below, which is now superseded.

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

**✅ RESOLVED 2026-07-26 (session 15) — and it resolves this question by removing it.** Grid, Board
and Calendar (plus AI Chat) are being **retired from the UI**: not creatable, not advertised, code
kept. See `specs/retire-non-core-surfaces.md` for the decision and the measurements behind it.

**What that means here: no-titles applies to documents, and only documents.** There is no "what
names a database" problem to solve, because no new database can exist. Do not build a naming rule
for them, and do not treat their name field as a case this feature must handle.

*Original framing and the counter-argument are kept below, because the reasoning is what a future
session would otherwise have to redo.*

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

## Interview — answers so far (session 15)

### ✅ Q3 — does the first line render as a heading automatically?

**No. The first line is a plain paragraph; you style it yourself, like any other line.** The
Obsidian model rather than the Apple Notes one.

**This is the purest reading of "titles as styles", and it is the answer with the most consequences,
so they are worth stating plainly:**

- **Naming and styling become fully independent.** The first line supplies the *name* whether or not
  it looks like a title. Nothing about the name is inferred from the style, and nothing about the
  style is inferred from being first. Two mechanisms that would otherwise be tangled stay apart.
- **A new page looks flat.** There is no visual signal that the first line is special, because it
  isn't — the specialness is entirely in what it *does* (name the page), which is invisible on the
  page itself and visible in the sidebar. That is the honest trade of this choice, not a defect to
  design around later.
- **It makes the ribbon's paragraph-style hierarchy load-bearing** (`specs/ribbon-menu.md`, "future
  button designs"). If styling your own titles is the model, then applying a heading has to be fast
  and obvious. **Scope the two together**, per the interaction note above.

### ✅ Q2 — what names an untitled page in the sidebar before anything is typed?

**"Untitled"** — what happens today. Kept deliberately over a blank row or no row at all.

Worth recording why the alternatives lose: a blank row is quieter but leaves an unlabelled,
unexplained thing in the sidebar; and hiding the row until something is typed would mean a page
created deliberately through a space's `+` appears to vanish. **The pad already solves the "don't
accumulate empty pages" problem** (`specs/ephemeral-pad.md`), which is what would otherwise have
pushed toward hiding — so this question no longer has to carry that weight.

### ✅ Q1 — rename versus first line

**An explicit rename wins permanently. There is no way back.** Session 14's answer, confirmed, and
chosen over an offered "use the first line again" escape hatch — the simpler rule was preferred to
the recoverable one.

**State the cost accurately, because it is smaller than it sounds:** an accidental rename (the
sidebar's double-click is easy to hit) permanently detaches that page from its first line. What you
lose is the *automatic tracking*, not the ability to name the page — you can still rename it to
anything, including its first line, by hand. Nothing becomes unreachable or unnameable.

**Never infer this state by comparing the name to the first line.** It must be a stored flag. A
comparison would silently re-arm itself the moment someone edited either one, which is the failure
mode this whole rule exists to prevent.

### ✅ Q2 — what an `@`-mention shows

**Always the live name, truncated** on the same word boundary as the sidebar.

This is mostly today's behaviour made explicit: mentions already store the page **id** and look the
name up (`mention_page_block.dart`), so they already follow renames. What is added is the truncation,
so a rambling first line cannot blow up a sentence inside another page. The rejected alternative —
freezing the name at insert time — was rejected on the grounds that **a link whose label disagrees
with its target is worse than one that moves.**

### ✅ Q3 — search results

**Just the name. Leave search alone.** No Rust change, no snippet work.

**A finding that made this easy:** local search results carry **no content snippet at all**
(`LocalSearchResponseItemPB` is id, name, icon, workspace — nothing else). Snippets were a *cloud*
search feature, and cloud is dead in this fork. So search results are already a list of names, and
once names are first lines they become a list of first lines. The real gap — you cannot see *why* a
page matched when the match is deep in its body — **already exists today** and is not made worse by
this feature. It is its own small feature if it ever becomes annoying in use.

### ✅ Truncating a long first line

**Reuse `PadContent.nameFrom`** — the pad's existing word-boundary truncation, with a hard cut when
there is no boundary to use. The user: *"First line and cut it somewhere. Not a big deal."* Do not
write a second truncation rule.

## ⚠️ The flag's polarity is the one thing that could destroy data

Session 14 recorded the requirement as *"a page needs a stored 'has been named deliberately'
state."* **Implemented literally, that flag is destructive**, and it is worth spelling out why
before anyone writes it:

If absence of the flag means "track my first line", then **every page that already exists** — none
of which carries the flag — starts tracking on the first launch after the feature ships. Their names
are deliberate and their first lines are ordinary body text, so the entire workspace gets renamed to
whatever each page happens to open with. That is not a migration; it is silent data loss with a
plausible-looking cause.

**So the flag must be inverted: it marks "this page tracks its first line", set on pages created
after the feature exists.** Absence means "leave this page's name alone", which is the safe reading
for every page in the wild. This also matches answer 2 exactly — the user converts pages by hand,
one at a time, and expects untouched pages to stay untouched.

Same shape as `is_pad`, `is_folder`, `is_temporary`: a namespaced key in `View.extra`, read
defensively, absence meaning "no". See `EphemeralPad` for the pattern to copy.

## Phased plan

**Phase 1 — the flag and the naming engine, with no visible change.** The `View.extra` flag, and
first-line-to-name syncing for pages that carry it. **Most of this already exists**: the pad's
`PadContent.nameFrom` (D6 naming, truncation) and `EphemeralPadPromoter` (400ms debounce, one write
in flight, reconcile-on-mount) are exactly this engine, built and live-verified. Phase 1 is largely
generalising them off the pad. Nothing on screen changes, because no page carries the flag yet.

**Phase 2 — new pages are titleless.** Newly created pages get the flag and render with no title
box. The pad already renders `header: null`, so "titleless" is a thing the app can already draw.
Existing pages are untouched and keep their title box — **the app deliberately shows two kinds of
page during the transition**, per answer 2.

**Phase 3 — rename means something.** The sidebar rename and the page top-bar rename clear the flag,
permanently detaching that page (Q1). This is the phase where `specs/sidebar-improvements.md`
Phase 2's rename gains its new meaning rather than losing it.

**Phase 4 — mentions and the edges.** Truncation on `@`-mentions (Q2), plus the sweep for anything
else that renders a page name in a space that assumed names were short. **Treat this as a D12-shaped
sweep** with a written list, not as things are noticed — `view.name` is read in **72 files**.

**Phase 5 — retire the title box entirely**, once the user has hand-converted their pages and no
page without the flag is left that they care about. This is the phase that deletes code rather than
adding it, and it is also where `specs/ephemeral-pad.md`'s frozen-appearance machinery becomes
unnecessary. **Do not delete that speculatively** — it is live and verified.

**Live verification belongs in every phase, not at the end.** Phase 1 in particular is invisible by
design, so it needs a deliberate check that names actually track, rather than an assumption that
silence means success.

## How we'll know it's done

- A new page has no title box, and typing its first line names it in the sidebar.
- A long first line is cut on a word boundary in the sidebar and in `@`-mentions.
- Renaming a page stops the first line driving it, permanently, and editing that first line
  afterwards leaves the name alone.
- **No page that existed before this feature is ever renamed by it** — the acceptance test that
  matters most, and the one to check first on real data rather than a scratch workspace.
- `@`-mentions of a page whose first line changed show the new name.
- Search still finds pages by name and by body text.
- Two kinds of page (flagged and not) coexist without special-casing anywhere but the flag check.

## ✅ Q4 — hand-converted pages stay name-frozen

**No opt-back-in action. A page that has been named deliberately never tracks its first line again,
including one the user converted by hand.** The clean rule was chosen over the recoverable one for
the second time, consistently.

### This collapses the model rather than splitting it — the reframe is worth having

The question was posed as "two kinds of page forever", which sounded like a cost. **Given this
answer it isn't, and the spec should not carry that framing forward.** There is exactly one rule:

> **Every page either has a deliberate name or it doesn't. If it doesn't, its first line names it.
> Setting a name is one-way.**

Existing pages are not a second kind of page and are not a migration problem — they are simply pages
that **have all already been named**, because the title box is where their names came from. New
pages start unnamed. Nothing special-cases "old", nothing detects "converted", and there is no
transition to finish.

**Two things follow, both simplifications:**

- **There is no conversion action to build.** Hand-converting is just typing; the page's name is
  already correct and stays correct. The rejected escape hatch stays rejected, and nothing needs it.
- **The flag polarity above is not a workaround, it is the rule.** "Tracks its first line" marks the
  pages that have no deliberate name yet. Absence meaning "leave the name alone" is the correct
  reading of history, not a defensive default.

**One consequence to keep visible:** with the title box gone (Phase 5), the **sidebar rename becomes
the only way to set a deliberate name.** It stops being a convenience and becomes the sole naming
mechanism in the product — so it must be discoverable, and Phase 3 should be judged on that rather
than on the code being small.

## Open questions

**None. The interview is complete** (2026-07-26, session 15). The model, every edge, the phases and
the done criteria are all settled above. Ready to build when it reaches the top of the priority list
in `specs/product-direction.md`, where it sits under "the page, and how it behaves".

## Session Log

### 2026-07-26 (session 15) — Phases 1–4 BUILT

Interviewed to completion and built the same session. **Phases 1–4 are in; Phase 5 (retiring the
title box for pages that predate the feature) is deliberately NOT built** — it is gated on the user
hand-converting their own pages, which is their work, not code.

**Phase 1 — the flag and the naming engine.** `ViewExtKeys.tracksFirstLineKey` plus two sidecars:
`first_line_naming.dart` (logic) and `first_line_namer.dart` (the widget that watches the editor).
**The namer is `EphemeralPadPromoter` with the promotion taken out** — the pad had already solved
debouncing a per-keystroke stream, keeping one write in flight, and reconciling once on mount, and
that code is live-verified. Copied rather than shared on purpose: the promoter can also *demote*,
which this must never do, and merging them would put a branch inside the one loop that has to stay
simple. Unifying belongs in Phase 5.

**Phase 2 — new pages are titleless.** The flag is set at **`ViewBackendService.createView`**, the
single choke point every creation path already goes through, so the sidebar, the space `+`, the
slash menu and the pad all get it without a sweep that can rot. **Verified end to end that the Rust
side already carries it** — `CreateViewPayloadPB.extra` → `CreateViewParams.extra` → `View.extra`
(`view_operation.rs:152`) — so it rides the *create* call rather than a follow-up update. No window
in which a page exists un-flagged, no second call that can fail and strand one, **and no Rust
change at all.**

`DocumentCoverWidget` gained `showTitle`. **The cover and icon deliberately stay** — they belong to
the page, not to its name. That is where this differs from the pad, which hides the whole header
because a pad is meant to be bare (D7). The title is *omitted*, not sized to zero: an invisible
`CoverTitle` still holds a focus node and still re-seeds from the view's name, and this header is
rebuilt whenever a paste grows the document — which is exactly session 11's title bug, and there is
no reason to keep a dormant copy of it.

**Phase 3 — rename detaches, permanently.** Hooked at `ViewEvent.rename`, which **every** rename UI
dispatches (sidebar double-click, the "…" menu, the title box, all the mobile paths). Safe on
spaces, folders and databases: with no flag to clear it writes only the name, on exactly the old
path.

**Phase 4 — mentions: NO CODE NEEDED, and the reason is worth keeping.** Truncation happens at the
moment the name is **written**, so the stored `view.name` is already short. Everything downstream —
the sidebar row, the breadcrumb, `@`-mentions, tab labels, search results — reads `view.name` and
gets the short form for free. `view.name` is read in **72 files**; giving each its own cut would have
been a D12-sized sweep, and writing the short name instead deletes the entire problem. Mentions were
confirmed to resolve live by id (`mention_page_bloc.dart:142`), so they follow renames already.

**The pad needed no changes whatsoever, and that is the model working.** The pad is created through
the same choke point, so it starts tracking; `EphemeralPad.promote` removes only `is_pad`, so the
promoted page goes on naming itself; `demote` merges `is_pad` back and keeps tracking. The namer is
guarded off while `is_pad` is set, because two namers on one page would fight — the promoter demotes
and the namer would immediately rename it back.

**A hazard found in this session's own code, before it shipped.** The first `extraWithoutFlag`
decoded `extra`, removed the key, and re-encoded. On a **malformed** `extra` that decodes to an empty
map — so it would have written `''` back, erasing the page's direction, theme, cover and margins to
remove a flag that was not even there. Now an unreadable `extra` is returned untouched, matching
`page_text_direction.dart`'s "bail rather than clobber". **Proven failing-then-passing.**

**Also decided while building:** an empty document leaves the name **alone** rather than blanking it
— select-all-delete keeps the row saying what the page was called until something is typed again,
because a page that loses its name mid-edit looks like a page that has been lost. And
`tracksFirstLine` is read from the view the page **opened** with, for the same reason `isPad` is: a
live read would rebuild the header on every debounce while the user is typing beneath it.

12 new unit tests, one proven failing-then-passing. 466 unit tests pass (the single failure is the
pre-existing `link_preview` test, which does a real DNS lookup). Analyzer clean — 0 errors,
0 warnings. Dock app rebuilt and content-verified: test bindings **0**, `runAppFlowy` **31**,
`FirstLineNamer` **6**, `tracks_first_line` **2**, `setDeliberateName` **3**.

**Not verified live.** The checklist handed to the user is in the session's closing message.

### 2026-07-26 (session 15, later) — live-tested, three fixes

The user walked the whole checklist. **The safety test passed first**: no page that predates the
feature was renamed by it, which was the one outcome worth stopping for. Naming, editing, long-line
truncation, Hebrew, space and folder renames, and `@`-mentions all passed — mentions were noticed to
follow a rename live, which is the id-based lookup working as designed.

**Bug 1 (the real one) — a rename did not stick.** Rename a page, edit its first line, and the name
went back to the first line. **`FirstLineNamer` read the tracking flag once, at page open.** Renaming
cleared it in the backend, but the widget was still on screen holding a stale `true`, so the next
keystroke renamed the page back.

**The fix, and the distinction worth keeping:** *mounting* stays on the flag frozen at open — so the
widget tree cannot change shape under a typing user — while the *write check* reads the flag **live**,
inside the sync loop, where nothing about the layout depends on it. Freezing was right for
appearance and wrong for behaviour; the original code applied one rule to both.

There was a second half: `ViewEvent.rename` rebuilt its state view with the new **name only**, not
the cleared `extra`, so even a live read saw stale data until some later listener happened to
refresh. Both halves fixed.

**Bug 2 — a promoted pad came back with a title box.** Correctly diagnosed by the user. Their pad was
created *before* this feature, so it carried `is_pad` and nothing else; promoting it produced a page
with no tracking flag. `EphemeralPad.promote` now **sets** the flag rather than merely preserving it:
a promoted pad has never been *deliberately* named — it was named by its own first line — so it must
keep tracking. Old and new pads now promote identically. Regression test covers the exact case.

**Polish — the top of a titleless page.** The "Add Cover / Add icon" row sat directly on the first
line, because on an ordinary page it is the *title* that holds them apart. A titleless page now
reserves that space via `kTitlelessHeaderGap`, derived from `kCoverTitleFontSize` rather than picked,
so the two move together. **That constant is the one number to change if it reads too tight.**

**Decision (user): the first line shows NO placeholder.** With the gap in place the slash hint landed
exactly where a title used to, reading as a label for the title rather than guidance for the body.
The first line is now bare, like the pad; the hint still appears on every line after it.

**Not a bug, recorded so it is not re-reported:** select-all-delete on the *pad* demotes rather than
keeping the name — that is D10, and the user confirmed the keep-the-name behaviour is correct on an
ordinary page.

**Honesty note:** bug 1's fix is widget wiring and rests on inspection plus the user's re-test. A
test reaching it would have to mount the editor, the same wall that killed the preview render test
earlier this session. The *pad* half of it (bug 2) is properly covered by a unit test.

## Phase 5 — the one-off migration and retiring the title box (SCOPED, NOT BUILT)

**Asked for by the user at the end of session 15**, reversing session 14's answer 2 ("the user
converts them by hand… no migration is written and none should be"):

> *"The idea would be for you to remove all titles from pages with titles, and switch the titles into
> first lines. This is a one-off because after the change — there will be no titles anymore."*

**Not built, and the reason is scheduling rather than doubt.** It writes into **every document in the
workspace**, and it was asked for in the same breath as "then wrap up". Shipping an untested
whole-workspace mutation at the end of a session is how someone loses writing. It is the first item
for the next session, with a backup taken first.

### What it has to do

1. **Take a snapshot first** (`BackupService.backupNow`), and refuse to proceed if it fails. The
   machinery exists and is proven; the pre-migration snapshot bug in `specs/temp-space.md` is exactly
   the precedent for *checking the result* rather than assuming it fired.
2. **Dry-run report before writing anything:** how many pages, which would gain a line, which would be
   skipped. The user sees it and gives the go-ahead.
3. **For each Document view with a non-empty name:** insert the name as a new first paragraph.
4. **Turn `showTitle` off everywhere** — the flag already exists on `DocumentCoverWidget`, so this
   half is one line plus the removal of the now-dead `CoverTitle` path.

### The hazards, named in advance

- **Idempotency is the whole ballgame.** Run it twice and every page gets two copies of its name.
  It needs a persisted "migration done" marker, and it must skip a page whose first line **already**
  equals its name — which is common, since many pages already open with their title as a heading.
- **That skip rule is a guess, and session 14 warned about exactly this guess.** It is the
  *conservative* direction (skip rather than duplicate), and the failure mode is a missing line the
  user adds by hand — not lost content. Worth stating so the trade is chosen, not stumbled into.
- **The failure mode is additive, which makes this far less frightening than it sounds.** Nothing is
  deleted; a wrong insertion is one line the user removes. The real risk is a *partial* run leaving
  the workspace half-migrated, which the marker plus a per-page log addresses.
- **It is slow.** ~100 pages means ~100 document opens and writes. It needs progress, and it must not
  run inside `SpaceEvent.initial` — that is where the pre-migration snapshot silently no-oped because
  it ran too early in startup.

### Sequencing note

Steps 3 and 4 belong together. Turning off title boxes **without** migrating hides the name of every
page whose first line is not its title — the name survives in the sidebar, but the page itself stops
showing what it is called.

### 2026-07-26 (session 15, round 2) — live-tested again; the model changed

The user tested the round-1 fixes and, in doing so, **changed the feature's central rule**. Four
outcomes, three of them reversals of things built earlier the same day.

**1. The New Page button was reverted to creating a page.** `specs/ephemeral-pad.md` D8 (built this
session) made it open the pad; the user rejected it within the hour: *"it should create a page in temp
named untitled. It's different than the pad, but it's expected."* Full reasoning in
`specs/capture-and-structure.md`. The page is created with an **empty name**, which the sidebar
already renders as "Untitled", so the namer replaces it cleanly on the first thing typed and no
literal string is stored.

**2. ⚠️ THE RULE CHANGED — a name freezes when you leave the page.** Q1's original answer (tracking
persists until an explicit rename) is **superseded**. The user's framing:

> *"A page title is a window in time. You can change it while you're inside for the first time, and
> then it sticks — and only sidebar rename changes it."*

So the naming window is **your first visit**, and `FirstLineNamer.dispose` closes it. Editing a first
line months later is editing body text, and renames nothing.

**This is a genuine improvement, and the reason is that it unifies two rules into one.** The pad
already worked this way — D10 makes promotion permanent by navigating away — and pages now do too.
One sentence covers both surfaces where there were two.

It also **undid a fix from round 1**: `EphemeralPad.promote` had been made to set the tracking flag,
so a promoted pad would go on naming itself. Under the window rule that is wrong — the pad's promoter
already names the page for as long as you are on it, and leaving closes the window at the very moment
D10 makes promotion permanent. Setting the flag there would reopen a window that just shut. Reverted,
and the test that asserted it replaced with one that asserts the freeze.

**3. Two spacing fixes at the top of a titleless page.** Round 1 added space *below* the header
(`kTitlelessHeaderGap`); round 2 added space *above* it (`kTitlelessHeaderTopGap`), because with the
title gone the "Add Cover / Add icon" row was pinned to the top edge of the sheet. The top gap is
suppressed when the page has a cover — padding above a cover would leave a strip of desk showing
through where the image should run to the edge. **Both constants are named and adjacent; they are the
two numbers to change if the top of a page reads wrong.**

**4. Phase 5 was requested and deliberately deferred** — see the Phase 5 section above.

Analyzer fully clean (0 issues in `lib/` and the new tests). 40 tests pass across naming + pad. Dock
app rebuilt and content-verified: test bindings **0**, `runAppFlowy` **31**, `closeNamingWindow` **3**,
`kTitlelessHeaderTopGap` **3**.

**None of round 2 is live-verified.** The re-test list is in the session's closing prompt.
