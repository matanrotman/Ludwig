import 'dart:async';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/pad/ephemeral_pad.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:ephemeral-pad] D5 — the app opens on the pad.
///
/// This deliberately drops "reopen the page I last had open": that page is one
/// click away in the sidebar, and opening on a blank sheet is the entire point
/// of the feature. See `specs/ephemeral-pad.md`.
///
/// Lives inside the sidebar's subtree because that is where `SpaceBloc` is
/// provided, and Temporary — where the pad lives — can only be resolved once
/// spaces have loaded.
///
/// **Fires exactly once per launch**, and never after the user has navigated:
/// spaces can be re-emitted (a page created, a space renamed, a workspace
/// switch), and yanking someone back to a blank pad mid-sentence because an
/// unrelated bloc rebuilt would be a bug with a very confusing report.
/// Resolve the pad (creating it if needed) and open it.
///
/// Shared by the launch path (D5) and the empty-sidebar gesture (D4), because
/// "make sure the pad exists, then show it" must have exactly one answer — two
/// copies of it is how you end up with two pads.
///
/// Returns false when there is nothing to open, so callers can stay put rather
/// than pretend something happened.
Future<bool> openEphemeralPad(List<ViewPB> spaces) async {
  final temporary = TemporarySpace.resolve(spaces);
  if (temporary == null) {
    // No Temporary yet — its migration is idempotent and runs again next
    // launch, so leave the app where it is rather than inventing somewhere for
    // the pad to live.
    Log.info('ephemeral-pad: no Temporary space yet, not opening the pad');
    return false;
  }
  final pad = await EphemeralPad.ensure(temporary: temporary);
  if (pad == null) {
    return false;
  }
  getIt<TabsBloc>().add(TabsEvent.openPlugin(plugin: pad.plugin(), view: pad));
  return true;
}

class EphemeralPadLauncher extends StatefulWidget {
  const EphemeralPadLauncher({super.key, required this.child});

  final Widget child;

  @override
  State<EphemeralPadLauncher> createState() => _EphemeralPadLauncherState();
}

class _EphemeralPadLauncherState extends State<EphemeralPadLauncher> {
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // Spaces may already have loaded before this mounts, in which case no
    // further SpaceBloc state arrives and the listener alone would never fire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeOpen(context.read<SpaceBloc>().state);
      }
    });
  }

  Future<void> _maybeOpen(SpaceState state) async {
    if (_handled || state.spaces.isEmpty) {
      return;
    }
    if (TemporarySpace.resolve(state.spaces) == null) {
      // Not resolvable yet — don't burn the one-shot on it; a later emission
      // (or the next launch, once the migration has run) can still succeed.
      Log.info('ephemeral-pad: no Temporary space yet, not opening the pad');
      return;
    }
    // Claim the launch before the first await: two SpaceBloc emissions a frame
    // apart would otherwise both get past the check and create two pads.
    _handled = true;
    await openEphemeralPad(state.spaces);
  }

  @override
  Widget build(BuildContext context) => BlocListener<SpaceBloc, SpaceState>(
        listenWhen: (previous, current) =>
            previous.spaces.length != current.spaces.length,
        listener: (_, state) => unawaited(_maybeOpen(state)),
        child: widget.child,
      );
}
