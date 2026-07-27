import 'package:flutter/material.dart';

/// Ludwig's mark, as shown above "Welcome to Ludwig" on first launch.
///
/// Upstream drew `FlowySvgs.app_logo_xl` here — AppFlowy's petal mark — which
/// survived the Phase 1 rebrand because that pass changed the *app icon* only.
/// A fresh Ludwig therefore greeted new users with someone else's logo.
///
/// The asset is the Ludwig icon's artwork with its white background removed, so
/// the coloured line-art reads the same on the light and dark welcome screens
/// (the tile version all but vanishes on light). Chosen by the user from a
/// side-by-side comparison, 2026-07-27.
///
/// It is a PNG rather than an SVG — the supplied artwork is raster, and the
/// generated `FlowySvgs` table only maps SVGs. 512px covers the largest use
/// (~40pt logical, 80px at 2x) with room to spare.
class AFLogo extends StatelessWidget {
  const AFLogo({
    super.key,
    this.size = const Size.square(36),
  });

  final Size size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/ludwig_logo.png',
      width: size.width,
      height: size.height,
      fit: BoxFit.contain,
    );
  }
}
