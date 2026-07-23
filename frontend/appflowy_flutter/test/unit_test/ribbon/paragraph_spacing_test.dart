// [fork:ribbon] Phase 3 — per-paragraph line height and paragraph spacing.
// See specs/ribbon-menu.md → "Phase 3 scoping".
//
// These assert attribute values and EdgeInsets arithmetic, not rendered
// geometry, so they are safe to run headless.

import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/paragraph_spacing.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EditorState _stateWithParagraph({Attributes? attributes}) {
  final node = paragraphNode(text: 'hello');
  if (attributes != null) {
    node.updateAttributes(attributes);
  }
  final document = Document.blank()..insert([0], [node]);
  return EditorState(document: document);
}

Node _first(EditorState editorState) => editorState.document.nodeAtPath([0])!;

void main() {
  group('defaults preserve the previous hardcoded desktop values', () {
    // The whole point: an untouched document must render byte-identically to
    // before Phase 3. Desktop previously hardcoded 1.4 line height and
    // EdgeInsets.symmetric(vertical: 5.0).
    test('a block with no attributes reports the old constants', () {
      final node = paragraphNode(text: 'hello');
      expect(lineHeightOf(node), kDefaultLineHeight);
      expect(lineHeightOf(node), 1.4);
      expect(spaceAfterOf(node), 0.0);
      expect(
        desktopBlockPadding(node),
        const EdgeInsets.symmetric(vertical: 5.0),
      );
    });

    // "Single" must be a no-op on an untouched paragraph. AppFlowy's baseline is
    // 1.4, not a word processor's 1.0, so pinning Single to the default is what
    // stops the preset from visibly jumping the first time it is chosen.
    test('the Single preset equals the default line height', () {
      expect(LineSpacingPreset.single.multiplier, kDefaultLineHeight);
    });

    test('presets scale off that baseline, in increasing order', () {
      final values = LineSpacingPreset.values.map((p) => p.multiplier).toList();
      expect(values, orderedEquals([...values]..sort()));
      expect(LineSpacingPreset.oneAndAHalf.multiplier, 1.4 * 1.5);
      expect(LineSpacingPreset.double$.multiplier, 2.8);
    });
  });

  group('reading a block that carries values', () {
    test('line height is read from the attribute', () {
      final node = paragraphNode(text: 'hello')
        ..updateAttributes({blockComponentLineHeight: 2.0});
      expect(lineHeightOf(node), 2.0);
      expect(lineHeightTextStyle(node).height, 2.0);
    });

    // Only `height` may be set: the editor's TextStyle.combine copies each field
    // from the incoming style, and Flutter's copyWith treats null as "keep", so
    // anything else set here would silently override the resolved style.
    test('the per-node text style sets height and nothing else', () {
      final node = paragraphNode(text: 'hello');
      final style = lineHeightTextStyle(node);
      expect(style.height, kDefaultLineHeight);
      expect(style.color, isNull);
      expect(style.fontSize, isNull);
      expect(style.fontWeight, isNull);
    });

    // Spacing goes below only — adding it to both edges would double the gap
    // between two spaced paragraphs.
    test('paragraph spacing is added below only', () {
      final node = paragraphNode(text: 'hello')
        ..updateAttributes({blockComponentSpaceAfter: 12.0});
      final padding = desktopBlockPadding(node);
      expect(padding.top, kDefaultBlockVerticalPadding);
      expect(padding.bottom, kDefaultBlockVerticalPadding + 12.0);
    });

    test('an integer attribute survives a JSON round-trip as a double', () {
      // Attributes come back from the backend as JSON, where 2.0 may arrive as
      // an int. Reading must not throw or fall back to the default.
      final node = paragraphNode(text: 'hello')
        ..updateAttributes({blockComponentLineHeight: 2});
      expect(lineHeightOf(node), 2.0);
    });
  });

  group('writing spacing attributes', () {
    test('sets the attribute on the selected block', () async {
      final editorState = _stateWithParagraph();
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await setBlockSpacingAttribute(
        editorState,
        blockComponentLineHeight,
        2.0,
      );

      expect(_first(editorState).attributes[blockComponentLineHeight], 2.0);
    });

    test('a null value removes the attribute, returning to the default',
        () async {
      final editorState =
          _stateWithParagraph(attributes: {blockComponentLineHeight: 2.0});
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await setBlockSpacingAttribute(
        editorState,
        blockComponentLineHeight,
        null,
      );

      final node = _first(editorState);
      expect(node.attributes.containsKey(blockComponentLineHeight), isFalse);
      expect(lineHeightOf(node), kDefaultLineHeight);
    });

    test('leaves other attributes alone', () async {
      final editorState = _stateWithParagraph(
        attributes: {blockComponentAlign: 'center'},
      );
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await setBlockSpacingAttribute(
        editorState,
        blockComponentSpaceAfter,
        6.0,
      );

      expect(_first(editorState).attributes[blockComponentAlign], 'center');
    });
  });

  group('blockSpacingIs', () {
    test('an untouched block reports the default as its current value', () {
      final editorState = _stateWithParagraph();
      editorState.selection = Selection.collapsed(Position(path: [0]));

      // This is what makes "Single" show its check mark on a fresh paragraph.
      expect(
        blockSpacingIs(
          editorState,
          blockComponentLineHeight,
          kDefaultLineHeight,
        ),
        isTrue,
      );
      expect(
        blockSpacingIs(editorState, blockComponentSpaceAfter, 0.0),
        isTrue,
      );
    });

    test('reports false for a value the block does not carry', () {
      final editorState = _stateWithParagraph();
      editorState.selection = Selection.collapsed(Position(path: [0]));
      expect(
        blockSpacingIs(editorState, blockComponentLineHeight, 2.0),
        isFalse,
      );
    });

    test('reports false with no cursor at all', () {
      final editorState = _stateWithParagraph();
      editorState.selection = null;
      expect(
        blockSpacingIs(
          editorState,
          blockComponentLineHeight,
          kDefaultLineHeight,
        ),
        isFalse,
      );
    });
  });
}
