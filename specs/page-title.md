# Page title — rethink, demote, or remove

**Status: idea captured, NOT scoped. Discussion scheduled for the session after the app-icon /
side-by-side distribution work.** Nothing here is decided; this file exists so the thinking isn't
lost.

## The user's case against the current title (2026-07-25, session 11, verbatim in substance)

> "The more I think about it, the less I see the reason this title text exists to begin with. It
> makes creating new pages on the fly cumbersome (someone calls you and says 'write this down, will
> you?' and now you need to think about what's this page title? where should I place it?), and
> creates more code and work when moving it LTR and RTL."

Two distinct complaints, worth keeping separate because they have different fixes:
1. **Friction at creation time.** A dedicated title field demands a naming decision at the exact
   moment the user wants to start typing content. Capture-first tools (Apple Notes, Bear, Obsidian's
   daily notes) deliberately avoid this.
2. **Ongoing maintenance cost in this fork.** The in-document title is its own widget with its own
   direction handling, and it has already produced real bugs here — see the "Page title reverted to
   'Untitled' after pasting" fix (commit `6b6fa80b2`) and the title/icon direction work in the ribbon
   Phase 2 notes. Every RTL/LTR change has to account for it separately.

## Options the user floated (unranked, unevaluated)

- **(a) Remove it entirely.** Cleanest, but severs a visible tie to upstream AppFlowy and raises the
  merge-conflict surface — the opposite of this fork's usual "isolate, don't rewrite core" stance.
- **(b) Make it a setting.** Keep upstream's behavior as an option, default it however the user
  prefers. The user's own leaning: *"for the sake of keeping some connection to the original package,
  perhaps it can go to settings."*
- **(c) Demote "Title" to a paragraph style.** No special title widget at all; `Title` becomes a
  style you can apply in the page body, and **the first `Title`-styled block acts as the page
  title**. This is roughly how Notion and Craft behave.
- **(d) Derive the page name automatically** — from the first content typed, or from an AI summary.
  Composable with (c): (c) decides what's *displayed*, (d) decides what the sidebar/breadcrumb shows.

## Questions to settle at the interview (not now)

- Is there a use case the user is unaware of? Worth checking what the title feeds besides display —
  sidebar name, breadcrumbs, search indexing, page references/links, exports, the backup manifest.
  **If page links or search read the title field, (a) is much more expensive than it looks.**
- If the name is derived (d), what happens when the first line later changes — does the page rename
  itself, and can the user pin a name to stop that?
- AI summarisation (d) is an **external-service call** on document content. Per `CLAUDE.md`'s privacy
  rules that is a flagged trade-off requiring an explicit decision, not a default.
- Multi-user angle: which default ships for other people, and does (c) change the on-disk document
  shape in a way that needs migration for existing pages?

## Relationship to other work

- Touches RTL work directly (the title's direction handling is one of the complaints) —
  `specs/rtl-support.md`.
- Interacts with the ribbon's paragraph-style hierarchy idea already captured in
  `specs/ribbon-menu.md` ("editable paragraph-style hierarchy à la Google Docs"). **Option (c) is
  essentially a special case of that feature** — if the style hierarchy gets built first, (c) becomes
  much cheaper. Sequence these deliberately.
