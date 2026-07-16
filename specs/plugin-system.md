# A Plugin System for AppFlowy — RESOLVED: not building one

## Verdict (2026-07-17, user signed off — do not re-litigate)
**No plugin system gets built, compile-time or runtime.** The ribbon menu (and every future feature) is built the way the backup feature was: **isolated "sidecar" modules — new files behind a feature flag, touching core files at a handful of known, documented points.** This was decided after a deep-research investigation (101 agents, 19 sources, every key claim adversarially fact-checked) plus a full codebase exploration. The evidence is recorded below so this question never needs re-opening.

**Ranking of the four options considered:**
1. **(A) Direct sidecar build — CHOSEN.** Matches the fork's proven discipline (backup: ~15 core lines, all else new files); zero new attack surface; smallest total work.
2. **(B) Thin compile-time extension layer — only if earned.** Trigger rule: if wiring the ribbon reveals **3+ scattered core touch-points doing the same kind of thing**, collapse them into one registry *then*. Never build the abstraction speculatively — an unused framework is itself merge-conflict surface.
3. **(D) Upstream-first — demoted to opportunistic complement.** Keep the PR #1222 habit (small generic fixes/seams when convenient), never block on upstream's timeline.
4. **(C) Runtime plugin system — REJECTED.**

## The evidence (fact-checked 2026-07-17; votes are 3-verifier adversarial checks)

1. **AppFlowy's own team already tried a runtime plugin system and publicly gave up** (3-0, first-party). Their Aug 2023 engineering post — *"Don't Try to Load Code Dynamically in Your Flutter App. It's Terrible"* (blog.appflowy.io) — documents trying code-push (app-store bans), isolates + mirrors (unavailable in Flutter), and dart_eval (a trivial plugin needed ~10 classes / ~1,000 lines of bridge code; they had to fork the eval tooling). Nothing has shipped since. Rebuilding their failed project solo is a non-starter.
2. **The Obsidian/VS Code plugin model doesn't transfer to Flutter** (3-0). Those apps host a JavaScript engine that loads code at runtime; VS Code additionally isolates extensions in a separate Node.js process, Joplin gives each plugin its own process (2-1). Flutter compiles ahead-of-time — no such engine exists. Bolting one on (dart_eval/flutter_eval, both pre-1.0): 10–50× slower, large Dart-language gaps, ~100 supported widgets, and a **self-reported, never-audited sandbox** (3-0).
3. **Security capstone** (3-0): Obsidian's own docs admit it "cannot reliably restrict plugins" — plugins get the app's full powers. This app holds the only copy of the user's writing (cloud sync is dead — see STATUS.md). And a single-user fork never installs third-party plugins, so runtime loading's entire benefit is absent while all its risk remains.
4. **No upstream landing zone for a ribbon** (2-1 — softest key finding, but the closure was API-verified): the one toolbar-customization request (AppFlowy #3546) was closed **"not planned"** Oct 2025 after two years; a fixed-toolbar request (editor #734) has sat since 2024; 9 of 10 recent editor customization seams were authored by the core team, not outsiders.
5. **Everything upstream calls a "plugin" is compile-time Dart composition** (3-0) — maintainers' own answer to "how do I write a plugin" points at the editor's customizing.md; the official AppFlowy-Plugins repo is three editor block components, none touching toolbars/menus/chrome.

**Honest limits:** the fork-maintenance "best practices" research leg mostly failed verification (even GitHub's own sync-cadence advice was refuted as stated), so that part of the decision leans on this fork's own proven discipline. Known residual risk of the sidecar approach: an upstream rename can break the build with no merge conflict (our new files call their APIs). Mitigation: every sidecar feature ships behind a feature flag, so the app keeps working with the feature off while we repair.

## Roadmap decided 2026-07-17
1. **`specs/ribbon-menu.md` will be created after its scoping interview** (interview prepped below — next session). Nothing gets coded before that spec is signed off.
2. **Order: ribbon FIRST, right-click context menu SECOND** (user's decision 2026-07-17, reversing Claude's suggested order).
3. Both are built sidecar-style per the verdict above.

## Ribbon scoping interview — prepped 2026-07-17, to run next session
Ask a few at a time, plain language, concrete comparisons:
1. **Contents/tabs:** Word has Home / Insert / Layout / etc. How much of that? Single-strip (like WordPad) or tabbed (like Word)? Which formatting actions are must-haves day one?
2. **Visibility:** always pinned, collapsible (Word's Ctrl+F1), or auto-hide? Per-page memory or one global state?
3. **Floating toolbar's fate:** dies entirely, or stays available behind the feature flag / a setting? (Architecture supports either — it's one branch point.)
4. **Right-click menu contents** (phase 2, but shapes shared pieces): which actions — the Word set is cut/copy/paste/paste-special, font, paragraph, styles, link, synonyms?
5. **Mobile:** proposal is desktop-only ribbon, mobile untouched (mobile has its own toolbar system). Confirm.
6. **RTL:** the ribbon must respect the app's RTL work — mirrored layout? (Likely yes given every prior feature; confirm and record.)
7. **Scope guard:** which Word behaviors are explicitly OUT (styles gallery? format painter? find/replace relocation?) so the spec has a fence.

## Architecture facts for the ribbon build (codebase exploration 2026-07-17 — verified, with file:line)
These supersede/extend the 2026-07-16 groundwork below. App = `frontend/appflowy_flutter`, Editor = `~/Projects/appflowy-editor-fork`.

- **The floating toolbar is app-side with a single clean gate** — the app opts into wrapping the editor with `FloatingToolbar` at `lib/plugins/document/presentation/editor_page.dart:440` (items hardcoded at `:97-117`). Replacing it = branch around that block (`:437-481`). **Zero editor-fork changes needed for removal.** It's already bypassed for mobile (`:417-435`) and deleted views (`:411-413`).
- **A ribbon can re-host the existing toolbar buttons.** `ToolbarItem.builder` (editor `lib/src/render/toolbar/toolbar_item.dart:30-36`) has no floating-toolbar dependency — call it directly with context/editorState/colors. Underlying commands are clean and UI-free: `toggleAttribute` / `formatDelta` / `formatNode` (editor `lib/src/editor/command/text_commands.dart:139-274`); `toggleAttribute` handles collapsed selections via `toggledStyle` (click-Bold-then-type works free). **Trap:** app item builders force-unwrap `editorState.selection!` (e.g. `custom_format_toolbar_items.dart:60`) — a persistent ribbon must gate on `isActive`/null selection or these throw. App item inventory: `editor_plugins/toolbar_item/` (10 files, IDs in `toolbar_id_enum.dart`).
- **Right-click already has a doorway the app uses.** Editor param `contextMenuItems` (consumed desktop-only via `DesktopSelectionServiceWidget`); the app already overrides it at `editor_page.dart:387` → `customContextMenuItems` (`editor_plugins/context_menu/custom_context_menu.dart` — Copy/Paste/Paste-plain/Cut). `ContextMenuItem` = clean command object `{getName, onPressed, isApplicable}`. **Gap:** the menu widget itself (`editor lib/src/service/context_menu/context_menu.dart`) is primitive — no icons, no submenus, no screen-edge flip; a Word-style menu means replacing that widget in the fork. Upstream 6.1.0 later added a "context menu builder" param (PR #1152, merged 2025-11-06) — **not in our pin (5.2.0-era)**; mirror its API shape in the fork so a future merge collapses. Show-guards worth knowing: right-click must land within 20px of the selection, text-only nodes (`desktop_selection_service.dart:366-412`).
- **Known wart:** right-click does NOT dismiss the floating toolbar — both can be on screen at once today. `FloatingToolbarController.hideToolbar()` (getIt singleton, `startup.dart:198-200`) exists for coordination. Moot if the ribbon replaces the floating toolbar.
- **Insertion point + precedent confirmed:** the `Column` at `lib/plugins/document/document_page.dart:228-235`; the deleted-page banner (`:230-232`, `if (... && UniversalPlatform.isDesktop)`) is the exact pinned-strip template — a ribbon is one more child above `Expanded(child: editor)`. Do NOT use the editor's `header:` param (scrolls away with the document).
- **Feature flag:** `FeatureFlag` enum (`lib/shared/feature_flags.dart:14-48`, KV-persisted, runtime-togglable) — a `ribbonMenu` flag is one enum member + one `isOn` case; precedent for use in editor_page: `FeatureFlag.inlineSubPageMention.isOn` at `editor_page.dart:84`.
- **Settings page precedent (backup, Stage 3):** enum member (`settings_dialog_bloc.dart:19`) → menu entry (`settings_menu.dart:82-85`) → page switch (`settings_dialog.dart:145-146`) → own view+bloc files. Device-local UI prefs use plain KV via cubit (model: `setSidebarDockSide`, `setTextScaleFactor` in `appearance_cubit.dart`).
- **Touch-point budget precedent (backup Stages 1-2):** ~15 core lines total (`kv_keys.dart` +7, `deps_resolver.dart` +5, `startup.dart` +2, `prelude.dart` +1), all marked `[fork:backup]`; everything else new files. The ribbon should match this discipline with a `[fork:ribbon]` marker.
- **Mobile branching pattern:** `UniversalPlatform.isMobile/.isDesktop` (35 uses in `lib/plugins/document` alone) — one guard at the insertion point suffices.
- **Correction to earlier notes:** `editor_plugins/shortcuts/` is upstream code, not one of our features. Our real modularity precedents are `lib/shared/backup/` and `desktop_toolbar/`.

---

## Original goal (kept for history)
Be able to add features to AppFlowy — starting with a **ribbon menu** for pages — without those features having to live inside the official app, and without every one of them becoming another file this fork has to reconcile with upstream forever. *(Resolution: the sidecar pattern achieves the second half of this; the first half — features living outside the app — is the part that was rejected as not worth its cost.)*

## Where this came from
The user wanted a **ribbon menu** (a Word-style formatting strip pinned above the page) but suspected it "might be too heavy for the official app," and hoped it could be added as a standalone plugin. Two other wants were attached to it:
1. **Per-page RTL/LTR** — direction chosen per page, not one global app setting.
2. **Turning off the floating selection toolbar** (the menu that pops up when you select text).

The investigation found the instinct was right — a ribbon probably *is* too heavy for upstream — but the escape hatch doesn't exist, and (per the verdict above) building it isn't worth it.

## Current state — there is no plugin system, in any sense (2026-07-16 groundwork, confirmed by 2026-07-17 research)

**Nothing can be added at runtime. Nothing is discovered. Nothing registers itself.** Three separate things in this codebase are called "plugin"; all three are compile-time Dart composition (import a class, pass it to a constructor, or add a line to a core file). Verified 2026-07-16 — no `loadLibrary`, no `deferred as`, no `DynamicLibrary.open` anywhere.

| Thing named "plugin" | What it actually is |
|---|---|
| Editor's `lib/src/plugins/` | Format codecs — markdown, html, pdf, quill_delta — plus word_count. Nothing loadable. |
| `AppFlowy-plugins` git dependency | A **two-widget library**: `code_block/` and `link_preview/`. Its `plugin.dart` files are pure barrel exports — no Plugin class, no registry, no lifecycle, no manifest. (README also advertises a Video Block; it does not exist at the pinned commit.) |
| AppFlowy's own `Plugin` / `PluginType` | An **internal view-type abstraction**, not an extension point. `PluginType` is a **closed enum** (`startup/plugin/plugin.dart:13-22`) and `PluginBuilder.layoutType` returns `ViewLayoutPB`, a **Rust backend protobuf enum** — also closed. It answers "which editor opens for this view type" (document vs board vs grid). |

**Today's real "extension mechanism" is global mutable statics.** `editor_page.dart:167-193` extends the editor by mutating package-level globals (`AppFlowyRichTextKeys.partialSliced`, `indentableBlockTypes`, `convertibleBlockTypes`, `editorLaunchUrl`, `DocumentHTMLDecoder.enableColorParse`), plus `toolbarItemWhiteList`. Process-wide, order-dependent, unscoped. *(If the ribbon work ever wants Option B's registry, THIS mess is the honest first candidate to collapse — not a new abstraction.)*

**Trap to know:** `EditorState.toolbarItems` (`editor_state.dart:215`) and `.selectionMenuItems` (`:211`) look exactly like a registration seam. **They are dead code** — grepped across both the package and the app, never read. Don't build on them without checking.

## The seams that DO exist
Injectable via the `AppFlowyEditor` constructor (`editor.dart:23-57`), each defaulting via `?? standardXxx` so you spread-and-extend:
- `blockComponentBuilders` (can also *override* built-ins), `characterShortcutEvents`, `commandShortcutEvents`, `contextMenuItems`
- `header` / `footer`, `editorStyle`, `documentRules`, `blockWrapper`, `editorScrollController`
- `disableSelectionService` / `disableKeyboardService` / `disableScrollService`

**Notable gap: there is no toolbar parameter at all** — but per the 2026-07-17 findings above, none is needed: the toolbar wrapper is app-side.

## The two motivating side-features still do NOT need the ribbon
- **Per-page RTL/LTR** — feasible today on `View.extra` (per-page JSON settings blob, `view_ext.dart:28-53`); injection point `text_direction_mixin.dart:147-150`. Caveat: the style bloc lives under `lib/mobile/`, desktop needs its own read path.
- **Turning off the floating toolbar** — for a *per-selection* suppression, `selectionExtraInfoDisableToolbar` works with no core edit (the app already uses it at `ai_writer_toolbar_item.dart:230`). For *permanent* removal, the single gate at `editor_page.dart:437-481` (see 2026-07-17 findings).

## Session Log
- **2026-07-16 — investigation only, no code.** Explored whether a plugin/extension system exists that could host a ribbon standalone. Conclusion: it does not, in any of the three senses the word is used in this codebase. Recorded the real seams, the dead-code trap (`EditorState.toolbarItems`), the global-mutation status quo, and the fact that both motivating features (per-page RTL, floating-toolbar off) are achievable without a ribbon or a plugin system. User asked to entertain building a real plugin system and scope it later; this stub is that placeholder. No interview yet.
- **2026-07-17 — RESOLVED, no code.** Deep-research investigation (101-agent web harness: upstream roadmap, comparable apps' plugin models, Flutter runtime-extensibility, fork-maintenance practice, security threat model — 25 key claims adversarially verified, 19 confirmed / 6 refuted) + full codebase exploration (context-menu chain, floating-toolbar wiring, toolbar-item reusability, modularity/settings/flag precedents). Verdict signed off by the user: **no plugin system — sidecar modules (Option A), with Option B's registry only if a 3+-touch-point trigger fires, upstream PRs opportunistic only, runtime plugins rejected outright.** Decisive evidence: AppFlowy's own failed first-party dart_eval attempt; JS-runtime dependence of the Obsidian/VS Code model; unaudited dart_eval sandbox vs. an app holding the user's only copy of their writing; upstream's "not planned" closure of toolbar customization. User also decided: **ribbon first, right-click menu second**; `specs/ribbon-menu.md` to be written after next session's scoping interview (questions prepped above). STATUS.md updated; spec restructured from stub → resolution record.
