import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [fork:ephemeral-pad] D12 — the filtering sweep, guarded.
///
/// `specs/ephemeral-pad.md` names the risk this file exists for: the pad's
/// filtering points are **not all in one place**, and missing one leaks a page
/// that does not exist yet into a surface that implies it does. That is not a
/// bug you notice — it is a "Pad" row in a search box that looks like a page
/// you forgot writing.
///
/// So rather than testing each filter (they are one-line predicates inside
/// widgets and blocs, and testing them would mostly restate them), this asserts
/// something a unit test can actually hold onto: **every place that asks the
/// folder for all views is accounted for.** A new one has to be classified —
/// filtered, or exempt with a reason — or this fails.
///
/// ## What this proves, and what it does not
///
/// It proves no *new* view-listing surface appears unnoticed. It does **not**
/// prove the existing filters are correct — a file could import `EphemeralPad`
/// and filter the wrong list. Correctness of each filter rests on the live
/// check in the spec's acceptance list ("searching for text that is in the
/// un-promoted pad finds nothing").
void main() {
  /// Surfaces that offer views to the user, and therefore filter the pad.
  const filtered = {
    'command_palette_bloc.dart': 'search results',
    'space_search_bloc.dart': 'sidebar + move-to search',
    'inline_page_reference.dart': 'editor @ page mention',
    'link_search_text_field.dart': 'toolbar link-to-page',
    'chat_input_control_cubit.dart': 'AI chat @ mention',
    'mobile_page_selector_sheet.dart': 'mobile page selector',
    'mention_page_bottom_sheet.dart': 'mobile AI mention',
  };

  /// Deliberately NOT filtered. Each entry is an argument, not an oversight —
  /// change one only by arguing with its reason.
  const exempt = {
    'view_service.dart': 'the backend call itself, not a surface',
    'snapshot_browse_service.dart':
        'the restore browser. It exists to show what a backup holds, and a '
            'recovery tool that hides content is worse than useless. A pad '
            'captured mid-sentence is exactly the thing someone would be '
            'looking for.',
    'fix_data_widget.dart':
        'the settings data-repair tool. It works on the raw folder on purpose; '
            'hiding rows from a repair tool would be actively harmful.',
    'reminder_bloc.dart':
        'resolves one already-known view id for display. It never offers a '
            'list to choose from, so there is nothing to leak into.',
  };

  test('every view-listing surface is filtered or explicitly exempt', () {
    final callers = <String>{};
    final lib = Directory('lib');
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('getAllViews()')) {
        callers.add(entity.uri.pathSegments.last);
      }
    }

    expect(
      callers,
      isNotEmpty,
      reason: 'found no getAllViews() callers at all — this test is looking in '
          'the wrong place (it expects to run from frontend/appflowy_flutter), '
          'so a green result would mean nothing',
    );

    final unclassified =
        callers.difference(filtered.keys.toSet()).difference(exempt.keys.toSet());
    expect(
      unclassified,
      isEmpty,
      reason: 'New place(s) listing every view: $unclassified.\n'
          'The ephemeral pad is a real page flagged in View.extra, so it comes '
          'back from getAllViews() like any other. Decide which this is:\n'
          '  • a surface the user picks pages from → filter it with '
          'EphemeralPad.withoutPad(...) and add it to `filtered` here\n'
          '  • not a discovery surface → add it to `exempt` WITH the reason\n'
          'See specs/ephemeral-pad.md, decision D12.',
    );
  });

  test('each filtered surface actually references the pad', () {
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = entity.uri.pathSegments.last;
      if (!filtered.containsKey(name)) continue;
      if (!entity.readAsStringSync().contains('EphemeralPad')) {
        missing.add('$name (${filtered[name]})');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'These surfaces are listed as pad-filtered but no longer mention '
          'EphemeralPad — a filter was removed or refactored away: $missing',
    );
  });
}
