// [fork:ribbon] Phase 5 — per-page background colour and per-page margin (text
// column width) storage. See specs/ribbon-menu.md → "Phase 5 scoping".
//
// These assert the View.extra storage format and the preset values. The RENDERED
// colour and column width are verified on the real macOS target (a headless test
// can't show theming or real geometry), so they are out of scope here — as with
// the per-page theme and direction tests.

import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/page_color.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ribbon/page_margin.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
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
  group('page colour storage', () {
    test('an unset page has no colour (inherits the theme surface)', () {
      expect(_view().pageColorId, isNull);
      expect(_view(extra: '').pageColorId, isNull);
      expect(_view(extra: '{}').pageColorId, isNull);
    });

    test('a tint id round-trips through the extra key', () {
      final extra = jsonEncode({kPageColorExtKey: 'appflowy_them_color_tint3'});
      expect(_view(extra: extra).pageColorId, 'appflowy_them_color_tint3');
    });

    test('a custom hex round-trips through the extra key', () {
      final extra = jsonEncode({kPageColorExtKey: '0xFFAABBCC'});
      expect(_view(extra: extra).pageColorId, '0xFFAABBCC');
    });

    test('an empty stored value reads back as unset', () {
      final extra = jsonEncode({kPageColorExtKey: ''});
      expect(_view(extra: extra).pageColorId, isNull);
    });

    test('other keys in extra are preserved alongside the colour key', () {
      expect(
        _view(extra: '{"font":"Arial","$kPageColorExtKey":"0xFF001122"}')
            .pageColorId,
        '0xFF001122',
      );
    });

    test('malformed extra falls back to null rather than throwing', () {
      expect(_view(extra: 'not json').pageColorId, isNull);
      expect(_view(extra: '[1,2,3]').pageColorId, isNull);
      expect(_view(extra: '{"$kPageColorExtKey":42}').pageColorId, isNull);
    });

    test('non-document layouts always inherit', () {
      final extra = jsonEncode({kPageColorExtKey: 'appflowy_them_color_tint1'});
      expect(_view(extra: extra, layout: ViewLayoutPB.Grid).pageColorId, isNull);
    });
  });

  group('page colour resolution', () {
    testWidgets('null / empty resolve to null (inherit)', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      );
      expect(resolvePageSheetColor(null, ctx), isNull);
      expect(resolvePageSheetColor('', ctx), isNull);
    });

    testWidgets('a custom hex resolves to that exact colour', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      );
      // The hex path does not touch the theme, so it is safe here; the tint path
      // needs the AppFlowy theme extension and is verified live.
      expect(resolvePageSheetColor('0xFFAABBCC', ctx), const Color(0xFFAABBCC));
    });
  });

  group('page margin storage', () {
    test('an unset page has no override (inherits the global width)', () {
      expect(_view().pageMarginWidth, isNull);
      expect(_view(extra: '').pageMarginWidth, isNull);
      expect(_view(extra: '{}').pageMarginWidth, isNull);
    });

    test('a stored width round-trips through the extra key', () {
      final extra = jsonEncode({kPageMarginExtKey: 600.0});
      expect(_view(extra: extra).pageMarginWidth, 600.0);
    });

    test('an int width (JSON round-trip) reads as a double', () {
      final extra = jsonEncode({kPageMarginExtKey: 960});
      expect(_view(extra: extra).pageMarginWidth, 960.0);
    });

    test('malformed extra falls back to null rather than throwing', () {
      expect(_view(extra: 'not json').pageMarginWidth, isNull);
      expect(_view(extra: '{"$kPageMarginExtKey":"wide"}').pageMarginWidth,
          isNull);
    });

    test('non-document layouts always inherit', () {
      final extra = jsonEncode({kPageMarginExtKey: 600.0});
      expect(
        _view(extra: extra, layout: ViewLayoutPB.Grid).pageMarginWidth,
        isNull,
      );
    });
  });

  group('margin presets', () {
    test('Full width equals the app default column width', () {
      // So the "Full width" preset reproduces today's no-margins look.
      expect(
        MarginWidthPreset.full.width,
        EditorStyleCustomizer.maxDocumentWidth,
      );
    });

    test('presets get progressively wider', () {
      final widths = MarginWidthPreset.values.map((p) => p.width).toList();
      expect(widths, orderedEquals([...widths]..sort()));
    });

    test('every preset width is within the global slider range', () {
      for (final preset in MarginWidthPreset.values) {
        expect(
          preset.width,
          inInclusiveRange(
            EditorStyleCustomizer.minDocumentWidth,
            EditorStyleCustomizer.maxDocumentWidth,
          ),
        );
      }
    });
  });
}
