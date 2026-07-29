import 'package:appflowy/plugins/document/application/editable_document.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fork:no-titles] Regression cover for "empty pages are dead no matter what"
/// (2026-07-29).
///
/// A document with no block that can hold text accepts no typing anywhere on
/// the page, and looks completely normal while doing it. Ludwig has no page
/// title to fall back on, so there is no way out for the user.
void main() {
  Document documentOf(List<Node> children) =>
      Document(root: pageNode(children: children));

  Node imageNode() => Node(
        type: 'image',
        attributes: const {'url': 'https://example.com/a.png'},
      );

  group('ensureDocumentIsEditable', () {
    test('adds a paragraph to a document with no blocks', () {
      final document = documentOf([]);

      expect(ensureDocumentIsEditable(document), isTrue);
      expect(document.root.children.length, 1);
      expect(document.root.children.first.delta, isNotNull);
    });

    test('adds a paragraph when every block is untypeable', () {
      final document = documentOf([imageNode(), Node(type: 'divider')]);

      expect(ensureDocumentIsEditable(document), isTrue);
      expect(document.root.children.length, 3);
      // Appended, not prepended: a page that legitimately opens with an image
      // must keep the image first.
      expect(document.root.children.first.type, 'image');
      expect(document.root.children.last.delta, isNotNull);
    });

    test('leaves an ordinary document alone', () {
      final document = documentOf([
        paragraphNode(text: 'hello'),
        paragraphNode(text: 'world'),
      ]);

      expect(ensureDocumentIsEditable(document), isFalse);
      expect(document.root.children.length, 2);
    });

    test('leaves a document with one EMPTY paragraph alone', () {
      // The ordinary blank page. It already has somewhere to type, so touching
      // it would add a spurious second line to every new page.
      final document = documentOf([paragraphNode(text: '')]);

      expect(ensureDocumentIsEditable(document), isFalse);
      expect(document.root.children.length, 1);
    });

    test('is idempotent', () {
      final document = documentOf([]);

      expect(ensureDocumentIsEditable(document), isTrue);
      expect(ensureDocumentIsEditable(document), isFalse);
      expect(document.root.children.length, 1);
    });

    test('counts a heading as somewhere to type', () {
      final document = documentOf([headingNode(level: 1, text: 'Title')]);

      expect(ensureDocumentIsEditable(document), isFalse);
      expect(document.root.children.length, 1);
    });
  });
}
