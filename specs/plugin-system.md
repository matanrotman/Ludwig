# A Plugin System for AppFlowy

## Goal
Be able to add features to AppFlowy — starting with a **ribbon menu** for pages — without those features having to live inside the official app, and without every one of them becoming another file this fork has to reconcile with upstream forever.

## Status
**Stub. Idea captured 2026-07-16, not scoped, no code.** Needs a scoping interview before anything is built. What follows is the groundwork from the 2026-07-16 investigation so that interview starts informed rather than from scratch.

## Where this came from
The user wanted a **ribbon menu** (a Word-style formatting strip pinned above the page) but suspected it "might be too heavy for the official app," and hoped it could be added as a standalone plugin. Two other wants were attached to it:
1. **Per-page RTL/LTR** — direction chosen per page, not one global app setting.
2. **Turning off the floating selection toolbar** (the menu that pops up when you select text).

The investigation found the instinct was right — a ribbon probably *is* too heavy for upstream — but the escape hatch doesn't exist. Hence this spec.

## Current state — there is no plugin system, in any sense

**Nothing can be added at runtime. Nothing is discovered. Nothing registers itself.** Three separate things in this codebase are called "plugin"; all three are compile-time Dart composition (import a class, pass it to a constructor, or add a line to a core file). Verified 2026-07-16 — no `loadLibrary`, no `deferred as`, no `DynamicLibrary.open` anywhere.

| Thing named "plugin" | What it actually is |
|---|---|
| Editor's `lib/src/plugins/` | Format codecs — markdown, html, pdf, quill_delta — plus word_count. Nothing loadable. |
| `AppFlowy-plugins` git dependency | A **two-widget library**: `code_block/` and `link_preview/`. Its `plugin.dart` files are pure barrel exports — no Plugin class, no registry, no lifecycle, no manifest. (README also advertises a Video Block; it does not exist at the pinned commit.) |
| AppFlowy's own `Plugin` / `PluginType` | An **internal view-type abstraction**, not an extension point. `PluginType` is a **closed enum** (`startup/plugin/plugin.dart:13-22`) and `PluginBuilder.layoutType` returns `ViewLayoutPB`, a **Rust backend protobuf enum** — also closed. It answers "which editor opens for this view type" (document vs board vs grid). Adding one means editing the enum + `startup/tasks/load_plugin.dart:22-42` + likely the backend protobuf. |

**Today's real "extension mechanism" is global mutable statics.** `editor_page.dart:167-193` extends the editor by mutating package-level globals (`AppFlowyRichTextKeys.partialSliced`, `indentableBlockTypes`, `convertibleBlockTypes`, `editorLaunchUrl`, `DocumentHTMLDecoder.enableColorParse`), plus `toolbarItemWhiteList`. Process-wide, order-dependent, unscoped. Any real plugin system would need to replace this, and that's a meaningful part of the work.

**Trap to know:** `EditorState.toolbarItems` (`editor_state.dart:215`) and `.selectionMenuItems` (`:211`) look exactly like a registration seam. **They are dead code** — grepped across both the package and the app, never read. Don't build on them without checking.

## The seams that DO exist (what a plugin system would be built out of)
Injectable via the `AppFlowyEditor` constructor (`editor.dart:23-57`), each defaulting via `?? standardXxx` so you spread-and-extend:
- `blockComponentBuilders` (can also *override* built-ins), `characterShortcutEvents`, `commandShortcutEvents`, `contextMenuItems`
- `header` / `footer`, `editorStyle`, `documentRules`, `blockWrapper`, `editorScrollController`
- `disableSelectionService` / `disableKeyboardService` / `disableScrollService`

**Notable gap: there is no toolbar parameter at all.** No `toolbarItems`, no `enableFloatingToolbar`. The floating toolbar isn't part of `AppFlowyEditor` — it's a separate widget the host wraps around it, attached **unconditionally** at `editor_page.dart:437`, with its items hardcoded as a `final` field at `editor_page.dart:96-116`.

## The two motivating features do NOT need a ribbon — or a plugin system
Worth stating plainly so they don't get blocked behind this much larger idea:

- **Per-page RTL/LTR** — feasible today on an existing, proven seam. `View.extra` is a per-page JSON settings blob (`view_ext.dart:28-53`, `ViewExtKeys`) already storing `font`, `font_layout`, `line_height_layout`, `cover`, `is_pinned`. Read via `jsonDecode(view.extra)` and written via `mergeMaps` + `ViewBackendService.updateView` (`document_page_style_bloc.dart:124-143`). A per-page direction would slot in where `EditorStyle.defaultTextDirection` is sourced — the fallback injection point is precise: `text_direction_mixin.dart:147-150`. **Zero changes to block-level direction semantics.** Caveat: that bloc lives under `lib/mobile/`, so desktop needs its own read path (or the bloc lifts out of `mobile/`).
- **Turning off the floating toolbar** — already possible **with no core edit**, at runtime, from your own file: set `selectionExtraInfoDisableToolbar` in `editorState.selectionExtraInfo` (checked at `floating_toolbar.dart:144`). It's public API and **the app already does exactly this** at `ai_writer_toolbar_item.dart:230`. Three confusable keys exist — `selectionExtraInfoDisableToolbar` (desktop), `selectionExtraInfoDisableFloatingToolbar` (mobile), `selectionExtraInfoDisableMobileToolbarKey`.

## If a ribbon gets built (with or without a plugin system)
- **Insertion point**: the existing `Column` at `document_page.dart:228-235` — the same pattern the deleted-page banner already uses (fixed strip above, editor fills the rest). ~1 line in a core file + your own new files. About as merge-friendly as this can get.
- **Do NOT use the editor's `header` param.** It renders as item index 0 *inside the scrollable list* (`page_block_component.dart:68`, `:102-106`) — it holds the cover/icon and **scrolls away with the document**. A ribbon must stay pinned.

## To confirm with me (interview before building)
- **What is a "plugin" here, concretely?** A compile-time module with a clean registration API (realistic, and would already remove the global-mutation mess), or genuinely loadable-at-runtime code (very hard in Flutter — AOT builds can't load arbitrary Dart; would likely mean a scripting layer or WASM)? These are wildly different projects.
- **Who is it for?** Just this fork (then it's really "an internal architecture cleanup so my features stop touching core"), or something upstream might adopt (then it needs their buy-in *first* — worth an issue/discussion before code, given the toolbar-PR precedent)?
- **What must a plugin be able to do?** Add pinned chrome (a ribbon)? Add blocks? Add shortcuts? Add toolbar items? Suppress built-in UI? Store per-page settings? The seam list above says some are nearly free today and some don't exist at all.
- **Is it worth it vs. just making the ~1-line core edit?** Honest framing: a ribbon costs one line in `document_page.dart`. A plugin system to avoid that line is a large project. The real payoff is *cumulative* — many features, no core edits, less merge pain — so it only pays off if a lot of features are coming.
- **Ribbon specifics** (needed either way): which buttons, does it replace or coexist with the floating toolbar, per-page or global, what happens on mobile?

## Files / interfaces likely involved
*Fill in during the interview — but the investigated seams are listed above and are the starting point.*

## Out of scope
*Fill in during the interview.*

## Verification
*Fill in during the interview.*

## Session Log
- **2026-07-16 — investigation only, no code.** Explored whether a plugin/extension system exists that could host a ribbon standalone. Conclusion: it does not, in any of the three senses the word is used in this codebase. Recorded the real seams, the dead-code trap (`EditorState.toolbarItems`), the global-mutation status quo, and the fact that both motivating features (per-page RTL, floating-toolbar off) are achievable without a ribbon or a plugin system. User asked to entertain building a real plugin system and scope it later; this stub is that placeholder. No interview yet.
