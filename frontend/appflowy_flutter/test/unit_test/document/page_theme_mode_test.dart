// [fork:page-surface] Covers the per-page light/dark override storage format
// (page_theme_mode.dart). Pure View.extra logic; the rendered brightness is
// verified on the real macOS target (see STATUS.md), since a headless test
// can't show theming.

import 'dart:convert';

import 'package:appflowy/plugins/document/application/page_theme_mode.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _view({String? extra, ViewLayoutPB layout = ViewLayoutPB.Document}) {
  final view = ViewPB()
    ..id = 'v1'
    ..layout = layout;
  if (extra != null) {
    view.extra = extra;
  }
  return view;
}

void main() {
  group('page theme mode storage', () {
    test('an unset page inherits the app-wide theme', () {
      expect(_view().pageThemeMode, PageThemeMode.inherit);
      expect(_view(extra: '').pageThemeMode, PageThemeMode.inherit);
      expect(_view(extra: '{}').pageThemeMode, PageThemeMode.inherit);
    });

    test('explicit light/dark round-trip through the extra key', () {
      for (final mode in [PageThemeMode.light, PageThemeMode.dark]) {
        final extra = jsonEncode({kPageThemeModeExtKey: mode.toStorage()});
        expect(_view(extra: extra).pageThemeMode, mode);
      }
    });

    test('inherit is the absence of the key, never a stored value', () {
      // A literal "inherit" string is not a valid stored value — inherit is
      // modelled as absence — so it reads back as inherit via the fallback.
      expect(
        _view(extra: '{"$kPageThemeModeExtKey":"inherit"}').pageThemeMode,
        PageThemeMode.inherit,
      );
    });

    test('other keys in extra are preserved alongside the theme key', () {
      expect(
        _view(extra: '{"font":"Arial","$kPageThemeModeExtKey":"dark"}')
            .pageThemeMode,
        PageThemeMode.dark,
      );
    });

    test('malformed extra falls back to inherit rather than throwing', () {
      expect(_view(extra: 'not json').pageThemeMode, PageThemeMode.inherit);
      expect(_view(extra: '[1,2,3]').pageThemeMode, PageThemeMode.inherit);
      expect(
        _view(extra: '{"$kPageThemeModeExtKey":42}').pageThemeMode,
        PageThemeMode.inherit,
      );
    });

    test('non-document layouts always inherit', () {
      final extra = jsonEncode({kPageThemeModeExtKey: 'dark'});
      expect(
        _view(extra: extra, layout: ViewLayoutPB.Grid).pageThemeMode,
        PageThemeMode.inherit,
      );
    });

    test('brightness maps as expected', () {
      expect(PageThemeMode.inherit.brightness, isNull);
      expect(PageThemeMode.light.brightness, Brightness.light);
      expect(PageThemeMode.dark.brightness, Brightness.dark);
    });
  });
}
