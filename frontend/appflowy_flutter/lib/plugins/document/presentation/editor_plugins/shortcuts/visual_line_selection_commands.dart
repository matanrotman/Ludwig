// [fork:rtl] Sidecar module — see specs/rtl-support.md
// "select-to-line and select-by-paragraph shortcuts" (decided 2026-07-20).
//
// Option+Shift+Left/Right extends the selection to the edge of the current
// VISUAL line — the soft-wrapped line as rendered, the way Word's Shift+Home/End
// behaves — and Option+Shift+Up/Down extends it by one whole paragraph per press.
// (Remapped 2026-07-24 r2 from Option+Ctrl+Shift+arrow at the user's request;
// the editor binds no `alt+shift+arrow` of its own, so there is no conflict.)
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
  command: 'alt+shift+arrow left',
  handler: (editorState) =>
      _extendToVisualLineEdge(editorState, towardLeft: true),
);

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
