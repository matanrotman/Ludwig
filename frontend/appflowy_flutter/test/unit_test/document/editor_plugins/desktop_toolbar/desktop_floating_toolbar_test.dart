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
      // LTR pointer anchor: 1/3 of the (420px, multi-node selection ->
      // short menu) toolbar pokes left of the pointer, 2/3 extends
      // right -- so its left edge sits 140px left of the release point.
      final expected = dragEnd + const Offset(-140, -48);
      expect(
        (toolbarTopLeft - expected).distance < 1.0,
        true,
        reason: 'toolbar $toolbarTopLeft should anchor 1/3 left of the '
            'release point $dragEnd (=> $expected)',
      );
    },
  );

  testWidgets(
    'a pointer hovering anywhere in the editor still anchors the toolbar '
    'at the pointer, even off the highlighted selection',
    (tester) async {
      // 2026-07-16 r3: the earlier version of this test asserted the
      // OPPOSITE -- that an off-selection hover was ignored. Live
      // testing found that wrong: Cmd+A on a long page kept landing on
      // the fallback anchor even with the mouse resting in the middle
      // of the page, just not on top of a highlighted glyph. The bar is
      // now "is the pointer on the page at all", not "is it on the
      // highlighted text".
      final tracker = EditorPointerTracker();
      await pumpEditorHarness(tester, tracker: tracker);

      // A 2-node selection, not single-node: onlyShowInSingleSelectionAnd
      // TextType is false for it, giving the toolbar its narrower 420px
      // menu width. A single-node selection here would trigger the
      // wide 660px menu, whose maxLeft clamp is narrow enough that
      // almost any hover point off the selected row gets clamped
      // regardless of this fix -- which isn't what this test is about.
      editorState.selection = Selection(
        start: Position(path: [5]),
        end: Position(
          path: [6],
          offset: editorState.getNodeAtPath([6])!.delta!.length,
        ),
      );
      await tester.pump();

      // Hover over paragraph 8 — inside the editor, well away from the
      // selected rows, and comfortably inside the editor's clamp-free
      // horizontal zone (menuWidth 420 + the 1/3-inward pointer offset +
      // margins leave only a middle band unclamped in an 800px-wide
      // test window). This test is about whether the pointer is used at
      // all, not about clamp behavior (covered elsewhere).
      final hoverPoint =
          globalRectOfNode([8]).centerLeft + const Offset(200, 0);
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
      // LTR pointer anchor: 1/3 of the 420px toolbar pokes left of the
      // pointer, 2/3 extends right.
      final expected = hoverPoint + const Offset(-140, -48);
      expect(
        (toolbarTopLeft - expected).distance < 1.0,
        true,
        reason: 'toolbar $toolbarTopLeft should anchor 1/3 left of the '
            'hover point $hoverPoint even though it is off the '
            'highlighted selection',
      );
    },
  );

  testWidgets(
    'a pointer outside the editor entirely falls back to the '
    'upper-third-of-selection anchor',
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

      // Stand in for "the pointer is somewhere outside the editor's own
      // viewport (e.g. over the sidebar)": EditorPointerTracker only
      // ever reflects positions its Listener actually received, so no
      // event having landed inside the editor is the real-world
      // equivalent of this.
      tracker.lastGlobalPosition = const Offset(-500, -500);

      await mountToolbar(tester, tracker: tracker);

      final toolbarTopLeft =
          tester.getTopLeft(find.byKey(const Key('toolbarChild')));
      final expectedDy =
          selectedRowRect.top + selectedRowRect.height / 3 - 48;
      expect(
        (toolbarTopLeft.dy - expectedDy).abs() < 2.0,
        true,
        reason: 'toolbar $toolbarTopLeft should fall back to a third of '
            'the way down the selected row $selectedRowRect '
            '(dy ≈ $expectedDy) when the pointer is not inside the '
            'editor at all',
      );
    },
  );

  testWidgets(
    'RTL: the upper-third fallback anchor opens from the selected row\'s '
    'right edge, not pinned to the far-left wall',
    (tester) async {
      // 2026-07-16 r3 regression (live user report, screenshot): mirroring
      // RTL off rect.left subtracted the toolbar's full width from a
      // full-width selection row's left edge -- which sits near the
      // editor's own left bound regardless of text direction -- driving
      // the result deeply negative and clamping the toolbar to the
      // far-left wall, unrelated to where the text actually was.
      // Mirroring off rect.right (the row's real RTL reading-start edge)
      // fixes it. This test forces isRTL via the mocked cubit; the
      // document itself renders LTR (English placeholder text) since
      // only the mirror math, not real bidi shaping, is under test.
      final rtlCubit = MockAppearanceSettingsCubit();
      final rtlState = MockAppearanceSettingsState();
      when(() => rtlState.layoutDirection)
          .thenReturn(LayoutDirection.rtlLayout);
      when(() => rtlCubit.state).thenReturn(rtlState);
      when(() => rtlCubit.stream)
          .thenAnswer((_) => Stream.fromIterable([rtlState]));

      // Long, word-wrapping text for the first paragraph: word-wrap packs
      // as much as fits per line before breaking, so the topmost visible
      // (and thus anchor) row ends up close to the block's full width --
      // matching the real-world wrapped-RTL-paragraph screenshot this
      // test reproduces. Short "paragraph N" text for the rest wouldn't
      // reach anywhere near the editor's right edge regardless of
      // direction, and couldn't have caught this bug.
      final rtlEditorState = EditorState(
        document: Document(
          root: pageNode(
            children: [
              paragraphNode(text: List.filled(40, 'paragraph').join(' ')),
              for (var i = 1; i < 30; i++) paragraphNode(text: 'paragraph $i'),
            ],
          ),
        ),
      );
      final rtlNavigatorKey = GlobalKey<NavigatorState>();
      final rtlEditorScrollController =
          EditorScrollController(editorState: rtlEditorState);
      await tester.pumpWidget(
        BlocProvider<AppearanceSettingsCubit>.value(
          value: rtlCubit,
          child: MaterialApp(
            navigatorKey: rtlNavigatorKey,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: AppFlowyEditor(
                  editorState: rtlEditorState,
                  editorScrollController: rtlEditorScrollController,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A 2-node selection (not single-node): onlyShowInSingleSelectionAnd
      // TextType is false for it, matching the real Cmd+A bug's menuWidth
      // (420, the "short menu" branch) -- a single-node selection instead
      // triggers the long-menu (660) branch, which genuinely doesn't fit
      // this test's ~480px-wide content column regardless of direction,
      // and would make this assertion meaningless.
      //
      // Setting a selection also auto-scrolls to reveal its END, which
      // for a caret several lines into a wrapped paragraph pushes the
      // earlier lines negative (above the viewport) -- force node 0 back
      // to the very top of the viewport afterward so its first (widest)
      // visible line is what upperThirdAnchorRect actually anchors on,
      // matching the real-world screenshot this test reproduces.
      final secondText =
          rtlEditorState.getNodeAtPath([1])!.delta!.toPlainText();
      rtlEditorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [1], offset: secondText.length),
      );
      await tester.pump();
      rtlEditorScrollController.itemScrollController.jumpTo(index: 0);
      await tester.pump();

      final entry = OverlayEntry(
        builder: (context) => DesktopFloatingToolbar(
          editorState: rtlEditorState,
          onDismiss: () {},
          enableAnimation: false,
          child: Container(
            key: const Key('rtlToolbarChild'),
            width: 40,
            height: 40,
            color: Colors.blue,
          ),
        ),
      );
      rtlNavigatorKey.currentState!.overlay!.insert(entry);
      await tester.pumpAndSettle();

      final editorRect = tester.getRect(find.byType(AppFlowyEditor));
      final toolbarLeft =
          tester.getTopLeft(find.byKey(const Key('rtlToolbarChild'))).dx;
      expect(
        toolbarLeft > editorRect.left + 16 + 1,
        true,
        reason: 'toolbar left=$toolbarLeft should not be pinned to the '
            'far-left wall (editorRect.left + margin = '
            '${editorRect.left + 16}) for a full-width RTL selection row',
      );
    },
  );

  testWidgets(
    'RTL pointer anchor: 1/3 of the toolbar pokes right of the pointer, '
    '2/3 extends left (the LTR case mirrored)',
    (tester) async {
      // 2026-07-16 r4, direct user request: the toolbar shouldn't sit
      // flush against either side of the pointer. LTR reads left-to-
      // right, so it opens mostly rightward (1/3 left of pointer, 2/3
      // right); RTL is the mirror image (1/3 right of pointer, 2/3
      // left). This test forces isRTL via the mocked cubit; the
      // document itself renders LTR (English placeholder text) since
      // only the mirror math, not real bidi shaping, is under test.
      final rtlCubit = MockAppearanceSettingsCubit();
      final rtlState = MockAppearanceSettingsState();
      when(() => rtlState.layoutDirection)
          .thenReturn(LayoutDirection.rtlLayout);
      when(() => rtlCubit.state).thenReturn(rtlState);
      when(() => rtlCubit.stream)
          .thenAnswer((_) => Stream.fromIterable([rtlState]));

      final rtlEditorState = EditorState(
        document: Document(
          root: pageNode(
            children: [
              for (var i = 0; i < 10; i++) paragraphNode(text: 'paragraph $i'),
            ],
          ),
        ),
      );
      final rtlTracker = EditorPointerTracker();
      final rtlNavigatorKey = GlobalKey<NavigatorState>();
      final editor = AppFlowyEditor(
        editorState: rtlEditorState,
        editorScrollController:
            EditorScrollController(editorState: rtlEditorState),
      );
      await tester.pumpWidget(
        BlocProvider<AppearanceSettingsCubit>.value(
          value: rtlCubit,
          child: MaterialApp(
            navigatorKey: rtlNavigatorKey,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: EditorPointerTrackingListener(
                  tracker: rtlTracker,
                  child: editor,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A 2-node selection: onlyShowInSingleSelectionAndTextType is
      // false for it, giving the toolbar its narrower 420px menu width
      // (matches the LTR pointer-anchor tests above, for the same
      // clamp-avoidance reason).
      final secondText =
          rtlEditorState.getNodeAtPath([1])!.delta!.toPlainText();
      rtlEditorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [1], offset: secondText.length),
      );
      await tester.pump();

      // A pointer position comfortably inside the clamp-free zone: for
      // a 420px menu with a 16px edge margin, RTL's rawLeft = pointer.x
      // - menuWidth*2/3 must stay >= minLeft, i.e. pointer.x >= minLeft
      // + 280 -- pick 350 so there's headroom on both sides.
      const pointerPosition = Offset(350, 100);
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: pointerPosition);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(pointerPosition);
      await tester.pump();
      expect(rtlTracker.lastGlobalPosition, pointerPosition);

      final entry = OverlayEntry(
        builder: (context) => DesktopFloatingToolbar(
          editorState: rtlEditorState,
          onDismiss: () {},
          enableAnimation: false,
          pointerTracker: rtlTracker,
          child: Container(
            key: const Key('rtlPointerToolbarChild'),
            width: 40,
            height: 40,
            color: Colors.blue,
          ),
        ),
      );
      rtlNavigatorKey.currentState!.overlay!.insert(entry);
      await tester.pumpAndSettle();

      final toolbarTopLeft = tester
          .getTopLeft(find.byKey(const Key('rtlPointerToolbarChild')));
      // RTL pointer anchor: 1/3 of the 420px toolbar pokes right of the
      // pointer, 2/3 extends left => left edge = pointer.x - 280.
      final expected = pointerPosition + const Offset(-280, -48);
      expect(
        (toolbarTopLeft - expected).distance < 1.0,
        true,
        reason: 'toolbar $toolbarTopLeft should anchor 1/3 right of the '
            'pointer $pointerPosition (=> $expected)',
      );
    },
  );
}
