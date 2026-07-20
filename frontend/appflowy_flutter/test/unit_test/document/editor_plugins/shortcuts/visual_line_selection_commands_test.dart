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

import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/visual_line_selection_commands.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Node paragraph(String text, {List<Node>? children}) {
  return Node(
    type: ParagraphBlockKeys.type,
    attributes: {
      ParagraphBlockKeys.delta: (Delta()..insert(text)).toJson(),
    },
    children: children ?? [],
  );
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

    test('RTL: left = logical END (forward in reading order), '
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
    test('down from mid-paragraph extends to that paragraph\'s end, '
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

    test('down again from a paragraph end takes in the whole next '
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

    test('down at the very end of the document changes nothing but is '
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

    test('up again from a paragraph start takes in the whole previous '
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
}
