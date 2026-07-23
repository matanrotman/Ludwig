// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 3).
//
// Two text operations the ribbon needs that AppFlowy did not have: clearing
// inline formatting, and changing letter case.
//
// Both follow the same rule, settled at Phase 3 sign-off (2026-07-23): with a
// range selected they act on the selection; with only a caret they act on the
// whole paragraph, matching the align/list/indent buttons already in the ribbon
// rather than greying out.

import 'package:appflowy_editor/appflowy_editor.dart';

/// The inline marks "Clear formatting" removes.
///
/// Deliberately inline-only (user decision, 2026-07-23): block type, alignment
/// and list membership survive, so a heading stays a heading. This is narrower
/// than Word's "Clear All Formatting" and was chosen for predictability — the
/// destructive version is easy to hit by accident and hard to undo mentally.
///
/// `findBackgroundColor` is excluded on purpose: it is the find-and-replace
/// highlight, owned by the editor's search UI, not user formatting.
const List<String> clearableInlineAttributes = [
  'bold',
  'italic',
  'underline',
  'strikethrough',
  'code',
  'font_color',
  'bg_color',
  'href',
  'font_family',
  'font_size',
];

/// The selection an action should operate on: the user's range if there is one,
/// otherwise the whole block the caret sits in.
///
/// Returns null when there is no cursor in the editor at all — the one genuinely
/// dead state (focus is in the sidebar).
Selection? effectiveSelection(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return null;
  }
  if (!selection.isCollapsed) {
    return selection;
  }
  final node = editorState.getNodeAtPath(selection.start.path);
  final length = node?.delta?.length;
  if (node == null || length == null) {
    return null;
  }
  return Selection(
    start: Position(path: node.path),
    end: Position(path: node.path, offset: length),
  );
}

/// Strips every mark in [clearableInlineAttributes] from the target text.
Future<void> clearInlineFormatting(EditorState editorState) async {
  final selection = effectiveSelection(editorState);
  if (selection == null) {
    return;
  }
  await editorState.formatDelta(
    selection,
    {for (final key in clearableInlineAttributes) key: null},
  );
}

/// The letter-case transforms offered by the ribbon's Change Case dropdown.
///
/// ⚠️ Every one of these is a no-op on Hebrew, Arabic and other unicase
/// scripts — they have no upper/lower distinction. That is correct behaviour,
/// not a bug, but it means the button can look broken to this project's primary
/// user. See [changesAnything], which the ribbon uses to grey the entry out
/// rather than let it silently do nothing.
enum LetterCase {
  sentence('Sentence case'),
  lower('lowercase'),
  upper('UPPERCASE'),
  capitalize('Capitalize Each Word'),
  toggle('tOGGLE cASE');

  const LetterCase(this.label);

  final String label;

  /// Applies this transform to [input].
  ///
  /// Sentence case is scoped to the block, not the whole selection: each
  /// paragraph starts its own first sentence. Sentence boundaries are `.`, `!`
  /// and `?` followed by whitespace — deliberately simple, since the alternative
  /// is abbreviation detection ("e.g.", "Dr.") that no editor gets fully right.
  String apply(String input) {
    switch (this) {
      case LetterCase.lower:
        return input.toLowerCase();
      case LetterCase.upper:
        return input.toUpperCase();
      case LetterCase.capitalize:
        return _mapWords(input, (word) => _capitalize(word));
      case LetterCase.toggle:
        return String.fromCharCodes(
          input.runes.map((rune) {
            final char = String.fromCharCode(rune);
            final lower = char.toLowerCase();
            // Unicase characters compare equal both ways; leave them alone.
            return char == lower
                ? char.toUpperCase().codeUnitAt(0)
                : lower.codeUnitAt(0);
          }),
        );
      case LetterCase.sentence:
        return _toSentenceCase(input);
    }
  }

  /// Whether applying this transform would actually change [input].
  ///
  /// Used to disable the entry rather than offer an action that does nothing —
  /// the Hebrew case above.
  bool changesAnything(String input) => apply(input) != input;
}

String _capitalize(String word) {
  if (word.isEmpty) {
    return word;
  }
  return word[0].toUpperCase() + word.substring(1).toLowerCase();
}

/// Applies [transform] to each run of non-whitespace, preserving the original
/// whitespace exactly (including runs of spaces and any line separators).
String _mapWords(String input, String Function(String) transform) {
  return input.replaceAllMapped(
    RegExp(r'\S+'),
    (match) => transform(match.group(0)!),
  );
}

String _toSentenceCase(String input) {
  final lowered = input.toLowerCase();
  final buffer = StringBuffer();
  var capitalizeNext = true;
  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    if (capitalizeNext && char.trim().isNotEmpty) {
      buffer.write(char.toUpperCase());
      capitalizeNext = false;
      continue;
    }
    buffer.write(char);
    if (char == '.' || char == '!' || char == '?') {
      capitalizeNext = true;
    }
  }
  return buffer.toString();
}

/// Rewrites the target text with [letterCase] applied, preserving every inline
/// attribute.
///
/// Works on the delta rather than replacing text: a naive "delete then insert"
/// would drop the bold/link/colour runs the user had applied. Each text insert
/// is transformed in place and its attributes carried over untouched.
Future<void> applyLetterCase(
  EditorState editorState,
  LetterCase letterCase,
) async {
  final selection = effectiveSelection(editorState);
  if (selection == null) {
    return;
  }
  final normalized = selection.normalized;
  final nodes = editorState.getNodesInSelection(normalized);
  if (nodes.isEmpty) {
    return;
  }

  final transaction = editorState.transaction;
  var changed = false;

  for (final node in nodes) {
    final delta = node.delta;
    if (delta == null) {
      continue;
    }
    // How much of this node the selection covers. Only the first and last node
    // of a multi-block selection are partial.
    final start =
        node.path.equals(normalized.start.path) ? normalized.start.offset : 0;
    final end = node.path.equals(normalized.end.path)
        ? normalized.end.offset
        : delta.length;
    if (start >= end) {
      continue;
    }

    final updated = Delta();
    var offset = 0;
    for (final op in delta) {
      if (op is! TextInsert) {
        updated.addAll([op]);
        offset += op.length;
        continue;
      }
      final opStart = offset;
      final opEnd = offset + op.length;
      offset = opEnd;

      // The part of this run that falls inside the target range.
      final overlapStart = opStart > start ? opStart : start;
      final overlapEnd = opEnd < end ? opEnd : end;
      if (overlapStart >= overlapEnd) {
        updated.insert(op.text, attributes: op.attributes);
        continue;
      }

      final before = op.text.substring(0, overlapStart - opStart);
      final middle =
          op.text.substring(overlapStart - opStart, overlapEnd - opStart);
      final after = op.text.substring(overlapEnd - opStart);
      final transformed = letterCase.apply(middle);
      if (transformed != middle) {
        changed = true;
      }
      if (before.isNotEmpty) {
        updated.insert(before, attributes: op.attributes);
      }
      updated.insert(transformed, attributes: op.attributes);
      if (after.isNotEmpty) {
        updated.insert(after, attributes: op.attributes);
      }
    }

    transaction.updateNode(node, {'delta': updated.toJson()});
  }

  if (!changed) {
    // Nothing to do — don't push an empty step onto the undo stack.
    return;
  }
  transaction.afterSelection = selection;
  await editorState.apply(transaction);
}
