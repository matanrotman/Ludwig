import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

final List<CommandShortcutEvent> customTextAlignCommands = [
  customTextLeftAlignCommand,
  customTextCenterAlignCommand,
  customTextRightAlignCommand,
  // [fork:ribbon] specs/ribbon-menu.md (Phase 4)
  customTextJustifyCommand,
];

/// [fork:ribbon] specs/ribbon-menu.md — the four alignment shortcuts moved to
/// Word's bindings on 2026-07-25 (user's request): ⌘L / ⌘E / ⌘R / ⌘J on macOS,
/// Ctrl+… elsewhere, replacing the old Ctrl+Shift+L/C/R/J.
///
/// Collision check done before the move: ⌘L, ⌘R and ⌘J are unclaimed both
/// app-side (`hotkeys.dart` — note ⌘⇧L, *with* shift, is toggle-theme and is a
/// different chord) and in the editor fork's command set.
///
/// Like the other shortcuts in this fork these resolve by physical key
/// LOCATION as well as logical key, so they fire from the same keys under a
/// Hebrew layout — see the fork's keybinding change (`d15e3c3a`).
///
/// Phase 4 — justify stores the `'justify'` align value, which the editor fork
/// maps to `TextAlign.justify` via `blockTextAlign` (align_mixin.dart).
/// Direction-agnostic, so it works in LTR and RTL.
final CommandShortcutEvent customTextJustifyCommand = CommandShortcutEvent(
  key: 'Justify text',
  command: 'ctrl+j',
  macOSCommand: 'cmd+j',
  getDescription: () => 'Justify text',
  handler: (editorState) => _textAlignHandler(editorState, 'justify'),
);

/// Windows / Linux : ctrl + l
/// macOS           : cmd + l
/// Allows the user to align text to the left
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customTextLeftAlignCommand = CommandShortcutEvent(
  key: 'Align text to the left',
  command: 'ctrl+l',
  macOSCommand: 'cmd+l',
  getDescription: LocaleKeys.settings_shortcutsPage_commands_textAlignLeft.tr,
  handler: (editorState) => _textAlignHandler(editorState, leftAlignmentKey),
);

/// Windows / Linux : ctrl + e
/// macOS           : cmd + e
/// Allows the user to align text to the center
///
/// ⌘E used to be the editor's "toggle inline code"; that moved to ⌘⇧C so the
/// four alignment shortcuts could match Word (see the note above and the fork's
/// `markdown_commands.dart`).
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customTextCenterAlignCommand = CommandShortcutEvent(
  key: 'Align text to the center',
  command: 'ctrl+e',
  macOSCommand: 'cmd+e',
  getDescription: LocaleKeys.settings_shortcutsPage_commands_textAlignCenter.tr,
  handler: (editorState) => _textAlignHandler(editorState, centerAlignmentKey),
);

/// Windows / Linux : ctrl + r
/// macOS           : cmd + r
/// Allows the user to align text to the right
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customTextRightAlignCommand = CommandShortcutEvent(
  key: 'Align text to the right',
  command: 'ctrl+r',
  macOSCommand: 'cmd+r',
  getDescription: LocaleKeys.settings_shortcutsPage_commands_textAlignRight.tr,
  handler: (editorState) => _textAlignHandler(editorState, rightAlignmentKey),
);

/// [fork:ribbon] specs/ribbon-menu.md — align became a TOGGLE (2026-07-25).
///
/// Pressing an alignment that is already active clears it instead of re-writing
/// it, so the block falls back to its direction-derived default (right in RTL,
/// left in LTR) exactly as if it had never been aligned. Previously every press
/// wrote the value unconditionally, so there was no way back to "no alignment"
/// short of undo — the user hit this with justify.
///
/// The clear is expressed as `blockComponentAlign: null`, **not** by omitting
/// the key: `transaction.updateNode` MERGES the returned attributes into the
/// node's existing ones (`composeAttributes`), so an omitted key leaves the old
/// value in place. A null value is what `composeAttributes` strips.
///
/// Toggling off requires *every* node in the selection to already carry this
/// alignment. A mixed selection therefore aligns everything first (one press),
/// and only a second press clears it — which is the behaviour Word has and the
/// one that keeps a multi-paragraph selection predictable.
KeyEventResult _textAlignHandler(EditorState editorState, String align) {
  final Selection? selection = editorState.selection;

  if (selection == null) {
    return KeyEventResult.ignored;
  }

  final nodes = editorState.getNodesInSelection(selection);
  final bool alreadyAligned = nodes.isNotEmpty &&
      nodes.every((node) => node.attributes[blockComponentAlign] == align);

  editorState.updateNode(
    selection,
    (node) => node.copyWith(
      attributes: {
        ...node.attributes,
        blockComponentAlign: alreadyAligned ? null : align,
      },
    ),
  );

  return KeyEventResult.handled;
}
