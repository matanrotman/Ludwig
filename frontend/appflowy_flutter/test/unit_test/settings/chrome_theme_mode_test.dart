// [fork:page-surface] Tests for the chrome/page theme split model —
// chrome_theme_mode.dart. The widget half (PageThemeScope) is thin
// glue over these two functions plus a brightness comparison, and was
// verified live on the real macOS target (dark chrome around a light
// page and every other combination of the two settings).

import 'package:appflowy/workspace/application/settings/appearance/chrome_theme_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveChromeThemeMode:', () {
    test('followPages mirrors the pages\' mode — the pre-split default', () {
      for (final pages in ThemeMode.values) {
        expect(
          resolveChromeThemeMode(ChromeThemeMode.followPages, pages),
          pages,
        );
      }
    });

    test('an explicit choice wins regardless of the pages\' mode', () {
      for (final pages in ThemeMode.values) {
        expect(
          resolveChromeThemeMode(ChromeThemeMode.light, pages),
          ThemeMode.light,
        );
        expect(
          resolveChromeThemeMode(ChromeThemeMode.dark, pages),
          ThemeMode.dark,
        );
        expect(
          resolveChromeThemeMode(ChromeThemeMode.system, pages),
          ThemeMode.system,
        );
      }
    });
  });

  group('resolvePageBrightness:', () {
    test('explicit page modes ignore the device', () {
      for (final platform in Brightness.values) {
        expect(
          resolvePageBrightness(ThemeMode.light, platform),
          Brightness.light,
        );
        expect(
          resolvePageBrightness(ThemeMode.dark, platform),
          Brightness.dark,
        );
      }
    });

    test('system follows the device', () {
      expect(
        resolvePageBrightness(ThemeMode.system, Brightness.light),
        Brightness.light,
      );
      expect(
        resolvePageBrightness(ThemeMode.system, Brightness.dark),
        Brightness.dark,
      );
    });
  });

  group('ChromeThemeMode keys:', () {
    test('round-trips through persistence keys', () {
      for (final mode in ChromeThemeMode.values) {
        expect(ChromeThemeMode.fromKey(mode.toKey()), mode);
      }
    });

    test('unknown or missing keys fall back to followPages', () {
      expect(ChromeThemeMode.fromKey(null), ChromeThemeMode.followPages);
      expect(ChromeThemeMode.fromKey('bogus'), ChromeThemeMode.followPages);
    });
  });
}
