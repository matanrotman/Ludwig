import 'package:appflowy/plugins/document/presentation/editor_plugins/header/header_click_target.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fork:no-titles] Regression cover for the 2026-07-29 "the keyboard stopped
/// working" report.
///
/// Clicking the blank band above the first line — the space Ludwig keeps where
/// the page title used to be — used to clear the editor's selection, leaving a
/// page that silently ignored every keystroke. It must now resolve to a caret
/// position on the first line that can hold one.
void main() {
  Document documentOf(List<Node> children) =>
      Document(root: pageNode(children: children));

  Node imageNode() => Node(
        type: 'image',
        attributes: const {'url': 'https://example.com/a.png'},
      );

  Node dividerNode() => Node(type: 'divider');

  group('headerClickCaretPosition', () {
    test('targets the first line of an ordinary page', () {
      final document = documentOf([
        paragraphNode(text: 'first'),
        paragraphNode(text: 'second'),
      ]);

      final position = headerClickCaretPosition(document);

      expect(position, isNotNull);
      expect(position!.path, [0]);
      expect(position.offset, 0);
    });

    test('targets the empty first line of a blank page', () {
      // The case that made this unrecoverable: an empty page has nothing to
      // drag-select, so a cleared selection could not be won back at all.
      final document = documentOf([paragraphNode(text: '')]);

      final position = headerClickCaretPosition(document);

      expect(position, isNotNull);
      expect(position!.path, [0]);
    });

    test('skips leading blocks that cannot hold a caret', () {
      // A page can open with an image or a divider on top. Putting the caret
      // there would select the block rather than start you typing.
      final document = documentOf([
        imageNode(),
        dividerNode(),
        paragraphNode(text: 'the first real line'),
      ]);

      final position = headerClickCaretPosition(document);

      expect(position, isNotNull);
      expect(position!.path, [2]);
    });

    test('returns null when no block can hold a caret', () {
      // Leave the selection alone rather than clearing it — clearing is the
      // very bug this exists to fix.
      final document = documentOf([imageNode(), dividerNode()]);

      expect(headerClickCaretPosition(document), isNull);
    });

    test('returns null for a document with no blocks at all', () {
      expect(headerClickCaretPosition(documentOf([])), isNull);
    });

    test('finds a heading, not only a paragraph', () {
      final document = documentOf([
        headingNode(level: 1, text: 'A title-ish first line'),
        paragraphNode(text: 'body'),
      ]);

      final position = headerClickCaretPosition(document);

      expect(position, isNotNull);
      expect(position!.path, [0]);
    });
  });
}
