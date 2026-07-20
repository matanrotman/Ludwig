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

/// Desk left above the sheet, so the page has a visible **top edge**.
///
/// The page shows three edges — top, left, right — and runs off the bottom of
/// the viewport. Corners are square: rounding them made the sheet read as a
/// panel or a card rather than a page (user's call, 2026-07-20).
///
/// One number to tune if the gap ever feels wrong; it is deliberately the same
/// as the minimum side margin so the visible border reads as even.
const double _kDeskMarginTop = _kMinDeskMargin;

/// Desk always left visible on each side of the sheet.
///
/// Without a floor here the feature silently does nothing for most users: the
/// document width defaults to [EditorStyleCustomizer.maxDocumentWidth] (1920),
/// which is wider than a typical editor pane, so the sheet gets clamped to the
/// full pane and there is no desk left to see. Reserving a strip guarantees the
/// page always reads as a page. Costs `2 ×` this much text width at wide
/// settings — accepted by the user 2026-07-20 in exchange for the page always
/// being visible.
///
/// Tuned 48 → 32 on 2026-07-20 after the user saw it: 48 read as too much
/// desk. Both the top and side margins come from this one value on purpose, so
/// the visible border stays even — split them only if the user asks for an
/// uneven border deliberately.
const double _kMinDeskMargin = 32.0;

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
class PageSurface extends StatefulWidget {
  const PageSurface({
    super.key,
    required this.pageWidth,
    required this.child,
  });

  final double pageWidth;
  final Widget child;

  @override
  State<PageSurface> createState() => _PageSurfaceState();
}

class _PageSurfaceState extends State<PageSurface> {
  /// Current gap between the ribbon and the top of the sheet.
  ///
  /// Held in a [ValueNotifier] rather than in [State] so a scroll repaints only
  /// the padding, not the whole editor beneath it — this updates on every
  /// scroll frame, and rebuilding the document each time would be wasteful.
  final ValueNotifier<double> _topMargin = ValueNotifier(_kDeskMarginTop);

  @override
  void dispose() {
    _topMargin.dispose();
    super.dispose();
  }

  /// Closes the gap above the page as the document scrolls down, so the page
  /// slides up against a desk that stays put — the thing that makes it read as
  /// a separate sheet rather than a painted background (user's request,
  /// 2026-07-20).
  ///
  /// Driven by [ScrollNotification], which bubbles *up* from the editor's own
  /// scrollable to this ancestor. That is deliberate: it needs no access to the
  /// editor's `ScrollController` and so adds nothing to the upstream merge
  /// surface.
  bool _onScroll(ScrollNotification notification) {
    // Only the document's own vertical scrolling should move the page. Nested
    // scrollables — a wide table, a code block, the slash menu — also send
    // notifications up this tree, and letting them drive the margin would make
    // the page twitch while scrolling something else entirely.
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    _topMargin.value = (_kDeskMarginTop - notification.metrics.pixels)
        .clamp(0.0, _kDeskMarginTop);
    // False: this is an observer, not a consumer. Swallowing the notification
    // would break anything else listening for scrolls.
    return false;
  }

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
            (constraints.maxWidth - widget.pageWidth) / 2,
          );

          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ValueListenableBuilder<double>(
              valueListenable: _topMargin,
              // Passed through untouched so the editor is not rebuilt when the
              // margin changes.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: sheetColor,
                  boxShadow: theme.shadow.medium,
                ),
                child: widget.child,
              ),
              builder: (context, topMargin, sheet) => Padding(
                padding: EdgeInsets.only(
                  left: desk,
                  right: desk,
                  // No bottom: the sheet runs off the bottom of the viewport on
                  // purpose. A bottom edge would imply the document ends there,
                  // which is rarely true and looks wrong mid-scroll.
                  top: topMargin,
                ),
                child: sheet,
              ),
            ),
          );
        },
      ),
    );
  }
}
