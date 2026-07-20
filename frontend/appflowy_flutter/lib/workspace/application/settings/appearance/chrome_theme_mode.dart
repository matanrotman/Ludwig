// [fork:page-surface] Sidecar module — chrome/page theme split
// (requested 2026-07-20: "dark/light mode should only affect page and
// desk, not the entire layout").
//
// The Appearance dark/light/system control drives the PAGES (the desk and
// the sheet the user writes on). This setting drives the app frame —
// sidebar, ribbon, top bar, dialogs — independently.
//
// The DEFAULT is [system]: the app frame follows the OS appearance, so the
// in-app light/dark toggle recolors ONLY the page — which is the whole
// point of the feature. On this user's Mac (Dark) that keeps the frame
// dark, so nothing about their current look changes; it just stops the
// page toggle from dragging the frame along with it. [followPages] (the
// old unified behavior, where the frame tracks the page toggle) is kept as
// an explicit option for anyone who wants the whole app to move together.

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/material.dart';

/// The default when no preference is stored — the app frame follows the OS,
/// so the in-app light/dark toggle affects only the page.
const kDefaultChromeThemeMode = ChromeThemeMode.system;

enum ChromeThemeMode {
  /// The app frame tracks the pages' in-app dark/light toggle — the old
  /// unified behavior. An explicit opt-in, no longer the default.
  followPages,
  light,
  dark,

  /// Follow the device's OS appearance. The default.
  system;

  static ChromeThemeMode fromKey(String? key) => switch (key) {
        'followPages' => ChromeThemeMode.followPages,
        'light' => ChromeThemeMode.light,
        'dark' => ChromeThemeMode.dark,
        'system' => ChromeThemeMode.system,
        _ => kDefaultChromeThemeMode,
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
