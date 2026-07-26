import 'package:appflowy/workspace/presentation/settings/pages/backup/snapshot_browser_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_wrapper.dart';

/// `specs/restore-redesign.md` Phase 1, from the first live look at the browser.
///
/// The browser holds no text field, so nothing inside the dialog route took
/// focus and Escape fell straight through to the app's own shortcuts — leaving
/// clicking outside as the only way out.
///
/// **Honesty note:** only the close-button test is a proof. The escape test
/// passes with the fix reverted, because this wrapper has none of the app's
/// global shortcut layer — the very thing that ate the key. It is a *guard*
/// against someone deleting the binding, and the real verification is live.
void main() {
  // A destination that holds no `snapshots/` folder: the browser lists nothing
  // and stays on its empty state, which is all these tests need it to reach.
  const emptyDestination = '/tmp/appflowy-snapshot-browser-test-empty';

  // Not `pumpAndSettle`: the empty-state spinner animates forever while the
  // day list loads, so "settled" never arrives.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openBrowser(WidgetTester tester) async {
    await tester.pumpWidget(
      WidgetTestWrapper(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const Dialog(
                child: SizedBox(
                  width: 900,
                  height: 620,
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: SnapshotBrowser(destinationPath: emptyDestination),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('Browse backups'), findsOneWidget);
  }

  testWidgets('escape closes the browser', (tester) async {
    await openBrowser(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(find.text('Browse backups'), findsNothing);
  });

  testWidgets('the close button closes the browser', (tester) async {
    await openBrowser(tester);

    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    expect(find.text('Browse backups'), findsNothing);
  });
}
