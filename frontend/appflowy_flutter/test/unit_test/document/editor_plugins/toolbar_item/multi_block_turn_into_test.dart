import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/toolbar_item/text_heading_toolbar_item.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression test for real data loss, 2026-07-27 (session 17).
//
// A page lost a paragraph: the user selected two paragraphs and changed their
// block type, and afterwards BOTH blocks held the FIRST paragraph's text. The
// second paragraph's writing was gone. Reconstructed from the sync log:
//
//   06:18:57  Insert heading  <- text "זה לא חייב..."   (paragraph 1)
//             Delete paragraph 1
//             Insert heading  <- text "זה לא חייב..."   (paragraph 1 AGAIN)
//             Delete paragraph 2                        (its text never written)
//
// These are pure data transformations with no geometry, so a headless unit test
// is the right tool here -- STATUS.md's "never trust headless" rule is about
// visual/RTL caret measurement, which none of this touches.

Document _twoParagraphs() => Document(
      root: pageNode(
        children: [
          paragraphNode(text: 'first paragraph'),
          paragraphNode(text: 'second paragraph'),
        ],
      ),
    );

/// Selects from the start of the first block to the end of the last.
Selection _selectAll(EditorState editorState) {
  final children = editorState.document.root.children;
  return Selection(
    start: Position(path: children.first.path),
    end: Position(
      path: children.last.path,
      offset: children.last.delta?.length ?? 0,
    ),
  );
}

List<String> _texts(EditorState editorState) => editorState.document.root.children
    .map((n) => n.delta?.toPlainText() ?? '')
    .toList();

void main() {
  group('block type change across a multi-block selection', () {
    test('turning two paragraphs into headings keeps each ones own text', () async {
      final editorState = EditorState(document: _twoParagraphs());
      editorState.selection = _selectAll(editorState);

      await BlockActionOptionCubit.turnIntoBlock(
        HeadingBlockKeys.type,
        editorState.getNodeAtPath([0])!,
        editorState,
        level: 3,
        keepSelection: true,
      );

      expect(
        _texts(editorState),
        ['first paragraph', 'second paragraph'],
        reason: 'each block must keep its own text, not the first blocks',
      );
      expect(
        editorState.document.root.children.map((n) => n.type),
        everyElement(HeadingBlockKeys.type),
      );
    });

    test('turning two headings back into text keeps each ones own text', () async {
      final editorState = EditorState(
        document: Document(
          root: pageNode(
            children: [
              headingNode(level: 3, text: 'first paragraph'),
              headingNode(level: 3, text: 'second paragraph'),
            ],
          ),
        ),
      );
      editorState.selection = _selectAll(editorState);

      formatNodeToText(editorState);
      await Future<void>.delayed(Duration.zero);

      expect(
        _texts(editorState),
        ['first paragraph', 'second paragraph'],
        reason: 'formatNodeToText captured one delta and stamped it over all nodes',
      );
    });

    // The real page had justify applied to the same two paragraphs three
    // seconds before the block type changed, so alignment is reproduced here
    // rather than assumed irrelevant.
    test('an alignment attribute does not reintroduce the duplication', () async {
      final editorState = EditorState(
        document: Document(
          root: pageNode(
            children: [
              paragraphNode(
                text: 'first paragraph',
                attributes: {blockComponentAlign: 'justify'},
              ),
              paragraphNode(
                text: 'second paragraph',
                attributes: {blockComponentAlign: 'justify'},
              ),
            ],
          ),
        ),
      );
      editorState.selection = _selectAll(editorState);

      await BlockActionOptionCubit.turnIntoBlock(
        HeadingBlockKeys.type,
        editorState.getNodeAtPath([0])!,
        editorState,
        level: 3,
        keepSelection: true,
      );
      expect(_texts(editorState), ['first paragraph', 'second paragraph']);

      editorState.selection = _selectAll(editorState);
      formatNodeToText(editorState);
      await Future<void>.delayed(Duration.zero);
      expect(_texts(editorState), ['first paragraph', 'second paragraph']);
    });

    test('a single-block selection is unaffected (guards the fix)', () async {
      final editorState = EditorState(document: _twoParagraphs());
      editorState.selection = Selection.single(path: [1], startOffset: 0);

      await BlockActionOptionCubit.turnIntoBlock(
        HeadingBlockKeys.type,
        editorState.getNodeAtPath([1])!,
        editorState,
        level: 1,
      );

      expect(_texts(editorState), ['first paragraph', 'second paragraph']);
    });
  });
}
