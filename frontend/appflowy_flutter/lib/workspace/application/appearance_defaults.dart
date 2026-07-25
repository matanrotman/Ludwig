import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';

/// A class for the default appearance settings for the app
class DefaultAppearanceSettings {
  static const kDefaultFontFamily = defaultFontFamily;
  static const kDefaultThemeMode = ThemeMode.system;
  static const kDefaultThemeName = "Default";
  static const kDefaultTheme = BuiltInTheme.defaultTheme;

  static Color getDefaultCursorColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  /// [fork:ribbon] Strengthened 2026-07-25 — the user reported the selection
  /// highlight was "indistinguishable in dark or light mode".
  ///
  /// It was the theme accent at a flat 0.2 alpha in both themes. On the default
  /// theme that accent is `#00BCF0`, the same low-contrast cyan that already
  /// had to be darkened for link text (see `util/color_contrast.dart`); at 0.2
  /// over a white sheet it is barely a tint, and over a dark one it is little
  /// better.
  ///
  /// The colour is kept — this stays recognisably AppFlowy, and it follows a
  /// custom theme's accent as before — but the alpha is now roughly doubled and
  /// split by brightness. Dark needs more than light: a translucent wash loses
  /// more contrast against a dark backdrop than a light one, so matching the
  /// two numbers would leave dark mode looking weaker than light.
  ///
  /// Raised again the same day: the first pass (0.32 / 0.42) was still too
  /// faint in use, so this is roughly TRIPLE the original 0.2 rather than
  /// double, at the user's explicit request.
  ///
  /// Checked against text legibility rather than just picked: the highlight
  /// paints *behind* the text, so the numbers are capped where the text still
  /// clears WCAG AA against the blended result. With the default `#00BCF0`
  /// accent, body text lands near 13:1 on light and 5:1 on dark — both
  /// comfortably above the 4.5:1 floor. Dark takes slightly less than light
  /// because the accent is a *bright* cyan: over a dark backdrop it gets
  /// lighter as alpha rises, moving toward the light text rather than away
  /// from it, which is the opposite of how it behaves on white.
  static Color getDefaultSelectionColor(BuildContext context) {
    final theme = Theme.of(context);
    final alpha = theme.brightness == Brightness.dark ? 0.55 : 0.62;
    return theme.colorScheme.primary.withValues(alpha: alpha);
  }
}
