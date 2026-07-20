// [fork:page-surface] Sidecar module — chrome/page theme split
// (requested 2026-07-20: "dark/light mode should only affect page and
// desk, not the entire layout").
//
// The existing Appearance dark/light/system setting keeps driving the
// PAGES (the desk and the sheet the user writes on). This setting drives
// the app frame — sidebar, ribbon, top bar, dialogs — independently.
// The default, [followPages], reproduces the pre-split behavior exactly,
// so a user who never touches it sees no change.

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/material.dart';

enum ChromeThemeMode {
  /// The app frame follows the pages' dark/light mode — the pre-split
  /// behavior, and the default.
  followPages,
  light,
  dark,

  /// Follow the device's appearance.
  system;

  static ChromeThemeMode fromKey(String? key) => switch (key) {
        'light' => ChromeThemeMode.light,
        'dark' => ChromeThemeMode.dark,
        'system' => ChromeThemeMode.system,
        _ => ChromeThemeMode.followPages,
      };

  String toKey() => name;
}

/// The [ThemeMode] the app frame (MaterialApp) should run with, given the
/// pages' theme mode and this chrome setting.
ThemeMode resolveChromeThemeMode(
  ChromeThemeMode chrome,
  ThemeMode pagesThemeMode,
) {
  return switch (chrome) {
    ChromeThemeMode.followPages => pagesThemeMode,
    ChromeThemeMode.light => ThemeMode.light,
    ChromeThemeMode.dark => ThemeMode.dark,
    ChromeThemeMode.system => ThemeMode.system,
  };
}

/// The [Brightness] the PAGE area should render with — the pages' theme
/// mode resolved against the device brightness.
Brightness resolvePageBrightness(
  ThemeMode pagesThemeMode,
  Brightness platformBrightness,
) {
  return switch (pagesThemeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => platformBrightness,
  };
}

/// Local-only setting (like text scale factor and the sidebar dock side)
/// — a per-device UI preference, not synced via the backend.
Future<ChromeThemeMode> readChromeThemeMode() async {
  final key = await getIt<KeyValueStorage>().get(KVKeys.chromeThemeMode);
  return ChromeThemeMode.fromKey(key);
}

Future<void> saveChromeThemeMode(ChromeThemeMode mode) {
  return getIt<KeyValueStorage>().set(KVKeys.chromeThemeMode, mode.toKey());
}
