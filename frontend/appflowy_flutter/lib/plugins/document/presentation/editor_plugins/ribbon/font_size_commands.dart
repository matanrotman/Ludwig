// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 5).
//
// Keyboard shortcuts for the font-size control: Cmd+Option+. enlarges the text
// and Cmd+Option+, shrinks it, by one step (matching the ▲▼ carets), applied to
// the selection — or as a pending size on a bare caret, exactly like the box.
// (The `.` and `,` keys are the unshifted `>` and `<`; the user asked for just
// Cmd+Option, no Shift.)
//
// Language-independent by design, two ways:
//
//  * The ACTION only changes font size, which is direction-agnostic, so it
//    behaves identically on Hebrew/Arabic (RTL) text as on English.
//
//  * The SHORTCUT matches by physical key LOCATION, not the character the layout
//    produces — see the fork's `keyToPhysicalCodeMapping` / `matchesKeyEvent`.
//    So Cmd+Option+`.` fires from the same key position whether the active
//    keyboard is English or Hebrew, and a user who rebinds it keeps that
//    location-stickiness for free. The command string uses key WORDS ('period',
//    'comma') so the ',' that would separate multi-bindings is unambiguous.

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

import 'font_size.dart';

/// Registered in `command_shortcuts.dart` alongside the other editor shortcuts,
/// so both show up in Settings → Shortcuts and are rebindable.
final List<CommandShortcutEvent> fontSizeCommands = [
  increaseFontSizeCommand,
  decreaseFontSizeCommand,
];

final CommandShortcutEvent increaseFontSizeCommand = CommandShortcutEvent(
  key: 'increase the font size',
  getDescription: () => 'Increase font size',
  command: 'meta+alt+period',
  handler: (editorState) => _stepFontSize(editorState, 1),
);

final CommandShortcutEvent decreaseFontSizeCommand = CommandShortcutEvent(
  key: 'decrease the font size',
  getDescription: () => 'Decrease font size',
  command: 'meta+alt+comma',
  handler: (editorState) => _stepFontSize(editorState, -1),
);

KeyEventResult _stepFontSize(EditorState editorState, double delta) {
  if (editorState.selection == null) {
    return KeyEventResult.ignored;
  }
  final base = currentFontSize(editorState, _editorDefaultFontSize(editorState)) ??
      _editorDefaultFontSize(editorState);
  unawaited(applyFontSize(editorState, base + delta));
  return KeyEventResult.handled;
}

/// The editor's own default body size, so a step from unstyled text starts from
/// what is actually on screen rather than a guess. Defensive: `editorStyle` is
/// `late`, so fall back to the shared default if it is not set (e.g. in a test).
double _editorDefaultFontSize(EditorState editorState) {
  try {
    return editorState.editorStyle.textStyleConfiguration.text.fontSize ??
        kDefaultBodyFontSize;
  } catch (_) {
    return kDefaultBodyFontSize;
  }
}
