import 'package:flutter/gestures.dart';

/// Detects whether a tap completes a double-click, for widgets that must
/// keep their single-tap handler immediate (a `GestureDetector.onDoubleTap`
/// would delay every single tap by the double-tap timeout).
///
/// Sidebar-improvements Phase 2 (specs/sidebar-improvements.md): sidebar
/// rows open the page on the first click and the inline rename box on the
/// second, so the first click can't wait on a disambiguation window.
class DoubleClickDetector {
  DoubleClickDetector({this.window = kDoubleTapTimeout});

  /// Two taps at most this far apart count as a double-click.
  final Duration window;

  DateTime? _lastTap;

  /// Registers a tap at [now]; returns true if it completes a double-click.
  ///
  /// A completed double-click resets the detector, so a rapid third tap
  /// starts a fresh sequence rather than chaining doubles.
  bool isDoubleClick(DateTime now) {
    final last = _lastTap;
    if (last != null && now.difference(last) < window) {
      _lastTap = null;
      return true;
    }
    _lastTap = now;
    return false;
  }
}
