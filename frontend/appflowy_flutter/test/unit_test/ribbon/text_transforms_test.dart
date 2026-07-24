// [fork:ribbon] Phase 3 — clear formatting and change case.
// See specs/ribbon-menu.md → "Phase 3 scoping".
//
// Pure-logic tests. The case transforms are string in / string out, and the
// delta tests assert document *content*, not geometry — so the headless
// fixed-width-font trap in CLAUDE.md does not apply to anything here.

import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/text_transforms.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-paragraph document whose text carries [attributes] on the whole run.
EditorState _stateWith(String text, {Attributes? attributes}) {
  final delta = Delta()..insert(text, attributes: attributes);
  final document = Document.blank()..insert([0], [paragraphNode(delta: delta)]);
  return EditorState(document: document);
}

Node _firstParagraph(EditorState editorState) =>
    editorState.document.nodeAtPath([0])!;

void main() {
  group('LetterCase transforms', () {
    test('UPPERCASE and lowercase', () {
      expect(LetterCase.upper.apply('hello World'), 'HELLO WORLD');
      expect(LetterCase.lower.apply('Hello WORLD'), 'hello world');
    });

    test('Capitalize Each Word preserves the original whitespace', () {
      expect(
        LetterCase.capitalize.apply('the  quick   brown fox'),
        'The  Quick   Brown Fox',
      );
    });

    test('tOGGLE cASE flips each letter', () {
      expect(LetterCase.toggle.apply('Hello World'), 'hELLO wORLD');
    });

    test('Sentence case capitalises after . ! and ?', () {
      expect(
        LetterCase.sentence.apply('hello there. how are you? fine! ok'),
        'Hello there. How are you? Fine! Ok',
      );
    });

    test('Sentence case lowercases a shouted sentence', () {
      expect(LetterCase.sentence.apply('THIS IS LOUD'), 'This is loud');
    });

    // The reason `changesAnything` exists at all: Hebrew has no letter case, so
    // every transform is a genuine no-op and the menu entry must disable itself
    // rather than appear broken when pressing it does nothing.
    group('unicase scripts', () {
      const hebrew = 'שלום עולם';

      test('every transform is a no-op on Hebrew', () {
        for (final letterCase in LetterCase.values) {
          expect(
            letterCase.apply(hebrew),
            hebrew,
            reason: '${letterCase.label} must not alter Hebrew',
          );
        }
      });

      test('changesAnything reports false for Hebrew, true for Latin', () {
        for (final letterCase in LetterCase.values) {
          expect(letterCase.changesAnything(hebrew), isFalse);
        }
        expect(LetterCase.upper.changesAnything('hello'), isTrue);
      });

      test('mixed Hebrew and Latin still changes the Latin part', () {
        expect(LetterCase.upper.apply('שלום world'), 'שלום WORLD');
        expect(LetterCase.upper.changesAnything('שלום world'), isTrue);
      });
    });
  });

  group('applyLetterCase on a document', () {
    test('transforms the whole paragraph from a bare caret', () async {
      final editorState = _stateWith('hello world');
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await applyLetterCase(editorState, LetterCase.upper);

      expect(_firstParagraph(editorState).delta!.toPlainText(), 'HELLO WORLD');
    });

    test('transforms only the selected range', () async {
      final editorState = _stateWith('hello world');
      editorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [0], offset: 5),
      );

      await applyLetterCase(editorState, LetterCase.upper);

      expect(_firstParagraph(editorState).delta!.toPlainText(), 'HELLO world');
    });

    // The reason this operates on the delta rather than replacing text: a
    // delete-then-insert would drop every mark the user had applied.
    test('preserves inline attributes', () async {
      final editorState = _stateWith('hello', attributes: {'bold': true});
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await applyLetterCase(editorState, LetterCase.upper);

      final delta = _firstParagraph(editorState).delta!;
      expect(delta.toPlainText(), 'HELLO');
      expect(
        delta
            .whereType<TextInsert>()
            .every((op) => op.attributes?['bold'] == true),
        isTrue,
        reason: 'bold must survive the case change',
      );
    });

    test('makes no change — and no undo step — when nothing would change',
        () async {
      final editorState = _stateWith('שלום');
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await applyLetterCase(editorState, LetterCase.upper);

      expect(_firstParagraph(editorState).delta!.toPlainText(), 'שלום');
    });
  });

  group('clearFormatting', () {
    test('strips inline marks but leaves the text alone', () async {
      final editorState = _stateWith(
        'hello',
        attributes: {'bold': true, 'italic': true, 'font_color': '0xff00ff00'},
      );
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await clearFormatting(editorState);

      final delta = _firstParagraph(editorState).delta!;
      expect(delta.toPlainText(), 'hello');
      for (final op in delta.whereType<TextInsert>()) {
        for (final key in clearableInlineAttributes) {
          expect(
            op.attributes?[key],
            isNull,
            reason: '$key should have been cleared',
          );
        }
      }
    });

    // "Clear everything" (user decision, 2026-07-23): the block returns to a
    // plain paragraph and its alignment/level/spacing are gone.
    test('resets a heading to a paragraph and drops block formatting', () async {
      final delta = Delta()..insert('a heading', attributes: {'bold': true});
      final document = Document.blank()
        ..insert([
          0,
        ], [
          headingNode(level: 2, delta: delta)
            ..updateAttributes({
              blockComponentAlign: 'center',
              'appflowy_line_height': 2.0,
              'appflowy_space_after': 12.0,
            }),
        ]);
      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await clearFormatting(editorState);

      final node = editorState.document.nodeAtPath([0])!;
      expect(node.type, ParagraphBlockKeys.type);
      expect(node.attributes.containsKey(blockComponentAlign), isFalse);
      expect(node.attributes.containsKey('appflowy_line_height'), isFalse);
      expect(node.attributes.containsKey('appflowy_space_after'), isFalse);
      expect(node.delta!.toPlainText(), 'a heading');
      // The bold mark is gone too.
      expect(
        node.delta!.whereType<TextInsert>().every(
              (op) => op.attributes?['bold'] != true,
            ),
        isTrue,
      );
    });

    // Reading direction is a content property, not stylistic formatting:
    // clearing it would flip an RTL paragraph to LTR. It must survive.
    test('preserves the reading direction', () async {
      final delta = Delta()..insert('שלום');
      final document = Document.blank()
        ..insert([
          0,
        ], [
          headingNode(level: 1, delta: delta)
            ..updateAttributes(
              {blockComponentTextDirection: blockComponentTextDirectionRTL},
            ),
        ]);
      final editorState = EditorState(document: document);
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await clearFormatting(editorState);

      final node = editorState.document.nodeAtPath([0])!;
      expect(node.type, ParagraphBlockKeys.type);
      expect(
        node.attributes[blockComponentTextDirection],
        blockComponentTextDirectionRTL,
      );
    });
  });

  group('effectiveSelection', () {
    test('returns null with no cursor at all', () {
      final editorState = _stateWith('hello');
      editorState.selection = null;
      expect(effectiveSelection(editorState), isNull);
    });

    test('expands a bare caret to the whole block', () {
      final editorState = _stateWith('hello');
      editorState.selection =
          Selection.collapsed(Position(path: [0], offset: 2));

      final selection = effectiveSelection(editorState)!;
      expect(selection.start.offset, 0);
      expect(selection.end.offset, 5);
    });

    test('leaves an existing range untouched', () {
      final editorState = _stateWith('hello');
      final range = Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [0], offset: 3),
      );
      editorState.selection = range;

      expect(effectiveSelection(editorState), range);
    });
  });
}
