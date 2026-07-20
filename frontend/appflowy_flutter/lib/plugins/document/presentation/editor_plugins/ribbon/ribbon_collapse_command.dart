// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// The keyboard shortcut that collapses/expands the ribbon.
//
// Registered as a real CommandShortcutEvent rather than a hardcoded key handler
// so it shows up in Settings → Shortcuts and can be rebound — which is also what
// lets the chevron's tooltip show the user's current binding.

import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/application/ribbon_settings_cubit.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Stable id — also the lookup key for the tooltip and for persisted rebinds.
const String kToggleRibbonCommandId = 'toggle the ribbon menu';

/// Default binding only — rebindable in Settings → Shortcuts.
///
/// Word's Ctrl+F1 is kept for Windows/Linux, but on macOS it is unreachable
/// on a default Mac: with `com.apple.keyboard.fnState` unset, F1 sends
/// brightness-down and the app never sees the key — and Ctrl+F1 itself is a
/// macOS system shortcut (found live 2026-07-20). Cmd+Option+R (R = ribbon)
/// needs no F-row, collides with nothing in the app, the editor, or macOS
/// defaults, and sits in the same family as the existing Cmd+Option+E.
final CommandShortcutEvent toggleRibbonCommand = CommandShortcutEvent(
  key: kToggleRibbonCommandId,
  command: 'ctrl+f1',
  macOSCommand: 'cmd+alt+r',
  getDescription: () => 'Collapse or expand the ribbon menu',
  handler: _toggleRibbonHandler,
);

CommandShortcutEventHandler _toggleRibbonHandler = (editorState) {
  // Registered in deps_resolver as a lazy singleton. Guarded so a shortcut
  // press can never crash the editor if registration order ever changes.
  if (!getIt.isRegistered<RibbonSettingsCubit>()) {
    return KeyEventResult.ignored;
  }
  getIt<RibbonSettingsCubit>().toggleCollapsed();
  return KeyEventResult.handled;
};
