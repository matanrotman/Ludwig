// [fork:page-surface] Sidecar module — applies a page's per-page light/dark
// override (page_theme_mode.dart) to the document subtree only.
//
// Wraps the document area (the desk and the page sheet, including the title
// and editor) — the same subtree PageSurface wraps — in the brightness the
// page is pinned to, when that differs from the app-wide theme the rest of
// the app (the layout) is showing. When the page is on [PageThemeMode.inherit]
// (the default) it is a no-op: the page just follows the app theme like
// everything else, so untouched pages are byte-identical to before.
//
// Known scope limits, deliberate:
// - Overlays that render in the app-level Overlay (floating toolbar, slash
//   menu, popovers) keep the app theme even when triggered from a page —
//   they are layout, consistent with the ribbon.
// - Database row documents (their own code path, see STATUS.md) are not
//   wrapped; same as their pending RTL work.

import 'package:appflowy/plugins/document/application/page_theme_mode.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PageThemeScope extends StatelessWidget {
  const PageThemeScope({
    super.key,
    required this.pageThemeMode,
    required this.child,
  });

  /// The current page's override; [PageThemeMode.inherit] means no override.
  final PageThemeMode pageThemeMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final override = pageThemeMode.brightness;
    final ambientBrightness = Theme.of(context).brightness;
    final targetBrightness = override ?? ambientBrightness;

    // CRITICAL: the widget structure is CONSTANT — always Theme > AppFlowyTheme
    // > child, whether or not a page override is active. Earlier this returned
    // `child` bare when there was no override and wrapped it in two extra
    // widgets when there was, so toggling a page's override changed the tree
    // SHAPE, which remounts the editor element and drops its keyboard focus
    // (reported "keyboard disabled" after using the per-page theme). Keeping the
    // shape fixed means toggling only changes the theme DATA, never remounts the
    // editor. When there's no effective override we simply re-provide the
    // ambient themes unchanged (a visual no-op).
    final ThemeData themeData;
    final AppFlowyThemeData afTheme;
    if (targetBrightness == ambientBrightness) {
      themeData = Theme.of(context);
      afTheme = AppFlowyTheme.of(context);
    } else {
      // Mirror the theme layers as app_widget.dart builds them, at the page's
      // brightness. Plain (non-animated) AppFlowyTheme — an implicitly-animated
      // one would rebuild the editor subtree every frame during a transition.
      final state = context.watch<AppearanceSettingsCubit>().state;
      themeData = targetBrightness == Brightness.light
          ? state.lightTheme
          : state.darkTheme;
      final fontFamily = state.font.orDefault(defaultFontFamily).fontFamilyName;
      afTheme = targetBrightness == Brightness.light
          ? AppFlowyDefaultTheme().light(fontFamily: fontFamily)
          : AppFlowyDefaultTheme().dark(fontFamily: fontFamily);
    }

    return Theme(
      data: themeData,
      child: AppFlowyTheme(
        data: afTheme,
        child: child,
      ),
    );
  }
}
