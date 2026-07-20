// [fork:page-surface] Sidecar module — see specs/ribbon-menu.md.
//
// Makes a document read as a *sheet of paper on a desk*: the text column gets
// its own surface, a soft shadow and rounded top corners, and the area around it
// is visibly recessed. Before this, the margins and the page were the same flat
// colour, so there was no visual cue where the page began or ended.
//
// Deliberately a plain wrapper around the editor rather than a change inside it:
// the editor owns its own scrolling and block painting, and reaching into that
// would be a merge liability at every upstream sync. This insets it instead.

import 'dart:math' as math;

import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Corner rounding at the top of the sheet.
const double _kPageCornerRadius = 8.0;

/// Desk always left visible on each side of the sheet.
///
/// Without a floor here the feature silently does nothing for most users: the
/// document width defaults to [EditorStyleCustomizer.maxDocumentWidth] (1920),
/// which is wider than a typical editor pane, so the sheet gets clamped to the
/// full pane and there is no desk left to see. Reserving a strip guarantees the
/// page always reads as a page. Costs `2 ×` this much text width at wide
/// settings — accepted by the user 2026-07-20 in exchange for the page always
/// being visible.
const double _kMinDeskMargin = 48.0;

/// How much darker the desk is than the sheet, in HSL lightness.
///
/// Two separate values because the same delta does not read the same at both
/// ends of the scale: near-white needs a bigger step to register as a different
/// surface, while near-black would turn muddy if pushed as far.
const double _kDeskDarkenLight = 0.055;
const double _kDeskDarkenDark = 0.035;

/// The desk colour, derived from the sheet rather than taken from a token.
///
/// The obvious implementation — `surfaceColorScheme.layer02` for the desk and
/// `primary` for the sheet — does not work, and the reason is worth recording:
/// in the default **light** theme those two tokens are both `neutralWhite`
/// (identical, so the page would vanish), and in the **dark** theme `layer02`
/// is *lighter* than `primary`, which reads as raised rather than recessed.
/// Deriving guarantees the page reads as a page in any theme, including custom
/// ones, instead of depending on a token relationship that does not hold.
Color _deskColorFor(Color sheet) {
  final hsl = HSLColor.fromColor(sheet);
  final darken = hsl.lightness > 0.5 ? _kDeskDarkenLight : _kDeskDarkenDark;
  return hsl.withLightness((hsl.lightness - darken).clamp(0.0, 1.0)).toColor();
}

/// Paints the page surface behind [child] and insets it onto the sheet.
///
/// [pageWidth] is the document column's own width setting
/// (`DocumentAppearanceCubit.state.width`).
class PageSurface extends StatelessWidget {
  const PageSurface({
    super.key,
    required this.pageWidth,
    required this.child,
  });

  final double pageWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final sheetColor = theme.surfaceColorScheme.primary;

    return ColoredBox(
      color: _deskColorFor(sheetColor),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Insetting (rather than painting a sheet *behind* a full-width
          // editor) is what keeps text on the paper: the editor lays its column
          // out inside whatever width it is given, so narrowing the sheet
          // without narrowing the editor would let text spill onto the desk.
          final desk = math.max(
            _kMinDeskMargin,
            (constraints.maxWidth - pageWidth) / 2,
          );

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: desk),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: sheetColor,
                // Top corners only: the sheet runs off the bottom of the
                // viewport on purpose. A bottom edge would imply the document
                // ends there, which is rarely true and looks wrong mid-scroll.
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(_kPageCornerRadius),
                  topRight: Radius.circular(_kPageCornerRadius),
                ),
                boxShadow: theme.shadow.medium,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
