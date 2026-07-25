# Sidebar Improvements

*Spec written 2026-07-21 after the scoping interview. Status: awaiting sign-off — no code yet.*

## Background

Four sidebar UX changes requested by the user, scoped in one interview (2026-07-21). The
current sidebar renders exactly **one** space's page tree at a time, switched via a dropdown
popover on the space header; renaming lives behind the "…" menu (a centered dialog) or the
F2 hotkey (an inline edit box few people discover); deleting a page you're viewing shows a
"this page is in trash" banner with Restore/Delete-permanently buttons; and hover icons on
rows are ordered […][+] with the "+" outermost.

## Goals (the four changes, with interview decisions)

1. **Spaces spread out, not behind a dropdown.** All spaces are listed vertically in the
   sidebar (scrolling when needed), each with a caret to expand/collapse its page tree.
   - **Several spaces may be expanded at once** (Notion-style, carets independent).
   - Each space's expanded state persists across restarts (per-space storage already
     exists: `KVKeys.expandedViews` in `SpaceBloc`).
   - Each space header keeps its own "…" (space actions) and "+" (new page in that space).
   - **"New Space" moves to its own row directly below the "New Page" button at the top**
     of the sidebar (user's placement choice).
   - The old space-switcher popover (`SidebarSpaceMenu`) is retired from the header.
2. **Double-click a name to rename.** Double-clicking a page's name in the sidebar opens
   the **inline edit box on the row itself** (the existing F2 `RenameViewPopover`), not the
   centered dialog. **Applies to spaces too** (consistent inline box; spaces currently use
   their own rename dialog).
3. **Trash banner removed; trash icon shows fullness.**
   - Remove the in-page "this page is in trash" banner (`DocumentBanner`).
   - **Deleting the page you're viewing navigates away automatically** (land on a sensible
     neighboring page) — you never sit on a trashed page outside the Trash view.
   - The sidebar footer's trash icon becomes a **custom "full trash" SVG** (lid ajar,
     paper sticking out) whenever the trash contains items; the normal icon when empty.
     Requires wiring `TrashBloc` (or a lightweight listener on `TrashListener`) into
     `SidebarTrashButton`, which today doesn't know trash contents.
4. **Swap "…" and "+" so "…" is outermost** (farthest from the name, at the row's outer
   edge) on **both** pages and spaces — they have separate implementations
   (`SingleInnerViewItem` vs `SidebarSpaceHeader`), so both get the swap. RTL mirroring is
   automatic for page rows (flex order) and manual for the space header (hardcoded
   `Positioned` offsets — preserve the documented left/right swap).

## Out of scope

- Any change to the Trash *page* itself (restore/delete-permanently stay available there).
- Reordering spaces by drag, space sections/grouping, or workspace-level changes.
- The mobile sidebar (all four changes are desktop-only paths).
- Keyboard-shortcut work beyond keeping existing shortcuts functional (the broader
  shortcuts effort remains deferred per STATUS.md).

## Key design decisions & seams

- **"Current space" survives as a derived concept.** `SpaceBloc.currentSpace` today drives
  which tree renders, what `SpaceEvent.createPage` targets (the top "New Page" button),
  and the ⌘/Ctrl+O next-space cycle. With all spaces visible, **current = the space
  containing the currently open page** (user's choice for New Page targeting). The bloc
  keeps a `currentSpace`, updated when the open page changes, rather than removing the
  concept — smallest change, keeps createPage/shortcuts working.
- **Expansion state:** reuse the existing per-space map (`_setSpaceExpandStatus`); the UI
  change is surfacing *all* spaces' bools instead of only the current one
  (`SpaceState.isExpanded` → per-space lookup).
- **Navigate-away-on-delete:** on `ViewEvent.delete` of the open view (and on trashing via
  any path), select a neighbor (next sibling, else previous, else parent/space landing).
  The existing read-only guard on trashed documents stays as a safety net.
- **Inline rename for spaces:** reuse `RenameViewPopover`'s pattern; spaces rename through
  their own backend call — new small widget, not shared blindly.

## Files / interfaces likely involved

- `lib/workspace/presentation/home/menu/sidebar/space/sidebar_space.dart` — the one-space
  render loop → all-spaces list. **Core file, biggest diff.**
- `space/sidebar_space_header.dart` — caret behavior, icon swap, drop the switcher popup.
- `space/shared_widget.dart` (`CurrentSpace`, `SpacePopup`) — retired/repurposed.
- `application/sidebar/space/space_bloc.dart` — per-space expansion surfaced; currentSpace
  derivation. **Core file.**
- `menu/view/view_item.dart` — double-tap handler + icon swap. **Core, heavily
  fork-touched already (RTL) — careful, small diffs.**
- `widgets/rename_view_popover.dart` — reused for double-click; space variant added.
- `plugins/document/document_page.dart` + `plugins/document/presentation/banner.dart` —
  banner removal, navigate-away.
- `sidebar/footer/sidebar_footer.dart` (`SidebarTrashButton`) + `plugins/trash/…`
  (`TrashBloc`/`TrashListener`) — full-trash icon. New SVG asset (custom-drawn) in
  `assets/flowy_icons/`.
- `sidebar/shared/sidebar_new_page_button.dart` — "New Space" row goes below it.
- New files where possible (fork discipline): space list container widget, space inline
  rename widget, trash-state listener, the SVG.

## Multi-user readiness

Universal UI changes; no personal/machine assumptions. RTL behavior must work for LTR
users identically (mirroring is by directionality, already the sidebar convention). One
watch item: expansion-state persistence uses local KV storage — fine for any user, nothing
account-specific.

## Fork-maintenance note (explicit, per CLAUDE.md)

Changes 1 and 4 must edit core sidebar files (`sidebar_space.dart`, `space_bloc.dart`,
`view_item.dart`, `sidebar_space_header.dart`) — there is no sidecar seam for restructuring
the space list. Mitigation: new widgets in new files, minimal edits at integration points,
and the spread-spaces list built as a new widget that `sidebar_space.dart` delegates to.
Change 2 is nearly sidecar (one gesture hook + one new widget). Change 3 is a deletion
(banner) + a new listener + one navigation hook.

## Phased plan (small → large, each phase shippable and live-verified alone)

- **Phase 1 — icon swap (change 4).** Two small ordered-row edits. Verify LTR + RTL.
- **Phase 2 — double-click rename (change 2), PAGES ONLY.** Manual double-click
  detection inside the row's existing tap handler (a `GestureDetector.onDoubleTap`
  would delay every page-open by the disambiguation window; the old 200ms click
  throttle is subsumed by the 300ms double-click window). Second click opens the F2
  inline popover instead of re-opening the view.
  **Scope adjustment (found during build, 2026-07-21): the SPACE half moves to
  Phase 4** — clicking a space's name is currently owned by the space-switcher
  popover (`SpacePopup`, `clickHandler: gestureDetector`), so double-click on the
  name would fight the switcher opening on the first click. Phase 4 retires that
  popover, which is exactly what frees the name for double-click rename.
- **Phase 3 — trash (change 3).** Remove banner; navigate-away-on-delete; TrashBloc-fed
  full/empty icon with the new custom SVG. User reviews the icon in-app before we call it
  done.
  - Navigate-away reuses the EXISTING permanent-delete flow (`onDeleted` →
    `didDeleteStackWidget`: previous sibling by index, else last, else blank) — zero new
    navigation logic. A background tab holding the trashed page closes instead.
  - **Known follow-up, deliberately left:** `database_document_page.dart` (database ROW
    documents — a separate code path) still shows the old banner; same deferral as its
    direction work (STATUS.md "Next step").
- **Phase 4 — spaces spread (change 1).** The restructure: all-spaces list, independent
  carets, persisted expansion, "New Space" row below "New Page", currentSpace derived from
  the open page, switcher popover retired. Biggest phase, its own session.

## Open questions (none block Phases 1–3)

1. ⌘/Ctrl+O "switch to next space": with all spaces visible, should it cycle which space
   is *expanded/scrolled to*, or be retired? (Decide before/during Phase 4.)
2. When a page is restored from Trash, should the app navigate to it? (Nice-to-have,
   decide in Phase 3 if cheap.)
3. Exact full-trash icon design — drawn during Phase 3, user judges it live.

## How we'll know it's done

- Each phase live-verified on the real dock app (`flutter build macos --debug`, verified
  by contents), in both the user's RTL-docked layout and an LTR check.
- Tests for new logic: double-tap → rename popover; trash empty/full icon state;
  navigate-away-on-delete picks the right neighbor; multi-space expansion persistence.
- The user confirms each change matches the interview decision it came from.

## Phase 4 implementation record (built 2026-07-21, same session — key decisions)

- **SpaceBloc is UNTOUCHED** (no freezed regen, mobile unaffected). Everything is
  app-side: `sidebar_space_list.dart` + `space_list_header.dart` (new sidecars) replace
  the private `_Space` widget in `sidebar_space.dart` (core edit = a swap + deletion).
- **Expansion persistence quirk fixed in passing:** the bloc's own writer REMOVED the
  key on collapse, and absent reads as expanded — so collapse never survived a restart
  upstream. The list writes explicit `false` (read-modify-write on the same
  `KVKeys.expandedViews` map; the bloc's reader handles explicit false fine).
- **`SpaceEvent.open` is deliberately never dispatched on cross-space page opens** —
  its side effect opens the target space's FIRST page (via the `lastCreatedPage`
  listener in sidebar.dart), which would hijack navigation. The space-follow notifier
  (`switchToSpaceNotifier`) now just expands the space. ⌘O still dispatches
  `switchToNextSpace` and keeps its old meaning (next space + its first page).
- **Per-space page creation bypasses `SpaceEvent.createPage`** (it can only target
  currentSpace): `ViewBackendService.createView` with the explicit space, then
  `TabsBloc.openPlugin`. Same for the top "New Page" button, which now resolves its
  target as the space of the currently open page (via `getViewAncestors`), falling
  back to currentSpace, then the first space.
- **`ManageSpacePopup` gained an optional `space` param** (defaults to currentSpace =
  old behavior); every per-space "…" action passes its space explicitly.
- **The "…" menu Rename and double-click both use the in-place InlineRenameField** —
  the space rename dialog is retired.
- **Header mirroring model changed:** the old header mirrored with the sidebar DOCK
  side (physical Positioned offsets); the new header is a flex row like page rows, so
  it mirrors with the ambient text direction and the ··· stays outermost name-relative.
  Visual consequence for a docked-right LTR layout: the space name now sits on the
  LEFT like page names do, where the old header put it on the right. Consistent with
  page rows; user to judge live.
- **Retired-but-kept upstream files (desktop-unused now):** `sidebar_space_header.dart`
  (+ its icon-order widget test, which documents the old dock-side flip),
  `shared_widget.dart`'s `CurrentSpace`/`SpacePopup`, `sidebar_space_menu.dart`. Kept
  untouched for upstream-merge friendliness.

## Open findings (2026-07-25, session 11 — user testing)

1. **Dragging a page from one space to another does not move it.** Reported by the user during live
   use. Untriaged — not yet reproduced or root-caused. Note Phase 4 made every space visible at once,
   which is what makes cross-space dragging reachable in the first place, so this may be a
   drop-target gap that simply had no way to surface before. Check whether the drag target list is
   built per-space or assumes a single active space.

2. **Feature request — keyboard navigation between pages and spaces, from inside a page.** User's
   words: *"We need to figure out an easy way to navigate between pages and spaces using the keyboard
   even while on a page (e.g., I want to copy a paragraph from one page to the other, and do it all
   using just the keyboard easily)."* Not scoped. This is its own feature (likely a quick-switcher /
   command-palette shape rather than more arrow-key wiring) and should get its own interview and
   spec, not be bolted onto the sidebar work.

## Session Log

- **2026-07-23 (session 3 of the feature) — Phase 4 LIVE-VERIFIED by the user; 3 bugs
  found and fixed (commit `7173fe076`); the header-position question is CLOSED.**
  The user walked the checklist in their own app.
  - **Passed:** (a) every space visible, two expanded at once, **collapse survived a
    full restart** (the persistence quirk fixed in Phase 4 holds); (d) the "…" menu on a
    non-first space targets that space; (f) the trash icon flips full/empty.
  - **(e) CLOSED — no rework.** The user's verdict on the space-header name position was
    "they look fine." The Phase 4 note predicted the name would read as moved to the
    *left*; the user described it as sitting on the right and being fine either way, so
    the observation didn't match the prediction but the outcome is a pass. **Headers stay
    as built; do not revisit dock-aware headers.**
  - **Bug 1 — rename frame was a loud blue.** It used `colorScheme.primary` (the theme
    *accent*). Now `_frameColor()` derives it from `colorScheme.surface` and nudges
    lightness ±0.30 in HSL: brighter than the sidebar in dark mode, darker in light.
    Theme-derived, so it follows per-page theme overrides too. Tuning = one number.
  - **Bug 2 — click-away silently dropped renames.** The field committed only on *focus
    loss*, but most of the sidebar takes no focus when clicked (space header rows are a
    bare `GestureDetector`; empty sidebar space is inert), so no focus event fired. Only
    a click that happened to hit a focusable target saved — which produced the user's
    tell-tale report, "doesn't save the first one, doesn't save the second one, saves the
    third one." **That pattern was the diagnosis**: not flakiness, but a dependence on
    what the click happened to land on. Fixed with `TapRegion.onTapOutside`, which fires
    on any outside pointer-down regardless of focus; `_finish`'s `done` guard prevents a
    double outcome. **Proven failing-then-passing** (test fails `+4 -1` without the fix).
  - **Bug 3 — the per-space "+" menu flashed and vanished (<1s).** The trailing hover
    icons only exist while `showActions` (`onHover || onEditing`) is true, so when the
    pointer left the row to travel to the open menu, the "+" button was removed from the
    tree **and took its own popover with it**. `ViewAddButton` reports its popover state
    via `onEditing` for exactly this reason; in `space_list_header.dart` it was wired to
    `(_) {}`. **`SpaceMorePopup` wires it correctly — which is precisely why the "…" menu
    worked and "+" did not.** Generalisable lesson: *when one of two sibling controls
    misbehaves, diff them against each other before theorising.*
    - **No automated test, deliberately.** Rendering `ViewAddButton` in a widget test
      requires `PluginSandbox` in GetIt — the whole plugin registry — plus an
      `AppearanceSettingsCubit` mock. Judged more brittle than a one-line wiring fix
      warrants. Rests on inspection + the "…" consistency argument + live check.
    - **This also unblocked checklist item (c):** per-space "+" targeting was never
      broken; the menu simply couldn't be reached to test it.
  - **⌘O beep — investigated, NOT fixed, not ours.** ⌘O navigates correctly but macOS
    emits the unhandled-key beep. `hotkey_manager` registers it at `HotKeyScope.inapp`
    without consuming the native event. Provenance checked: the binding is **upstream
    code, byte-identical in `upstream/main`** (`hotkeys.dart:191-198`), untouched by this
    feature, and likely affects every AppFlowy hotkey — a shared-core (possibly
    upstream-worthy) fix, not a sidebar one. Logged in the shortcuts backlog.
  - **New roadmap item (user):** a full **icon-set revamp**, scheduled *after* ribbon
    behavior is finished, as its own scoping pass. The trash full/empty pair stays.
  - 8/8 widget tests green, analyzer clean, shipped to the dock app and content-verified
    (`_frameColor` present). **The 3 fixes shipped after the user stopped testing, so
    they are NOT yet user-verified — that is next session's first item.**

- **2026-07-21 (session 2 of the feature) — Phases 1–3 verified by the user; Phase 2
  reworked to in-place rename on feedback; Phase 4 BUILT, awaiting live verification.**
  User verdicts: icon swap "good", trash "great", rename wanted in-place instead of the
  popover → rebuilt as `InlineRenameField` (thin frame in the row, Enter commits, Esc
  cancels, focus-loss commits) used by both page rows and the new space headers.
  Phase 4 decisions recorded above. 12+3 tests green, analyzer clean (3 pre-existing
  lints in sidebar.dart untouched), shipped to the dock app, contents-verified.
- **2026-07-21 — scoping interview done, spec written.** Codebase mapped first (space
  switcher renders one tree; two rename UIs exist; trash button is blind to trash state;
  icon order confirmed "+" outermost; RTL seams inventoried). All interview decisions
  recorded above. Sign-off received same day.
