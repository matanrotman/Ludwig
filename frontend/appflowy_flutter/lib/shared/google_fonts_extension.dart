import 'package:appflowy/env/ludwig_bundled_fonts.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _defaultFontFamilies = [
  defaultFontFamily,
  builtInCodeFontFamily,
];

/// Ludwig: the 111 bundled families are registered in `pubspec.yaml` as ordinary
/// Flutter families, so they resolve through a plain [TextStyle] and never touch
/// `google_fonts` — which is the point, since runtime fetching is off and 46 of
/// them are variable fonts that `google_fonts` cannot match by filename anyway.
/// See `specs/fonts.md`.
final Set<String> _bundledFamilies = LudwigBundledFonts.families.toSet();

// if the font family is not available, google fonts packages will throw an exception
// this method will return the system font family if the font family is not available
TextStyle getGoogleFontSafely(
  String fontFamily, {
  FontWeight? fontWeight,
  double? fontSize,
  Color? fontColor,
  double? letterSpacing,
  double? lineHeight,
}) {
  // if the font family is the built-in font family, we can use it directly
  if (_defaultFontFamilies.contains(fontFamily) ||
      _bundledFamilies.contains(fontFamily)) {
    return TextStyle(
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: fontColor,
      letterSpacing: letterSpacing,
      height: lineHeight,
    );
  } else {
    try {
      return GoogleFonts.getFont(
        fontFamily,
        fontWeight: fontWeight,
        fontSize: fontSize,
        color: fontColor,
        letterSpacing: letterSpacing,
        height: lineHeight,
      );
    } catch (_) {}
  }

  return TextStyle(
    fontWeight: fontWeight,
    fontSize: fontSize,
    color: fontColor,
    letterSpacing: letterSpacing,
    height: lineHeight,
  );
}
