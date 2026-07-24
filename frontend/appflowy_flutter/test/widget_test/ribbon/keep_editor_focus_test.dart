// [fork:ribbon] Regression for "clicking buttons deselects the selection"
// (user report, 2026-07-23). See specs/ribbon-menu.md.
//
// The editor's keyboard service nulls `editorState.selection` when its focus
// node loses focus unless `keepEditorFocusNotifier.shouldKeepFocus` is true.
// A ribbon control that steals focus (any popover) therefore wiped the
// selection before the action could read it. These tests assert the notifier
// is held up across a ribbon interaction — the thing that keeps the selection
// alive — without needing to mount the whole editor.

import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/keep_editor_focus.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/ribbon_action.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/ribbon_button.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => keepEditorFocusNotifier.reset());
  tearDown(() => keepEditorFocusNotifier.reset());

  group('runKeepingEditorFocus', () {
    test('holds the notifier up during the action, releases after a frame',
        () async {
      expect(keepEditorFocusNotifier.shouldKeepFocus, isFalse);

      var sawFocusHeld = false;
      runKeepingEditorFocus(() {
        // Inside the action — i.e. exactly when the button's onPressed reads
        // editorState.selection — focus must be held.
        sawFocusHeld = keepEditorFocusNotifier.shouldKeepFocus;
      });

      expect(sawFocusHeld, isTrue);
      // Still held until the frame settles.
      expect(keepEditorFocusNotifier.shouldKeepFocus, isTrue);

      // The decrease is scheduled for the next frame.
      await Future<void>.delayed(Duration.zero);
      WidgetsBinding.instance.handleBeginFrame(Duration.zero);
      WidgetsBinding.instance.handleDrawFrame();

      expect(keepEditorFocusNotifier.shouldKeepFocus, isFalse);
    });

    test('releases even when the action throws', () {
      expect(
        () => runKeepingEditorFocus(() => throw StateError('boom')),
        throwsStateError,
      );
      // The increase was still scheduled to be undone (post-frame); the counter
      // must not be left permanently raised. Pump a frame to run the callback.
      WidgetsBinding.instance.handleBeginFrame(Duration.zero);
      WidgetsBinding.instance.handleDrawFrame();
      expect(keepEditorFocusNotifier.value, 0);
    });
  });

  testWidgets('tapping a ribbon button holds focus while onPressed runs',
      (tester) async {
    final editorState = EditorState.blank();
    bool? focusHeldWhenPressed;

    final action = RibbonAction(
      id: 'probe',
      label: 'Probe',
      icon: FlowySvgs.type_text_m,
      isEnabled: (_) => true,
      onPressed: (_, __) {
        focusHeldWhenPressed = keepEditorFocusNotifier.shouldKeepFocus;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(),
            child: RibbonButton(action: action, editorState: editorState),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(RibbonButton));
    await tester.pump();

    expect(
      focusHeldWhenPressed,
      isTrue,
      reason: 'the selection must be protected while the action runs',
    );
  });
}
