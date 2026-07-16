import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Kill-switch for the pointer-anchored floating toolbar experiment
/// (2026-07-16). `false` restores the previous behavior exactly: anchor on
/// the selection's extent with no viewport clamping.
const bool anchorToolbarToPointer = true;

/// Toolbar height (40) + the 8px gap the toolbar keeps above its anchor —
/// mirrors `topLimit` in DesktopFloatingToolbar.calculateSelectionMenuOffset.
/// An anchor at least this far below the viewport's top edge guarantees the
/// toolbar itself renders fully inside the viewport.
const double _toolbarTopInset = 48;

/// Passively records the last known global mouse position over the editor.
///
/// Flutter has no public "current mouse position" API (MouseTracker keeps
/// per-device state private), so [EditorPointerTrackingListener] feeds this
/// from raw pointer events instead.
class EditorPointerTracker {
  Offset? lastGlobalPosition;

  /// The recorded position, but only when it lies inside one of [rects] —
  /// e.g. "is the pointer inside the visible editor area?".
  Offset? positionInside(Iterable<Rect> rects) {
    final position = lastGlobalPosition;
    if (position == null) {
      return null;
    }
    return rects.any((rect) => rect.contains(position)) ? position : null;
  }

  void clear() => lastGlobalPosition = null;
}

/// Wraps the editor to feed an [EditorPointerTracker].
///
/// Raw pointer events reach every listener on the hit-test path regardless
/// of who wins the gesture arena, so this never interferes with the
/// editor's own click/drag-selection gestures.
///
/// The [MouseRegion.onExit] clear matters: hover events stop arriving once
/// the mouse leaves the editor, so without it the last recorded position
/// would freeze at the editor's edge — still *inside* the editor rect, and
/// wrongly counted as usable.
class EditorPointerTrackingListener extends StatelessWidget {
  const EditorPointerTrackingListener({
    super.key,
    required this.tracker,
    required this.child,
  });

  final EditorPointerTracker tracker;
  final Widget child;

  static const _trackedKinds = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  void _record(PointerEvent event) {
    if (_trackedKinds.contains(event.kind)) {
      tracker.lastGlobalPosition = event.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _record,
      onPointerMove: _record,
      onPointerUp: _record,
      onPointerCancel: (_) => tracker.clear(),
      child: MouseRegion(
        opaque: false,
        onHover: _record,
        onExit: (_) => tracker.clear(),
        child: child,
      ),
    );
  }
}

/// Fallback anchor when the pointer isn't over the selection: about a third
/// of the way down the selection's *visible* vertical span — near the top,
/// but not glued to it, and never so high the toolbar would leave the
/// viewport.
///
/// [visibleSelectionRects] must be non-empty and already intersected with
/// the viewport. The returned rect spans the selection row's full left..right
/// width at that height (not a single point) — the horizontal placement math
/// mirrors off `left` for LTR and `right` for RTL, and a full-width RTL row's
/// `right` is its real reading-start edge, nowhere near its `left`.
Rect upperThirdAnchorRect(
  List<Rect> visibleSelectionRects,
  Rect viewport, {
  double topInset = _toolbarTopInset,
}) {
  assert(visibleSelectionRects.isNotEmpty);
  final sorted = [...visibleSelectionRects]
    ..sort((a, b) => a.top.compareTo(b.top));
  final top = sorted.first.top;
  final bottom = sorted.map((rect) => rect.bottom).reduce(math.max);
  final anchorY = math.max(top + (bottom - top) / 3, viewport.top + topInset);

  Rect anchorRow = sorted.first;
  var bestDistance = double.infinity;
  for (final rect in sorted) {
    if (rect.top <= anchorY && anchorY <= rect.bottom) {
      anchorRow = rect;
      break;
    }
    final distance =
        anchorY < rect.top ? rect.top - anchorY : anchorY - rect.bottom;
    if (distance < bestDistance) {
      bestDistance = distance;
      anchorRow = rect;
    }
  }
  return Rect.fromLTRB(anchorRow.left, anchorY, anchorRow.right, anchorY + 16);
}

/// Safety net for when no part of the selection is visible at all: pulls
/// [rect] into [viewport] so the toolbar can never render off-screen.
Rect clampRectIntoViewport(
  Rect rect,
  Rect viewport, {
  double topInset = _toolbarTopInset,
}) {
  final minTop = viewport.top + topInset;
  final maxTop = math.max(minTop, viewport.bottom - rect.height);
  final maxLeft = math.max(viewport.left, viewport.right - rect.width);
  return Rect.fromLTWH(
    rect.left.clamp(viewport.left, maxLeft),
    rect.top.clamp(minTop, maxTop),
    rect.width,
    rect.height,
  );
}
