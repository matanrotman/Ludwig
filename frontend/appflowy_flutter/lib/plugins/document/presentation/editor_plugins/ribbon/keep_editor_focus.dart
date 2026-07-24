// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// Keeping the editor's selection alive while the user interacts with the ribbon.
//
// The problem (user report, 2026-07-23): "clicking on buttons deselects the
// selection and makes it impossible to apply some behaviors to text." The
// editor's keyboard service clears `editorState.selection` the moment its focus
// node loses focus (keyboard_service_widget.dart) — UNLESS something has raised
// `keepEditorFocusNotifier`. A ribbon control that steals focus (any popover
// does) therefore wipes the very selection the action was about to read, so by
// the time you pick "UPPERCASE" or "1.5 lines" there is nothing to act on.
//
// AppFlowy's own toolbar solves this the same way everywhere (colour menu, link
// menu, highlight popover): raise the notifier before the interaction, lower it
// after. This module is just the ribbon's shared wrappers for that.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/scheduler.dart';

/// Runs [action] with the editor's selection held across the call, then hands
/// focus back to the editor.
///
/// For a plain button tap: the increase guarantees the selection survives even
/// if the tap moves focus, and the post-frame decrease re-focuses the editor so
/// the user can keep typing. Leak-safe — every increase is paired with exactly
/// one decrease, even if [action] throws.
void runKeepingEditorFocus(void Function() action) {
  keepEditorFocusNotifier.increase();
  try {
    action();
  } finally {
    // Decrease after this frame, once any focus change from the tap has settled.
    // Lowering to zero makes the keyboard service re-request editor focus.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      keepEditorFocusNotifier.decrease();
    });
  }
}
