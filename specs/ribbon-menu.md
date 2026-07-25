# Ribbon Menu

## Background — why this exists
The user wants a Word-style **ribbon**: a tabbed formatting strip pinned above the page, replacing the floating toolbar that appears on text selection. The architecture question this raised ("can it be a plugin?") was investigated and settled in `specs/plugin-system.md` on 2026-07-17: **no plugin system will be built; the ribbon is a sidecar module** — new files behind a feature flag, with a small, marked budget of edits to AppFlowy's own files. That decision is closed; this spec is about *what the ribbon is*, not how it plugs in.

The button inventory is the user's own, written in their AppFlowy page "Stuff to put into the ribbon" and read directly from the app during the 2026-07-19 scoping interview. It is deliberately **not** a copy of Word's ribbon.

## Goals
1. A tabbed ribbon that makes AppFlowy's formatting reachable without selecting text first.
2. Give the user's full intended shape a home immediately — including capabilities that don't exist yet — so the ribbon is a visible roadmap rather than a sparse strip.
3. Add **per-page RTL/LTR direction**, the single most-wanted capability, which the ribbon finally gives a natural home.
4. Stay a sidecar: minimal, marked touches to core files so upstream merges stay cheap.

## Decisions from the scoping interview (2026-07-19)
- **Tabbed**, not a single strip. **Four tabs: Content, Page, Elements, Tools.** The user's source page has five sections; **Text + Paragraph merge into "Content"** (~30 buttons — needs internal visual grouping to stay legible; treated as a build-time design detail).
- **Collapsible, remembered globally** (one state for the whole app, persisted across restarts). Collapse via **a chevron button on the strip** *and* **a keyboard shortcut**.
- **The ribbon replaces the floating selection toolbar** — but a **settings toggle** brings the floating toolbar back. (The removal point is a single clean branch, `editor_page.dart:437-481`, so both paths are cheap.)
- **Unbuilt capabilities appear as visibly disabled buttons** with a "coming soon" tooltip. The user sees the full intended shape from day one; each later session lights one up.
- **Sequencing: build the frame first**, wire up everything that already works, then fill in missing capabilities session by session.
- **Every button's tooltip shows its name AND its keyboard shortcut.** Shortcuts are registered in AppFlowy's existing rebindable shortcuts system (so they appear in Settings → Shortcuts and can be changed), not hardcoded. This shapes the button component from the start — retrofitting it later would be expensive.
- **Right-click menu (phase 2 of the feature): context-aware per element** — a table offers table actions, an image offers image actions, text offers text actions.
- **Do not mimic Word's button set.** The user's list governs.
- **Desktop-only** (mobile keeps its own toolbar system, untouched). **Mirrors in RTL.**

## The button inventory, with real availability
Audited against both the app and the editor fork on 2026-07-19 (file:line evidence in the session log's audit). This is the honest basis for sequencing — roughly 21 items work today, 7 are partly there, and 15 do not exist.

### Content tab
| Button | State | Note |
|---|---|---|
| Cut / Copy / Paste | ✅ exists | custom commands + context menu |
| Font selection | ✅ exists | toolbar ⋯ → Font, writes `fontFamily` on selection |
| Font colour / Highlight colour | ✅ exists | dedicated toolbar items |
| Bold / Italic / Underline | ✅ exists | `customMarkdownFormatItems` |
| Strikethrough | ✅ exists | toolbar ⋯ + Cmd+Shift+S |
| Link | ✅ exists | dedicated toolbar item |
| Bullets / Numbers / Multilevel list | ✅ exists | slash menu + markdown + Tab/Shift+Tab |
| Align left / centre / right | ✅ exists | align dropdown |
| Increase / decrease indent | ✅ exists | keyboard only today — ribbon gives it a button |
| RTL / LTR text direction | ✅ exists | fork items, currently hidden behind a Settings → Appearance toggle |
| Font size (per selection) | ⚠️ partial | attribute exists in the fork; **nothing writes it** |
| Line & paragraph spacing | ⚠️ partial | line spacing is mobile-page-style only; desktop hardcodes 1.4. Paragraph spacing missing entirely |
| Sentence case | ❌ missing | small |
| Clear formatting | ❌ missing | small |
| Justify | ❌ missing | small; only 3 align values exist |
| Superscript / Subscript | ❌ missing | **needs a new delta attribute in the editor fork** |
| Footnote | ❌ missing | **needs a new delta attribute in the editor fork** |
| Text box | ❌ missing | **large** — needs absolute positioning the flow layout doesn't support |

### Page tab
| Button | State | Note |
|---|---|---|
| Table of contents | ✅ exists | the "Outline" block |
| **RTL / LTR page direction** | ⚠️ partial | **the headline item — see below** |
| Page colour | ⚠️ partial | only *covers* exist; no page-body colour |
| Margins | ⚠️ partial | only a document-width preference |
| Show/hide ruler | ❌ missing | no ruler concept at all |

### Elements tab
| Button | State | Note |
|---|---|---|
| Table | ✅ exists | slash menu |
| Image | ✅ exists | slash menu, drag-drop, paste |
| Equation | ✅ exists | block + inline (Cmd+Shift+E) |
| Video | ⚠️ partial | renders legacy blocks; **no insertion path, no player** |
| Audio | ⚠️ partial | generic file attachment only; no audio block or player |
| Drawing / Diagram / Chart | ❌ missing | **large** — each needs a new block type and rendering surface |

### Tools tab
| Button | State | Note |
|---|---|---|
| Publish page | ✅ exists | Share → Publish |
| Light/Dark mode | ✅ exists | settings only — ribbon adds the one-click toggle |
| Translate | ❌ missing | **large**, external service; AI infrastructure is the natural host |
| Transcribe / Record | ❌ missing | **large**, and already their own feature — `specs/meeting-transcription.md` |

### Per-page RTL/LTR — cheaper than expected
The audit's most useful finding. `defaultTextDirection` is **already read per-document** through `DocumentAppearanceCubit` (`application/document_appearance_cubit.dart:89-91,146`) — but persisted in one global SharedPreferences value set from app-wide settings. So per-page direction is **changing where that value is stored**, not building a new system. The per-page storage seam already exists: `View.extra`, a JSON settings blob (`view_ext.dart:28-53`). The RTL/LTR *buttons* also already exist in the fork (`text_direction_toolbar_items.dart:6-17`), currently gated behind Settings → Appearance → "Enable RTL toolbar items" (`editor_page.dart:518-526`).
Known caveat from the earlier investigation: the page-style bloc lives under `lib/mobile/`, so desktop needs its own read path.

## What's in scope (Phase 1)
1. The tabbed ribbon frame: four tabs, pinned above the editor, desktop-only, behind a `ribbonMenu` feature flag.
2. Collapse/expand via chevron + registered keyboard shortcut, state persisted globally.
3. A reusable ribbon-button component with **tooltip = name + shortcut**, and a disabled state with a "coming soon" tooltip.
4. Every ✅ item wired to its existing command.
5. Every ⚠️ and ❌ item present as a **disabled** button, so the full shape is visible.
6. RTL mirroring of the whole strip.
7. Floating toolbar suppressed by default, restorable via a new settings toggle.

## Out of scope
- **Copying Word's button set** — the user's list governs. No styles gallery, no format painter.
- **A user-customizable ribbon** (choosing/reordering buttons) — explicitly fenced off.
- **Moving find/replace** into the ribbon.
- **Mobile** — untouched; it has its own toolbar system.
- Implementing the ❌ *large* features (text box, drawing, diagram, chart, translate, transcribe, record) — they get disabled buttons and their own future specs.

## Phased plan
- **Phase 1 — the frame.** Everything in "in scope" above. Ends with a usable ribbon showing the complete intended shape.
- **Phase 2 — per-page RTL/LTR.** The most-wanted capability and among the cheapest. Move direction storage to `View.extra`, add the desktop read path, wire the Page tab buttons.
- **Phase 3 — the small app-side gaps.** Clear formatting, change case, paragraph spacing **and line height** (both per paragraph). ~~justify~~ — moved to Phase 4, see "Phase 3 scoping" below. Line height moved *in* from Phase 5: it shares a seam with paragraph spacing and splitting them would mean doing the same work twice.
- **Phase 4 — the fork-crossing gaps.** Superscript, subscript, footnote, **and justify** — each needs a fork change, a fork commit, and a pin re-sync. Grouped so there's one fork round-trip, not four.
- **Phase 5 — the partials.** Font size per selection, ~~desktop line spacing~~ (moved to Phase 3), page colour, margins, ruler.
- **Phase 6 — the context-aware right-click menu.** Needs the fork's context-menu widget rebuilt (today's is primitive: no icons, no submenus, no screen-edge flip). Mirror upstream 6.1.0's "context menu builder" API shape (PR #1152) so a future merge collapses cleanly.
- **Not scheduled:** the large Elements/Tools features, each needing its own spec.

## Files / interfaces likely involved
All verified 2026-07-17 (`specs/plugin-system.md` → "Architecture facts"), unchanged as of this spec.
- **Insertion point:** the `Column` at `lib/plugins/document/document_page.dart:228-235` — a ribbon is one more child above `Expanded(child: editor)`. The deleted-page banner at `:230-232` is the exact pinned-strip precedent. **Do not** use the editor's `header:` param — it scrolls away with the document.
- **Floating toolbar gate:** `lib/plugins/document/presentation/editor_page.dart:437-481` (items at `:97-117`). App-side; **zero editor-fork changes needed to remove it.**
- **Re-hosting buttons:** `ToolbarItem.builder` (fork `lib/src/render/toolbar/toolbar_item.dart:30-36`) has no floating-toolbar dependency. **Trap:** app item builders force-unwrap `editorState.selection!` (e.g. `custom_format_toolbar_items.dart:60`) — a *persistent* ribbon must gate on null selection or these throw. This is the single most likely Phase 1 bug.
- **Feature flag:** `lib/shared/feature_flags.dart:14-48` — one enum member + one `isOn` case.
- **Settings toggle precedent:** the backup page (Stage 3) — enum member → menu entry → page switch → own view+bloc.
- **Context menu (Phase 6):** `contextMenuItems` param, already overridden by the app at `editor_page.dart:387`.
- **New files:** `lib/plugins/document/presentation/editor_plugins/ribbon/` (following `lib/shared/backup/` and `desktop_toolbar/` as the modularity precedents).
- **Touch budget:** match the backup feature's discipline — ~15 core lines total, every one marked `[fork:ribbon]`.

## Multi-user readiness
Per `CLAUDE.md` → "Designing for other users": the ribbon is **universal by design**. It carries no personal data, no account assumptions, no machine-specific paths. It is desktop-only, which matches the macOS-first distribution goal in `specs/distribution.md`. The one thing to watch: it must behave correctly for LTR and `auto` users, not just the user's own `rtl` default — the same trap that made RTL bugs invisible in earlier sessions. Per-page direction (Phase 2) must default to the app-level setting so existing pages don't change behaviour on upgrade.

## How we'll know it's done (Phase 1)
1. Ribbon appears above the editor on desktop, four tabs, behind the flag; flag off restores today's behaviour exactly.
2. Every ✅ button performs the same action as its floating-toolbar equivalent, **including with no text selected** (the force-unwrap trap).
3. Disabled buttons are visibly disabled and explain themselves on hover.
4. Every enabled button's tooltip shows its shortcut, and those shortcuts appear in Settings → Shortcuts.
5. Collapse/expand works from both chevron and shortcut, and survives a restart.
6. The strip mirrors correctly with the app in RTL, verified on the real macOS target (not headless — see `CLAUDE.md`).
7. The floating toolbar no longer appears by default, and the settings toggle brings it back.
8. `flutter analyze` clean; unit/widget tests for the ribbon's own logic.

## Corrections to this spec, made at sign-off (2026-07-19, session 2)
Three claims above were checked against the code before building and did not survive contact. Kept here rather than silently edited, because each one changed a build decision.

**1. The `editorState.selection!` force-unwrap is NOT the main Phase 1 risk.** The spec (line ~110) calls it "the single most likely Phase 1 bug." In fact those items already declare `isActive: showInAnyTextType`, and `showInAnyTextType` (`editor_page.dart:639-647`) returns `false` only when `selection == null`. A *collapsed cursor is not null*, so with the caret anywhere in the document the items are active and the unwrap is safe. The real dead state is narrower: **no cursor in the editor at all** (focus in the sidebar). Handling = grey the buttons out, not a crash fix. The ribbon must respect `isActive` and never call `builder` for an inactive item.

**2. Word-style pending formatting ALREADY EXISTS in the editor fork** — this was assumed missing and estimated "large." It is essentially free:
- `EditorState._toggledStyle` + `toggledStyleNotifier` — `editor_state.dart:231-238`
- `toggleAttribute` already branches on a collapsed selection and sets pending style — `text_commands.dart:197-199`
- Typing consumes it: `toggledAttributes: editorState.toggledStyle` — `delta_input_on_insert_impl.dart:85`
- It self-clears on selection change — `editor_state.dart:157`
**No editor-fork change is needed for pending format.**

**3. "Reuse the existing toolbar items" and "a reusable ribbon button with tooltip = name + shortcut" are mutually exclusive.** In-scope items 3 and 4 asked for both. `ToolbarItem.builder` does not expose an icon + action for re-skinning — it returns the *entire finished button*, hardcoded to `FlowyIconButton(width: 36, height: 32)` with its own hover colours and its own tooltip (`custom_format_toolbar_items.dart:76-101`). Relatedly, spec line 20's claim that shortcuts are "not hardcoded" is false today: the tooltips embed literal strings like `'⌘ + B'` (`custom_format_toolbar_items.dart:107-125`), so a rebound shortcut would make the tooltip lie.

## Decisions taken at sign-off (2026-07-19, user)
- **No-selection behaviour: Word-style pending format.** Inline marks (bold/italic/underline/code/strike) with a collapsed cursor set pending style — already works, see correction 2. Block-level actions (align, lists, indent, headings) apply to the current block, which is their natural behaviour. With **no cursor at all**, buttons grey out.
- **Own the button component.** The ribbon extracts each item's *action* and renders it with a single ribbon-button widget, rather than re-hosting `ToolbarItem.builder`. This makes the uniform look and truthful rebindable-shortcut tooltips possible. Costs more in Phase 1 and is deliberate: it is exactly the retrofit the spec said to avoid.
- **Content tab grouping: clusters with a caption underneath each group** (Word's arrangement — Clipboard, Font, Paragraph…). Chosen for scannability at ~30 buttons, accepting the extra vertical height.

## Decisions taken during the Phase 1 build (2026-07-19, session 2)
- **~~The ribbon is ALWAYS left-to-right, never mirrored.~~ SUPERSEDED 2026-07-20 — see below.** The original reasoning is kept for the record: the ribbon, like the sidebar, belongs to the *application frame*, not to the page, so flipping it when a page's direction changes would move every control under the user's hands.
  - **Distinct from the document's own margins**, which *do* follow the page — see `EditorStyleCustomizer.documentPaddingFor`.

## Decisions taken during the Phase 2 build (2026-07-20, session 3)
- **The ribbon MIRRORS THE APP LAYOUT direction** — sidebar on the right ⇒ ribbon starts from the right, and vice versa. The user reversed the 2026-07-19 always-LTR decision after living with it. This is *not* a return to the original "mirrors in RTL" wording either; the distinction that matters is **which** direction it follows:
  - **The app layout direction — yes.** That is a deliberate, rarely-changed setting, and the ribbon is part of the frame that already mirrors with it (like the sidebar). Nothing moves under the user's hands unexpectedly.
  - **The page's direction — no.** A per-page RTL/LTR switch must never rearrange the toolbar. This is what the 2026-07-19 worry was really about, and it is preserved.
  - **⚠️ It follows `SidebarDockSide`, not `LayoutDirection`** — and getting this wrong silently does nothing, so it cost a build. The two settings are deliberately independent (`sidebar_dock_side.dart`): `LayoutDirection` governs *document content*, `SidebarDockSide` governs *app chrome*. This user runs an **English (LTR) interface with the sidebar docked right**, so the first attempt — deleting the hardcoded `Directionality` and inheriting the ambient one — left the ribbon stubbornly left-aligned, because the ambient direction is LTR. The user's own phrasing ("if the sidebar is on the right, the ribbon should start from RTL") is the correct spec: it keys off the sidebar.
  - The strip's internals were already written with `EdgeInsetsDirectional`, so wrapping in the right `Directionality` was the only change needed.
- **The page title and icon follow the PAGE's direction** (not the layout's). Reported by the user: setting a page to LTR from the ribbon moved the body text but left the title right-aligned under an RTL layout. Cause: `cover_title.dart`'s text field sets no `textDirection`, so it inherited the app layout's. Fixed with `EditorStyleCustomizer.headerTextDirection`, which resolves page-then-global-then-frame and reads `auto` from the title's own text. Note the inherited quirk it documents: the editor's `determineTextDirection` treats **ASCII digits as LTR evidence**, so "2026 סיכום" resolves LTR — kept deliberately, because every block resolves `auto` the same way.
- **The document now renders as a sheet on a desk** (user request): the text column gets `surfaceColorScheme.primary` plus `shadow.medium` and rounded top corners, on a recessed background. **No bottom edge** — the sheet runs off the bottom of the viewport on purpose, since a bottom edge would imply the document ends there. Covers the whole page including cover, icon and title. Implemented as a sidecar wrapper (`page_surface.dart`) around the editor rather than a change inside it, to keep it off the upstream merge path. Two things that were **not** obvious and cost a build each:
  - **The desk colour must be derived, not taken from a token.** The natural choice — `primary` for the sheet, `layer02` for the desk — is wrong twice over: in the default **light** theme both are `neutralWhite` (identical, page invisible), and in **dark** `layer02` is *lighter* than `primary` (reads raised, not recessed). `_deskColorFor()` darkens the sheet in HSL instead, which holds for any theme.
  - **A minimum desk margin is required or the feature silently does nothing.** Document width defaults to `maxDocumentWidth` (1920) — wider than a typical editor pane — so the sheet clamps to the full pane and no desk remains. `_kMinDeskMargin` guarantees the page reads as a page; the user accepted the text width this costs at wide settings. Note the wrapper **insets** the editor rather than painting behind it: narrowing only the painted sheet would let text spill onto the desk.
  - **Final shape after two rounds of live feedback:** **square corners** (rounded read as a card, not a page), a **top margin so the page has three visible edges** (top/left/right, running off the bottom), and the margin **tuned 48 → 32** — one constant drives top and sides together so the border stays even.
  - **The top margin closes as the document scrolls down**, so the page slides up against a desk that stays put. This is what makes it read as a separate sheet rather than a painted background, and it was the user's explicit intent — *not*, as an earlier draft of this spec wrongly recorded, an emergent behaviour they had observed. (Claude misread "scrolling removes the top edge, as a real page would" as an observation rather than a request, and wrote it down as already working. Corrected 2026-07-20; the lesson is to check whether a user is describing what *is* or what *should be* before recording it as fact.)
    - Driven by `ScrollNotification` bubbling up from the editor's own scrollable to the `PageSurface` ancestor — no access to the editor's `ScrollController`, so nothing is added to the upstream merge surface. Guarded on `depth == 0` and a vertical axis so nested scrollables (wide tables, code blocks, the slash menu) cannot make the page twitch.
    - The margin lives in a `ValueNotifier` so a scroll repaints only the padding, not the document beneath it.
    - **Note for whoever verifies this:** computer-use `scroll` events do **not** reach the editor's scroll view (pixel-identical screenshots before/after). Drive it with the keyboard (click an existing line of text, then Page Down) or have the user check.
- **Measured result of the margin fix** (real macOS target, 1422pt window): rendered text edges now sit at **≈104px left / ≈104px right**, against **97/116** measured on 2026-07-19. The 2026-07-19 diagnosis that blamed the `Center()` was wrong — centring is symmetric by construction; the real cause was the block option gutter growing 44→73 (commit `ffc069150`) while three separate compensation sites kept the old number.

## Button designs specified for future phases (2026-07-19, user)
Captured while building Phase 1; each gets built in its own session.
- **Font picker** — a dropdown with a **filter/search box**. Each font's *name* renders **in that font**, so the list previews itself.
- **Font size** — a **type-in box flanked by two carets** ("elevator" styling): one to increase, one to decrease. Not a plain dropdown.
- **Paragraph styles** — the ability to edit the **hierarchy of styles** (heading levels and body), in the style of Google Docs' "paragraph styles". This is a new capability, not in the original inventory, and likely needs its own spec.

## Phase 3 scoping (2026-07-23, session 8) — awaiting sign-off
Four code findings came first; two of them moved a item between phases, so they are
recorded before the decisions they caused.

### Findings (verified in code, 2026-07-23)
1. **Justify cannot be done app-side — it moves to Phase 4.** Alignment flows
   `blockComponentAlign` string (`left|center|right`) → `align_mixin.dart:8` → a Flutter
   **`Alignment`** → `alignment_extension.dart`'s `toTextAlign` → `TextAlign`. The middle
   step kills it: `Alignment` is a *box position*, and there is no `Alignment` value meaning
   justify — justify is a paragraph-layout instruction, not a position. Supporting it means
   carrying the align string past that conversion, and **six** block components
   (paragraph, heading, quote, bulleted/numbered list, todo) read `alignment` for real box
   positioning as well, so it is a restructure rather than an added `case`.
2. **Paragraph spacing and line height are BOTH per-node-capable app-side — no fork change.**
   This corrects an earlier worry in this session that per-paragraph spacing would need the
   fork. Both seams already receive the node:
   `BlockComponentConfiguration.padding` is `EdgeInsets Function(Node)`
   (`block_component_configuration.dart:93`) and `textStyle` is a
   `BlockComponentTextStyleBuilder` taking a `Node` (`:35`, `:106`). So a paragraph can carry
   its own spacing and its own line height as block attributes, read app-side — exactly the
   mechanism `blockComponentAlign` already uses.
3. **Desktop is the only platform missing a read path**, which is why these look "missing"
   rather than "broken". Mobile already reads `DocumentPageStyleBloc` for both
   (`editor_configuration.dart:108-127`, `editor_style.dart:293-307`); desktop returns
   hardcoded constants — `EdgeInsets.symmetric(vertical: 5.0)` and `lineHeight: 1.4`
   (`editor_style.dart:243`). Phase 3 is largely "give desktop the read path mobile has,"
   keyed off the node instead of a page-wide bloc.
4. **Clear formatting has its primitive already.** `editorState.formatDelta(selection, {key: null})`
   exists in the fork and the app's own colour buttons already use it.

### Decisions (user, 2026-07-23)
- **Justify → Phase 4.** Grouped with superscript/subscript/footnote so there is one fork
  round-trip and one pin re-sync, not two. The Justify button stays visibly disabled until then.
- **Clear formatting clears INLINE MARKS ONLY** — bold, italic, underline, strikethrough,
  code, font colour, highlight, font family, links. Block type, alignment and lists survive:
  a heading stays a heading. Chosen for predictability over Word's more destructive
  "Clear All Formatting".
- **Change Case is a dropdown**, not a single Sentence-case button: Word's five —
  Sentence case, lowercase, UPPERCASE, Capitalize Each Word, tOGGLE cASE. One ribbon slot,
  five actions, one shared transform. This widens the signed-off scope (which said only
  "sentence case") at the user's request. **Note it is a no-op on Hebrew, which has no letter
  case** — so the button must not appear broken when nothing changes.
- **Spacing and line height are PER PARAGRAPH, not per page** (user: *"per content because it
  affects each paragraph, not the entire page"*). Deliberately **unlike** per-page direction
  and per-page theme, which live in `View.extra`: those describe the page, this describes a
  block. Stored as block attributes on the node, so they travel with the paragraph when it
  moves and inherit nothing when absent.

### Resolved at sign-off (user, 2026-07-23)
- **Signed off as scoped**, including pulling line height into Phase 3.
- **Spacing is a preset dropdown**, not a numeric control — matching the existing align
  dropdown, nothing to type, no weird intermediate states. A numeric "elevator" control is
  deferred to the font-size button so both can share one component rather than inventing it
  twice.
- **Change Case with a collapsed cursor acts on the whole paragraph**, consistent with the
  align/list/indent buttons already in the ribbon. It does not require an explicit selection.

## Phase 5 scoping (2026-07-24, session 9) — awaiting sign-off
Phase 5 is "the partials" (font size, page colour, margins, ruler). This session takes on
**font size + page colour + margins**; the **ruler is deferred to its own scoping pass** (see
below). As in Phase 3, the code findings came first and shaped the decisions, so they lead.

### Findings (verified in code, 2026-07-24)
1. **Font size is app-side only — no fork change.** The fork already *defines and renders* the
   attribute: `AppFlowyRichTextKeys.fontSize = 'font_size'`
   (`appflowy_rich_text_keys.dart:12`), read as a double off the span's delta attributes
   (`appflowy_rich_text.dart:883-885`) and applied as `TextStyle(fontSize:)` (`:748-750`).
   Nothing in the *app* ever writes it. So font size is "write the attribute the fork already
   reads on the current selection" — the same shape as the existing colour/mark buttons, not a
   fork round-trip. This is why it sits in Phase 5 (a partial), not Phase 4 (fork-crossing).
2. **The per-page storage seam is already built and proven twice.** `page_theme_mode.dart` and
   `page_text_direction.dart` are the template: a namespaced key inside `View.extra`'s JSON, a
   `ViewPB` getter extension that falls back (never throws) on a non-document layout or
   unparseable `extra`, and a read-**latest**-from-backend / modify / write setter that
   preserves every other key. `inherit` is modelled as the *absence* of the key, so untouched
   pages behave exactly as before. Page colour and margins each become one helper in this exact
   mold — no change to upstream's `view_ext.dart`.
3. **Width already has machinery, just globally.** `DocumentAppearanceCubit` carries a `width`
   (`document_appearance_cubit.dart:31`), clamped `minDocumentWidth`(480)‥`maxDocumentWidth`
   (1920) (`editor_style.dart:53-54`), set by the Settings → Workspace slider. Per-page margins
   = storing a per-page width override in `View.extra` and letting the read path prefer it over
   the global default. No new width plumbing.
4. **The sheet is not a fixed paper size.** The page-surface "sheet" (`page_surface.dart`) wraps
   the text column; its width tracks `width`, not a Letter/A4 page. So Word-style "page minus
   text area" margins have no page size to subtract from — see the margins decision.

### Decisions (user, 2026-07-24)
- **Font size — an "elevator" control** (the design captured 2026-07-19): a type-in box flanked
  by ▲▼ carets. This is the reusable numeric control Phase 3 deliberately deferred here.
  - **▲▼ step ±1**; the box accepts any typed value. **Range 8‥96** (clamp on both entry and
    stepping). *(Not Word's uneven preset ladder — the user chose even single steps.)*
  - **Applies per-selection like Bold**; with a bare cursor it sets a **pending size** so the
    next typed text uses it (the ribbon's established no-selection behaviour). The box **shows
    the current selection's size** and goes **blank when the selection mixes sizes** (Word-style).
  - **Value is a raw number, not "pt."** AppFlowy's `font_size` is logical pixels; labelling it
    "pt" would be a lie. Shown unitless. The baseline number a fresh paragraph shows is
    whatever the app's default body size resolves to — to be read from code at build time and
    noted, not invented.
  - **Wired into "Clear formatting."** Phase 3's Clear-All-Formatting already strips inline
    marks incl. font *family*; font *size* joins that list, giving a clean way back to default
    (plus typing the default number). Confirm at sign-off.
- **Page colour — per-page background tint**, stored in `View.extra` (mirrors direction/theme).
  - **Presets + custom.** A row of preset swatches reusing **AppFlowy's existing theme-aware
    palette** (the font-colour/highlight swatches) for one click, plus the existing custom
    colour path for an exact colour. Reusing the theme-aware palette means a colour **adapts if
    that page is also flipped to dark** — sidestepping a page-colour-vs-per-page-theme conflict.
  - **Tints only the sheet**; the desk behind it **auto-derives a recessed shade** (the HSL
    darken already in `page_surface.dart`) so the "sheet on a desk" depth survives. `inherit`
    (absence) = today's theme surface colour, unchanged.
- **Margins — per-page text-width presets** (not Word-style fixed-page margins; finding 4).
  "Wider margins" = narrower centred text column, the Notion / Google-Docs page-width model.
  - **Per-page, inherits the global slider.** A page that sets nothing follows Settings →
    Workspace exactly as now (absence = inherit); a page that sets a width overrides it. Same
    `View.extra` seam.
  - Presets (proposed, confirm at sign-off): **Narrow / Normal / Wide / Full-width**, mapped to
    concrete widths inside the existing 480‥1920 clamp, with **Normal** = today's default so
    nothing shifts for untouched pages. A custom numeric width can follow later if wanted.
- **Ruler — deferred to its own scoping pass.** It is mis-filed as a "partial." A real ruler is
  *interactive* (drag margin markers, set tab stops), and AppFlowy has **no tab-stop concept and
  no draggable margin markers** — inventing both puts it in the size class of the text-box /
  drawing items already carved into their own specs, not a tail-end partial. Its Page-tab button
  stays visibly disabled until then.

### Cross-cutting: the focus rule applies to all three (load-bearing)
Every one of these controls can steal editor focus — the font-size **text field** most of all
(a real input that needs focus to type into), and both the colour and margin **dropdowns**. Per
the Phase 3 lesson, each **must** hold `keepEditorFocusNotifier` or it nulls the selection before
the action runs (`keep_editor_focus.dart`). The font-size box is the sharper case: capture the
selection when the field gains focus, hold the notifier while focused, and apply to the captured
selection on commit (Enter / blur) — the same shape the editor's own link-edit popover uses.

### Multi-user readiness
All three are **universal — no personal assumptions.** Font size, page colour and margins work
for any user, any language, LTR or RTL. Page colour reuses AppFlowy's theme-aware palette, which
already generalises. Nothing here hardcodes anything to this Mac or account.

### To confirm at sign-off — RESOLVED (user, 2026-07-24)
1. **Font size joins "Clear formatting"** — yes. 2. **Margin presets Narrow/Normal/Wide/Full,
Normal = current default** — yes. **Signed off as scoped; build order: font size → page colour
→ margins.**

## Phase 4 scoping (2026-07-24, session 10) — signed off
Phase 4 is "the fork-crossing gaps." The signed-off scope is **justify + superscript +
subscript** — one fork commit, one pin re-sync. **Footnote is split out to its own spec** (see
decisions). As before, the code findings lead.

### Findings (verified in code, 2026-07-24)
1. **Superscript/subscript do not exist in the fork.** The inline-mark system is a flat list of
   string keys in `AppFlowyRichTextKeys` (`appflowy_rich_text_keys.dart`) with membership lists
   (`supportToggled`, `supportSliced`, `partialSliced`). Adding the two marks = two new keys +
   the right list memberships + a render path — the same *shape* as bold/italic, so the wiring is
   familiar. **The render path is the catch (finding 2).**
2. **⚠️ Flutter has no clean superscript/subscript for *editable* rich text — this is Phase 4's
   one real risk.** `FontFeature.superscripts()/subscripts()` is font-dependent and silently
   no-ops on many fonts (including, likely, the Hebrew-capable defaults this user runs). The
   robust route is rendering the run smaller with a raised/lowered baseline, but a per-span
   vertical shift isn't a `TextStyle` property, and doing it via `WidgetSpan`/transform inside an
   editable paragraph risks throwing off **caret placement and selection geometry** around those
   characters — the exact class of bug the RTL caret work has repeatedly shown is invisible to
   headless tests. **Decision: the build opens with a rendering spike** (prove it renders *and*
   the caret/selection behave on the real macOS target) before any button/shortcut is wired.
3. **Footnote does not exist in any form** (no marker system, no note store, no numbering) and is
   its own small feature — as big as the other three combined. Not an inline mark.
4. **Justify's blocker is already documented** (Phase 3 scoping, finding 1): alignment resolves
   `blockComponentAlign` (`left|center|right`) → a Flutter `Alignment` (a *box position*, which
   has no justify value) → `TextAlign`. Justify means carrying the align string past that
   conversion to `TextAlign.justify` while the box position defaults, and **six** block components
   read `alignment` for real positioning — a small restructure, not an added `case`. No render
   risk (unlike super/subscript); works in RTL for free (`TextAlign.justify` is direction-agnostic).

### Decisions (user, 2026-07-24)
- **Phase 4 = justify + superscript + subscript.** One fork round-trip + pin re-sync, targeting
  one session.
- **Footnote → its own spec.** It's a feature, not a mark. Its ribbon button stays a visible
  "coming soon" until that spec is scoped and built. (This narrows Phase 4 from the four-item plan
  recorded at line 101/207.)
- **Super/subscript = two toggle buttons** in the Content tab's Font group, beside
  strikethrough/inline-code. Toggle like Bold; **mutually exclusive** (enabling one clears the
  other); the character **auto-shrinks**.
- **Shortcuts: ⌘⇧= superscript, ⌘⇧− subscript** — symmetric (`=`/`+` = "up", `−` = "down"),
  location-matched so they fire under Hebrew too (the `d15e3c3a` engine). **Word's ⌘= for subscript
  was rejected** because ⌘= collides with zoom in many apps; ⌘⇧= / ⌘⇧− are both free (verified: no
  app- or fork-side binding on the equal/minus keys). A small `text_script_commands.dart` sidecar,
  registered in `command_shortcuts.dart`, mirroring `font_size_commands.dart`.
- **Justify = the 4th option in the existing align dropdown**, applying to the same blocks
  alignment already covers.
- **Build order (agreed): super/subscript rendering spike first**, then the buttons + shortcuts,
  then justify (the low-risk item). Fork commit → push → pin re-sync last.

### Multi-user readiness
All three are **universal — no personal assumptions.** Justify and super/subscript work for any
user, any language, LTR or RTL. Nothing hardcodes to this Mac or account. (Super/subscript are rare
in Hebrew, which has no such convention, but they're harmless there and the shortcuts still fire.)

### Sign-off
**Signed off 2026-07-24 (session 10)** as scoped above: scope, the ⌘⇧= / ⌘⇧− shortcut pair, and
opening the build with a super/subscript rendering spike. No code written this session.

## Open questions
- Which keyboard shortcut collapses the ribbon (Word uses Ctrl+F1; AppFlowy's rebindable system means this is a default, not a commitment).
- Whether the Tools tab's Translate/Transcribe/Record buttons should link out to their future specs or simply sit disabled.

## Sign-off
**Signed off 2026-07-19** (session 2), subject to the three corrections and three decisions recorded above.

## Phase 4 live-verification results (2026-07-25, session 11 — user tested on real hardware)

**Verdict: the core works, with one design-level limitation and a set of gaps.** Justify and
super/subscript both do what they were built to do; what failed is mostly *reach* (which characters,
which block types) plus polish.

### ✅ Passed
- **Superscript / subscript render correctly on digits** — the `2` in `H2O` and `E=mc2` shrinks and
  raises/lowers as designed. The `FontFeature` approach is confirmed working end-to-end.
- **Justify works in English and in Hebrew**, in ordinary paragraphs. The Phase 4 `blockTextAlign`
  fork change is validated, RTL included.
- **The shortcuts fire under a Hebrew input source** — location-based binding confirmed working.
  (See limitation 1 below: they fire, but the *mark* has no visible effect on Hebrew letters.)

### ⚠️ Limitation 1 (design-level, needs a decision): super/subscript only affects DIGITS
User found it works on the `2` in `H2O` but **not on the `O`**, **not on Hebrew text at all**, and
**not inside inline code**. All three are one root cause, and it is inherent to the chosen approach.

`FontFeature.superscripts()` / `subscripts()` request the OpenType `sups`/`subs` features
(`appflowy_rich_text.dart:759,764`). Those features only substitute glyphs the font actually ships
in raised/lowered form — in practice digits and a handful of Latin letters. **Hebrew has no such
glyphs in any common font, so nothing can render.** Inline code fails for the same reason plus a
monospace font that carries even fewer of them. The mark is being applied correctly; the font simply
has nothing to draw.

**This was a known trade-off, not an oversight.** Phase 4 chose `FontFeature` precisely because it
keeps the text a pure `TextSpan`, so caret and selection stay 1:1 with characters — the alternative
(`WidgetSpan`) collapses a run to a single placeholder and breaks editing offsets. Flutter's
`TextStyle` has **no baseline-shift property**, so "smaller font, raised baseline" — how Word and
Google Docs do it — is not directly expressible in a `TextSpan`.

**Open decision for the user (do not pick unilaterally):**
- (a) **Accept and document** — super/subscript is a digits feature (covers `H₂O`, `E=mc²`, footnote
  markers, chemical/maths notation, which is most real use). Cheapest, zero risk. The buttons should
  then *say so* rather than silently doing nothing on Hebrew.
- (b) **Synthetic rendering** — smaller font size plus a real vertical offset, which buys arbitrary
  characters including Hebrew, at the cost of leaving pure-`TextSpan` territory. **Must be
  investigated before being offered as a real option**: the caret/offset consequence is exactly what
  Phase 4 avoided, and it may reintroduce the class of RTL caret bugs this project keeps fighting.
- (c) **Hybrid** — `FontFeature` where the font supports it, synthetic only as a fallback. Best
  result, most machinery, two code paths to keep correct.

### ⚠️ Gaps found (all straightforward, none design-level)
1. **Justify does nothing inside a bulleted paragraph** (numbered untested, presume the same). Note
   `bulleted_list_block_component.dart` *does* already read `blockTextAlign` — so this is more likely
   a **layout** issue than a missing wire-up: list text sits in a row beside its bullet and may
   shrink-wrap, leaving justify nothing to stretch to. Verify before fixing.
2. **Justify does not toggle off.** Pressing it a second time should return the block to its default
   alignment (right or left per direction). Today `_textAlignHandler`
   (`custom_text_align_command.dart`) writes the align attribute unconditionally with no off-state.
   The user wants toggle-back on *all four* align buttons, not just justify.
3. **Alignment shortcuts should move to Word's:** ⌘L left, ⌘E centre, ⌘R right, ⌘J justify —
   replacing today's ⌃⇧L/⌃⇧C/⌃⇧R/⌃⇧J. **Check for collisions first** (⌘R and ⌘L are commonly claimed
   app-wide), and keep them location-based so they survive a Hebrew layout.
4. **Duplicate "coming soon" Superscript/Subscript buttons** still sit in the Content tab's *Editing*
   group (`ribbon_tabs.dart:791-792`), alongside the now-real pair in the *Font* group. Stale
   leftovers — delete them.
5. **⌘Z does not undo a page-colour change.** Page colour lives in `View.extra`, outside the editor's
   own undo stack, so the editor's undo never sees it. Same will be true of any other `View.extra`
   setting (per-page direction, per-page theme, margins). Needs a deliberate answer, not a patch:
   either bring these into an app-level undo, or accept and document that page-level settings are not
   undoable.
6. **The selection highlight is hard to see in both dark and light mode.** Independent of Phase 4 —
   found incidentally — but a real readability problem worth its own small fix.

## ⚠️ Changing a default keyboard shortcut in code DOES NOT WORK (found 2026-07-25, session 11)

**This is the most reusable finding of the session — read it before editing any `command:` string.**

`SettingsShortcutService.updateCommandShortcuts` runs at startup, walks the saved
`shortcuts/shortcuts.json` in the app data folder, and for every entry whose `key` matches a
registered command calls `updateCommand(...)`. **The saved value wins over the code default,
silently and permanently.** The user's debug-build file holds **86** saved entries.

Consequences, all confirmed against that file:
- Changing `command:` for an *existing* command is a no-op for anyone who has the file. The
  2026-07-25 move of align to ⌘L/⌘E/⌘R did nothing for exactly this reason.
- A *new* command (absent from the file) does pick up its code default — which is why superscript,
  subscript and the font-size shortcuts all worked first time. **This asymmetry is what makes the
  trap so easy to miss: some of your shortcut changes work and some don't.**
- `Justify text` was also absent from the file, so ⌃⇧J was live from the start.

**To actually change a binding:** rebind in Settings → Shortcuts, or use its reset-to-defaults, or
write a migration over the saved file. Not by editing the default.

## Alignment shortcuts — REVERTED, open for discussion (2026-07-25)

Moved to Word's ⌘L / ⌘E / ⌘R / ⌘J at the user's request, then reverted the same session: **the user
did not approve the assignment.** Back to ⌃⇧L / ⌃⇧C / ⌃⇧R / ⌃⇧J, and the editor's inline-code
shortcut is back on ⌘E.

The problem to solve when this is revisited: **⌘E is the natural Word binding for centre, but it is
already inline code**, and the obvious relief valve ⌘⇧E is already the app's math-equation shortcut.
Any Word-matching scheme therefore has to displace at least one existing shortcut. Options worth
putting to the user: take ⌘E and move inline code somewhere free (⌘⇧C was the best candidate —
free, mnemonic, matches Slack); keep inline code and give centre a non-Word chord; or leave all four
on the existing ⌃⇧ set. **Whatever is chosen, it must be applied through Settings → Shortcuts or a
migration, not by editing defaults** (see the section above).

## Selection highlight (2026-07-25)

Was the theme accent at a flat 0.2 alpha in both themes — reported "indistinguishable". Raised in two
passes after live feedback: 0.32/0.42 was still too faint, so it is now **0.62 light / 0.55 dark**,
roughly triple the original. Colour deliberately unchanged, so it still follows a custom theme's
accent. Dark takes slightly less than light because the accent is a bright cyan that moves *toward*
light text as alpha rises. Capped where body text still clears WCAG AA against the blended result.

## Decision: page-level settings get their own undo (user, 2026-07-25)

⌘Z does not undo a page-colour change, and the same is true of per-page direction, per-page theme
mode and margins — all live in `View.extra`, outside the editor's undo stack, so the editor's undo
never sees them. **The user's decision: they get their own undo**, rather than being documented as
non-undoable. Not yet scoped — needs its own design pass covering: whether one shared undo stack
spans document edits *and* page settings (so ⌘Z interleaves them in true chronological order) or a
separate stack, what the scope is (per page? per session?), and how it interacts with the editor's
existing history. **Do not bolt this onto one setting; it is a cross-cutting feature.**

## Session Log
- **2026-07-25 (session 10) — Phase 4 scoped, signed off, and BUILT: justify + superscript + subscript. Footnote split out to its own future spec. Fork committed + re-pinned. Visual verification deferred to the user (a keyboard tooling wall, below).**
  - **Scope decision:** Phase 4 = justify + super/subscript only; **footnote deferred to its own spec** (it's a feature — marker system + note store + numbering — not an inline mark; the button stays "coming soon"). See "Phase 4 scoping" above.
  - **Superscript / subscript** (fork): two new inline-mark keys in `AppFlowyRichTextKeys` (added to `supportSliced` + `supportToggled`), rendered via OpenType **`FontFeature.superscripts()` / `subscripts()`**. This is deliberately the *only* clean approach for editable rich text: it stays pure `TextSpan`s, so caret and selection map **1:1 to characters**. A `WidgetSpan`/`Transform` baseline shift — the obvious alternative — collapses a multi-char run to a single placeholder (`￼`, length 1), which would break every offset in the editor's delta↔render mapping. Trade-off: font-dependent (silently no-ops on fonts lacking the glyphs), but the macOS system font supports it for digits (the mc²/H₂O case).
  - **Mutual exclusivity** (fork): new `EditorState.toggleExclusiveAttribute(key, opposite)` beside `toggleAttribute` — toggles `key`, and whenever that turns it ON also clears `opposite`, so super/sub can't both apply. Mirrors `toggleAttribute`'s collapsed (pending `toggledStyle`) and expanded (`formatDelta`) handling. The ribbon buttons and the shortcuts share it via app-side `toggleTextScript`.
  - **Super/sub shortcuts** (app, `text_script_commands.dart`): **⌘⇧=** superscript, **⌘⇧−** subscript. Symmetric (=/+ = "up", − = "down"); Word's ⌘= for subscript rejected (zoom clash). Both `equal`/`minus` are already in the fork's `keyToPhysicalCodeMapping`, so — like font size — they fire under a Hebrew keyboard by physical location. Two ribbon toggle buttons in the Content-tab Font group call the same helper (`_scriptAction`). **Icons are temporary placeholders** (no x²/x₂ glyphs exist yet — the icon-set revamp will supply them).
  - **Justify** (app + fork): the align string→`Alignment`→`TextAlign` chain couldn't express justify (an `Alignment` is a box position). Fixed with a parallel **`blockTextAlign`** getter on `BlockComponentAlignMixin` that maps the string *directly* to `TextAlign` (incl. `TextAlign.justify`); the **six** alignable components (paragraph, heading, quote, bulleted/numbered/todo) now read it instead of `alignment?.toTextAlign`. For left/center/right it's behaviour-identical (proven by test); for justify the box `alignment` stays null so the block keeps full width and the text stretches. New app command `customTextJustifyCommand` (**⌃⇧J**, matching l/c/r + Word/Docs) writes `'justify'`; the ribbon's "coming soon" placeholder became a real button. Direction-agnostic → works in RTL.
  - **Tests:** 7 new fork logic tests (`text_script_and_align_test.dart`) — mutual exclusivity, justify mapping, box-alignment-stays-null — all pass. No regressions: 80 app ribbon tests + 13 fork `text_commands` tests green. `flutter analyze` clean both sides.
  - **⚠️ Fork committed `c48c69f5` (pushed; pin re-synced from `d15e3c3a`).** Dock app rebuilt against the pinned fork and content-verified. **The user must quit+reopen AppFlowy.**
  - **⚠️ Visual verification NOT done this session — a hard tooling wall, not a code problem.** After a mid-session app relaunch (via `open`/`open_application`), **synthetic keyboard input stopped reaching the Flutter window entirely** — not editor keys, not even the global Cmd+Option+R; only OS-level combos (Cmd+Q, Cmd+Tab) worked. Mouse clicks registered (focus/placeholder responded) but the window never became key for keyboard. Mouse-only fallbacks failed too: no scratch text survived to drive them, and ribbon **Paste** dropped the selection. So *does super/subscript actually render, and does justify visibly stretch* is **delegated to the user's real-hardware check** (the same reliable path that verified the font-size shortcut earlier). The `FontFeature` approach + logic are sound; if a font ever doesn't render the marks, that's an isolated 2-line fork tweak, not a rework. **This is the standing "never trust synthetic input" rule biting again — recorded so next session doesn't re-fight it.**
- **2026-07-24 (session 9) — Phase 5 built and live-verified over three feedback rounds: font size, page colour, margins. Plus a keyboard-shortcut remap and a fork keybinding-engine change ("bind to location").**
  - **Font size — the "elevator" control** (`font_size.dart`): type-in box flanked by ▼▲ carets, step ±1, range 8–96, applies per-selection or as a pending size on a bare caret; blanks on a mixed selection. No fork change — the fork already *renders* the `font_size` attribute; nothing in the app wrote it. Already covered by "Clear formatting" (`font_size` was in `clearableInlineAttributes`). **Live-round fix:** clicking the box deselected the text (and disabled it) — the keep-focus notifier was raised in the focus listener, one beat *after* the editor had already nulled the selection. Fixed by raising it on **pointer-down** (a `Listener`), before focus moves. This is a sharper case of session 8's load-bearing lesson: a text field needs the hold set up before focus leaves the editor, not on focus-gain.
  - **Page colour** (`page_color.dart`): per-page sheet tint stored in `View.extra` like direction/theme. Theme-aware **tint presets** (reusing `FlowyTint`, so a colour adapts if the page is flipped to dark) + a **Default** clear + a **custom hex**. Resolved *inside* `PageSurface` (which builds under `PageThemeScope`) so tints follow the page theme; the desk auto-derives its recessed shade from whatever the sheet becomes. **Live-round fix:** swatches were a tall vertical list that pushed the custom-colour control off the bottom of the popover → switched to a compact horizontal `Wrap`.
  - **Margins** (`page_margin.dart`): per-page **text-column width** presets (Narrow/Normal/Wide/Full), inheriting the global width when unset. **Live-round fix (design):** first version narrowed the *whole sheet*; the user's model is Word's — the paper stays, the content narrows *inside* it. Decoupled: `PageSurface.pageWidth` uses the global width (the sheet), `EditorStyleCustomizer.width` uses the per-page width (the column). **Preset values retuned** after live feedback (600/960/1400 had Wide==Full on the user's ~1000–1100px sheet, Narrow too tight) → **700 / 850 / 1000 / Full**.
  - **Ruler stays deferred** — a disabled button; it needs tab-stops + draggable markers AppFlowy lacks (its own future feature, not a partial).
  - **Selection shortcut remap:** the visual-line / paragraph selection moved from **Option+Ctrl+Shift+arrow** to **Option+Shift+arrow** (all four; `visual_line_selection_commands.dart`). No conflict — the editor binds no `alt+shift+arrow` of its own. Behaviour (incl. the RTL visual-direction logic) unchanged.
  - **Font-size shortcuts:** **Cmd+Option+.** enlarges, **Cmd+Option+,** shrinks (the unshifted `>`/`<` keys), one step, on the selection or as a pending size (`font_size_commands.dart`, registered in `command_shortcuts.dart`). Direction-agnostic action, so identical on RTL text.
  - **⚠️ Fork change — physical ("bind to location") keybinding matching (fork `d15e3c3a`, pushed; pin re-synced from `3c2a2fce`).** The user asked that the font-size shortcut work in *all keyboard languages*, and that user-customized rebinds stick regardless of input language. Implemented in the fork's keybinding engine: a parallel `keyToPhysicalCodeMapping` (label → USB HID) and `Keybinding.matchesKeyEvent`, which now matches on the **logical key OR the physical key location**. Additive — logical is tried first, so Latin-layout behaviour is unchanged; keys absent from the physical table fall back to logical-only. This makes **all** shortcuts (built-in and user-rebound) location-robust across layouts, which is the general improvement the user leaned toward. 5 new fork tests (incl. the "logical differs, physical matches" Hebrew case).
  - **Build/verify:** analyzer clean; **77 ribbon tests + 13 fork keybinding tests pass**. Dock app rebuilt against the pushed fork pin and content-verified (test-binding 0, `runAppFlowy` 31, `keyToPhysicalCodeMapping` 5, `meta+alt+period` 2, `PageColorControl` 6). **The user must quit+reopen AppFlowy** to pick up the fork-pinned build. Font size / page colour / margins all live-verified "working well"; the shortcut + cross-language behaviour await the user's live check next session.
- **2026-07-24 (session 8) — Phase 3 built, live-verified, and hardened over two feedback rounds. Plus two editor-fork fixes (triple-click timing, unrelated) and, earlier in the session, the sidebar rename polish.**
  - **Phase 3 shipped:** Clear formatting, Change Case (Word's five, as a dropdown), and per-paragraph line height + space-after (preset dropdowns). Justify was found *not* app-doable and moved to Phase 4 (alignment resolves through a Flutter `Alignment`, which has no justify value; six block components read it for box positioning — a restructure, not a case). Line height pulled *into* Phase 3 from Phase 5 because it shares the block-config seam with paragraph spacing. All app-side; commit `2aec4fad8`. New files: `text_transforms.dart`, `paragraph_spacing.dart`, `ribbon_dropdown.dart`.
    - **Spacing is per-*paragraph*, not per-page** (user: "per content because it affects each paragraph") — stored as block attributes, deliberately unlike per-page direction/theme which live in `View.extra`. Needed no fork change: both `BlockComponentConfiguration.padding` and `.textStyle` already take the node; desktop was simply the only platform without a read path (mobile already had one). Defaults pinned to the exact prior hardcoded values (1.4 line height, 5pt padding) so untouched docs are unchanged, and "Single" == 1.4 (AppFlowy's baseline, not a word processor's 1.0), so choosing it is a no-op.
    - **A real bug caught by its own test:** removing a spacing attribute silently did nothing. Attribute updates compose delta-style, so removal is `key: null`, not dropping the key — an omitted key means "leave as was" and merged the old value back.
  - **Live-testing round 1 — the important one:** clicking ribbon controls **deselected the text**, so dropdown actions had nothing to act on. Root cause: the editor nulls `editorState.selection` on focus loss unless `keepEditorFocusNotifier` is raised — the pattern AppFlowy's own colour/link popovers already use. Fix (`939de6bb6`, `keep_editor_focus.dart`): dropdowns hold it while open (`onOpen`/`onClose`); plain buttons hold it across the tap and hand focus back afterwards. New widget/logic tests assert the notifier is held while the action runs. **General lesson for any future ribbon control: if it can steal focus, it must raise keepEditorFocusNotifier or it will eat the selection.**
  - **Live-testing round 2:** user chose to expand Clear formatting to Word's full **"Clear All Formatting"** (was inline-only at sign-off): now also resets block type (heading/quote/list → paragraph), alignment, line height, spacing. Implemented via `formatNode` (wholesale node replacement, the sanctioned block-type-toggle path) preserving only delta + reading direction. **Two documented exceptions:** reading direction survives (clearing it would flip RTL paragraphs to LTR — worse for this user than the formatting removed), and letter *case* can't be reversed (uppercasing rewrites the characters; only undo does).
  - **Editor-fork fix — triple-click timing** (user request, unrelated to the ribbon). Double-click-word → click-paragraph felt finicky because the gesture detector timed all three clicks against the **first** tap in one budget. Fixed to time each click against the *previous* one (fork `c8b6c1c1`), then widened the grace period 500 → 700ms after the user asked for it easier still (fork `3c2a2fce`). Regression test proven failing-then-passing; **pin re-synced to `3c2a2fce`** and the dock app rebuilt on it. Plausibly upstream-worthy (vanilla has the same anchoring bug).
  - **Earlier in the session (committed separately, `2d45f5f3f`):** the sidebar in-place rename got an 8pt directional edge margin (`EdgeInsetsDirectional`, so it follows a moveable sidebar) and **visually-correct arrow keys for RTL names** — Flutter moves the caret in logical order, so in Hebrew ArrowLeft stepped right; measured (offset 4 → ArrowLeft 3, ArrowRight 5), remapped for RTL names only, character + word + shift-extended. Also re-verified the 3 session-7 sidebar fixes live (all passed) and confirmed ⌘O beep stays as-is (user's call).
  - **Process win worth keeping:** the "measure before changing" rule paid off twice — a throwaway probe test proved the arrow keys really were inverted (and that setting `textDirection` alone would *not* fix it) before any code changed, and reading `composeAttributes` in the fork explained the silent-no-op removal bug rather than guessing.
- **2026-07-21 (session 4) — the ribbon Appearance button became a per-page light/dark override, and the layout/page theme split was reworked to the user's rule. Plus a keyboard-focus bug this introduced, found and fixed.**
  - **The rule (user's words): Settings control the layout + the default page look; the ribbon controls this page's look.** First attempt got it inverted (Settings drove the page, the app frame followed the OS) — the user rightly rejected it because the *layout* could no longer be made light. Reworked: Settings → Appearance drives the whole app again (upstream behaviour restored); the ribbon "Appearance" button now writes a **per-page override** to `View.extra` (`page_theme_mode.dart`, mirroring the per-page text direction exactly — `inherit` = absence of key). `PageThemeScope` applies the override to the document subtree (page + desk) only. Removed the interim "App frame appearance" setting and `ChromeThemeMode` entirely. Commits `4762b470d` (rework), superseding `3ba5f93b8`/`0b818f19d`.
  - **Text + link colours now follow the page's theme** (`bbd1c386a`): the editor read colours from the context it was *constructed* in — above `PageThemeScope` — so an overridden page kept the layout's colours and lost contrast. Fixed by building the editor under `PageThemeScope` (a `Builder`). Also added `util/color_contrast.dart` (`ensureContrast`, WCAG) because the default cyan link is only 2.2:1 on white — now darkened to ~4.8:1 on light pages, untouched (7.3:1) on dark. 10 WCAG unit tests.
  - **⚠️ Keyboard-focus regression — introduced by this work, then fixed (`e992e4908` + `17a0ba146`).** `PageThemeScope` returned the child bare with no override and wrapped it in two theme widgets with one, so toggling a page's override changed the widget-tree **shape** → remounted the editor → dropped its keyboard focus. Symptom: "keyboard disabled" that persisted until relaunch. Root-caused via individual `key` presses (the physical path, not text injection) after ruling out a stuck OS modifier and the computer-use click offset (both real confounds this session). Fix: **constant widget structure** (always `Theme > AppFlowyTheme > child`, re-providing ambient themes when there's no override) so a toggle changes only theme DATA, never remounts; plus swapping `AnimatedAppFlowyTheme` → plain `AppFlowyTheme` (no per-frame subtree rebuild). Verified live and **user-confirmed working.** Lesson: conditionally adding/removing ancestor widgets around a stateful, focus-holding subtree remounts it — keep the shape constant.
  - **Process notes:** (1) an early misdiagnosis blamed a stuck modifier before the real cause was found — individual `key`-press testing (not `type` injection) was what isolated it. (2) Page-context menus (sidebar "…") will not open from synthetic clicks, so junk pages can't be deleted via automation.
- **2026-07-20 (session 3) — Phase 1 verified live, Phase 2 built, page surface added, RTL margins fixed. 7 commits.**
  - **Phase 1's outstanding verification was done on the real target**, closing the honesty gap left on 2026-07-19: tooltips show name+shortcut, the greyed no-cursor state explains itself, button actions apply with correct highlight states, Word-style pending formatting works (caret only, no selection), the floating toolbar stays suppressed, and collapse/tab state survives a restart. **The one failure was the collapse shortcut — and it is not a code bug:** `com.apple.keyboard.fnState` is unset on this Mac so F1 sends brightness-down, and Ctrl+F1 is a macOS system shortcut. The binding parses and is registered correctly; the *key* is unreachable. Deferred with the rest of the shortcuts work at the user's request.
  - **Phase 2 (per-page RTL/LTR) landed**, including the headline margin fix — see the decisions section above for the measured before/after and the corrected root cause.
  - **Three user requests built:** ribbon mirrors the sidebar's dock side; title/icon follow the page's direction; the document renders as a sheet on a desk (square corners, three edges, 32pt margin, top gap closing on scroll).
  - **Four review findings from reading the uncommitted Phase 2 draft** were worked through; one of them (a "falsely highlighted" direction button) turned out **not to be a bug** — it was a hover state, confirmed by re-testing with the pointer moved away. Recorded because a wrong bug report is worth the same scrutiny as a wrong fix.
  - **Process notes worth keeping (all three cost real mistakes this session):**
    1. `tail`-ing analyzer output hid a genuine compile error. Capture full output, then grep the file — the same rule `CLAUDE.md` already states for test runs applies to `flutter analyze`.
    2. **Computer-use `scroll` events do not reach Flutter scroll views here.** They silently no-op on both the Settings dialog and the editor. This produced a false bug report ("Settings → Workspace doesn't scroll") that the user corrected. Drive scrolling with the keyboard instead.
    3. **A click for focus is an edit.** Clicking the empty space below a document's content appends an empty paragraph; this happened to a real page and had to be undone. Focus the window via neutral chrome.
  - **A misread worth recording:** the user's "scrolling removes the top edge, as a real page would" was a *request*, not an observation, and it was briefly written into this spec as already-working emergent behaviour. Check whether the user is describing what **is** or what **should be** before recording it as fact.
- **2026-07-19 — scoping interview run; spec written; no code.** Architecture was already settled (`specs/plugin-system.md`, 2026-07-17), so the interview covered UI/UX only. All decisions above are the user's. The button inventory was read directly from the user's own AppFlowy page "Stuff to put into the ribbon" rather than reconstructed from memory. A capability audit against the app + editor fork sorted all ~50 items into exists / partial / missing with file:line evidence — the key finding being that **per-page RTL/LTR is far cheaper than assumed** (already read per-document, merely stored globally), while rulers, margins, footnotes, text boxes, drawing, diagrams and charts do not exist in any form. Honest framing agreed with the user: Phase 1 is one solid session; the remainder is a multi-session roadmap.

- **2026-07-19 (session 2) — spec signed off (with corrections) and Phase 1 BUILT.**
  Three spec claims were checked against the code and did not survive: the `selection!` force-unwrap is not the main risk (items already gate on `isActive`/`showInAnyTextType`, and a *collapsed* cursor is not null); **Word-style pending formatting already exists** in the editor fork (`EditorState.toggledStyle`), making the user's chosen no-selection behaviour nearly free and needing no fork change; and "reuse the toolbar items" is mutually exclusive with "a uniform button whose tooltip shows the live shortcut", because `ToolbarItem.builder` returns the entire finished button with a hardcoded shortcut string. The user chose to **own the button component**. Details in "Corrections to this spec".
  Built: nine files under `editor_plugins/ribbon/` plus marked `[fork:ribbon]` touches to six core files (feature flag, KV keys, deps_resolver, command_shortcuts, document_page, editor_page, settings_workspace_view). Wired and working: bold, italic, underline, strikethrough, inline code, cut/copy/paste, bulleted/numbered list, indent/outdent, align L/C/R, text direction LTR/RTL/auto, light-dark toggle. Everything else ships as visibly disabled "coming soon".
  **Verified on the real macOS target** (not headless): ribbon renders pinned above the editor, four tabs, tab switching works, chevron collapse works, groups render with captions, floating toolbar suppressed. `flutter analyze` clean; 13/13 unit tests pass. **Not verified live:** button *actions*, tooltips, the collapse shortcut, and restart persistence — no live typing was done, per the 2026-07-13 incident rule that live editing happens only in a scratch page.
  A near-full session was lost to a **blank-window red herring**. Root cause: the Flutter surface only presents a frame when the window receives an input event, so an app launched from a shell and screenshotted without clicking paints black. `sample` showed every Flutter thread parked in `mach_msg2_trap` with nothing queued; the Rust core was healthy throughout (workspace and views loading). A stash-and-rebuild of pristine code reproduced it, proving the ribbon was not the cause. Forcing frames via a window resize painted everything. Two false leads worth remembering: "translation assets are missing" (an `ls` run from the wrong directory — they are all present) and "the flag-on build is broken" (the same repaint issue needing more frames).
  Also this session: **the ribbon was changed to always-LTR** (see "Decisions taken during the Phase 1 build"), and future button designs were captured for the font picker, font size control, and paragraph styles.
  **Left unfixed and honestly flagged:** the RTL page-margin asymmetry. `EditorStyleCustomizer.documentPaddingFor` was added and is direction-aware, but measurement afterwards showed the visible margins essentially unchanged (left ~97px, right ~116px). The ~19px residual is close to `optionMenuWidth / 2`, pointing at the document column being *centred* inside a width that already reserves the option-menu gutter — centring absorbs the padding change. Needs a different fix; the added code is groundwork only and is marked as such in a code comment.
