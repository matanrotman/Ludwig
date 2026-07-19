// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// Resolves a ribbon action's keyboard shortcut for display in its tooltip.
//
// The point of this file is that the shortcut shown must be the one that is
// actually bound *right now*. AppFlowy's existing toolbar tooltips embed literal
// strings (`'⌘ + B'` in `custom_format_toolbar_items.dart`), so rebinding Bold in
// Settings → Shortcuts leaves the tooltip lying. Ribbon tooltips read the live
// `CommandShortcutEvent.command` instead.
//
// This works because `SettingsShortcutService.updateCommandShortcuts` mutates
// the `CommandShortcutEvent` objects in place, and those objects are shared
// references — so the customised binding is visible from the global list.

import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/command_shortcuts.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:universal_platform/universal_platform.dart';

/// Looks up the current binding for [commandId] and formats it for display.
///
/// Returns null when the command is unknown or has been deliberately cleared,
/// in which case the tooltip should show the name alone.
String? resolveShortcutLabel(
  String commandId, {
  List<CommandShortcutEvent>? shortcuts,
}) {
  // `commandShortcutEvents` — not `defaultCommandShortcutEvents`. The latter is
  // the pristine copy kept for "reset to default"; the former is the live list
  // whose events `SettingsShortcutService.updateCommandShortcuts` mutates in
  // place when the user rebinds something.
  final events = shortcuts ?? commandShortcutEvents;
  CommandShortcutEvent? event;
  for (final e in events) {
    if (e.key == commandId) {
      event = e;
      break;
    }
  }
  if (event == null) {
    return null;
  }
  return formatCommand(event.command);
}

/// Turns a raw command string such as `'ctrl+b,meta+b'` into something a person
/// can read, e.g. `⌘ B` on macOS or `Ctrl B` elsewhere.
///
/// A command may list several alternatives separated by ','; the one matching
/// this platform is preferred, otherwise the first is used.
String? formatCommand(String command) {
  if (command.isEmpty) {
    return null;
  }

  final alternatives = command
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (alternatives.isEmpty) {
    return null;
  }

  final isMacOS = UniversalPlatform.isMacOS;
  // On macOS prefer the 'meta'/'cmd' variant; elsewhere prefer 'ctrl'.
  final preferred = alternatives.firstWhere(
    (e) {
      final lower = e.toLowerCase();
      final usesMeta = lower.contains('meta') || lower.contains('cmd');
      return isMacOS ? usesMeta : !usesMeta;
    },
    orElse: () => alternatives.first,
  );

  return preferred
      .split('+')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map(_prettifyKey)
      .join(' ');
}

String _prettifyKey(String key) {
  final isMacOS = UniversalPlatform.isMacOS;
  switch (key.toLowerCase()) {
    case 'meta':
    case 'cmd':
    case 'win':
      return isMacOS ? '⌘' : 'Win';
    case 'ctrl':
      return isMacOS ? '⌃' : 'Ctrl';
    case 'alt':
      return isMacOS ? '⌥' : 'Alt';
    case 'shift':
      return isMacOS ? '⇧' : 'Shift';
    case 'arrow up':
      return '↑';
    case 'arrow down':
      return '↓';
    case 'arrow left':
      return '←';
    case 'arrow right':
      return '→';
    case 'escape':
      return 'Esc';
    case 'delete':
      return 'Del';
    default:
      // Single letters read better capitalised: 'b' -> 'B'.
      return key.length == 1 ? key.toUpperCase() : _titleCase(key);
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
