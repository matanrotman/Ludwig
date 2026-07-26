# The ephemeral pad — the app opens on nothing

*Status: scoped 2026-07-26 (session 13), awaiting sign-off. Promised by
`specs/capture-and-structure.md` → "Deferred, but part of the model: the ephemeral pad", which
this replaces as the authoritative document.*

## Background

`capture-and-structure.md` decision 3 removed the *destination* decision from capture: the top New
Page button always targets Temporary, so you never choose where a thought goes. This feature
removes the remaining decision — **the act of creation itself.**

The user's framing, from 2026-07-25: the app should always open on an **open, ephemeral writing pad
that is "nothing"** — not a page, not a sidebar row, not a file. Only when something is written into
it does it *become* a page. *"From chaos and nothing into context and structure"*; the experience
has to allow spontaneity.

**This is one feature with two halves, deliberately built together.** The pad is the destination;
**clicking empty sidebar space to deselect the open page** is the gesture that makes it reachable
in the middle of working, rather than only as a launch state. `specs/folder.md` follow-up 5 raised
that gesture and blocked it precisely because there was nothing to return *to*.

## Goals

1. **Writing costs nothing.** No page to create, no place to choose, no name to invent.
2. **Nothing written is ever lost**, including across a crash.
3. **The pad is always blank and always ready** — it is a pad, not a document.
4. **Getting back to it is one gesture**, from anywhere.

## Non-goals / out of scope

- **A second inbox.** The pad holds nothing over time; content leaves it immediately for Temporary.
  If it accumulated, it would become a place writing hides — and the one place not in the sidebar.
- **Multiple pads.** Exactly one exists.
- **Pad-specific formatting or features.** It is an ordinary editor on an ordinary page.
- **Changing Temporary.** `specs/temp-space.md` is complete and unchanged; the pad simply produces
  pages that land there, which is what Temporary already exists for.
- **Mobile.** Desktop only for now; the launch and sidebar-gesture behaviour both assume it.

## Decisions (user, session 13)

| # | Question | Decision |
|---|---|---|
| D1 | Crash before the pad becomes a page | **Kept.** The pad is backed by a real page, saved continuously like any other. Nothing typed can be lost. |
| D2 | What promotes the pad to a page | **The first real character, paste or image.** Whitespace and stray keypresses don't count, so Temporary never fills with junk. |
| D3 | Coming back after writing | **A fresh empty pad.** What you wrote lives on as a page in Temporary. Tear off the sheet; the pad is blank again. |
| D4 | The sidebar gesture | **Clicking empty sidebar space always returns you to the pad.** It is navigation, not a destructive act — nothing is lost, so it needs no guard. |
| D5 | On launch | **Always the pad.** The app opens on nothing. This deliberately drops "reopen the page I last had open"; that page is one click away. |
| D6 | Name of the promoted page | **Its first line, Apple Notes style**, tracking edits to that line until a real title is set. |
| D7 | The empty pad's appearance | **Bare** — a blank sheet and a cursor. No title field, no placeholder, no buttons. |
| D8 | The top New Page button | **Opens the pad** instead of creating a page. One capture route, not two. |
| D9 | The pad and tabs | **The pad can never be open in two tabs at once.** Asking for it while it is already open focuses the tab that has it. |
| D10 | Emptying a promoted pad | **While you are still on it, it is still the pad.** Type (it promotes), delete it all again, and it demotes — the sidebar row goes away. Promotion only becomes final when you navigate away. |
| D11 | The pad's own look | **The pad gets its own page colour, theme and margins**, like any page. Each **new pad starts from the defaults** — the look does not carry forward. |
| D12 | The pad and search | **The pad must not be findable before it promotes.** It is not a page yet, so it must not appear in search, recent views, or any "where was I" surface. |

## ⚠️ The main technical risk, and the design that avoids it

The obvious implementation — an in-memory buffer that becomes a real page on the first keystroke —
requires **swapping the editor from a buffer to a real page's editor mid-keystroke**. This fork has
been bitten by exactly that failure mode twice, and both times it presented as a mystery:

- `PageThemeScope` returned its child bare in one case and wrapped in another, changing the widget
  **tree shape**, which remounted the editor and dropped keyboard focus (session 4; reported as
  "the keyboard is disabled").
- The in-document title seeded itself once from a `ViewPB` captured at open, and a paste that
  rebuilt the header re-seeded it from stale data (session 11's title bug, and the cover bug in
  session 12 — the same root cause twice).

A swap on the first character would remount the editor **while the user is typing into it**, which
is the worst possible moment, and would also have to re-deliver the keystroke that triggered it.

**So: don't swap.** Recommended design —

> **The pad is a real, ordinary page that already exists, flagged as the pad and filtered out of
> the sidebar. On promotion it stops being the pad — the flag is cleared, so it simply appears in
> Temporary where it already was — and a fresh pad page is created for next time.**

Nothing remounts, because the editor was always editing a real page. Promotion is a **flag change
plus a name**, not a content migration. There is exactly one pad view at any moment, so no orphans
accumulate and there is no per-launch churn beyond one create at the moment of promotion.

The flag follows the fork's existing convention — a key in `View.extra`, like `is_space`,
`is_folder` and `is_temporary` — and is resolved the same way (`TemporarySpace` is the model to
copy, including its "identify by flag, never by name" lesson).

**Consequence to accept honestly:** the pad is slightly less "nothing" in the plumbing than the
idea suggests. On screen it is exactly nothing, which is what was asked for. The alternative buys
purity at the price of the two most expensive bug classes this fork has hit.

## Files and interfaces likely involved

- **New sidecar** `ephemeral_pad.dart`: resolve/create the pad view, the flag, promotion.
- **Sidebar filtering**: the pad must not render in Temporary. `ViewItem` already takes a
  `shouldIgnoreView` callback — check whether the space's child list honours it before assuming.
- **Promotion trigger**: the document's change stream; must distinguish "first real content" from
  whitespace (D2).
- **Naming**: first-line-as-title (D6). Related but distinct from the existing title/name sync —
  read session 11's title fix before touching this, because the stale-`ViewPB` trap lives here.
- **Launch** (D5): wherever `MenuSharedState.latestOpenView` drives what opens.
- **The gesture** (D4): a tap target on the sidebar's empty area. Note session 7's lesson — most
  of the sidebar takes no focus when clicked, which is why the rename fix needed a `TapRegion`.
- **New Page button** (D8): its current always-Temporary behaviour is `capture-and-structure.md`
  decision 3; this refines it, and the spec text there should be updated rather than contradicted.
- **Temporary's `(n)` count**: must not count the pad. Likely the first thing to break.
- **Tabs** (D9): `TabsBloc` — opening the pad must focus an existing pad tab rather than add one.
- **Search / recent exclusion** (D12): `flowy-search` indexing plus the recent-views surfaces. The
  pad flag is the filter; the work is finding every place that needs it.

## Phased plan

**Phase 1 — the pad exists.** Pad view + flag + sidebar filtering + always-open-on-pad (D5, D7).
No promotion yet: the pad is a scratch page that never leaves. Already useful, and it proves the
filtering and launch behaviour in isolation.

**Phase 2 — promotion.** First-real-content detection (D2), flag clearing, fresh pad creation
(D3), first-line naming (D6), demote-on-empty while still on the pad (D10), and carrying the pad's
look forward (D11).

**Phase 3 — the gesture.** Click empty sidebar space → pad (D4). Unblocks `folder.md` follow-up 5.

**Phase 4 — the New Page button** (D8), plus updating `capture-and-structure.md` decision 3.

**Phase 5 — live verification**, including the two failure modes above: type continuously across
the promotion moment and confirm **no keystroke is lost and focus never moves**. Also judge the
D10 sidebar flicker on the real thing.

## How we'll know it's done

- Launching the app shows a blank pad with a cursor, and no sidebar row for it.
- Typing a character promotes it: it appears in Temporary named after its first line, **without
  the editor losing focus or dropping a character**. This is the acceptance test that matters.
- Typing only spaces, then leaving, creates nothing.
- After promotion the pad is blank again, and the promoted page is intact in Temporary.
- Force-quitting mid-sentence loses nothing.
- Clicking empty sidebar space from any page returns to the pad; the page left behind is unchanged.
- Temporary's `(n)` never counts the pad.
- Exactly one pad view exists — verifiable in the folder data, not just on screen.
- The pad is never open in two tabs (D9).
- Searching for text that is in the un-promoted pad finds **nothing** (D12).
- A page colour set on the pad is **gone** on the next pad, and still there on the promoted page (D11).
- Typing then deleting everything, without navigating away, leaves **nothing** in Temporary (D10).
- Navigating away after typing makes the page permanent, even if it is later emptied.

## Multi-user readiness

General; no personal, machine- or account-specific assumptions. Desktop-only for now, and the
launch behaviour (D5) is a product decision others might not want — worth keeping the "what opens
on launch" resolution in one place so it could become a setting without restructuring.

## Promotion is reversible until you leave (D10) — and what that costs

D10 makes promotion **provisional**: the pad promotes on the first real character, demotes if you
empty it again, and only becomes permanent when you navigate away. This is better than the version
first scoped — it means an emptied pad never leaves an empty page behind in Temporary, without
anything being silently deleted (the thing `specs/delete-and-trash.md` just spent a session
removing). Nothing is destroyed on demotion because the view is the same view throughout; only the
flag moves.

**⚠️ The cost to watch in live testing: sidebar flicker.** A row appears in Temporary on the first
character and disappears when you delete back to empty. Type-and-delete while thinking, and the
sidebar twitches. Two mitigations if it proves annoying, neither committed to yet:

- **Debounce the sidebar row** — promote the *data* immediately (so nothing is at risk) but delay
  the row's appearance a beat, so a quick correction never shows one.
- **Promote on first character, but only demote on a deliberate empty** — e.g. select-all-delete
  rather than backspacing to nothing. More rules to hold in your head; likely worse.

Decide from the real thing, not from here.

## Where the pad's look lives (D11)

The pad carries per-page settings in `View.extra` like any page, alongside the pad flag. **A new pad
starts from the defaults** (user, 2026-07-26): the look you gave one pad does not follow you into the
next one. A pad is a fresh sheet in every sense.

Two consequences worth stating, because neither is a bug:

- **The page you just promoted keeps the look you gave it.** Unavoidable and correct — it is the same
  view, and the look is part of the page you wrote.
- **Styling the pad is therefore a per-sheet act, not a preference.** If a persistent "this is how my
  pad always looks" is ever wanted, that is a different feature (a stored default applied at pad
  creation) and should be asked for as one rather than grown into.

Everything stays in `View.extra`. No second place for this to live, and nothing to migrate.

## Open questions

None outstanding. All four raised at scoping were answered by the user on 2026-07-26 (D9–D12, plus
the D11 amendment).

Two **watch items** carried into the build rather than left as questions:

1. **First-line naming and RTL** (Phase 2). The first line may be Hebrew; sidebar name rendering
   already has direction handling worth re-checking rather than assuming.
2. **D12's filtering points are not all in one place.** The pad must be excluded from search, recent
   views and `latestOpenView`, and those are separate call sites. Missing one would leak a
   not-yet-a-page into a surface that implies it is one — worth a deliberate sweep rather than
   fixing them as they are noticed.

## Session Log

### 2026-07-26 (session 13) — scoped

Interviewed and scoped; eight decisions taken (table above). The substantive addition beyond the
interview is the implementation design: the pad is a **real page flagged and filtered**, not an
in-memory buffer, specifically to avoid remounting the editor mid-keystroke — the failure mode
behind session 4's "keyboard disabled" report and session 11's title bug.

The four open questions were then answered by the user the same day, adding D9–D11. D10 (promotion
stays provisional until you navigate away) is a genuine improvement on the original scope and
removes the "empty page left in Temporary" case entirely; its one cost — sidebar flicker while
type-and-deleting — is written up above to be judged live rather than guessed at. D11's follow-on
question (does a *new* pad inherit the look?) was not asked; it was proposed as "carried forward",
flagged for correction, and the user **corrected it the same day: reset each time**. D12 (never
findable before promotion) closed the last open question. No open questions remain. Not yet built.

### 2026-07-26 (session 13, later) — open questions closed

The user answered all four the same day, adding D9–D12 and amending D11:

- **D9** the pad can never be open in two tabs.
- **D10** promotion is provisional until you navigate away — a genuine improvement on the original
  scope, since it removes the "empty page left in Temporary" case without silently deleting
  anything. Its cost (sidebar flicker while type-and-deleting) is written up above with two possible
  mitigations, to be judged on the real thing.
- **D11 amended.** It was proposed that a new pad inherit the promoted one's look, flagged as a
  judgment call; the user corrected it to **reset each time**. A pad is a fresh sheet in every sense.
- **D12** the pad must not be findable before it promotes — no search, no recent views, no
  "where was I".

**No open questions remain.** Two watch items carried into the build: RTL first-line naming, and the
fact that D12's filtering points are spread across several call sites and need a deliberate sweep
rather than being fixed as they are noticed.
