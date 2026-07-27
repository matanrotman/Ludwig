import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// [fork:retire-non-core-surfaces] Grid, Board, Calendar and AI Chat are gone
/// from the UI. See `specs/retire-non-core-surfaces.md`.
///
/// > *Project management is not a problem Ludwig is trying to solve, so anything
/// > shaped like it is deadweight regardless of quality.*
/// > — `specs/product-direction.md`
///
/// ## This is a reversible product decision, and this file is the reversal
///
/// The code for all four surfaces stays in the repo, untouched. What is removed
/// is every route that **creates** one or **advertises** that one exists. The
/// user's words: *"it's ok to remove them from the UI but keep them in the code
/// for even a couple of months. If we see we need them… we can have a
/// discussion."*
///
/// So re-enabling must be **one edit, not archaeology**: empty [layouts] and
/// [pluginTypes] and every surface below comes back. That is the whole point of
/// routing every call site through here rather than writing twenty independent
/// conditions, and it is why nothing below hard-codes a layout inline.
///
/// ## AI Chat is hidden, not rejected
///
/// The user wants an AI chat — *"our own version, and very specific and
/// limited."* What is retired is AppFlowy's general-purpose chat, so it does not
/// squat on the space a deliberate one will need. That feature gets its own
/// interview and spec; do not read this file as a verdict on AI.
///
/// ## Opening an existing one still works, deliberately
///
/// `view_ext.dart`'s layout→icon/plugin/tab mappings are **out of scope and stay
/// working**. Retiring creation is not the same as breaking what exists. This
/// user has none of these views, but a fork built from this one might, and a
/// page that cannot open is data loss wearing a product decision's clothes.
class RetiredSurfaces {
  const RetiredSurfaces._();

  /// The retired view layouts. Empty this set to bring all four back.
  static const Set<ViewLayoutPB> layouts = {
    ViewLayoutPB.Grid,
    ViewLayoutPB.Board,
    ViewLayoutPB.Calendar,
    ViewLayoutPB.Chat,
  };

  /// The same four as plugin types, for the sidebar's `+` menu.
  ///
  /// Two vocabularies exist because the app has two: the folder speaks
  /// `ViewLayoutPB`, the plugin sandbox speaks [PluginType], and there is no
  /// total mapping between them (`blank`, `trash` and `databaseDocument` have no
  /// layout of their own). Listing both beats a lossy conversion.
  static const Set<PluginType> pluginTypes = {
    PluginType.grid,
    PluginType.board,
    PluginType.calendar,
    PluginType.chat,
  };

  /// Whether [layout] is retired from the UI.
  static bool isRetired(ViewLayoutPB layout) => layouts.contains(layout);

  /// Whether [type] is retired from the UI.
  static bool isRetiredPlugin(PluginType type) => pluginTypes.contains(type);

  /// Every surface this retirement touches, written down.
  ///
  /// `specs/retire-non-core-surfaces.md` names the trap: **the surfaces are
  /// spread across many call sites, and finding them is the actual work.** This
  /// is the same shape as `specs/ephemeral-pad.md`'s D12, where "just filter it
  /// out" turned out to touch seven surfaces. The guard test
  /// `test/unit_test/retired_surfaces/retired_creation_surfaces_test.dart` fails
  /// when a new call site appears that is neither listed here nor exempt.
  ///
  /// | Surface | Where |
  /// |---|---|
  /// | Sidebar `+` new-page menu | `plugin.dart` → `pluginBuilders()` |
  /// | Slash menu Grid/Board/Calendar | `slash_menu_items_builder.dart` |
  /// | Slash menu *referenced* database items | `slash_menu_items_builder.dart` |
  /// | Inline + referenced database menu | `inline_database_menu_item.dart`, `referenced_database_menu_item.dart` |
  /// | CSV import (creates a Grid) | `import_panel.dart` |
  /// | Command palette "Ask AI" | `command_palette.dart` |
  /// | Mobile add-new-page sheet | `bottom_sheet_add_new_page.dart` |
  ///
  /// Deliberately **exempt**, each an argument rather than an oversight:
  ///
  /// - `view_ext.dart` — layout→icon/plugin/tab mappings. An existing view must
  ///   still open. See the class doc above.
  /// - `lib/plugins/database/**`, `lib/plugins/ai_chat/**` — the subsystems
  ///   themselves. Kept whole and untouched; that is the decision.
  /// - `view_more_action_button.dart`, `more_view_actions.dart` — these already
  ///   *exclude* Chat from actions. They suppress, never create, so they need no
  ///   change and must not be "fixed".
  /// - `link_to_page_widget.dart`, `insert_page_command.dart` — link to a view
  ///   that already exists. They offer nothing that can be created.
  /// - `mobile/**` viewers (`mobile_grid_screen.dart`, `mobile_chat_screen.dart`,
  ///   `mobile_router.dart`, `mobile_view_page.dart`) — display an existing view.
  ///   This fork does not ship mobile yet regardless.
  /// - `ai_prompt_database_modal.dart`, `select_sources_menu.dart` — the AI
  ///   *writer*, a different surface from AI Chat and explicitly out of scope
  ///   (`specs/retire-non-core-surfaces.md`, "Out of scope").
  static const surfacesDocumentedAbove = true;
}
