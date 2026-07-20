// [fork:rtl] Sidecar module — see specs/rtl-support.md
// "select-to-line and select-by-paragraph shortcuts" (decided 2026-07-20).
//
// Option+Ctrl+Shift+Left/Right extends the selection to the edge of the
// current VISUAL line — the soft-wrapped line as rendered, the way Word's
// Shift+Home/End behaves — and Option+Ctrl+Shift+Up/Down extends it by one
// whole paragraph per press.
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

final List<CommandShortcutEvent> visualLineSelectionCommands = [
  selectToVisualLineLeftCommand,
  selectToVisualLineRightCommand,
  selectParagraphUpCommand,
  selectParagraphDownCommand,
];

final CommandShortcutEvent selectToVisualLineLeftCommand =
    CommandShortcutEvent(
  key: 'extend the selection to the left edge of the visual line',
  getDescription: () => 'Extend selection to the left edge of the line',
  command: 'alt+ctrl+shift+arrow left',
  handler: (editorState) =>
      _extendToVisualLineEdge(editorState, towardLeft: true),
);

final CommandShortcutEvent selectToVisualLineRightCommand =
    CommandShortcutEvent(
  key: 'extend the selection to the right edge of the visual line',
  getDescription: () => 'Extend selection to the right edge of the line',
  command: 'alt+ctrl+shift+arrow right',
  handler: (editorState) =>
      _extendToVisualLineEdge(editorState, towardLeft: false),
);

final CommandShortcutEvent selectParagraphUpCommand = CommandShortcutEvent(
  key: 'extend the selection up by one paragraph',
  getDescription: () => 'Extend selection up by one paragraph',
  command: 'alt+ctrl+shift+arrow up',
  handler: (editorState) => _extendByParagraph(editorState, up: true),
);

final CommandShortcutEvent selectParagraphDownCommand = CommandShortcutEvent(
  key: 'extend the selection down by one paragraph',
  getDescription: () => 'Extend selection down by one paragraph',
  command: 'alt+ctrl+shift+arrow down',
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
  final selectable = editorState.getNodeAtPath(extent.path)?.selectable;
  final line = selectable?.getLineBoundaryInPosition(extent);
  if (selectable == null || line == null) {
    return KeyEventResult.ignored;
  }
  final target = visualLineEdgeTarget(
    line: line,
    towardLeft: towardLeft,
    isRtl: selectable.textDirection() == TextDirection.rtl,
  );
  if (target.offset != extent.offset) {
    editorState.updateSelectionWithReason(
      selection.copyWith(end: target),
      reason: SelectionUpdateReason.uiEvent,
    );
  }
  return KeyEventResult.handled;
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

  // Word-style, repeatable: first press snaps the extent to this
  // paragraph's start/end; each further press takes in one more whole
  // paragraph. "Paragraph" here is any text block (delta != null), found
  // in document order at any nesting depth.
  Position? target;
  final delta = node.delta;
  if (up) {
    if (delta != null && extent.offset > 0) {
      target = Position(path: node.path);
    } else {
      final previous = node.previousNodeWhere((n) => n.delta != null);
      if (previous != null) {
        target = Position(path: previous.path);
      }
    }
  } else {
    if (delta != null && extent.offset < delta.length) {
      target = Position(path: node.path, offset: delta.length);
    } else {
      final next = _nextTextNodeInDocumentOrder(node);
      if (next != null) {
        target = Position(path: next.path, offset: next.delta!.length);
      }
    }
  }

  if (target != null && target != extent) {
    editorState.updateSelectionWithReason(
      selection.copyWith(end: target),
      reason: SelectionUpdateReason.uiEvent,
    );
  }
  return KeyEventResult.handled;
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
