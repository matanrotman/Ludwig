import 'dart:async';

import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/pad/ephemeral_pad_launcher.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:ephemeral-pad] D4 — clicking empty sidebar space returns you to the
/// pad. See `specs/ephemeral-pad.md`.
///
/// It is navigation, not a destructive act: nothing you wrote is lost (the pad
/// is a real page, saved continuously), so it needs no confirmation.
///
/// ## Why this wraps the scroll view rather than sitting behind it
///
/// The obvious shape — a full-size tap target *underneath* the list in a
/// `Stack` — does not work. `Scrollable` hit-tests its entire viewport, empty
/// region included, so it absorbs the hit and the layer below is never reached.
///
/// Wrapping is what turns that from a problem into the mechanism: the hit test
/// descends *through* this detector to reach the scrollable, so an opaque tap
/// recognizer here is in the path for every point of the viewport, including
/// the blank area under the last row. Taps on a page row still open that page —
/// the row's own recognizer is deeper in the tree, enters the gesture arena
/// first, and wins. Dragging still scrolls, for the same reason in reverse: a
/// tap recognizer never claims a drag.
class SidebarPadTapArea extends StatelessWidget {
  const SidebarPadTapArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(
        openEphemeralPad(context.read<SpaceBloc>().state.spaces),
      ),
      child: child,
    );
  }
}
