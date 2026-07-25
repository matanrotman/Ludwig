// [fork:sidebar] Sidecar module — see specs/sidebar-improvements.md.
//
// Makes a space's header row a drop target, so dragging a page onto a space
// name moves that page into the space.
//
// Why this exists: nothing under `sidebar/space/` was a drag target at all —
// dragging a page onto a space header did literally nothing, with no cursor
// feedback to say so (user report, 2026-07-25). Page-to-page dragging has
// always worked (`draggable_view_item.dart`), and there is a "Move to" menu
// action, but dropping onto the space itself is the obvious gesture and it
// silently failed.
//
// This is deliberately a NEW widget wrapping the existing header rather than an
// edit to `space_list_header.dart`, to keep the upstream-merge surface small
// (CLAUDE.md → Fork maintenance).

import 'dart:async';

import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// Wraps [child] (a space header row) in a [DragTarget] that accepts pages.
///
/// A drop moves the dragged view to the top of [space]'s page list. Moving to
/// the *top* rather than the bottom is deliberate: the drop point is the space
/// header, which sits above the pages, so the page appearing directly beneath
/// the cursor is what the gesture visually promises.
class SpaceDropTarget extends StatefulWidget {
  const SpaceDropTarget({
    super.key,
    required this.space,
    required this.child,
    this.highlightColor,
  });

  final ViewPB space;
  final Widget child;
  final Color? highlightColor;

  @override
  State<SpaceDropTarget> createState() => _SpaceDropTargetState();
}

class _SpaceDropTargetState extends State<SpaceDropTarget> {
  bool _isHoveringWithPage = false;

  /// Matches `draggable_view_item.dart`'s hover colour so cross-space drops
  /// look like the page-to-page drops the user already knows.
  static const _defaultHighlightColor = Color(0xFF00C8FF);

  @override
  Widget build(BuildContext context) {
    return DragTarget<ViewPB>(
      onWillAcceptWithDetails: (details) => _canAccept(details.data),
      onMove: (details) {
        if (_canAccept(details.data) && !_isHoveringWithPage) {
          setState(() => _isHoveringWithPage = true);
        }
      },
      onLeave: (_) {
        if (_isHoveringWithPage) {
          setState(() => _isHoveringWithPage = false);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _isHoveringWithPage = false);
        _moveIntoSpace(details.data);
      },
      builder: (context, _, __) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6.0),
          color: _isHoveringWithPage
              ? (widget.highlightColor ?? _defaultHighlightColor)
                  .withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        child: widget.child,
      ),
    );
  }

  bool _canAccept(ViewPB view) {
    // A space cannot be nested inside another space.
    if (view.isSpace) {
      return false;
    }

    // Dropping onto the space it already belongs to is a no-op, not a move —
    // and highlighting it would promise something that will not happen.
    if (view.parentViewId == widget.space.id) {
      return false;
    }

    // Guard against dropping a space's own ancestor into it.
    if (view.id == widget.space.id) {
      return false;
    }

    return true;
  }

  void _moveIntoSpace(ViewPB view) {
    // `prevViewId: null` == "first child". Uses the backend service directly
    // rather than `ViewEvent.move`, because the bloc reachable from a space
    // header's context belongs to the SPACE, not to the page being dragged —
    // dispatching there would move the wrong view.
    unawaited(
      ViewBackendService.moveViewV2(
        viewId: view.id,
        newParentId: widget.space.id,
        prevViewId: null,
      ),
    );
  }
}
