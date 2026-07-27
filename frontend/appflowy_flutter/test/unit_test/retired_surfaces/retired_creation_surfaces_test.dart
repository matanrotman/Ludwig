import 'dart:io';

import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/retired_surfaces.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fork:retire-non-core-surfaces] The sweep, guarded.
///
/// `specs/retire-non-core-surfaces.md` names the trap explicitly, having learned
/// it once already: **the surfaces are spread across many call sites, and
/// finding them is the actual work.** `specs/ephemeral-pad.md`'s D12 was the
/// same shape — "just filter it out" turned out to touch seven surfaces — and
/// the failure mode here is identical: a menu nobody remembered, still offering
/// to create a thing that is supposed to be gone.
///
/// So this does not test each filter (they are one-line predicates, and testing
/// them would restate them). It asserts the thing a unit test can hold onto:
/// **every file that names a retired layout is accounted for** — retired, or
/// exempt with a reason.
///
/// ## What this proves, and what it does not
///
/// It proves no *new* call site appears unnoticed. It does **not** prove the
/// existing filters are correct — a file could import `RetiredSurfaces` and
/// filter the wrong list. Correctness rests on the live check in the spec's
/// acceptance list ("no route through the UI produces a Grid, Board, Calendar
/// or AI Chat").
void main() {
  /// Files that gate a creation/advertisement surface on [RetiredSurfaces].
  const retired = {
    'plugin.dart': 'sidebar + new-page menu (pluginBuilders)',
    'slash_menu_items_builder.dart': 'slash menu grid/kanban/calendar',
    'import_panel.dart': 'CSV + database imports',
    'import_type.dart': 'declares which layout each import creates',
    'command_palette.dart': 'the "Ask AI" entrance',
    'bottom_sheet_add_new_page.dart': 'mobile add-new-page sheet',
    'retired_surfaces.dart': 'the list itself',
  };

  /// Deliberately NOT gated. Each is an argument, not an oversight — change one
  /// only by arguing with its reason.
  const exempt = {
    'view_ext.dart':
        'layout to icon/plugin/tab mappings. An existing view of a retired '
            'type must still OPEN — retiring creation is not the same as '
            'breaking what exists, and a page that cannot open is data loss '
            'wearing a product decision as a disguise.',
    'view_more_action_button.dart':
        'already EXCLUDES Chat from its actions. It suppresses, never creates, '
            'so it needs no change — and must not be "fixed" into one.',
    'more_view_actions.dart': 'same: excludes Chat, creates nothing.',
    'link_to_page_widget.dart':
        'links to a view that already exists. Offers nothing creatable.',
    'insert_page_command.dart': 'same: references an existing view.',
    'shared_page_actions_button.dart':
        'acts on an already-shared page; creates nothing.',
    'ai_prompt_database_modal.dart':
        'the AI WRITER, a different surface from AI Chat and explicitly out of '
            'scope in the spec.',
    'select_sources_menu.dart': 'AI writer source picker; out of scope, as above.',
    'mobile_router.dart': 'routes to an existing view.',
    'mobile_view_page.dart': 'displays an existing view.',
    'mobile_grid_screen.dart': 'displays an existing grid.',
    'mobile_chat_screen.dart': 'displays an existing chat.',
    'default_mobile_action_pane.dart': 'acts on an existing view.',
    'mobile_page_card.dart': 'renders an existing view.',
    'mobile_space_tab.dart': 'renders existing views.',
    'chat.dart': 'the AI chat plugin itself — kept whole, that is the decision.',
    'database_items.dart':
        'DEFINES the grid/kanban/calendar slash-menu items. It offers nothing '
            'by itself; the only consumer is slash_menu_items_builder.dart, '
            'which is gated. Left defined so re-enabling is one edit there.',
    'inline_database_menu_item.dart':
        'defines inline database menu items that NOTHING references — verified '
            'by grep across lib/. Already dead before this change; retiring it '
            'again would be theatre.',
    'referenced_database_menu_item.dart': 'same: defined, referenced nowhere.',
    'view_item.dart':
        'names a newly created view ("a new document or chat starts unnamed"). '
            'It runs AFTER the sidebar picker has chosen a type, and that '
            'picker is gated in pluginBuilders() — so it can only ever be '
            'handed a type that survived the gate. It offers no choice itself.',
  };

  test('the four surfaces are retired in one findable place', () {
    expect(
      RetiredSurfaces.layouts,
      {
        ViewLayoutPB.Grid,
        ViewLayoutPB.Board,
        ViewLayoutPB.Calendar,
        ViewLayoutPB.Chat,
      },
      reason: 'if this changed deliberately, the spec and STATUS.md should say '
          'so — this is a product decision, not an implementation detail',
    );
    expect(
      RetiredSurfaces.pluginTypes,
      {
        PluginType.grid,
        PluginType.board,
        PluginType.calendar,
        PluginType.chat,
      },
      reason: 'the layout list and the plugin list must stay in step, or the '
          'sidebar menu and the rest of the app disagree about what exists',
    );
  });

  test('every file naming a retired layout is retired or explicitly exempt', () {
    final pattern = RegExp(
      r'ViewLayoutPB\.(Grid|Board|Calendar|Chat)\b',
    );
    final callers = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The retired subsystems themselves are kept whole and untouched — that
      // IS the decision, so their internals are not surfaces to classify.
      if (entity.path.startsWith('lib/plugins/database')) continue;
      if (pattern.hasMatch(entity.readAsStringSync())) {
        callers.add(entity.uri.pathSegments.last);
      }
    }

    expect(
      callers,
      isNotEmpty,
      reason: 'found no references at all — this test is looking in the wrong '
          'place (it expects to run from frontend/appflowy_flutter), so a green '
          'result would mean nothing',
    );

    final unclassified = callers.difference(retired.keys.toSet())
      ..removeAll(exempt.keys);

    expect(
      unclassified,
      isEmpty,
      reason: 'A new place names Grid/Board/Calendar/Chat: $unclassified.\n'
          'Classify it. Either gate it on RetiredSurfaces and add it to '
          '`retired`, or add it to `exempt` WITH A REASON. Do not add it to '
          '`exempt` just to make this pass — the whole point of this test is '
          'that a surface offering a retired thing gets noticed here rather '
          'than by the user finding a Kanban board in a menu.',
    );
  });
}
