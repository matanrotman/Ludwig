import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/desktop_floating_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/toolbar_pointer_tracker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppearanceSettingsCubit extends Mock
    implements AppearanceSettingsCubit {}

class MockAppearanceSettingsState extends Mock
    implements AppearanceSettingsState {}

// Regression test for the floating toolbar landing at a stale position
// after a selection that requires auto-scroll to reveal.
//
// `DesktopFloatingToolbar` used to compute its position once,
// synchronously, in initState(). But initState() runs during a frame's
// BUILD phase, which happens BEFORE that same frame's LAYOUT phase. When
// this widget is (re)created in the same frame a scroll offset changes --
// exactly what happens when the outer FloatingToolbar's scroll-change
// handler tears down and recreates it via a Duration.zero (synchronous)
// debounce -- reading render-object geometry at that point reads whatever
// layout was left over from the PREVIOUS frame, since the scrolled
// content hasn't been laid out at its new position yet this frame.
//
// Mounted via a real root OverlayEntry (matching how the app's outer
// FloatingToolbar actually displays DesktopFloatingToolbar), not a
// hand-rolled Stack -- Positioned's left/top read GLOBAL coordinates from
// selectionExtentRect, which is only meaningful inside a root overlay.

const _selectedPath = [25];

void main() {
  late MockAppearanceSettingsCubit appearanceSettingsCubit;

  setUp(() {
    getIt.registerSingleton<FloatingToolbarController>(
      FloatingToolbarController(),
    );
    // DesktopFloatingToolbar reads the document's layout direction (LTR
    // vs RTL) to mirror where the toolbar opens relative to the cursor.
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

  Widget wrapWithAppearanceProvider(Widget child) {
    return BlocProvider<AppearanceSettingsCubit>.value(
      value: appearanceSettingsCubit,
      child: child,
    );
  }

  testWidgets(
    'toolbar lands at the settled position, not a stale pre-scroll one, '
    'when mounted in the same frame a scroll offset changes',
    (tester) async {
      final document = Document(
        root: pageNode(
          children: [
            for (var i = 0; i < 30; i++) paragraphNode(text: 'paragraph $i'),
          ],
        ),
      );
      final editorState = EditorState(document: document);
      // Default (shrinkWrap: false) -- matches production desktop exactly:
      // a ScrollablePositionedList, scrolled via editorScrollController's
      // own jumpTo(), not a manually-attached ScrollController.
      final editorScrollController = EditorScrollController(
        editorState: editorState,
      );

      // A selection far down the document -- off-screen in the 300px
      // viewport below until something scrolls it into view.
      editorState.selection = Selection.single(
        path: _selectedPath,
        startOffset: 0,
        endOffset: 9,
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      OverlayEntry? toolbarEntry;

      void mountToolbar() {
        toolbarEntry?.remove();
        toolbarEntry = OverlayEntry(
          builder: (context) => DesktopFloatingToolbar(
            editorState: editorState,
            onDismiss: () {},
            enableAnimation: false,
            child: Container(
              key: const Key('toolbarChild'),
              width: 40,
              height: 40,
              color: Colors.blue,
            ),
          ),
        );
        navigatorKey.currentState!.overlay!.insert(toolbarEntry!);
      }

      await tester.pumpWidget(
        wrapWithAppearanceProvider(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: AppFlowyEditor(
                  editorState: editorState,
                  editorScrollController: editorScrollController,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to reveal the selection AND mount the toolbar in the same
      // synchronous block, before any pump() -- this reproduces the same
      // ordering the real app produces when a scroll-offset change tears
      // down and recreates DesktopFloatingToolbar via the outer widget's
      // OverlayEntry teardown/rebuild cycle.
      editorScrollController.jumpTo(offset: _selectedPath.first.toDouble());
      mountToolbar();

      // One frame: build phase mounts the new DesktopFloatingToolbar;
      // layout phase then catches the scrolled content up to its new
      // position. By the end of this single pump(), layout has already
      // settled (jumpTo is instantaneous, not animated).
      await tester.pump();
      final selectable =
          editorState.document.nodeAtPath(_selectedPath)!.selectable!;
      final settledExtentRect = selectable.transformRectToGlobal(
        selectable.getCursorRectInPosition(
          Position(path: _selectedPath, offset: 9),
        )!,
      );

      // Let any deferred (post-frame-callback) position update apply.
      await tester.pumpAndSettle();

      final toolbarChildRect =
          tester.getTopLeft(find.byKey(const Key('toolbarChild')));
      expect(
        (toolbarChildRect.dy - settledExtentRect.top).abs() < 60,
        true,
        reason: 'toolbar child $toolbarChildRect should land near the '
            'settled, post-scroll selection extent $settledExtentRect '
            '(within about one line height), not a stale pre-scroll '
            'position',
      );
    },
  );

  // ---- pointer-anchored toolbar (2026-07-16) ----------------------------
  //
  // Shared harness for the three anchor-decision cases: a 30-paragraph
  // document in a 300px viewport, toolbar mounted via a real root
  // OverlayEntry exactly like the regression test above.

  late EditorState editorState;
  late GlobalKey<NavigatorState> navigatorKey;
  OverlayEntry? toolbarEntry;

  Future<void> pumpEditorHarness(
    WidgetTester tester, {
    EditorPointerTracker? tracker,
  }) async {
    editorState = EditorState(
      document: Document(
        root: pageNode(
          children: [
            for (var i = 0; i < 30; i++) paragraphNode(text: 'paragraph $i'),
          ],
        ),
      ),
    );
    navigatorKey = GlobalKey<NavigatorState>();
    final editor = AppFlowyEditor(
      editorState: editorState,
      editorScrollController: EditorScrollController(editorState: editorState),
    );
    await tester.pumpWidget(
      wrapWithAppearanceProvider(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: tracker == null
                  ? editor
                  : EditorPointerTrackingListener(
                      tracker: tracker,
                      child: editor,
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountToolbar(
    WidgetTester tester, {
    EditorPointerTracker? tracker,
  }) async {
    toolbarEntry?.remove();
    toolbarEntry = OverlayEntry(
      builder: (context) => DesktopFloatingToolbar(
        editorState: editorState,
        onDismiss: () {},
        enableAnimation: false,
        pointerTracker: tracker,
        child: Container(
          key: const Key('toolbarChild'),
          width: 40,
          height: 40,
          color: Colors.blue,
        ),
      ),
    );
    navigatorKey.currentState!.overlay!.insert(toolbarEntry!);
    await tester.pumpAndSettle();
  }

  tearDown(() {
    toolbarEntry = null;
  });

  Rect globalRectOfNode(List<int> path) {
    final renderBox = editorState.getNodeAtPath(path)!.renderBox!;
    return renderBox.localToGlobal(Offset.zero) & renderBox.size;
  }

  testWidgets(
    'select-all with no usable pointer anchors near the top of the visible '
    'selection, inside the viewport — not at the far-below selection end',
    (tester) async {
      await pumpEditorHarness(tester);
      final lastText = editorState.getNodeAtPath([29])!.delta!.toPlainText();
      editorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [29], offset: lastText.length),
      );
      await tester.pump();

      await mountToolbar(tester);

      final editorRect = tester.getRect(find.byType(AppFlowyEditor));
      final toolbarTopLeft =
          tester.getTopLeft(find.byKey(const Key('toolbarChild')));
      expect(
        toolbarTopLeft.dy >= editorRect.top &&
            toolbarTopLeft.dy <= editorRect.center.dy,
        true,
        reason: 'toolbar $toolbarTopLeft should sit in the upper half of the '
            'visible viewport $editorRect (about a third down the visible '
            'selection), not at the document\'s last block below it',
      );
    },
  );

  testWidgets(
    'a real mouse drag records the release point despite the editor\'s own '
    'selection gestures, and the toolbar anchors just above that point',
    (tester) async {
      final tracker = EditorPointerTracker();
      await pumpEditorHarness(tester, tracker: tracker);

      final dragStart = globalRectOfNode([0]).centerLeft + const Offset(2, 0);
      // Release over the actual glyphs of paragraph 2 (mid-text, mid-line):
      // the row's render box is full-width, but the selection highlight —
      // which is what the pointer must be inside — only spans the text.
      final endSelectable = editorState.getNodeAtPath([2])!.selectable!;
      final endCaretRect = endSelectable.transformRectToGlobal(
        endSelectable.getCursorRectInPosition(
          Position(path: [2], offset: 5),
          shiftWithBaseOffset: true,
        )!,
        shiftWithBaseOffset: true,
      );
      final dragEnd = endCaretRect.center;
      final gesture = await tester.startGesture(
        dragStart,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(dragEnd);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tracker.lastGlobalPosition,
        dragEnd,
        reason: 'the translucent Listener must receive raw pointer events '
            'even while the editor\'s drag-selection gesture is active',
      );

      // Ensure the dragged range is the selection regardless of how the
      // editor's own gesture handling resolved the drag.
      editorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(
          path: [2],
          offset: editorState.getNodeAtPath([2])!.delta!.length,
        ),
      );
      await tester.pump();
      await mountToolbar(tester, tracker: tracker);

      final toolbarTopLeft =
          tester.getTopLeft(find.byKey(const Key('toolbarChild')));
      // LTR opens toward the right of the cursor: toolbar's left edge
      // sits at the anchor's x (no horizontal shift), 48px above it.
      final expected = dragEnd + const Offset(0, -48);
      expect(
        (toolbarTopLeft - expected).distance < 1.0,
        true,
        reason: 'toolbar $toolbarTopLeft should anchor at the release point '
            '$dragEnd (48 up, no horizontal shift in LTR => $expected)',
      );
    },
  );

  testWidgets(
    'a pointer hovering over the document but off the selection is ignored: '
    'the toolbar uses the upper-third-of-selection anchor instead',
    (tester) async {
      final tracker = EditorPointerTracker();
      await pumpEditorHarness(tester, tracker: tracker);

      final selectedRowRect = globalRectOfNode([5]);
      editorState.selection = Selection(
        start: Position(path: [5]),
        end: Position(
          path: [5],
          offset: editorState.getNodeAtPath([5])!.delta!.length,
        ),
      );
      await tester.pump();

      // Hover over paragraph 8 — inside the editor, outside the selection.
      final hoverPoint = globalRectOfNode([8]).center;
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: hoverPoint);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(hoverPoint);
      await tester.pump();
      expect(tracker.lastGlobalPosition, hoverPoint);

      await mountToolbar(tester, tracker: tracker);

      final toolbarTopLeft =
          tester.getTopLeft(find.byKey(const Key('toolbarChild')));
      final expectedDy =
          selectedRowRect.top + selectedRowRect.height / 3 - 48;
      expect(
        (toolbarTopLeft.dy - expectedDy).abs() < 2.0,
        true,
        reason: 'toolbar $toolbarTopLeft should anchor a third of the way '
            'down the selected row $selectedRowRect (dy ≈ $expectedDy), not '
            'at the hover point $hoverPoint',
      );
      expect(
        (toolbarTopLeft.dy - (hoverPoint.dy - 48)).abs() > 20,
        true,
        reason: 'toolbar must not anchor at the off-selection hover point',
      );
    },
  );
}
