import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/delete_with_children_dialog.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

/// Tests for the ask-first delete dialog (`specs/delete-and-trash.md`, Phase 2).
///
/// The behaviour worth defending here is what the dialog *tells* the user: an
/// understated count is precisely how a page was lost on 2026-07-25, so the number
/// shown and the buttons offered are the contract, not the styling.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  /// Holds what the dialog handed back, so a test can assert on the outcome as well
  /// as on what was rendered.
  final outcome = <String, Object?>{};

  Future<void> pumpDialog(
    WidgetTester tester, {
    required int descendantCount,
    bool containsPublishedPage = false,
    bool canMoveElsewhere = true,
    String name = 'Q3 planning',
  }) async {
    outcome
      ..clear()
      ..['closed'] = false
      ..['choice'] = null;

    final view = ViewPB()
      ..id = 'test-id'
      ..name = name;

    await tester.pumpWidget(
      WidgetTestApp(
        child: Builder(
          builder: (context) => TextButton(
            child: const Text('open'),
            onPressed: () async {
              outcome['choice'] = await showDialog<DeleteChoice>(
                context: context,
                builder: (_) => AppFlowyTheme(
                  data: AppFlowyDefaultTheme().light(),
                  child: DeleteWithChildrenDialog(
                    view: view,
                    descendantCount: descendantCount,
                    containsPublishedPage: containsPublishedPage,
                    canMoveElsewhere: canMoveElsewhere,
                  ),
                ),
              );
              outcome['closed'] = true;
            },
          ),
        ),
      ),
    );
    // The harness loads translations asynchronously, so the button only exists
    // after a settle.
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Every piece of text currently on screen, joined — the description is built by
  /// concatenation, so asserting on fragments is more honest than on a whole string.
  String visibleText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join(' ');

  group('what the dialog says', () {
    testWidgets('names the page being deleted', (tester) async {
      await pumpDialog(tester, descendantCount: 3, name: 'Q3 planning');

      expect(
        find.text(
          LocaleKeys.deleteWithChildren_title.tr(args: ['Q3 planning']),
        ),
        findsOneWidget,
      );
    });

    testWidgets('states the count of everything inside', (tester) async {
      await pumpDialog(tester, descendantCount: 7);

      expect(
        find.text(LocaleKeys.deleteWithChildren_countMany.tr(args: ['7'])),
        findsOneWidget,
      );
    });

    testWidgets('uses the singular wording for exactly one page',
        (tester) async {
      await pumpDialog(tester, descendantCount: 1);

      expect(
        find.text(LocaleKeys.deleteWithChildren_countOne.tr()),
        findsOneWidget,
      );
      expect(
        find.text(LocaleKeys.deleteWithChildren_countMany.tr(args: ['1'])),
        findsNothing,
      );
    });

    testWidgets(
        'the published-page warning is added to the count, not swapped for it',
        (tester) async {
      await pumpDialog(
        tester,
        descendantCount: 4,
        containsPublishedPage: true,
      );

      final text = visibleText(tester);
      expect(
        text.contains(LocaleKeys.deleteWithChildren_countMany.tr(args: ['4'])),
        isTrue,
        reason: 'the count must survive the published-page warning',
      );
      expect(
        text.contains(LocaleKeys.deleteWithChildren_alsoPublished.tr()),
        isTrue,
      );
    });
  });

  group('what the dialog offers', () {
    testWidgets('offers cancel, move elsewhere and delete everything',
        (tester) async {
      await pumpDialog(tester, descendantCount: 2);

      expect(find.text(LocaleKeys.button_cancel.tr()), findsOneWidget);
      expect(
        find.text(LocaleKeys.deleteWithChildren_moveThemElsewhere.tr()),
        findsOneWidget,
      );
      expect(
        find.text(LocaleKeys.deleteWithChildren_deleteEverything.tr()),
        findsOneWidget,
      );
    });

    testWidgets('hides the rescue route where moving is not supported',
        (tester) async {
      await pumpDialog(tester, descendantCount: 2, canMoveElsewhere: false);

      expect(
        find.text(LocaleKeys.deleteWithChildren_moveThemElsewhere.tr()),
        findsNothing,
        reason:
            'offering a rescue that cannot run would be worse than not offering it',
      );
      expect(
        find.text(LocaleKeys.deleteWithChildren_deleteEverything.tr()),
        findsOneWidget,
        reason: 'the destructive path must still be reachable',
      );
    });
  });

  group('what the dialog returns', () {
    testWidgets('"delete everything" returns deleteEverything', (tester) async {
      await pumpDialog(tester, descendantCount: 3);

      await tester
          .tap(find.text(LocaleKeys.deleteWithChildren_deleteEverything.tr()));
      await tester.pumpAndSettle();

      expect(outcome['choice'], DeleteChoice.deleteEverything);
    });

    testWidgets('"move them elsewhere" returns moveThemElsewhere',
        (tester) async {
      await pumpDialog(tester, descendantCount: 3);

      await tester
          .tap(find.text(LocaleKeys.deleteWithChildren_moveThemElsewhere.tr()));
      await tester.pumpAndSettle();

      expect(outcome['choice'], DeleteChoice.moveThemElsewhere);
    });

    testWidgets('cancel returns nothing, so nothing is deleted',
        (tester) async {
      await pumpDialog(tester, descendantCount: 3);

      await tester.tap(find.text(LocaleKeys.button_cancel.tr()));
      await tester.pumpAndSettle();

      expect(outcome['closed'], isTrue);
      expect(outcome['choice'], isNull);
    });

    testWidgets('Enter does nothing — there is no safe default here',
        (tester) async {
      await pumpDialog(tester, descendantCount: 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        find.text(LocaleKeys.deleteWithChildren_deleteEverything.tr()),
        findsOneWidget,
        reason: 'Enter must not commit either choice',
      );
      expect(outcome['choice'], isNull);
      expect(outcome['closed'], isFalse);
    });

    testWidgets('Escape cancels', (tester) async {
      await pumpDialog(tester, descendantCount: 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.text(LocaleKeys.deleteWithChildren_deleteEverything.tr()),
        findsNothing,
        reason: 'Escape should close the dialog',
      );
      expect(outcome['choice'], isNull);
    });
  });
}
