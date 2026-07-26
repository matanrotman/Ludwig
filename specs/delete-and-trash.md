# Delete and trash — nothing disappears without saying so

*Status: scoped 2026-07-26 (session 13), awaiting sign-off. Supersedes follow-up (a) in
`specs/folder.md`, which raised the folder half of this.*

## Background

Session 12 ended with a data-loss scare. A page (`מעבר על דו״ח קלוד…`) vanished and had to be
recovered by hand from a Google Drive snapshot. The trigger was known — its **parent** page was
deleted — but the mechanism was not, and "deletes are supposed to be recoverable" made it look
like the trash system had failed outright.

Session 13 reproduced it at the Rust event-handler layer (the same code path the app drives), in a
throwaway workspace. Three findings, all proven, none theorised:

1. **Deleting a page that has children puts only the parent in trash.** The children are not in
   trash, and are not returned by `GetAllViews` either — the query that deliberately includes
   trashed *and* orphaned views. They are invisible to every list the app can render.
2. **They are not actually deleted.** Restoring the parent brings the whole branch back. So the
   "just deleted" state is recoverable — through a route the UI never mentions.
3. **Permanently deleting that parent from trash orphans the children.** Their data survives, but
   they now point at a parent that no longer exists: unreachable from the sidebar, absent from
   trash, with no way back through the UI. **This is the state the lost page was in.**

### Root cause, in the code

Both in `frontend/rust-lib/flowy-folder/src/manager.rs`, both **upstream AppFlowy code**:

- `move_view_to_trash` (line ~841). Its own doc comment says *"When the view is moved to trash, all
  the child views will be moved to trash as well."* The code does
  `folder.add_trash_view_ids(vec![view_id])` — **one id, the parent's**. The comment describes an
  intention that was never implemented. Children stop being reachable only as a side effect of
  their parent carrying the trash flag.
- `delete_trash` (line ~2032). Permanent delete does `folder.delete_views(vec![view_id])` — again
  just the one. Children are neither deleted, nor trashed, nor re-parented. They are stranded.

**Delete is depth-1 everywhere, while the UI presents it as removing the whole branch.** The gap
between those two is where the page went.

This affects every AppFlowy user, not just this fork.

## Goals

1. **It must be impossible to orphan a view.** Whatever the UI does, the data layer never leaves a
   view pointing at a parent that isn't there. This is the non-negotiable half.
2. **Deleting something that contains things asks first**, tells the truth about how much is
   inside, and offers a way to keep the contents.
3. **Restore restores what was deleted** — the whole branch, not a stump.

## Non-goals / out of scope

- **The trash screen's design.** The user has said trash is getting its own redesign, so what the
  trash list *shows* (one row per branch, labels, counts, grouping) is deliberately not decided
  here. This spec only guarantees the trash *data* is correct and complete; presentation is the
  redesign's problem. **Do not let a trash-list rendering question block this work.**
- **Restore-with-conflicts.** Restoring a branch whose original parent has since been deleted is
  possible in principle; not scoped here because goal 1 makes it unreachable in practice.
- **Undo (⌘Z) for deletion.** Separate mechanism, separate conversation.
- **Bulk / multi-select delete.** The sidebar deletes one thing at a time today.

## Decisions (user, session 13)

| # | Question | Decision |
|---|---|---|
| D1 | What does the dialog count? | **Everything inside, at any depth.** Children, grandchildren, all of it — the number must never understate the loss. |
| D2 | Where does "move them elsewhere" put things? | **One destination for all of them, user-picked**, via the existing `MovePageMenu`. Each direct child moves there and keeps its own sub-pages with it. |
| D3 | Which containers ask first? | **Pages, folders, and spaces — anything with children.** One rule, no exceptions. Consistent with `capture-and-structure.md` decision 1 (a space IS a top-level folder), so treating them differently here would contradict the model. |
| D4 | "Don't ask again"? | **No. Always ask.** Deleting a container is rare; a suppression checkbox is how someone re-creates this exact silent-loss problem for themselves later. |
| D5 | Fix upstream too? | **Fix ours now, decide upstream later.** Noted as upstream-worthy; two PRs are already stalled at AppFlowy's first-contributor CI gate, so there's no appetite for a third right now. |

## The dialog, in detail

Appears **only when the target has at least one descendant**. A leaf page deletes exactly as it
does today — no new friction on the common case.

```
Delete "Q3 planning"?

It contains 7 pages.

[ Cancel ]   [ Move them elsewhere… ]   [ Delete everything ]
```

- **Count** is the full descendant count (D1). Singular/plural handled; the string is
  translatable and must read correctly in Hebrew (this fork's primary language).
- **"Move them elsewhere…"** opens the existing `MovePageMenu` picker. On confirm: every **direct
  child** is re-parented to the chosen destination (their own subtrees ride along), *then* the now-
  empty target is deleted. Cancelling the picker returns to the dialog, not to nothing.
- **"Delete everything"** trashes the whole branch.
- The existing published-page warning (`ViewBackendService.containPublishedPage` →
  `showConfirmDeletionDialog`) must still fire; the two conditions can both be true, and the
  dialog should say both rather than one silently replacing the other.
- **RTL:** the dialog follows the app layout direction like every other dialog in this fork.

## Files and interfaces likely involved

**Rust (the data fix — shared/core, unavoidable):**
- `frontend/rust-lib/flowy-folder/src/manager.rs` — `move_view_to_trash` (trash the branch),
  `delete_trash` (delete the branch). These are shared upstream files; the edit is small and
  surgical, and is exactly the kind of core touch `CLAUDE.md` says to name explicitly. **There is
  no sidecar option here** — the bug is in upstream's own function bodies.
- Descendant collection already exists in the same file (`unfavorite_view_and_decendants` uses
  `folder.get_views_belong_to`); the recursive walk should be factored out and shared rather than
  written twice.

**Dart (the dialog — new sidecar file where possible):**
- New: `workspace/presentation/home/menu/view/delete_with_children_dialog.dart` (sidecar).
- Touched: `workspace/presentation/home/menu/view/view_item.dart` — the
  `ViewMoreActionType.delete` branch (~line 888), which already contains the published-page
  confirm, so this is one more condition in an existing decision point.
- Reused, not modified: `workspace/presentation/home/menu/sidebar/move_to/move_page_menu.dart`.
- Space deletion path (`sidebar/space/…`) needs the same hook — confirm during Phase 2 whether it
  routes through `view_item.dart` or its own action handler.
- Translations: `assets/translations/en.json` + `he.json`.

## Phased plan

**Phase 1 — the data fix (no UI).** `move_view_to_trash` and `delete_trash` operate on the whole
branch. Orphaning becomes impossible regardless of what the UI does. Ships independently and is
worth shipping alone. Proven by the existing reproduction test, converted from a
bug-demonstrating test into a passing regression test.

**Phase 2 — the dialog.** Descendant count, three buttons, the `MovePageMenu` hand-off, the
published-page interaction. Wired into pages, folders and spaces.

**Phase 3 — live verification with the user.** In a scratch space only, never real pages: delete a
leaf (no dialog), delete a page with one child, delete a folder with a nested branch, use "move
elsewhere", then restore from trash and confirm the branch comes back whole.

## How we'll know it's done

- The reproduction test at
  `frontend/rust-lib/event-integration-test/tests/folder/local_test/` passes with the *correct*
  assertions: after deleting a parent, every descendant is in the trash section; after permanently
  deleting it, no view anywhere has a missing parent.
- A test proves the orphan case specifically: permanently delete a parent → `GetAllViews` contains
  no view whose `parent_view_id` names a view that no longer exists.
- Deleting a leaf page shows no dialog (no new friction).
- Deleting a page/folder/space with children shows the count, and the count matches the real
  descendant total at any depth.
- "Move them elsewhere" leaves every rescued page reachable in the sidebar afterwards.
- Restoring a trashed branch from trash brings back every page in it.
- The user has done Phase 3 in a scratch space and confirmed it.

## Multi-user readiness

Entirely general — no personal, machine-specific or account-specific assumption anywhere in this
feature. The Rust half is a straight bug fix to upstream behaviour and would benefit every
AppFlowy user; the dialog is ordinary UI. **Upstream-worthy (D5), deferred by choice, not by
design.**

## Open questions

1. **Does deleting a space route through the same action handler as a page?** Needs a read of the
   space action code during Phase 2. If it doesn't, the hook lands in two places rather than one.
2. **Database views.** `delete_trash` calls a per-layout handler that deletes the underlying
   database when a database view is permanently deleted. Deleting a branch containing database
   views must call that handler for **each** deleted view, not just the root — otherwise Phase 1
   fixes the orphan bug while leaving orphaned *databases*. Verify before shipping Phase 1.
3. **Trash screen redesign** — explicitly out of scope here, but it is now a known upcoming
   feature and needs its own spec.

## Session Log

### 2026-07-26 (session 13) — reproduced, scoped, Phases 1 and 2 built

Reproduced the session-12 data-loss bug at the Rust event-handler layer (three tests, throwaway
workspace, no real data touched), pinned the root cause, scoped the fix with the user (five
decisions, table above), then built both phases. **Phase 3 — the user's live pass — is what
remains.**

**Implementation note that changed the plan: the codebase already expands a trashed root to its
whole branch — but only on the READ side.** `get_all_trash_ids` (manager.rs) walks a trashed
view's descendants via `get_all_child_view_ids`, which is why the children vanish from every list
the moment their parent is trashed, and why restoring the parent already restored the whole
branch. The scoping conversation had assumed the fix was to write every descendant into the trash
*section*; that turned out to be the wrong half. Doing it would have broken restore (descendants
would stay flagged as trashed after the root was un-flagged) and turned one deleted page into N
trash rows. **The asymmetry was on the delete side alone**, so that is the only place that
changed. A comment now sits on `move_view_to_trash`'s `add_trash_view_ids` call explaining why
adding descendants there would be a regression, not a fix.

**Phase 1 — the data fix (`flowy-folder/src/manager.rs`):**
- `delete_trash` now collects the branch with `get_view_recursively` **before** deleting anything
  (once the root's entry is gone the descendants can't be walked to), removes every branch id from
  both the trash section and the view store, and calls the per-layout resource handler for **each**
  view in the branch — closing open question 2 (a branch containing database views would otherwise
  have traded orphaned pages for orphaned databases). Handler failures are logged and the loop
  continues; the folder entries are already gone, so aborting would strand the rest. Callers
  already discarded the error, so no error semantics were lost.
- `unfavorite_view_and_decendants` genuinely walks the branch now. It used `get_views_belong_to`,
  which returns only *direct* children despite the function's name — so a favourited grandchild
  stayed in the favourites list pointing at a page that could no longer be opened. Small
  latent bug, same class as the main one, fixed while in there.

**Phase 2 — the dialog:** new sidecar `delete_with_children_dialog.dart`, wired into all three
live delete entry points (sidebar page/folder `view_item.dart`, the page's top-bar menu
`common_view_action.dart`, and the space header `space_list_header.dart`). `sidebar_space_header.dart`
was confirmed retired (nothing imports it) and deliberately left alone. Descendant counting reuses
`ViewBackendService.getAllChildViews`, which the published-page check on the same path already
used — no new backend surface. "Move them elsewhere" reuses `MovePageMenu` and re-parents each
direct child (subtrees ride along) via `moveViewV2`, and **only deletes once every child moved** —
a failed rescue must not fall through to deleting what was being rescued.

**Tests:**
- `event-integration-test/tests/folder/local_test/delete_branch_test.rs` — 5 tests, **proven
  failing-then-passing**: 3 fail against the pre-fix code, all 5 pass after. The other 2 pass
  either way, correctly, because hiding and restoring were already right. Includes a reusable
  `assert_no_orphans` invariant check.
- `test/widget_test/delete_with_children_dialog_test.dart` — 11 tests on what the dialog says,
  offers and returns. **These caught a real layout bug**: three labelled buttons overflowed the
  dialog in a `Row`, so it is now a `Wrap` (translations vary enough in length that this would
  have bitten in Hebrew regardless).
- Repaired `test/widget_test/space_list_header_test.dart`, which had been red since session 12 —
  it didn't compile (`onCreateFolder` became required) and its `MockSpaceBloc` returned a null
  state to the temp-space check. Pre-existing, unrelated, fixed because a permanently-red file is
  a hole in the net.

**Known gaps, deliberate:**
- **"Move them elsewhere" is hidden on local (non-server) workspaces**, matching upstream's
  existing gate on the Move to action. Offering a rescue that can't run would be worse than not
  offering it. Multi-user note: this is the one place a non-cloud user sees a reduced dialog.
- **Restoring a branch also un-trashes a descendant that had been deleted separately first.**
  Recovering slightly too much, in the safe direction; not worth machinery to distinguish.
- Trash-list presentation untouched, per the user — it is getting its own redesign.

**Live pass (Phase 3) — all five checks PASSED**, first time through: no dialog on a leaf, correct
count on a page with one child, full-depth count on a nested folder, "move them elsewhere" left the
rescued pages reachable, and restoring a deleted branch brought back every level. Two visual
corrections came out of it:
- **The dialog wrapped its buttons.** Three labelled buttons didn't fit at 460pt, so "Delete
  everything" was stranded alone on a second row. Widened to **640pt** so all three sit on one
  right-aligned row (user's choice). The `Wrap` stays as a safety net for translations longer than
  English or Hebrew — it renders identically to a `Row` when everything fits.
- **The destructive button is now outlined with red text**, not a solid red fill (user's choice).
  All three choices here are legitimate; the irreversible one should be *marked*, not shouted. A
  filled red button reads as "this is what you came to do" — the wrong suggestion in a dialog whose
  entire purpose is to slow that down.

**Shipped:** Rust core rebuilt, dock app rebuilt in place, verified by contents — test-binding refs
**0**, `runAppFlowy` **31**, `showDeleteViewDialog` **5**, `deleteWithChildren` **19**,
`moveThemElsewhere` **8**, and the Rust fix's own log strings present in the linked dylib. No stray
test data-path pref (no integration tests were run this session).
