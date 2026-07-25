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

/// ⚠️ ALIGNMENT SHORTCUTS: reverted to the original Ctrl+Shift+… bindings on
/// 2026-07-25 (same session they were changed) — the user did not approve the
/// move to Word's ⌘L/⌘E/⌘R/⌘J, and the change could not take effect anyway.
///
/// READ THIS BEFORE CHANGING ANY `command:` STRING IN THIS CODEBASE:
/// editing a default here does NOT change the binding for anyone who already
/// has a `shortcuts.json`. On startup `SettingsShortcutService
/// .updateCommandShortcuts` walks the saved file and calls `updateCommand` for
/// every entry whose `key` matches, so the SAVED value wins over the code
/// default, permanently and silently. Only commands absent from that file
/// (i.e. ones introduced after it was last written) actually pick up a code
/// default. That is why the ⌘L/⌘E/⌘R changes did nothing while brand-new
/// commands like superscript worked first time.
///
/// To genuinely change an existing binding: rebind it in Settings → Shortcuts,
/// or reset shortcuts to defaults there, or migrate the saved file.
///
/// Phase 4 — justify stores the `'justify'` align value, which the editor fork
/// maps to `TextAlign.justify` via `blockTextAlign` (align_mixin.dart).
/// Direction-agnostic, so it works in LTR and RTL.
final CommandShortcutEvent customTextJustifyCommand = CommandShortcutEvent(
  key: 'Justify text',
  command: 'ctrl+shift+j',
  getDescription: () => 'Justify text',
  handler: (editorState) => _textAlignHandler(editorState, 'justify'),
);

/// Windows / Linux : ctrl + shift + l
/// macOS           : ctrl + shift + l
/// Allows the user to align text to the left
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customTextLeftAlignCommand = CommandShortcutEvent(
  key: 'Align text to the left',
  command: 'ctrl+shift+l',
  getDescription: LocaleKeys.settings_shortcutsPage_commands_textAlignLeft.tr,
  handler: (editorState) => _textAlignHandler(editorState, leftAlignmentKey),
);

/// Windows / Linux : ctrl + shift + c
/// macOS           : ctrl + shift + c
/// Allows the user to align text to the center
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customTextCenterAlignCommand = CommandShortcutEvent(
  key: 'Align text to the center',
  command: 'ctrl+shift+c',
  getDescription: LocaleKeys.settings_shortcutsPage_commands_textAlignCenter.tr,
  handler: (editorState) => _textAlignHandler(editorState, centerAlignmentKey),
);

/// Windows / Linux : ctrl + shift + r
/// macOS           : ctrl + shift + r
/// Allows the user to align text to the right
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customTextRightAlignCommand = CommandShortcutEvent(
  key: 'Align text to the right',
  command: 'ctrl+shift+r',
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
