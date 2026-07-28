// [fork:rtl] Tests for the visual-line / paragraph selection shortcuts —
// see specs/rtl-support.md "select-to-line and select-by-paragraph
// shortcuts".
//
// The paragraph-extension handlers and the left/right→start/end mapping
// are pure model logic and are tested headlessly here. The visual LINE
// span itself (soft-wrap geometry) lives in the editor fork's
// getLineBoundaryInPosition and is tested there (plus verified live on
// the real macOS target — headless tests cannot see real RTL geometry,
// see CLAUDE.md).

import 'package:appflowy/plugins/document/presentation/editor_plugins/base/cover_title_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/visual_line_selection_commands.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Node paragraph(String text, {List<Node>? children, String? direction}) {
  return Node(
    type: ParagraphBlockKeys.type,
    attributes: {
      ParagraphBlockKeys.delta: (Delta()..insert(text)).toJson(),
      if (direction != null) blockComponentTextDirection: direction,
    },
    children: children ?? [],
  );
}

// ~40 Hebrew words — wraps to several visual lines on the 800px test
// surface. Direction `auto` resolves RTL from the Hebrew content, same as
// the fork's own soft-wrap tests.
final wrappedRtlText = List.generate(40, (i) => 'מילים').join(' ');

Future<EditorState> pumpEditor(
  WidgetTester tester,
  List<Node> nodes, {
  SharedEditorContext? sharedContext,
}) async {
  final document = Document(root: pageNode(children: nodes));
  final editorState = EditorState(document: document);
  Widget editor = AppFlowyEditor(editorState: editorState);
  if (sharedContext != null) {
    editor = Provider<SharedEditorContext>.value(
      value: sharedContext,
      child: editor,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await tester.pumpAndSettle();
  return editorState;
}

/// The tiled visual-line spans of the block at [path], via the same
/// fork API the commands use (validated against caret rects in the
/// fork's own soft_wrap_caret_affinity_test.dart).
List<Selection> lineSpans(EditorState editorState, List<int> path) {
  final node = editorState.getNodeAtPath(path)!;
  final selectable = node.selectable!;
  final length = node.delta!.length;
  final spans = <Selection>[];
  var offset = 0;
  while (offset <= length) {
    final line = selectable.getLineBoundaryInPosition(
      Position(path: path, offset: offset),
    )!;
    spans.add(line);
    if (line.end.offset >= length) {
      break;
    }
    offset = line.end.offset + 1;
  }
  return spans;
}

EditorState editorWith(List<Node> nodes, Selection selection) {
  final document = Document.blank()..insert([0], nodes);
  final editorState = EditorState(document: document);
  editorState.selection = selection;
  return editorState;
}

void main() {
  // updateSelectionWithReason(uiEvent) schedules a post-frame callback via
  // WidgetsBinding, which plain test() does not initialize.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('visualLineEdgeTarget mapping (visual, not logical):', () {
    final line = Selection(
      start: Position(path: [0], offset: 10),
      end: Position(path: [0], offset: 20),
    );

    test('LTR: left = logical start, right = logical end', () {
      expect(
        visualLineEdgeTarget(line: line, towardLeft: true, isRtl: false),
        line.start,
      );
      expect(
        visualLineEdgeTarget(line: line, towardLeft: false, isRtl: false),
        line.end,
      );
    });

    test(
        'RTL: left = logical END (forward in reading order), '
        'right = logical start', () {
      expect(
        visualLineEdgeTarget(line: line, towardLeft: true, isRtl: true),
        line.end,
      );
      expect(
        visualLineEdgeTarget(line: line, towardLeft: false, isRtl: true),
        line.start,
      );
    });
  });

  group('extend selection by paragraph:', () {
    test(
        'down from mid-paragraph extends to that paragraph\'s end, '
        'keeping the anchor', () {
      final editorState = editorWith(
        [paragraph('one one'), paragraph('two two')],
        Selection.collapsed(Position(path: [0], offset: 2)),
      );
      final result = selectParagraphDownCommand.handler(editorState);
      expect(result, KeyEventResult.handled);
      expect(
        editorState.selection,
        Selection(
          start: Position(path: [0], offset: 2),
          end: Position(path: [0], offset: 7),
        ),
      );
    });

    test(
        'down again from a paragraph end takes in the whole next '
        'paragraph', () {
      final editorState = editorWith(
        [paragraph('one one'), paragraph('two two')],
        Selection(
          start: Position(path: [0], offset: 2),
          end: Position(path: [0], offset: 7),
        ),
      );
      selectParagraphDownCommand.handler(editorState);
      expect(
        editorState.selection,
        Selection(
          start: Position(path: [0], offset: 2),
          end: Position(path: [1], offset: 7),
        ),
      );
    });

    test('down descends into nested children in document order', () {
      final editorState = editorWith(
        [
          paragraph('parent', children: [paragraph('child')]),
          paragraph('after'),
        ],
        Selection(
          start: Position(path: [0]),
          end: Position(path: [0], offset: 6),
        ),
      );
      selectParagraphDownCommand.handler(editorState);
      expect(
        editorState.selection?.end,
        Position(path: [0, 0], offset: 5),
        reason: 'the nested child is the next paragraph in document order',
      );
    });

    test(
        'down at the very end of the document changes nothing but is '
        'handled', () {
      final end = Selection(
        start: Position(path: [0]),
        end: Position(path: [1], offset: 7),
      );
      final editorState = editorWith(
        [paragraph('one one'), paragraph('two two')],
        end,
      );
      final result = selectParagraphDownCommand.handler(editorState);
      expect(result, KeyEventResult.handled);
      expect(editorState.selection, end);
    });

    test('up from mid-paragraph extends to that paragraph\'s start', () {
      final editorState = editorWith(
        [paragraph('one one'), paragraph('two two')],
        Selection.collapsed(Position(path: [1], offset: 3)),
      );
      selectParagraphUpCommand.handler(editorState);
      expect(
        editorState.selection,
        Selection(
          start: Position(path: [1], offset: 3),
          end: Position(path: [1]),
        ),
      );
    });

    test(
        'up again from a paragraph start takes in the whole previous '
        'paragraph', () {
      final editorState = editorWith(
        [paragraph('one one'), paragraph('two two')],
        Selection(
          start: Position(path: [1], offset: 3),
          end: Position(path: [1]),
        ),
      );
      selectParagraphUpCommand.handler(editorState);
      expect(
        editorState.selection,
        Selection(
          start: Position(path: [1], offset: 3),
          end: Position(path: [0]),
        ),
      );
    });

    test('no selection → ignored', () {
      final editorState = editorWith(
        [paragraph('one')],
        Selection.collapsed(Position(path: [0])),
      );
      editorState.selection = null;
      expect(
        selectParagraphUpCommand.handler(editorState),
        KeyEventResult.ignored,
      );
      expect(
        selectParagraphDownCommand.handler(editorState),
        KeyEventResult.ignored,
      );
    });
  });

  group('visual line stepping (repeatable, user request 2026-07-20 r2):', () {
    testWidgets(
        'pressing Left again in RTL walks the extent down one visual line '
        'per press, and Right retraces the same steps (deselection)',
        (tester) async {
      final editorState = await pumpEditor(tester, [
        paragraph(wrappedRtlText, direction: 'auto'),
      ]);
      final lines = lineSpans(editorState, [0]);
      expect(
        lines.length,
        greaterThanOrEqualTo(3),
        reason: 'test paragraph must wrap — setup broken',
      );

      // Anchor mid visual line 2. In RTL, Left is logically forward.
      final anchor = Position(
        path: [0],
        offset: lines[1].start.offset + 2,
      );
      editorState.selection = Selection.collapsed(anchor);

      selectToVisualLineLeftCommand.handler(editorState);
      expect(editorState.selection!.start, anchor, reason: 'anchor fixed');
      expect(
        editorState.selection!.end.offset,
        lines[1].end.offset,
        reason: '1st press: to the end of line 2',
      );

      selectToVisualLineLeftCommand.handler(editorState);
      expect(
        editorState.selection!.end.offset,
        lines[2].end.offset,
        reason: '2nd press: one more visual line (line 3)',
      );

      selectToVisualLineRightCommand.handler(editorState);
      expect(
        editorState.selection!.end.offset,
        lines[2].start.offset,
        reason: 'opposite arrow shrinks back to line 3\'s start',
      );

      selectToVisualLineRightCommand.handler(editorState);
      expect(
        editorState.selection!.end.offset,
        lines[1].start.offset,
        reason: 'and again: back to line 2\'s start',
      );
    });

    testWidgets(
        'at the block\'s last position, the forward press crosses into the '
        'next text block\'s first visual line', (tester) async {
      final editorState = await pumpEditor(tester, [
        paragraph(wrappedRtlText, direction: 'auto'),
        paragraph('קצר', direction: 'auto'),
      ]);
      final length = editorState.getNodeAtPath([0])!.delta!.length;
      final anchor = Position(path: [0], offset: length - 2);
      editorState.selection = Selection.collapsed(anchor);

      // First press reaches the block's end (last line's edge)…
      selectToVisualLineLeftCommand.handler(editorState);
      expect(editorState.selection!.end, Position(path: [0], offset: length));
      // …next press flows into the second block's first line end.
      selectToVisualLineLeftCommand.handler(editorState);
      expect(editorState.selection!.end, Position(path: [1], offset: 3));
    });
  });

  group('arrow up to title (fixed 2026-07-20 r2):', () {
    testWidgets(
        'fires only from the first VISUAL line of the first block — a '
        'lower line of a wrapped first paragraph is ignored', (tester) async {
      final sharedContext = SharedEditorContext();
      addTearDown(sharedContext.dispose);
      final editorState = await pumpEditor(
        tester,
        [paragraph(wrappedRtlText, direction: 'auto')],
        sharedContext: sharedContext,
      );
      final lines = lineSpans(editorState, [0]);
      expect(lines.length, greaterThanOrEqualTo(2));

      // Caret on visual line 2 → must NOT jump to the title.
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: lines[1].start.offset + 1),
      );
      expect(arrowUpToTitle.handler(editorState), KeyEventResult.ignored);
      expect(
        editorState.selection,
        isNotNull,
        reason: 'selection must survive — the editor moves up a line',
      );

      // Caret on visual line 1 → the title takes over.
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 1),
      );
      expect(arrowUpToTitle.handler(editorState), KeyEventResult.handled);
      expect(
        editorState.selection,
        isNull,
        reason: 'selection cleared when focus moves to the title',
      );
    });
  });

  group('Option+Shift+Left/Right belongs to word selection (2026-07-28):', () {
    // The user reported that Option+Shift+Left/Right selected far too much and
    // asked for Word's behaviour — one WORD per press. The cause was that these
    // two commands were registered on `alt+shift+arrow left/right`, which the
    // editor fork already binds to word selection via `macOSCommand`
    // (arrow_left_command.dart:131, arrow_right_command.dart:135). Registering
    // them ahead of standardCommandShortcutEvents shadowed it.
    //
    // These tests fail if either is put back into the registered list.
    test('the visual-line left/right commands are NOT registered', () {
      expect(
        visualLineSelectionCommands.contains(selectToVisualLineLeftCommand),
        isFalse,
        reason: 'registering this shadows the editor word selection on '
            'Option+Shift+Left — see this file\'s header',
      );
      expect(
        visualLineSelectionCommands.contains(selectToVisualLineRightCommand),
        isFalse,
        reason: 'registering this shadows the editor word selection on '
            'Option+Shift+Right',
      );
    });

    test('nothing registered here claims alt+shift+arrow left/right', () {
      final claimed = visualLineSelectionCommands
          .map((c) => c.command.toLowerCase())
          .toList();
      expect(claimed, isNot(contains('alt+shift+arrow left')));
      expect(claimed, isNot(contains('alt+shift+arrow right')));
    });

    test('paragraph selection keeps up/down, which the editor does not bind',
        () {
      final claimed =
          visualLineSelectionCommands.map((c) => c.command.toLowerCase());
      expect(claimed, contains('alt+shift+arrow up'));
      expect(claimed, contains('alt+shift+arrow down'));
      expect(visualLineSelectionCommands.length, 2);
    });
  });
}
