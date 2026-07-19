// [fork:ribbon] Tests for the ribbon's own logic — see specs/ribbon-menu.md.
//
// Deliberately pure-logic tests. Anything visual or geometric (RTL mirroring,
// strip layout) is NOT tested here: per CLAUDE.md, headless `flutter test`
// forces a fixed-width fake font that collapses text geometry, so a green
// headless test proves nothing about how the ribbon actually renders. Those
// aspects are verified on the real macOS target instead.

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/application/ribbon_settings_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/ribbon_action.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/ribbon_shortcuts.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for SharedPreferences.
class _FakeKV implements KeyValueStorage {
  final Map<String, String> values = {};

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

void main() {
  group('shortcut formatting', () {
    test('picks the platform-appropriate alternative and prettifies it', () {
      // Tests run on macOS here, so the meta variant should win over ctrl.
      final label = formatCommand('ctrl+b,meta+b');
      expect(label, '⌘ B');
    });

    test('single-letter keys are capitalised', () {
      expect(formatCommand('meta+k'), '⌘ K');
    });

    test('a cleared command yields null rather than an empty tooltip', () {
      // A binding can genuinely be cleared in Settings → Shortcuts; the tooltip
      // must then show the name alone, not a dangling separator.
      expect(formatCommand(''), isNull);
    });

    test('unknown command ids resolve to null instead of throwing', () {
      expect(resolveShortcutLabel('no such command', shortcuts: []), isNull);
    });

    test('resolves against the live list, so a rebind is reflected', () {
      final event = CommandShortcutEvent(
        key: 'test command',
        command: 'meta+b',
        getDescription: () => 'test',
        handler: (_) => KeyEventResult.ignored,
      );
      expect(resolveShortcutLabel('test command', shortcuts: [event]), '⌘ B');

      // Simulate the user rebinding it — the same mutation path
      // SettingsShortcutService uses.
      event.updateCommand(command: 'meta+j');
      expect(resolveShortcutLabel('test command', shortcuts: [event]), '⌘ J');
    });
  });

  group('RibbonAction state', () {
    RibbonAction comingSoonAction() =>
        const RibbonAction(id: 'x', label: 'X', comingSoon: true);

    test('a coming-soon action reports itself as such', () {
      final editorState = EditorState.blank();
      expect(
        comingSoonAction().disabledReason(editorState),
        RibbonDisabledReason.comingSoon,
      );
    });

    test('an action with no cursor at all is disabled', () {
      final editorState = EditorState.blank();
      editorState.selection = null;

      final action = RibbonAction(
        id: 'bold',
        label: 'Bold',
        onPressed: (_, __) {},
      );
      expect(
        action.disabledReason(editorState),
        RibbonDisabledReason.noTarget,
      );
    });

    test('a COLLAPSED cursor still enables the action', () {
      // This is the correction that shaped Phase 1: a collapsed cursor is not
      // "no selection". Inline marks set a pending style from here, so the
      // button must stay live — otherwise the ribbon is blank exactly when it
      // is meant to be useful.
      final editorState = EditorState.blank();
      editorState.selection = Selection.collapsed(Position(path: [0]));

      final action = RibbonAction(
        id: 'bold',
        label: 'Bold',
        onPressed: (_, __) {},
      );
      expect(action.disabledReason(editorState), isNull);
    });
  });

  group('RibbonSettingsCubit', () {
    test('defaults are sane when nothing has been persisted', () async {
      final cubit = RibbonSettingsCubit(storage: _FakeKV());
      await cubit.load();

      expect(cubit.state.isCollapsed, isFalse);
      expect(cubit.state.activeTabId, RibbonSettingsState.defaultTabId);
      // The ribbon replaces the floating toolbar by default.
      expect(cubit.state.showFloatingToolbar, isFalse);
      expect(cubit.state.isLoaded, isTrue);
    });

    test('collapse state round-trips through storage', () async {
      final storage = _FakeKV();
      final cubit = RibbonSettingsCubit(storage: storage);
      await cubit.load();

      await cubit.toggleCollapsed();
      expect(cubit.state.isCollapsed, isTrue);
      expect(storage.values[KVKeys.ribbonCollapsed], 'true');

      // A fresh cubit — i.e. an app restart — must see the same state.
      final reopened = RibbonSettingsCubit(storage: storage);
      await reopened.load();
      expect(reopened.state.isCollapsed, isTrue);
    });

    test('active tab survives a restart', () async {
      final storage = _FakeKV();
      final cubit = RibbonSettingsCubit(storage: storage);
      await cubit.load();

      await cubit.setActiveTab('elements');

      final reopened = RibbonSettingsCubit(storage: storage);
      await reopened.load();
      expect(reopened.state.activeTabId, 'elements');
    });

    test('a malformed stored value falls back instead of throwing', () async {
      final storage = _FakeKV();
      storage.values[KVKeys.ribbonCollapsed] = 'not a bool';
      storage.values[KVKeys.ribbonActiveTab] = '';

      final cubit = RibbonSettingsCubit(storage: storage);
      await cubit.load();

      expect(cubit.state.isCollapsed, isFalse);
      expect(cubit.state.activeTabId, RibbonSettingsState.defaultTabId);
    });

    test('the floating-toolbar toggle round-trips', () async {
      final storage = _FakeKV();
      final cubit = RibbonSettingsCubit(storage: storage);
      await cubit.load();

      await cubit.setShowFloatingToolbar(true);
      expect(storage.values[KVKeys.showFloatingToolbar], 'true');

      final reopened = RibbonSettingsCubit(storage: storage);
      await reopened.load();
      expect(reopened.state.showFloatingToolbar, isTrue);
    });
  });
}
