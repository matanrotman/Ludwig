import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/trash/application/trash_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:sidebar-improvements] The sidebar footer's trash icon, live-updating
/// with the trash's contents: the normal can when empty, a "full" variant
/// (lid ajar, scraps poking out) when anything is in it. Phase 3 of
/// specs/sidebar-improvements.md — replaces the removed in-page trash banner
/// as the visible cue that trash holds pages.
///
/// The full-trash asset is referenced directly rather than through the
/// generated [FlowySvgs] catalog so this feature stays out of the generated
/// file (fork discipline: fewer core/generated diffs to merge).
const FlowySvgData fullTrashIcon =
    FlowySvgData('assets/flowy_icons/16x/icon_delete_full.svg');

class SidebarTrashIcon extends StatelessWidget {
  const SidebarTrashIcon({super.key, @visibleForTesting this.trashBloc});

  /// Tests inject a mock; production creates (and owns) a real bloc that
  /// starts the trash listener.
  final TrashBloc? trashBloc;

  @override
  Widget build(BuildContext context) {
    const icon = _TrashSvg();
    final bloc = trashBloc;
    if (bloc != null) {
      return BlocProvider<TrashBloc>.value(value: bloc, child: icon);
    }
    return BlocProvider<TrashBloc>(
      create: (_) => TrashBloc()..add(const TrashEvent.initial()),
      child: icon,
    );
  }
}

class _TrashSvg extends StatelessWidget {
  const _TrashSvg();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TrashBloc, TrashState>(
      buildWhen: (prev, curr) => prev.objects.isEmpty != curr.objects.isEmpty,
      builder: (context, state) => FlowySvg(
        state.objects.isEmpty ? FlowySvgs.icon_delete_s : fullTrashIcon,
      ),
    );
  }
}
