import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../shared/util.dart';

/// Real-macOS-render regression for the empty RTL line "very far cursor" bug.
///
/// Run on the real target, never headless `flutter test`.
///
/// Reproduces the user's exact scenario: document default text direction = RTL
/// (Settings > Workspace). Every line — including empty ones and the first
/// line — is RTL and shows the LTR English "Type '/'…" placeholder. The caret
/// used to render at the LEFT end of that hint instead of the line's RTL start
/// (the right).
///
/// IMPORTANT: measures the actual rendered [Cursor] widget's global rect, NOT
/// editorState.selectionRects() — the latter's transformRectToGlobal
/// mis-reports the caret for this shrink-wrapped RTL block, hiding the bug.
///
/// Deliberately registered in NO test runner, and it must stay that way. CI runs
/// the desktop_runner_* suites on Linux, where this test cannot be trusted: the
/// thresholds below were tuned against macOS text metrics, and Hebrew font
/// coverage on the runner isn't guaranteed. Run it by path on macOS instead —
/// see the guard in setUpAll for the command. Its absence from the runners is
/// intentional, not an oversight.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Backstop against the fake test font, which renders every glyph at one
    // fixed advance width and so flattens the RTL geometry this test exists to
    // measure — the assertions below would all pass while the app stayed
    // visibly broken.
    //
    // Today this cannot trigger from `flutter test <this path>`: living under
    // integration_test/ makes the tool demand a `-d` device, which gives us
    // real fonts. That protection is purely positional, though. The same
    // binding under test/ runs headless, reports "All tests passed", and
    // measures 'iii', 'WWW' and 'אאא' at an identical 42.0 (verified). So this
    // guard earns its place the day the file is moved or copied — which is
    // exactly how a test like this spreads.
    double widthOf(String s) => (TextPainter(
          text: TextSpan(text: s, style: const TextStyle(fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout())
        .width;

    if (widthOf('iii') == widthOf('WWW')) {
      fail(
        'Fake-font rendering detected: every glyph has the same advance width, '
        'so RTL caret geometry here is meaningless and this test would report a '
        'false pass. Run it against the real macOS target instead:\n\n'
        '  flutter test integration_test/desktop/document/'
        'document_rtl_empty_caret_test.dart -d macos\n\n'
        'Afterwards, clear the test data-path it writes into the real app prefs, '
        'or the app opens a blank sandbox:\n'
        '  defaults delete com.appflowy.appflowy.flutter '
        'flutter.io.appflowy.appflowy_flutter.path_location',
      );
    }
  });

  // The caret widget ([Cursor]) is in appflowy_editor/src and not exported,
  // so match it by runtime type name.
  final cursorFinder =
      find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Cursor');

  double caretLeft(WidgetTester tester) =>
      tester.getRect(cursorFinder.first).left;

  group('RTL empty-line caret (rtl default direction)', () {
    testWidgets('empty first line caret sits where RTL typing lands',
        (tester) async {
      await tester.initializeAppFlowy();
      await tester.tapAnonymousSignInButton();

      // Match the user's setting: default document direction = RTL.
      final ctx = tester.element(find.byType(WidgetsApp).first);
      await ctx.read<DocumentAppearanceCubit>().syncDefaultTextDirection('rtl');
      await tester.pumpAndSettle();

      await tester.createNewPageWithNameUnderParent(name: 'rtl_default_doc');
      await tester.pumpAndSettle();

      // First line is empty + RTL, showing the English "Type '/'…" hint.
      await tester.editor.tapLineOfEditorAt(0);
      await tester.pumpAndSettle();
      expect(cursorFinder, findsWidgets, reason: 'expected a caret on screen');
      final emptyCaret = caretLeft(tester);

      // Type one Hebrew character; its caret lands at the RTL start (right).
      await tester.ime.insertText('א');
      await tester.pumpAndSettle();
      final typedCaret = caretLeft(tester);

      final editorRect = tester.getRect(find.byType(AppFlowyEditorPage));
      final diff = (emptyCaret - typedCaret).abs();
      debugPrint('RTLDIAG emptyCaret=${emptyCaret.toStringAsFixed(1)} '
          'typedCaret=${typedCaret.toStringAsFixed(1)} '
          'diff=${diff.toStringAsFixed(1)} '
          'editorL=${editorRect.left.toStringAsFixed(1)} '
          'editorR=${editorRect.right.toStringAsFixed(1)}');

      // (1) No jump: the empty-line caret must sit within ~one glyph of where
      // typing actually lands. Reverting either fix breaks this (empty and
      // typed diverge by a placeholder-width).
      expect(
        diff < 40,
        true,
        reason: 'empty RTL caret $emptyCaret should be near the post-typing '
            'caret $typedCaret (within ~one character), not stranded to the '
            'left of the English placeholder',
      );

      // (2) Correct side: both must be near the content-area RIGHT edge (the
      // RTL start), not stranded on the left. This guards the "both regress
      // together" case that (1) alone would miss — pre-fix both sat a
      // placeholder-width (~300px) left of the right edge.
      final rightThreshold = editorRect.left + editorRect.width * 0.75;
      expect(
        typedCaret > rightThreshold && emptyCaret > rightThreshold,
        true,
        reason: 'RTL carets (empty=$emptyCaret, typed=$typedCaret) should be '
            'in the right quarter of the editor (> $rightThreshold), where '
            'RTL text begins — not stranded left of the content edge',
      );
    });
  });
}
