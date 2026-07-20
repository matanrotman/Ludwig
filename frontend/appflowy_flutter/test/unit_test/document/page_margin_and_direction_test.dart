// [fork:rtl] Covers the two pieces of Phase 2 that are pure logic:
// the page-direction storage format, and the margin arithmetic that has to stay
// in step with the block option gutter.
//
// The *rendered* geometry these produce cannot be trusted from a headless test
// (the fake font flattens text metrics), so this file deliberately asserts only
// the numbers going in. The rendered result is measured on the real macOS
// target — see specs/rtl-support.md.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/application/page_text_direction.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
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
  group('page text direction storage', () {
    test('an unset page inherits the app-wide default', () {
      expect(_view().pageTextDirection, PageTextDirection.inherit);
      expect(_view(extra: '').pageTextDirection, PageTextDirection.inherit);
      expect(
        _view(extra: '{}').pageTextDirection,
        PageTextDirection.inherit,
      );
    });

    test('reads each stored direction back', () {
      for (final direction in [
        PageTextDirection.ltr,
        PageTextDirection.rtl,
        PageTextDirection.auto,
      ]) {
        final extra =
            jsonEncode({kPageTextDirectionExtKey: direction.editorValue});
        expect(_view(extra: extra).pageTextDirection, direction);
      }
    });

    test('inherit is absence, not a stored value', () {
      // Storing the string "inherit" must never happen — the writer removes the
      // key instead. If it somehow appears, it still reads as inherit.
      expect(PageTextDirection.inherit.editorValue, isNull);
      expect(
        _view(extra: '{"$kPageTextDirectionExtKey":"inherit"}')
            .pageTextDirection,
        PageTextDirection.inherit,
      );
    });

    test('survives unrelated keys and malformed extra', () {
      expect(
        _view(extra: '{"font":"Arial","$kPageTextDirectionExtKey":"rtl"}')
            .pageTextDirection,
        PageTextDirection.rtl,
      );
      // Corrupt or unexpected shapes fall back rather than throwing — `extra`
      // is free-form JSON shared by several features.
      expect(
        _view(extra: 'not json').pageTextDirection,
        PageTextDirection.inherit,
      );
      expect(
        _view(extra: '[1,2,3]').pageTextDirection,
        PageTextDirection.inherit,
      );
      expect(
        _view(extra: '{"$kPageTextDirectionExtKey":42}').pageTextDirection,
        PageTextDirection.inherit,
      );
    });

    test('non-document layouts have no page direction', () {
      final grid = _view(
        extra: '{"$kPageTextDirectionExtKey":"rtl"}',
        layout: ViewLayoutPB.Grid,
      );
      expect(grid.pageTextDirection, PageTextDirection.inherit);
    });
  });

  group('document margins vs the block option gutter', () {
    // The regression this guards: the option menu is in-flow space on the
    // text's LEADING side, so the TRAILING padding has to reserve the same
    // amount by hand. Commit ffc069150 grew the gutter and left the
    // compensation behind, making every page 29px lopsided.
    test('both text edges land the same distance from the pane', () {
      final gutter = EditorStyleCustomizer.blockOptionGutterWidth;

      final ltr =
          EditorStyleCustomizer.documentPaddingFor(ui.TextDirection.ltr);
      // LTR: gutter sits on the left, so the left text edge is padding + gutter.
      expect(ltr.left + gutter, ltr.right);

      final rtl =
          EditorStyleCustomizer.documentPaddingFor(ui.TextDirection.rtl);
      // RTL: gutter sits on the right; the arithmetic mirrors exactly.
      expect(rtl.right + gutter, rtl.left);

      // ...and the two directions are true mirrors of each other.
      expect(ltr.left, rtl.right);
      expect(ltr.right, rtl.left);
    });

    test('the gutter is derived from its parts, not hardcoded', () {
      expect(
        EditorStyleCustomizer.blockOptionGutterWidth,
        EditorStyleCustomizer.optionMenuWidth +
            EditorStyleCustomizer.blockActionTrailingGap,
      );
    });

    test('header widgets get the gutter added on the text-leading side', () {
      // The title/icon are rendered outside the block wrapper, so they have to
      // add the gutter by hand or they sit 29px outside the text.
      final gutter = EditorStyleCustomizer.blockOptionGutterWidth;

      final ltr =
          EditorStyleCustomizer.documentPaddingFor(ui.TextDirection.ltr);
      final ltrInset = EditorStyleCustomizer.textAlignmentInsetFor(ltr);
      expect(ltrInset.left, gutter);
      expect(ltrInset.right, 0);
      // ...which lands the header exactly where the body text starts.
      expect(ltr.left + ltrInset.left, EditorStyleCustomizer.documentTextInset);

      final rtl =
          EditorStyleCustomizer.documentPaddingFor(ui.TextDirection.rtl);
      final rtlInset = EditorStyleCustomizer.textAlignmentInsetFor(rtl);
      expect(rtlInset.right, gutter);
      expect(rtlInset.left, 0);
      expect(
        rtl.right + rtlInset.right,
        EditorStyleCustomizer.documentTextInset,
      );
    });

    test('header direction follows the page, not the app layout', () {
      // The reported bug: setting a page to LTR while the app is laid out RTL
      // moved the body text but left the title right-aligned.
      ui.TextDirection resolve(String? pageDirection,
              {String text = 'Hello'}) =>
          EditorStyleCustomizer.headerTextDirection(
            defaultTextDirection: pageDirection,
            text: text,
            layoutDirection: ui.TextDirection.rtl, // app laid out RTL
          );

      expect(resolve('ltr'), ui.TextDirection.ltr);
      expect(resolve('rtl'), ui.TextDirection.rtl);

      // Unset falls back to the frame, which is the pre-Phase-2 behaviour.
      expect(resolve(null), ui.TextDirection.rtl);

      // 'auto' reads the title's own text...
      expect(resolve('auto', text: 'Hello'), ui.TextDirection.ltr);
      expect(resolve('auto', text: 'שלום'), ui.TextDirection.rtl);
      // ...and falls back to the frame only when nothing in the text is
      // directional at all.
      expect(resolve('auto', text: ''), ui.TextDirection.rtl);
      expect(resolve('auto', text: '—  ·'), ui.TextDirection.rtl);

      // Quirk, asserted so it is a decision rather than a surprise: the
      // editor's `determineTextDirection` counts ASCII DIGITS as LTR evidence
      // (they sit in its Latin-and-friends character class), even though
      // Unicode bidi treats them as weak. A title of "2026 סיכום" therefore
      // reads LTR. Left as-is deliberately — every block already resolves
      // `auto` this way, so matching it keeps the title consistent with the
      // body text underneath it. Changing it belongs in the editor fork.
      expect(resolve('auto', text: '123'), ui.TextDirection.ltr);
    });

    test('the leading margin is unchanged by the fix', () {
      // Only the trailing side widened. If this ever fails, text has moved
      // inward on the side it already sat on, which is a visible regression.
      expect(
        EditorStyleCustomizer.documentPaddingFor(ui.TextDirection.ltr).left,
        EditorStyleCustomizer.baseDocumentMargin,
      );
    });
  });
}
