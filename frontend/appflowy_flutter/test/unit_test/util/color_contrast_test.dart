// [fork:page-surface] Verifies link/text legibility with real WCAG contrast
// numbers — the "measure clearness" the split-theme fix asked for.
//
// The default theme's colours (default_colorscheme.dart):
//   light page: sheet #FFFFFF, text #333333, link (primary) #00BCF0
//   dark  page: sheet #1A202C, text #BBC3CD, link (primary) #00BCF0
// Text is fine on both; the raw cyan link is only ~2.2:1 on white — below
// the WCAG AA body-text threshold (4.5:1). ensureContrast must fix that
// without touching the already-legible dark-page link.

import 'package:appflowy/util/color_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _lightSheet = Color(0xFFFFFFFF);
const _lightText = Color(0xFF333333);
const _darkSheet = Color(0xFF1A202C);
const _darkText = Color(0xFFBBC3CD);
const _linkPrimary = Color(0xFF00BCF0);

const _aa = 4.5;

void main() {
  group('contrastRatio', () {
    test('black on white is the maximum 21:1', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.1),
      );
    });

    test('a colour against itself is 1:1', () {
      expect(contrastRatio(_linkPrimary, _linkPrimary), closeTo(1.0, 0.001));
    });

    test('is symmetric', () {
      expect(
        contrastRatio(_lightText, _lightSheet),
        closeTo(contrastRatio(_lightSheet, _lightText), 0.001),
      );
    });
  });

  group('default body text is already legible (documents the good defaults)',
      () {
    test('light page text clears AA', () {
      expect(contrastRatio(_lightText, _lightSheet), greaterThanOrEqualTo(_aa));
    });
    test('dark page text clears AA', () {
      expect(contrastRatio(_darkText, _darkSheet), greaterThanOrEqualTo(_aa));
    });
  });

  group('ensureContrast fixes links', () {
    test('the raw cyan link fails AA on a white sheet', () {
      expect(contrastRatio(_linkPrimary, _lightSheet), lessThan(_aa));
    });

    test('on a white sheet it is darkened until it clears AA', () {
      final fixed = ensureContrast(_linkPrimary, _lightSheet);
      expect(contrastRatio(fixed, _lightSheet), greaterThanOrEqualTo(_aa));
      // Darkened, not lightened, on a light background.
      expect(
        fixed.computeLuminance(),
        lessThan(_linkPrimary.computeLuminance()),
      );
      // Still recognisably the same hue (a blue), not recoloured.
      expect(
        HSLColor.fromColor(fixed).hue,
        closeTo(HSLColor.fromColor(_linkPrimary).hue, 8.0),
      );
    });

    test('on a dark sheet the link already passes and is left untouched', () {
      expect(
        contrastRatio(_linkPrimary, _darkSheet),
        greaterThanOrEqualTo(_aa),
      );
      expect(ensureContrast(_linkPrimary, _darkSheet), _linkPrimary);
    });

    test('an already-legible foreground is returned unchanged', () {
      expect(ensureContrast(_lightText, _lightSheet), _lightText);
    });

    test('lightens (not darkens) a too-dark foreground on a dark background',
        () {
      const tooDark = Color(0xFF222244);
      final fixed = ensureContrast(tooDark, _darkSheet);
      expect(contrastRatio(fixed, _darkSheet), greaterThanOrEqualTo(_aa));
      expect(fixed.computeLuminance(), greaterThan(tooDark.computeLuminance()));
    });
  });
}
