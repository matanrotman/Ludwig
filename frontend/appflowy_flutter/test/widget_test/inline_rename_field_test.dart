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
    final field =
        tester.widget<TextField>(find.byType(TextField).first);
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
}
