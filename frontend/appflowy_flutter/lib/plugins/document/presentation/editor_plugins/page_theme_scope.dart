// [fork:page-surface] Sidecar module — chrome/page theme split
// (requested 2026-07-20). See chrome_theme_mode.dart for the model.
//
// Wraps the document area (the desk and the page sheet, including the
// title and editor) in the theme the PAGES' dark/light setting asks for,
// which may differ from the app frame's. Mounted around the same subtree
// as PageSurface, so the ribbon above it stays on the app chrome.
//
// Known scope limits, deliberate:
// - Overlays that render in the app-level Overlay (floating toolbar,
//   slash menu, popovers) keep the CHROME theme even when triggered from
//   the page — they are chrome, consistent with the ribbon.
// - Database row documents (their own code path, see STATUS.md) are not
//   wrapped; same as their pending RTL work.

import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/chrome_theme_mode.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PageThemeScope extends StatelessWidget {
  const PageThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppearanceSettingsCubit>().state;
    final pageBrightness = resolvePageBrightness(
      state.themeMode,
      MediaQuery.platformBrightnessOf(context),
    );
    // Same brightness as the surrounding chrome — nothing to override.
    // This is always the case while chromeThemeMode is followPages, so
    // the pre-split behavior is byte-identical by construction.
    if (pageBrightness == Theme.of(context).brightness) {
      return child;
    }

    final themeData =
        pageBrightness == Brightness.light ? state.lightTheme : state.darkTheme;
    // Mirror the AppFlowyTheme layer exactly as app_widget.dart builds it
    // for the chrome, at the page's brightness.
    final fontFamily = state.font.orDefault(defaultFontFamily).fontFamilyName;
    final afTheme = pageBrightness == Brightness.light
        ? AppFlowyDefaultTheme().light(fontFamily: fontFamily)
        : AppFlowyDefaultTheme().dark(fontFamily: fontFamily);

    return Theme(
      data: themeData,
      child: AnimatedAppFlowyTheme(
        data: afTheme,
        child: child,
      ),
    );
  }
}
