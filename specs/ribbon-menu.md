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

## Open questions
- Visual grouping inside the ~30-button Content tab (separators? group captions? icon-only vs icon+label?) — a build-time design decision to walk through with the user.
- Which keyboard shortcut collapses the ribbon (Word uses Ctrl+F1; AppFlowy's rebindable system means this is a default, not a commitment).
- Whether the Tools tab's Translate/Transcribe/Record buttons should link out to their future specs or simply sit disabled.

## Sign-off
**Awaiting user sign-off on this spec before any code is written** (per `CLAUDE.md` → "Scoping a new feature").

## Session Log
- **2026-07-19 — scoping interview run; spec written; no code.** Architecture was already settled (`specs/plugin-system.md`, 2026-07-17), so the interview covered UI/UX only. All decisions above are the user's. The button inventory was read directly from the user's own AppFlowy page "Stuff to put into the ribbon" rather than reconstructed from memory. A capability audit against the app + editor fork sorted all ~50 items into exists / partial / missing with file:line evidence — the key finding being that **per-page RTL/LTR is far cheaper than assumed** (already read per-document, merely stored globally), while rulers, margins, footnotes, text boxes, drawing, diagrams and charts do not exist in any form. Honest framing agreed with the user: Phase 1 is one solid session; the remainder is a multi-session roadmap.
