// [fork:page-surface] WCAG contrast helpers.
//
// Used to keep link text legible on whatever background a page is showing.
// A page can now be light or dark independently of the app theme
// (page_theme_mode.dart), and the default link colour — a bright cyan — has
// only ~2.2:1 contrast on a white sheet, well under the WCAG AA 4.5:1
// threshold for body text. [ensureContrast] nudges such a colour along its
// own lightness until it is legible, keeping its hue.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.x contrast ratio between [a] and [b], in the range [1, 21].
///
/// Uses Flutter's [Color.computeLuminance], which is the WCAG relative
/// luminance (sRGB-linearised). Alpha is ignored — callers pass opaque
/// foreground/background colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Returns [foreground] adjusted so it meets [minRatio] against [background],
/// keeping its hue and saturation.
///
/// Darkens on a light background and lightens on a dark one. If it already
/// passes, returns it unchanged. If no lightness in [0, 1] can reach the
/// target (a very light background paired with an unavoidably light hue, say),
/// returns the highest-contrast candidate found rather than failing — some
/// improvement beats none.
Color ensureContrast(
  Color foreground,
  Color background, {
  double minRatio = 4.5,
}) {
  if (contrastRatio(foreground, background) >= minRatio) {
    return foreground;
  }

  // 0.18 ~ the luminance of mid-grey: brighter backgrounds want a darker
  // foreground, darker ones a lighter foreground.
  final backgroundIsLight = background.computeLuminance() > 0.18;
  final hsl = HSLColor.fromColor(foreground);

  Color best = foreground;
  double bestRatio = contrastRatio(foreground, background);
  const step = 0.02;
  for (var i = 1; i <= 50; i++) {
    final lightness = hsl.lightness + (backgroundIsLight ? -step : step) * i;
    if (lightness < 0 || lightness > 1) {
      break;
    }
    final candidate = hsl.withLightness(lightness).toColor();
    final ratio = contrastRatio(candidate, background);
    if (ratio > bestRatio) {
      bestRatio = ratio;
      best = candidate;
    }
    if (ratio >= minRatio) {
      return candidate;
    }
  }
  return best;
}
