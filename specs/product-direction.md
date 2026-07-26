# What Ludwig is — product direction

**Status: the philosophy is settled and binding. The roadmap below it is a DRAFT with no
commitment** (the user's words, 2026-07-26 session 15). Read the philosophy before scoping any
feature; treat the roadmap as a list of candidates, not promises.

This document exists because the clearest statement of what this product is arrived in
conversation, and a chat log is not somewhere a decision can survive. Everything in the first
section is the user's own reasoning, recorded close to their words.

## The philosophy (user, 2026-07-26)

> *Ludwig's not about managing projects. It's about putting thoughts on the go into a piece of
> digital paper.*

Ludwig is **digital paper**. You put a thought on it. Scrape together a report. Track the sales
pipeline for the personal project. It is for the on-the-go version of a thing, not the
professional version of it.

**Ludwig should not be anybody's professional software for anything.** That is a deliberate
position, not modesty, and it is what keeps the product from sprawling:

| For the serious version of… | Use |
|---|---|
| Heavy documents | Word, Google Docs |
| Layouts | Figma |
| Print design | InDesign |
| Raster | Photoshop |
| Vector | Illustrator |

**Ludwig is where you go when you don't need any of those.** The sketch when you wanted vector.
The small drawing you wanted to add. Your signature. A video dropped in beside your lecture notes.
Article summaries for your degree, written in a closed, secure, easy environment you can reach on
the go — and later on mobile and Windows too.

### The rejected direction, and why

AppFlowy's shape — Grid, Board, Calendar, team workspaces — is the user's explicit counter-example:

> *This is a note app that understood it has no audience and/or money at note taking, so it spread
> to more of a teamwork developer's product-manager work. And I'll tell you a secret — no one likes
> these apps for this, and people rarely use it for that. It just doesn't work, it's messy, it's all
> over the place.*

The position is not "Kanban is badly built here". It is that **project management is not a problem
Ludwig is trying to solve**, so anything shaped like it is deadweight regardless of quality.

Per-feature verdicts recorded at the same time: **Kanban — useless, and this is not the place to
create it. Calendar — Google Calendar plus Slack is a better fit. Grid — undecided, no use in
mind.** See `specs/retire-non-core-surfaces.md` for what was actually done about them.

### The design rule that follows

> *I would really like to develop Ludwig through my actual needs in life, so I know exactly what
> problem I am solving each time.*

**Features come from a real, felt need, not from a category being missing.** When scoping, the
first question is which of the user's own situations the feature is for. "Competitors have one" is
not an answer, and neither is "it would round out the product". This is a genuine constraint on
what gets built, and it is the reason the roadmap below is explicitly uncommitted.

## Draft roadmap — candidates, no commitment

Recorded 2026-07-26 as *"a very rough draft of my thoughts"*. Nothing here is scoped, promised or
ordered beyond the priority list in the next section. Several would be large features in their own
right and each needs its own interview before it is anything more than a line here.

**The surfaces Ludwig might eventually hold:**

- **The page** — text, or text + images. The core, and the only one that exists today.
- **An Excalidraw board** — illustrations, org charts, mind maps. Already identified in session 12
  as a webview-embedded foreign app rather than a plugin runtime (`specs/plugin-system.md`).
- **A music-sheet writer** — for writing sheet music.
- **Study tools** — something to help students read articles and summarise classes. Deliberately
  vague; the user has not thought it through yet, and it should not be sharpened by guessing.

**Helper tools, more speculative still:**

- **Simple photo editing and manipulation** — "there's got to be an open source project we can use."
- **Meeting recording** — related to, and possibly superseding, the parked
  `specs/meeting-transcription.md` stub.

## Priority order (the user's, 2026-07-26)

This *is* committed, in the sense that it is what work should follow. Roughly a month of work.

1. **Rebrand and distribution** — `specs/distribution.md` (placeholder, not scoped) plus the Ludwig
   identity work. The user is making an icon; app identity, bundle id and data location are all
   entangled here.
2. **The page, and how it behaves** — includes `specs/no-titles.md`, still mid-interview.
3. **The pad, and how it behaves** — `specs/ephemeral-pad.md` is complete and verified; this is
   whatever comes after living with it.
4. **Folders — behaviour and capabilities** — `specs/folder.md` Phase 2 onward.
5. **Ribbon capabilities** — `specs/ribbon-menu.md`; phases 1–5 are done, so this is what's next.
6. **Excalidraw.**
7. *"Then we see."*

**Note what is not in the top six:** the restore redesign (Phases 3–5 outstanding), RTL bidi
arrow-keys, and tables. They are live specs with real work left; they are simply not what the user
wants next. Do not treat their absence as cancellation, and do not quietly promote them because
they happen to be half-built.
