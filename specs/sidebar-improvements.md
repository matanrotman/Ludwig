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

## Session Log

- **2026-07-21 — scoping interview done, spec written.** Codebase mapped first (space
  switcher renders one tree; two rename UIs exist; trash button is blind to trash state;
  icon order confirmed "+" outermost; RTL seams inventoried). All interview decisions
  recorded above. Awaiting sign-off; no code written.
