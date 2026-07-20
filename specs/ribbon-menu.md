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
- **Phase 3 — the small app-side gaps.** Clear formatting, sentence case, justify, paragraph spacing.
- **Phase 4 — the fork-crossing gaps.** Superscript, subscript, footnote — each needs a new delta attribute in the editor fork, a fork commit, and a pin re-sync. Grouped so there's one fork round-trip, not three.
- **Phase 5 — the partials.** Font size per selection, desktop line spacing, page colour, margins, ruler.
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
  - **A minimum desk margin is required or the feature silently does nothing.** Document width defaults to `maxDocumentWidth` (1920) — wider than a typical editor pane — so the sheet clamps to the full pane and no desk remains. `_kMinDeskMargin` (48pt each side) guarantees the page reads as a page; the user accepted the ~96pt of text width this costs at wide settings. Note the wrapper **insets** the editor rather than painting behind it: narrowing only the painted sheet would let text spill onto the desk.
- **Measured result of the margin fix** (real macOS target, 1422pt window): rendered text edges now sit at **≈104px left / ≈104px right**, against **97/116** measured on 2026-07-19. The 2026-07-19 diagnosis that blamed the `Center()` was wrong — centring is symmetric by construction; the real cause was the block option gutter growing 44→73 (commit `ffc069150`) while three separate compensation sites kept the old number.

## Button designs specified for future phases (2026-07-19, user)
Captured while building Phase 1; each gets built in its own session.
- **Font picker** — a dropdown with a **filter/search box**. Each font's *name* renders **in that font**, so the list previews itself.
- **Font size** — a **type-in box flanked by two carets** ("elevator" styling): one to increase, one to decrease. Not a plain dropdown.
- **Paragraph styles** — the ability to edit the **hierarchy of styles** (heading levels and body), in the style of Google Docs' "paragraph styles". This is a new capability, not in the original inventory, and likely needs its own spec.

## Open questions
- Which keyboard shortcut collapses the ribbon (Word uses Ctrl+F1; AppFlowy's rebindable system means this is a default, not a commitment).
- Whether the Tools tab's Translate/Transcribe/Record buttons should link out to their future specs or simply sit disabled.

## Sign-off
**Signed off 2026-07-19** (session 2), subject to the three corrections and three decisions recorded above.

## Session Log
- **2026-07-19 — scoping interview run; spec written; no code.** Architecture was already settled (`specs/plugin-system.md`, 2026-07-17), so the interview covered UI/UX only. All decisions above are the user's. The button inventory was read directly from the user's own AppFlowy page "Stuff to put into the ribbon" rather than reconstructed from memory. A capability audit against the app + editor fork sorted all ~50 items into exists / partial / missing with file:line evidence — the key finding being that **per-page RTL/LTR is far cheaper than assumed** (already read per-document, merely stored globally), while rulers, margins, footnotes, text boxes, drawing, diagrams and charts do not exist in any form. Honest framing agreed with the user: Phase 1 is one solid session; the remainder is a multi-session roadmap.

- **2026-07-19 (session 2) — spec signed off (with corrections) and Phase 1 BUILT.**
  Three spec claims were checked against the code and did not survive: the `selection!` force-unwrap is not the main risk (items already gate on `isActive`/`showInAnyTextType`, and a *collapsed* cursor is not null); **Word-style pending formatting already exists** in the editor fork (`EditorState.toggledStyle`), making the user's chosen no-selection behaviour nearly free and needing no fork change; and "reuse the toolbar items" is mutually exclusive with "a uniform button whose tooltip shows the live shortcut", because `ToolbarItem.builder` returns the entire finished button with a hardcoded shortcut string. The user chose to **own the button component**. Details in "Corrections to this spec".
  Built: nine files under `editor_plugins/ribbon/` plus marked `[fork:ribbon]` touches to six core files (feature flag, KV keys, deps_resolver, command_shortcuts, document_page, editor_page, settings_workspace_view). Wired and working: bold, italic, underline, strikethrough, inline code, cut/copy/paste, bulleted/numbered list, indent/outdent, align L/C/R, text direction LTR/RTL/auto, light-dark toggle. Everything else ships as visibly disabled "coming soon".
  **Verified on the real macOS target** (not headless): ribbon renders pinned above the editor, four tabs, tab switching works, chevron collapse works, groups render with captions, floating toolbar suppressed. `flutter analyze` clean; 13/13 unit tests pass. **Not verified live:** button *actions*, tooltips, the collapse shortcut, and restart persistence — no live typing was done, per the 2026-07-13 incident rule that live editing happens only in a scratch page.
  A near-full session was lost to a **blank-window red herring**. Root cause: the Flutter surface only presents a frame when the window receives an input event, so an app launched from a shell and screenshotted without clicking paints black. `sample` showed every Flutter thread parked in `mach_msg2_trap` with nothing queued; the Rust core was healthy throughout (workspace and views loading). A stash-and-rebuild of pristine code reproduced it, proving the ribbon was not the cause. Forcing frames via a window resize painted everything. Two false leads worth remembering: "translation assets are missing" (an `ls` run from the wrong directory — they are all present) and "the flag-on build is broken" (the same repaint issue needing more frames).
  Also this session: **the ribbon was changed to always-LTR** (see "Decisions taken during the Phase 1 build"), and future button designs were captured for the font picker, font size control, and paragraph styles.
  **Left unfixed and honestly flagged:** the RTL page-margin asymmetry. `EditorStyleCustomizer.documentPaddingFor` was added and is direction-aware, but measurement afterwards showed the visible margins essentially unchanged (left ~97px, right ~116px). The ~19px residual is close to `optionMenuWidth / 2`, pointing at the document column being *centred* inside a width that already reserves the option-menu gutter — centring absorbs the padding change. Needs a different fix; the added code is groundwork only and is marked as such in a code comment.
