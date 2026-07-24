// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 4).
//
// Keyboard shortcuts for superscript / subscript:
//   Cmd+Shift+=  toggles superscript  (`=`/`+` reads as "up")
//   Cmd+Shift+-  toggles subscript    (`-` reads as "down")
//
// Word's Mac subscript is Cmd+= (no Shift), but that collides with zoom in many
// apps, so this uses the symmetric ⌘⇧= / ⌘⇧− pair instead. Both `equal` and
// `minus` are in the fork's `keyToPhysicalCodeMapping`, so — like the font-size
// shortcut — these fire from the same physical key positions under a Hebrew (or
// any non-Latin) keyboard, and a user rebinding keeps that location-stickiness.
//
// The two marks are MUTUALLY EXCLUSIVE: enabling one clears the other. That is
// enforced in the fork's `toggleExclusiveAttribute` (text_commands.dart), which
// mirrors the built-in `toggleAttribute`'s collapsed/expanded handling so a
// pending toggle on a bare caret works exactly like Bold. The two ribbon toggle
// buttons call the same helper via [toggleTextScript].

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

/// Registered in `command_shortcuts.dart` alongside the other editor shortcuts,
/// so both show up in Settings → Shortcuts and are rebindable.
final List<CommandShortcutEvent> textScriptCommands = [
  superscriptCommand,
  subscriptCommand,
];

final CommandShortcutEvent superscriptCommand = CommandShortcutEvent(
  key: 'toggle superscript',
  getDescription: () => 'Superscript',
  command: 'meta+shift+equal',
  handler: (editorState) => _toggle(
    editorState,
    AppFlowyRichTextKeys.superscript,
    AppFlowyRichTextKeys.subscript,
  ),
);

final CommandShortcutEvent subscriptCommand = CommandShortcutEvent(
  key: 'toggle subscript',
  getDescription: () => 'Subscript',
  command: 'meta+shift+minus',
  handler: (editorState) => _toggle(
    editorState,
    AppFlowyRichTextKeys.subscript,
    AppFlowyRichTextKeys.superscript,
  ),
);

/// Shared entry point for both the shortcuts and the ribbon buttons: toggle
/// [key], clearing [opposite] whenever [key] turns on.
Future<void> toggleTextScript(
  EditorState editorState,
  String key,
  String opposite,
) {
  return editorState.toggleExclusiveAttribute(key, opposite);
}

KeyEventResult _toggle(EditorState editorState, String key, String opposite) {
  if (editorState.selection == null) {
    return KeyEventResult.ignored;
  }
  unawaited(toggleTextScript(editorState, key, opposite));
  return KeyEventResult.handled;
}
