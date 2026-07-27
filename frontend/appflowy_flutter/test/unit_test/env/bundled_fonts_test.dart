import 'dart:io';

import 'package:appflowy/env/ludwig_bundled_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ludwig bundles its fonts and never fetches one. `specs/fonts.md`.
///
/// These guard the seam between three things that must agree, and that nothing
/// else checks: the family names in [LudwigBundledFonts], the `.ttf` files in
/// `assets/google_fonts_ludwig/`, and what `google_fonts` will accept. If they
/// drift, the picker offers a font that cannot load — and with runtime fetching
/// off, that is a dead entry rather than a slow one.
void main() {
  final assetDir = Directory('assets/google_fonts_ludwig');

  group('bundled fonts', () {
    test('the asset folder exists and holds the fonts', () {
      expect(
        assetDir.existsSync(),
        isTrue,
        reason: 'assets/google_fonts_ludwig/ is missing — fonts not bundled',
      );
      final ttf = assetDir
          .listSync()
          .where((f) => f.path.endsWith('.ttf'))
          .length;
      expect(ttf, greaterThan(150), reason: 'expected ~195 bundled font files');
    });

    test('the licence text ships with the fonts, as the OFL requires', () {
      final licence = File('${assetDir.path}/OFL-LICENSES.txt');
      expect(licence.existsSync(), isTrue);
      final text = licence.readAsStringSync();
      expect(text, contains('SIL OPEN FONT LICENSE'));
      // One block per family. If families are added without their licence, this
      // is what catches it.
      final blocks = '='.padRight(64, '=');
      final count = blocks.allMatches(text).length;
      expect(
        count ~/ 2,
        LudwigBundledFonts.families.length,
        reason: 'every bundled family needs its licence block',
      );
    });

    test('every listed family is declared in pubspec.yaml', () {
      // The families are ordinary Flutter families, NOT resolved through
      // google_fonts: 46 of the files are variable fonts (`Cairo[slnt,wght]`)
      // that google_fonts cannot match by filename, and several families are
      // absent from its catalogue. A family in the picker but not in pubspec is
      // a dead entry, and with runtime fetching off there is no fallback.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final undeclared = LudwigBundledFonts.families
          .where((f) => !pubspec.contains('- family: $f\n'))
          .toList();
      expect(undeclared, isEmpty, reason: 'in the picker but not in pubspec');
    });

    test('every listed family has at least one font file bundled', () {
      final present = assetDir
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.ttf'))
          .toList();

      // Files are either `Family-Variant.ttf` or the variable `Family[axes].ttf`,
      // with the family compacted: 'Aref Ruqaa Ink' -> 'ArefRuqaaInk'.
      final missing = <String>[];
      for (final family in LudwigBundledFonts.families) {
        final prefix = family.replaceAll(' ', '');
        final hit = present.any(
          (n) => n.startsWith('$prefix-') || n.startsWith('$prefix['),
        );
        if (!hit) missing.add(family);
      }
      expect(missing, isEmpty, reason: 'listed but no .ttf bundled');
    });

    test('covers a useful number of Hebrew/Arabic families', () {
      expect(LudwigBundledFonts.families.length, greaterThanOrEqualTo(100));
      // Rubik is the UI font and the one family known to cover Latin, Hebrew
      // and Arabic together — it must be among the bundled set.
      expect(LudwigBundledFonts.families, contains('Rubik'));
    });
  });
}
