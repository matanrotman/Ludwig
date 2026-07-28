import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Press the backspace at the first position of first line to go to the title
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent backspaceToTitle = CommandShortcutEvent(
  key: 'backspace to title',
  command: 'backspace',
  getDescription: () => 'backspace to title',
  handler: (editorState) => _backspaceToTitle(
    editorState: editorState,
  ),
);

KeyEventResult _backspaceToTitle({
  required EditorState editorState,
}) {
  final coverTitleFocusNode = editorState.document.root.context
      ?.read<SharedEditorContext?>()
      ?.coverTitleFocusNode;
  if (coverTitleFocusNode == null) {
    return KeyEventResult.ignored;
  }

  // [fork:no-titles] Ludwig retired the in-document title (specs/no-titles.md),
  // so on most pages this focus node is never attached to a widget. Focusing an
  // unattached node after clearing the selection sends focus NOWHERE and the
  // document becomes uneditable until the page is reopened — reported
  // 2026-07-28 as "left arrow at the start of the sentence and I can't edit any
  // more". A FocusNode that was never attached has a null context, which is the
  // precise test for "there is nothing to move focus to".
  if (coverTitleFocusNode.context == null) {
    return KeyEventResult.ignored;
  }

  final selection = editorState.selection;
  // only active when the backspace is at the first position of first line
  if (selection == null ||
      !selection.isCollapsed ||
      !selection.start.path.equals([0]) ||
      selection.start.offset != 0) {
    return KeyEventResult.ignored;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null || node.type != ParagraphBlockKeys.type) {
    return KeyEventResult.ignored;
  }

  // delete the first line
  () async {
    // only delete the first line if it is empty
    if (node.delta == null || node.delta!.isEmpty) {
      final transaction = editorState.transaction;
      transaction.deleteNode(node);
      transaction.afterSelection = null;
      await editorState.apply(transaction);
    }

    editorState.selection = null;
    coverTitleFocusNode.requestFocus();
  }();

  return KeyEventResult.handled;
}

/// Press the arrow left at the first position of first line to go to the title
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent arrowLeftToTitle = CommandShortcutEvent(
  key: 'arrow left to title',
  command: 'arrow left',
  getDescription: () => 'arrow left to title',
  handler: (editorState) => _arrowKeyToTitle(
    editorState: editorState,
    checkSelection: (selection) {
      if (!selection.isCollapsed ||
          !selection.start.path.equals([0]) ||
          selection.start.offset != 0) {
        return false;
      }
      return true;
    },
  ),
);

/// Press the arrow up at the first line to go to the title
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent arrowUpToTitle = CommandShortcutEvent(
  key: 'arrow up to title',
  command: 'arrow up',
  getDescription: () => 'arrow up to title',
  handler: (editorState) => _arrowKeyToTitle(
    editorState: editorState,
    checkSelection: (selection) {
      if (!selection.isCollapsed || !selection.start.path.equals([0])) {
        return false;
      }
      // Only from the first VISUAL line of the first block. "First block"
      // alone is not enough: when it wraps, arrow-up from a lower visual
      // line must walk up through the block's own lines first, not jump
      // straight to the title (reported 2026-07-20). When the line span is
      // unavailable (unmounted render object), fall back to firing, which
      // is the pre-fix behavior and only affects the wrapped case.
      final line = editorState
          .getNodeAtPath([0])
          ?.selectable
          ?.getLineBoundaryInPosition(selection.end);
      if (line != null && line.start.offset > 0) {
        return false;
      }
      return true;
    },
  ),
);

KeyEventResult _arrowKeyToTitle({
  required EditorState editorState,
  required bool Function(Selection selection) checkSelection,
}) {
  final coverTitleFocusNode = editorState.document.root.context
      ?.read<SharedEditorContext?>()
      ?.coverTitleFocusNode;
  if (coverTitleFocusNode == null) {
    return KeyEventResult.ignored;
  }

  // [fork:no-titles] Ludwig retired the in-document title (specs/no-titles.md),
  // so on most pages this focus node is never attached to a widget. Focusing an
  // unattached node after clearing the selection sends focus NOWHERE and the
  // document becomes uneditable until the page is reopened — reported
  // 2026-07-28 as "left arrow at the start of the sentence and I can't edit any
  // more". A FocusNode that was never attached has a null context, which is the
  // precise test for "there is nothing to move focus to".
  if (coverTitleFocusNode.context == null) {
    return KeyEventResult.ignored;
  }

  final selection = editorState.selection;
  // only active when the arrow up is at the first line
  if (selection == null || !checkSelection(selection)) {
    return KeyEventResult.ignored;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null) {
    return KeyEventResult.ignored;
  }

  editorState.selection = null;
  coverTitleFocusNode.requestFocus();

  return KeyEventResult.handled;
}
