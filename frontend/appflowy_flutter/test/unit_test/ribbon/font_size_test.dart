// [fork:ribbon] Phase 5 — the font-size "elevator" control.
// See specs/ribbon-menu.md → "Phase 5 scoping".
//
// These assert attribute values and clamping, not rendered geometry, so they are
// safe to run headless.

import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/font_size.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/font_size_commands.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const double _default = 16.0;

EditorState _stateWith(Delta delta) {
  final node = paragraphNode(delta: delta);
  final document = Document.blank()..insert([0], [node]);
  return EditorState(document: document);
}

Selection _wholeFirstBlock(EditorState editorState) {
  final length = editorState.document.nodeAtPath([0])!.delta!.length;
  return Selection(
    start: Position(path: [0]),
    end: Position(path: [0], offset: length),
  );
}

Node _first(EditorState editorState) => editorState.document.nodeAtPath([0])!;

void main() {
  group('formatFontSize', () {
    test('whole numbers drop the trailing .0', () {
      expect(formatFontSize(16.0), '16');
      expect(formatFontSize(8.0), '8');
      expect(formatFontSize(96.0), '96');
    });

    test('a half step keeps its decimal', () {
      expect(formatFontSize(16.5), '16.5');
    });
  });

  group('currentFontSize', () {
    test('unstyled text reports the supplied default', () {
      final editorState = _stateWith(Delta()..insert('hello'));
      editorState.selection = _wholeFirstBlock(editorState);
      expect(currentFontSize(editorState, _default), _default);
    });

    test('a uniformly-sized run reports that size', () {
      final editorState = _stateWith(
        Delta()..insert('hello', attributes: {kFontSizeAttribute: 20.0}),
      );
      editorState.selection = _wholeFirstBlock(editorState);
      expect(currentFontSize(editorState, _default), 20.0);
    });

    test('a selection mixing two sizes reports null (blank box)', () {
      final editorState = _stateWith(
        Delta()
          ..insert('big', attributes: {kFontSizeAttribute: 24.0})
          ..insert('small', attributes: {kFontSizeAttribute: 12.0}),
      );
      editorState.selection = _wholeFirstBlock(editorState);
      expect(currentFontSize(editorState, _default), isNull);
    });

    test('a sized run mixed with an unstyled run is still mixed', () {
      // The unstyled run counts as the default, which differs from 24 — so the
      // box must blank rather than pretend the whole thing is 24.
      final editorState = _stateWith(
        Delta()
          ..insert('big', attributes: {kFontSizeAttribute: 24.0})
          ..insert('plain'),
      );
      editorState.selection = _wholeFirstBlock(editorState);
      expect(currentFontSize(editorState, _default), isNull);
    });

    test('a pending size (toggledStyle) wins for a bare caret', () {
      final editorState = _stateWith(Delta()..insert('hello'));
      editorState.selection = Selection.collapsed(Position(path: [0]));
      editorState.updateToggledStyle(kFontSizeAttribute, 22.0);
      expect(currentFontSize(editorState, _default), 22.0);
    });

    test('an int attribute (JSON round-trip) is read as a double', () {
      final editorState = _stateWith(
        Delta()..insert('hello', attributes: {kFontSizeAttribute: 20}),
      );
      editorState.selection = _wholeFirstBlock(editorState);
      expect(currentFontSize(editorState, _default), 20.0);
    });
  });

  group('applyFontSize', () {
    test('a range writes the attribute onto the run', () async {
      final editorState = _stateWith(Delta()..insert('hello'));
      final selection = _wholeFirstBlock(editorState);
      editorState.selection = selection;

      await applyFontSize(editorState, 28.0, selection: selection);

      expect(currentFontSize(editorState, _default), 28.0);
      // Nothing pending — it was a real range write.
      expect(editorState.toggledStyle[kFontSizeAttribute], isNull);
    });

    test('a bare caret sets a pending size, not a document change', () async {
      final editorState = _stateWith(Delta()..insert('hello'));
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await applyFontSize(editorState, 22.0);

      expect(editorState.toggledStyle[kFontSizeAttribute], 22.0);
      // The text run is untouched.
      expect(_first(editorState).delta!.first.attributes, isNull);
    });

    test('the size is clamped to the [8, 96] range', () async {
      final editorState = _stateWith(Delta()..insert('hello'));
      editorState.selection = Selection.collapsed(Position(path: [0]));

      await applyFontSize(editorState, 500.0);
      expect(editorState.toggledStyle[kFontSizeAttribute], kMaxFontSize);

      await applyFontSize(editorState, 1.0);
      expect(editorState.toggledStyle[kFontSizeAttribute], kMinFontSize);
    });

    test('does nothing when there is no cursor at all', () async {
      final editorState = _stateWith(Delta()..insert('hello'));
      editorState.selection = null;

      await applyFontSize(editorState, 20.0);

      expect(editorState.toggledStyle[kFontSizeAttribute], isNull);
      expect(_first(editorState).delta!.first.attributes, isNull);
    });
  });

  group('font size shortcuts', () {
    test('increase / decrease bind Cmd+Option+. and Cmd+Option+, (no shift)', () {
      // The unshifted `>`/`<` keys; matched by physical location in the fork so
      // they work across keyboard languages.
      expect(increaseFontSizeCommand.command, 'meta+alt+period');
      expect(decreaseFontSizeCommand.command, 'meta+alt+comma');
    });

    test('increase bumps the selected size by one', () async {
      final editorState = _stateWith(
        Delta()..insert('hello', attributes: {kFontSizeAttribute: 20.0}),
      );
      editorState.selection = _wholeFirstBlock(editorState);

      increaseFontSizeCommand.handler!(editorState);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(currentFontSize(editorState, _default), 21.0);
    });

    test('decrease drops the selected size by one', () async {
      final editorState = _stateWith(
        Delta()..insert('hello', attributes: {kFontSizeAttribute: 20.0}),
      );
      editorState.selection = _wholeFirstBlock(editorState);

      decreaseFontSizeCommand.handler!(editorState);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(currentFontSize(editorState, _default), 19.0);
    });

    test('is ignored when there is no cursor', () {
      final editorState = _stateWith(Delta()..insert('hello'));
      editorState.selection = null;
      expect(
        increaseFontSizeCommand.handler!(editorState),
        KeyEventResult.ignored,
      );
    });
  });
}
