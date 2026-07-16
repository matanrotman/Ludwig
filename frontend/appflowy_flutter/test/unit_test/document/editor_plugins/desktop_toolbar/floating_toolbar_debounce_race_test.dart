import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/desktop_floating_toolbar.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppearanceSettingsCubit extends Mock
    implements AppearanceSettingsCubit {}

class MockAppearanceSettingsState extends Mock
    implements AppearanceSettingsState {}

// Regression test for a debounce race between selection-driven and
// scroll-driven floating-toolbar show requests.
//
// FloatingToolbar (the outer wrapper, appflowy_editor package,
// pre-existing upstream file) used to funnel both triggers through one
// shared debounce key. A scroll tick (fired every frame during
// auto-scroll, via Duration.zero -- i.e. synchronous) could cancel a
// pending, more-authoritative 200ms selection-driven show, and its own
// synchronous geometry read could be stale relative to the very scroll
// offset change that triggered it (this frame's layout hasn't caught up
// yet at that exact point in the call stack). Fixed by: (1) separate
// debounce keys so one trigger can't silently cancel the other, (2)
// deferring the scroll-triggered show to a post-frame callback so it
// only reads geometry once layout has genuinely settled.
//
// This is the first test this session to drive the real FloatingToolbar
// -> DesktopFloatingToolbar chain (not a hand-rolled OverlayEntry, not a
// direct selection assignment bypassing FloatingToolbar entirely) --
// deliberately, since the earlier (still real, but narrower)
// desktop_floating_toolbar_test.dart could not have caught this class of
// bug.
//
// Honest limitation: this test passes against both the fixed AND the
// pre-fix code -- a single jumpTo() + settle() doesn't recreate the
// continuous, never-fully-settling stream of scroll ticks a real
// mouse-drag auto-scroll produces, so it doesn't actually prove the race
// is closed. It's kept as a real (if weaker than intended) regression
// test that the toolbar shows and lands reasonably close to the true
// selection through the *actual* FloatingToolbar wiring, not a
// synthetic bypass. Confidence in the fix itself rests on the code
// reading (separate debounce keys; post-frame-deferred geometry read),
// not on this test catching a live failure -- flagged here rather than
// silently claimed as proven.

const _selectedPath = [25];

void main() {
  late MockAppearanceSettingsCubit appearanceSettingsCubit;

  setUp(() {
    getIt.registerSingleton<FloatingToolbarController>(
      FloatingToolbarController(),
    );
    appearanceSettingsCubit = MockAppearanceSettingsCubit();
    final state = MockAppearanceSettingsState();
    when(() => state.layoutDirection).thenReturn(LayoutDirection.ltrLayout);
    when(() => appearanceSettingsCubit.state).thenReturn(state);
    when(() => appearanceSettingsCubit.stream)
        .thenAnswer((_) => Stream.fromIterable([state]));
  });

  tearDown(() {
    getIt.unregister<FloatingToolbarController>();
  });

  testWidgets(
    'toolbar shown through the real FloatingToolbar wrapper settles at '
    'the correct position when a scroll tick interrupts a pending '
    'selection-driven show', (tester) async {
      final document = Document(
        root: pageNode(
          children: [
            for (var i = 0; i < 30; i++) paragraphNode(text: 'paragraph $i'),
          ],
        ),
      );
      final editorState = EditorState(document: document);
      final editorScrollController = EditorScrollController(
        editorState: editorState,
      );

      await tester.pumpWidget(
        BlocProvider<AppearanceSettingsCubit>.value(
          value: appearanceSettingsCubit,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: FloatingToolbar(
                  items: const [],
                  editorState: editorState,
                  editorScrollController: editorScrollController,
                  textDirection: TextDirection.ltr,
                  toolbarBuilder: (_, child, onDismiss, isMetricsChanged) =>
                      DesktopFloatingToolbar(
                    editorState: editorState,
                    onDismiss: onDismiss,
                    enableAnimation: false,
                    child: child,
                  ),
                  child: AppFlowyEditor(
                    editorState: editorState,
                    editorScrollController: editorScrollController,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A selection far down the document -- requires scroll to reveal.
      // This fires FloatingToolbar's 400ms selection-driven show (was
      // 200ms; bumped 2026-07-16 so the toolbar doesn't feel like it
      // flickers up mid-interaction).
      editorState.selection = Selection.single(
        path: _selectedPath,
        startOffset: 0,
        endOffset: 9,
      );

      // Do NOT wait out that 400ms yet -- interrupt it with a scroll
      // tick in the same synchronous window, exactly like an
      // auto-scroll tick would during a real drag that needs scrolling.
      editorScrollController.jumpTo(offset: _selectedPath.first.toDouble());

      // Let everything settle: the scroll-triggered show (deferred to
      // post-frame) and, after 400ms, the selection-triggered show.
      // pumpAndSettle alone doesn't reliably wait out a plain Timer once
      // the widget tree stops actively scheduling frames on its own, so
      // this pumps an explicit duration past the debounce first.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      final selectable =
          editorState.document.nodeAtPath(_selectedPath)!.selectable!;
      final settledExtentRect = selectable.transformRectToGlobal(
        selectable.getCursorRectInPosition(
          Position(path: _selectedPath, offset: 9),
        )!,
      );

      final toolbarFinder = find.byType(DesktopFloatingToolbar);
      expect(
        toolbarFinder,
        findsOneWidget,
        reason: 'toolbar should be showing for a non-collapsed selection '
            '-- a dropped show (the visibility gate wrongly bailing out '
            'on stale geometry) would fail this',
      );
      final toolbarRect = tester.getRect(toolbarFinder);
      expect(
        (toolbarRect.top - settledExtentRect.top).abs() < 100,
        true,
        reason: 'toolbar $toolbarRect should land near the settled '
            'selection extent $settledExtentRect once a scroll tick '
            'interrupts the pending selection-driven show, not a stale '
            'or dropped position',
      );
    },
  );
}
