// [fork:rtl] Sidecar module — see specs/rtl-support.md
// "select-to-line and select-by-paragraph shortcuts" (decided 2026-07-20).
//
// Option+Shift+Up/Down extends the selection by one whole paragraph per press.
//
// ⚠️ Option+Shift+LEFT/RIGHT IS NO LONGER BOUND HERE (changed 2026-07-28 at the
// user's request: "make option+shift+left/right select the next word, not the
// whole sentence ... mimic Word's behavior").
//
// The 2026-07-24 r2 comment this replaces claimed "the editor binds no
// `alt+shift+arrow` of its own, so there is no conflict." **That was wrong.**
// The editor fork binds word-wise selection to exactly those keys via
// `macOSCommand` — `arrow_left_command.dart:131` and
// `arrow_right_command.dart:135` — so registering these two ahead of
// `standardCommandShortcutEvents` silently shadowed word selection for four
// days. Whenever a shortcut here "has no conflict", check `macOSCommand` and
// not just `command`.
//
// `selectToVisualLineLeftCommand`/`RightCommand` are deliberately KEPT but left
// out of [visualLineSelectionCommands], so the behaviour is one line away if it
// is ever wanted on a free binding — and so their tests keep covering it.
//
// RTL semantics are VISUAL, not logical: Left always extends toward the
// left of the screen, which in an RTL block is *forward* in reading order.
// The visual line span itself comes from the editor fork's
// `SelectableMixin.getLineBoundaryInPosition` (only render objects know
// where a line wraps); these commands only map "left/right" onto the
// span's logical start/end using the block's resolved text direction.
//
// Registered as CommandShortcutEvents so they show up in Settings →
// Shortcuts and are rebindable, same as every other shortcut.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Registered shortcuts. Left/right are intentionally absent — see the header:
/// Option+Shift+Left/Right belongs to the editor's own word selection.
final List<CommandShortcutEvent> visualLineSelectionCommands = [
  selectParagraphUpCommand,
  selectParagraphDownCommand,
  moveCursorParagraphUpCommand,
  moveCursorParagraphDownCommand,
];

/// Option+Up/Down (no shift) — the collapsed-caret counterpart of
/// [selectParagraphUpCommand]/[selectParagraphDownCommand]. Previously
/// unbound entirely (reported 2026-08-05: "option + arrow up/down doesn't
/// work"), matching the native macOS convention (TextEdit's
/// moveToBeginningOfParagraph:/moveToEndOfParagraph:) rather than inventing
/// one — first press goes to this paragraph's start/end, a further press at
/// that edge steps into the neighboring one.
final CommandShortcutEvent moveCursorParagraphUpCommand = CommandShortcutEvent(
  key: 'move the cursor to the start of the paragraph',
  getDescription: () => 'Move cursor to paragraph start',
  command: 'alt+arrow up',
  macOSCommand: 'alt+arrow up',
  handler: (editorState) => _moveCursorByParagraph(editorState, up: true),
);

final CommandShortcutEvent moveCursorParagraphDownCommand =
    CommandShortcutEvent(
  key: 'move the cursor to the end of the paragraph',
  getDescription: () => 'Move cursor to paragraph end',
  command: 'alt+arrow down',
  macOSCommand: 'alt+arrow down',
  handler: (editorState) => _moveCursorByParagraph(editorState, up: false),
);

KeyEventResult _moveCursorByParagraph(
  EditorState editorState, {
  required bool up,
}) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  final extent = selection.end;
  final node = editorState.getNodeAtPath(extent.path);
  if (node == null) {
    return KeyEventResult.ignored;
  }
  final target = _paragraphTarget(node, extent, up: up);
  if (target != null) {
    editorState.updateSelectionWithReason(
      Selection.collapsed(target),
      reason: SelectionUpdateReason.uiEvent,
    );
  }
  return KeyEventResult.handled;
}

/// ⚠️ NOT REGISTERED — adding this back to [visualLineSelectionCommands] would
/// shadow the editor's word selection again. See the header.
final CommandShortcutEvent selectToVisualLineLeftCommand =
    CommandShortcutEvent(
  key: 'extend the selection to the left edge of the visual line',
  getDescription: () => 'Extend selection to the left edge of the line',
  command: 'alt+shift+arrow left',
  handler: (editorState) =>
      _extendToVisualLineEdge(editorState, towardLeft: true),
);

/// ⚠️ NOT REGISTERED — see [selectToVisualLineLeftCommand].
final CommandShortcutEvent selectToVisualLineRightCommand =
    CommandShortcutEvent(
  key: 'extend the selection to the right edge of the visual line',
  getDescription: () => 'Extend selection to the right edge of the line',
  command: 'alt+shift+arrow right',
  handler: (editorState) =>
      _extendToVisualLineEdge(editorState, towardLeft: false),
);

final CommandShortcutEvent selectParagraphUpCommand = CommandShortcutEvent(
  key: 'extend the selection up by one paragraph',
  getDescription: () => 'Extend selection up by one paragraph',
  command: 'alt+shift+arrow up',
  handler: (editorState) => _extendByParagraph(editorState, up: true),
);

final CommandShortcutEvent selectParagraphDownCommand = CommandShortcutEvent(
  key: 'extend the selection down by one paragraph',
  getDescription: () => 'Extend selection down by one paragraph',
  command: 'alt+shift+arrow down',
  handler: (editorState) => _extendByParagraph(editorState, up: false),
);

KeyEventResult _extendToVisualLineEdge(
  EditorState editorState, {
  required bool towardLeft,
}) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  // selection.end is the extent (the moving side of a shift-selection);
  // the anchor at selection.start stays put, matching how the editor's
  // own shift+arrow commands extend.
  final extent = selection.end;
  final node = editorState.getNodeAtPath(extent.path);
  final selectable = node?.selectable;
  final line = selectable?.getLineBoundaryInPosition(extent);
  if (node == null || selectable == null || line == null) {
    return KeyEventResult.ignored;
  }
  final isRtl = selectable.textDirection() == TextDirection.rtl;
  Position? target = visualLineEdgeTarget(
    line: line,
    towardLeft: towardLeft,
    isRtl: isRtl,
  );
  if (target.offset == extent.offset) {
    // Already at this line's edge — keep walking one visual line per
    // press in the same on-screen direction (user request 2026-07-20 r2:
    // "click again on the arrow, it should select the next line — same
    // for deselection"). Pressing the opposite arrow retraces the same
    // steps, so a multi-line extension shrinks line by line.
    //
    // Within a block, only the logically-forward edge needs this step: a
    // backward-edge offset IS the previous line's boundary, so the next
    // press re-resolves onto that line by itself (upstream affinity).
    // The exceptions are block edges — offset 0 going backward, the
    // block's last offset going forward — where the step crosses into
    // the neighboring text block.
    target = _adjacentVisualLineEdge(
      editorState,
      node,
      extent,
      forward: towardLeft == isRtl,
    );
  }
  if (target != null && target != extent) {
    editorState.updateSelectionWithReason(
      selection.copyWith(end: target),
      reason: SelectionUpdateReason.uiEvent,
    );
  }
  return KeyEventResult.handled;
}

/// The edge of the visual line adjacent to [extent], in logical
/// [forward]/backward direction, crossing into the neighboring text block
/// when [extent] sits at this block's first/last position.
///
/// Falls back to the neighboring block's start/end (block precision
/// instead of line precision) when that block's render object is not
/// mounted, and to null at the document's edges.
Position? _adjacentVisualLineEdge(
  EditorState editorState,
  Node node,
  Position extent, {
  required bool forward,
}) {
  final delta = node.delta;
  final selectable = node.selectable;
  if (delta == null || selectable == null) {
    return null;
  }
  if (forward) {
    if (extent.offset < delta.length) {
      // One past the boundary resolves (upstream) onto the next visual
      // line; its forward edge is that line's end.
      final nextLine = selectable.getLineBoundaryInPosition(
        Position(path: node.path, offset: extent.offset + 1),
      );
      return nextLine?.end;
    }
    final next = _nextTextNodeInDocumentOrder(node);
    if (next == null) {
      return null;
    }
    final firstLine = editorState
        .getNodeAtPath(next.path)
        ?.selectable
        ?.getLineBoundaryInPosition(Position(path: next.path));
    return firstLine?.end ?? Position(path: next.path);
  } else {
    if (extent.offset > 0) {
      final previousLine = selectable.getLineBoundaryInPosition(
        Position(path: node.path, offset: extent.offset - 1),
      );
      return previousLine?.start;
    }
    final previous = node.previousNodeWhere((n) => n.delta != null);
    if (previous == null) {
      return null;
    }
    final lastLine = editorState
        .getNodeAtPath(previous.path)
        ?.selectable
        ?.getLineBoundaryInPosition(
          Position(path: previous.path, offset: previous.delta!.length),
        );
    return lastLine?.start ??
        Position(path: previous.path, offset: previous.delta!.length);
  }
}

/// In an RTL block the visual LEFT edge of a line is its logical END; in
/// LTR it is the logical START. [line] is the visual line's span in
/// logical order (start <= end).
@visibleForTesting
Position visualLineEdgeTarget({
  required Selection line,
  required bool towardLeft,
  required bool isRtl,
}) =>
    (towardLeft != isRtl) ? line.start : line.end;

KeyEventResult _extendByParagraph(
  EditorState editorState, {
  required bool up,
}) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  final extent = selection.end;
  final node = editorState.getNodeAtPath(extent.path);
  if (node == null) {
    return KeyEventResult.ignored;
  }
  final target = _paragraphTarget(node, extent, up: up);

  if (target != null && target != extent) {
    editorState.updateSelectionWithReason(
      selection.copyWith(end: target),
      reason: SelectionUpdateReason.uiEvent,
    );
  }
  return KeyEventResult.handled;
}

/// Word-style, repeatable: at this paragraph's start/end already, the target
/// is the neighboring paragraph's start/end; otherwise this paragraph's own.
/// "Paragraph" here is any text block (delta != null), found in document
/// order at any nesting depth. Shared by the select-by-paragraph and
/// move-by-paragraph (Option+Up/Down) commands above.
Position? _paragraphTarget(Node node, Position extent, {required bool up}) {
  final delta = node.delta;
  if (up) {
    if (delta != null && extent.offset > 0) {
      return Position(path: node.path);
    }
    final previous = node.previousNodeWhere((n) => n.delta != null);
    return previous != null ? Position(path: previous.path) : null;
  } else {
    if (delta != null && extent.offset < delta.length) {
      return Position(path: node.path, offset: delta.length);
    }
    final next = _nextTextNodeInDocumentOrder(node);
    return next != null
        ? Position(path: next.path, offset: next.delta!.length)
        : null;
  }
}

/// The next text block after [node] in document order (first child, then
/// next sibling, then climbing to ancestors' next siblings) — the forward
/// counterpart of the editor's `previousNodeWhere`, which has no `next`
/// equivalent.
Node? _nextTextNodeInDocumentOrder(Node node) {
  Node? candidate = _nextInDocumentOrder(node);
  while (candidate != null && candidate.delta == null) {
    candidate = _nextInDocumentOrder(candidate);
  }
  return candidate;
}

Node? _nextInDocumentOrder(Node node) {
  if (node.children.isNotEmpty) {
    return node.children.first;
  }
  Node? current = node;
  while (current != null) {
    if (current.next != null) {
      return current.next;
    }
    current = current.parent;
  }
  return null;
}
