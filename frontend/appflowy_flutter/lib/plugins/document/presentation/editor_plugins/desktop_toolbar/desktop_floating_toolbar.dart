import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/base/toolbar_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'selection_extent_rect.dart';
import 'toolbar_animation.dart';
import 'toolbar_pointer_tracker.dart';

class DesktopFloatingToolbar extends StatefulWidget {
  const DesktopFloatingToolbar({
    super.key,
    required this.editorState,
    required this.child,
    required this.onDismiss,
    this.enableAnimation = true,
    this.pointerTracker,
  });

  final EditorState editorState;
  final Widget child;
  final VoidCallback onDismiss;
  final bool enableAnimation;

  /// When provided (and [anchorToolbarToPointer] is on), the toolbar
  /// anchors at the mouse pointer whenever the pointer is over the visible
  /// selection.
  final EditorPointerTracker? pointerTracker;

  @override
  State<DesktopFloatingToolbar> createState() => _DesktopFloatingToolbarState();
}

class _DesktopFloatingToolbarState extends State<DesktopFloatingToolbar> {
  EditorState get editorState => widget.editorState;

  _Position? position;
  final toolbarController = getIt<FloatingToolbarController>();

  // Mirrors documentPopoverDirection's convention for other document
  // popovers (text align/color, heading, code language, etc.): keyed off
  // the document's own layout direction setting, not the sidebar's dock
  // side. Read (not watch) since this is a one-shot placement computed
  // outside build().
  bool get _isRTL =>
      context.read<AppearanceSettingsCubit>().state.layoutDirection ==
      LayoutDirection.rtlLayout;

  @override
  void initState() {
    super.initState();
    final selection = editorState.selection;
    if (selection == null || selection.isCollapsed) {
      return;
    }
    toolbarController._addCallback(dismiss);
    // Geometry must be read in a post-frame callback, not synchronously:
    // this widget is recreated inside a fresh OverlayEntry whenever the
    // outer FloatingToolbar's scroll-offset listener fires (Duration.zero
    // debounce), so initState() can run during the BUILD phase of the very
    // frame a scroll happens — before that frame's LAYOUT phase — and a
    // synchronous read would return the previous frame's stale geometry
    // (regression test: desktop_floating_toolbar_test.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchorRect = _resolveAnchorRect();
      if (anchorRect == null) return;
      setState(() {
        position = calculateSelectionMenuOffset(anchorRect, isRTL: _isRTL);
      });
    });
  }

  /// Where the toolbar anchors (it renders just above the returned rect):
  /// 1. the mouse pointer, whenever it's anywhere inside the visible
  ///    editor area — NOT only when it's literally over highlighted text.
  ///    (2026-07-16 r3: the earlier "over the selection" check made
  ///    Cmd+A land on the fallback anchor even with the pointer resting
  ///    in the middle of the page, just not on top of a text glyph —
  ///    the user's read was "the pointer is on the page, it should
  ///    still be used".)
  /// 2. otherwise about a third of the way down the selection's visible
  ///    vertical span — anchoring on the selection's raw extent instead
  ///    put the toolbar below the viewport after Cmd+A on a long page;
  /// 3. if no part of the selection is visible, the extent clamped into
  ///    the viewport, so the toolbar can never render off-screen.
  Rect? _resolveAnchorRect() {
    if (!anchorToolbarToPointer) {
      return selectionExtentRect(editorState);
    }
    final editorOffset =
        editorState.renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorSize = editorState.renderBox?.size ?? Size.zero;
    // editorState.renderBox is the scroll service's box — the visible
    // viewport, not the full document height.
    final viewport = editorOffset & editorSize;

    final pointer = widget.pointerTracker?.positionInside([viewport]);
    if (pointer != null) {
      return Rect.fromLTWH(pointer.dx, pointer.dy, 1, 16);
    }

    final visibleSelectionRects = editorState
        .selectionRects()
        .map((rect) => rect.intersect(viewport))
        .where((rect) => !rect.isEmpty)
        .toList();
    if (visibleSelectionRects.isNotEmpty) {
      return upperThirdAnchorRect(visibleSelectionRects, viewport);
    }
    final extentRect = selectionExtentRect(editorState);
    return extentRect == null
        ? null
        : clampRectIntoViewport(extentRect, viewport);
  }

  @override
  void dispose() {
    toolbarController._removeCallback(dismiss);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (position == null) return Container();
    return Positioned(
      left: position!.left,
      top: position!.top,
      right: position!.right,
      child: widget.enableAnimation
          ? ToolbarAnimationWidget(child: widget.child)
          : widget.child,
    );
  }

  void dismiss() {
    widget.onDismiss.call();
  }

  _Position calculateSelectionMenuOffset(
    Rect rect, {
    required bool isRTL,
  }) {
    const toolbarHeight = 40, topLimit = toolbarHeight + 8;
    // Never sit flush against the editor's own left/right bound (which is
    // already positioned clear of the sidebar) -- a toolbar with no gap
    // there reads as glued to the sidebar edge.
    const edgeMargin = 16.0;
    final bool isLongMenu = onlyShowInSingleSelectionAndTextType(editorState);
    final editorOffset =
        editorState.renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorSize = editorState.renderBox?.size ?? Size.zero;
    final menuWidth =
        isLongMenu ? (isNarrowWindow(editorState) ? 490.0 : 660.0) : 420.0;
    final editorRect = editorOffset & editorSize;
    final top =
        rect.top < topLimit ? rect.bottom + topLimit : rect.top - topLimit;

    // Mirrors documentPopoverDirection's convention for other document
    // popovers: LTR opens toward the right of the cursor (toolbar's left
    // edge at the anchor's left edge), RTL toward the left (toolbar's
    // right edge at the anchor's RIGHT edge) -- keyed off the document's
    // own layout direction, not the sidebar's dock side.
    //
    // Mirroring off rect.right (not rect.left) matters for the
    // upper-third fallback anchor: unlike the 1px-wide pointer anchor,
    // that rect spans a whole selection row, so its `left` sits near the
    // editor's own left edge regardless of text direction. Subtracting
    // menuWidth from THAT drove the toolbar deeply negative and pinned
    // it to the far-left wall (2026-07-16 r3 user report) -- rect.right
    // is the row's actual RTL reading-start edge.
    final rawLeft = isRTL ? rect.right - menuWidth : rect.left;
    final minLeft = editorRect.left + edgeMargin;
    final maxLeft = editorRect.right - edgeMargin - menuWidth;
    final left = math.min(
      math.max(rawLeft, minLeft),
      math.max(minLeft, maxLeft),
    );
    return _Position(left, top, null);
  }
}

class _Position {
  _Position(this.left, this.top, this.right);

  final double? left;
  final double? top;
  final double? right;
}

class FloatingToolbarController {
  final Set<VoidCallback> _dismissCallbacks = {};
  final Set<VoidCallback> _displayListeners = {};

  void _addCallback(VoidCallback callback) {
    _dismissCallbacks.add(callback);
    for (final listener in Set.of(_displayListeners)) {
      listener.call();
    }
  }

  void _removeCallback(VoidCallback callback) =>
      _dismissCallbacks.remove(callback);

  bool get isToolbarShowing => _dismissCallbacks.isNotEmpty;

  void addDisplayListener(VoidCallback listener) =>
      _displayListeners.add(listener);

  void removeDisplayListener(VoidCallback listener) =>
      _displayListeners.remove(listener);

  void hideToolbar() {
    if (_dismissCallbacks.isEmpty) return;
    for (final callback in _dismissCallbacks) {
      callback.call();
    }
  }
}
