import 'package:appflowy/workspace/presentation/home/menu/view/inline_rename_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? submitted;
  var dismissed = 0;

  setUp(() {
    submitted = null;
    dismissed = 0;
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: InlineRenameField(
                  initialName: 'old name',
                  onSubmitted: (v) => submitted = v,
                  onDismissed: () => dismissed++,
                ),
              ),
              // Somewhere else to move focus to.
              const SizedBox(width: 50, child: TextField()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts with the current name fully selected', (tester) async {
    await pumpField(tester);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'old name');
    expect(field.controller!.selection.baseOffset, 0);
    expect(field.controller!.selection.extentOffset, 'old name'.length);
  });

  testWidgets('Enter commits the edited text', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, 'new name');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, 'new name');
    expect(dismissed, 0);
  });

  testWidgets('Escape cancels without committing', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, 'new name');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(submitted, isNull);
    expect(dismissed, 1);
  });

  testWidgets('losing focus commits (Finder-style)', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField).first, 'clicked away');
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(submitted, 'clicked away');
    expect(dismissed, 0);
  });

  // Regression (user feedback 2026-07-23): renames were silently dropped when
  // the click-away landed on something that takes no focus — which is most of
  // the sidebar (space header rows are a bare GestureDetector, and empty
  // sidebar space is inert). Focus never changed, so the focus-loss listener
  // never fired. Only a click that happened to hit a focusable target saved.
  testWidgets('clicking a NON-focusable target still commits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              InlineRenameField(
                initialName: 'old name',
                onSubmitted: (v) => submitted = v,
                onDismissed: () => dismissed++,
              ),
              // Stands in for sidebar chrome: handles the tap, takes no focus.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const SizedBox(height: 100, width: 100),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'saved anyway');
    await tester.tap(find.byType(SizedBox).last, warnIfMissed: false);
    await tester.pump();

    expect(submitted, 'saved anyway');
    expect(dismissed, 0);
  });

  // Regression (user feedback 2026-07-23): arrow keys moved the caret the wrong
  // way visually in a Hebrew page name. Flutter's stock bindings move the caret
  // in LOGICAL order, so in RTL text ArrowLeft steps to the previous character
  // — which is drawn to the RIGHT. These assert offsets, not pixels, so the
  // headless fixed-width font can't distort them (see CLAUDE.md's rule about
  // trusting headless tests only for non-geometric facts).
  //
  // In pure RTL text: visually-left == logically-forward == offset INCREASES.
  group('arrow keys move the caret visually in RTL names', () {
    Future<TextEditingController> pumpNamed(
      WidgetTester tester,
      String name,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          // The user runs an LTR interface, so the ambient direction is LTR
          // even when the name itself is Hebrew — the case that was broken.
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: InlineRenameField(
                initialName: name,
                onSubmitted: (v) => submitted = v,
                onDismissed: () => dismissed++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<TextField>(find.byType(TextField)).controller!;
    }

    testWidgets('RTL name: ArrowLeft goes visually left', (tester) async {
      final controller = await pumpNamed(tester, 'שלום עולם');

      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        controller.selection.baseOffset,
        5,
        reason: 'visually left in RTL is logically forward',
      );

      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        controller.selection.baseOffset,
        3,
        reason: 'visually right in RTL is logically backward',
      );
    });

    testWidgets('RTL name: Shift+Arrow extends the same way', (tester) async {
      final controller = await pumpNamed(tester, 'שלום עולם');

      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(controller.selection.baseOffset, 4, reason: 'anchor stays put');
      expect(controller.selection.extentOffset, 5);
    });

    testWidgets('LTR name keeps stock behaviour', (tester) async {
      final controller = await pumpNamed(tester, 'hello world');

      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.selection.baseOffset, 3);
    });
  });

  group('focus stolen by the editor opening underneath (2026-07-28):', () {
    // Renaming starts on a DOUBLE-click, and the first of those clicks already
    // opened the page. The document editor mounts afterwards and asks for focus
    // itself — on macOS via a deliberately delayed request — so the rename box
    // appeared and vanished instantly, committing as if the user had clicked
    // away. See InlineRenameField._isFocusSteal.
    testWidgets('a programmatic focus grab is reclaimed, and does NOT commit',
        (tester) async {
      final thief = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InlineRenameField(
                  initialName: 'old name',
                  onSubmitted: (v) => submitted = v,
                  onDismissed: () => dismissed++,
                ),
                Focus(focusNode: thief, child: const SizedBox(height: 20)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editable = tester.widget<TextField>(find.byType(TextField));
      expect(editable.focusNode?.hasFocus, isTrue, reason: 'autofocus');

      // What the editor does: takes focus with no pointer event involved.
      thief.requestFocus();
      await tester.pumpAndSettle();

      expect(
        editable.focusNode?.hasFocus,
        isTrue,
        reason: 'the field should have taken its focus back',
      );
      expect(
        submitted,
        isNull,
        reason: 'a stolen focus must not be read as the user committing',
      );
      expect(dismissed, 0);

      thief.dispose();
    });

    testWidgets('after the grace window, focus loss still commits as before',
        (tester) async {
      final thief = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InlineRenameField(
                  initialName: 'old name',
                  onSubmitted: (v) => submitted = v,
                  onDismissed: () => dismissed++,
                ),
                Focus(focusNode: thief, child: const SizedBox(height: 20)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Past the window, this is an ordinary exit (Tab-away and friends).
      await tester.pump(const Duration(seconds: 2));
      thief.requestFocus();
      await tester.pumpAndSettle();

      expect(
        submitted,
        'old name',
        reason: 'ordinary focus loss must still commit',
      );

      thief.dispose();
    });
  });
}
