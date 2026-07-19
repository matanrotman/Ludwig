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

/// Default binding only. Word uses Ctrl+F1; because this goes through the
/// rebindable system, that is a starting point rather than a commitment.
final CommandShortcutEvent toggleRibbonCommand = CommandShortcutEvent(
  key: kToggleRibbonCommandId,
  command: 'ctrl+f1',
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
