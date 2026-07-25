import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:temp-space] Phase 4 — the quiet count of what is sitting unfiled in
/// Temporary. See `specs/temp-space.md`.
///
/// Decision 5 of `specs/capture-and-structure.md`: the size of the pile has to
/// be visible, or "structure later" degrades into "never" with nothing in the
/// interface to notice. It is deliberately a **count, not a warning** — no red,
/// no notification-badge styling, no copy implying you are behind on something.
/// It reports; it does not scold. Keep it that way.
///
/// Two decisions taken by the user (2026-07-25):
/// - **direct children only**, not everything nested underneath
/// - **hidden entirely at zero**
///
/// ## Why this owns its own [ViewBloc]
///
/// The obvious source, `SpaceState.spaces`, carries `childViews` from the
/// sections fetch — a snapshot, which would leave the count stale after a page
/// is created or filed. The sidebar's own page list instead reads
/// `ViewBloc(view: space).state.view.childViews`, which stays live through
/// `ViewListener.onViewChildViewsUpdated`.
///
/// That bloc can't be shared, though: it is created inside `SpacePages`, which
/// only exists while the space is **expanded** — and a collapsed Temporary is
/// exactly when the count matters most. So this widget keeps a small one of its
/// own. `ViewEvent.initial` only reads and subscribes; it writes nothing.
class TemporaryUnfiledCount extends StatelessWidget {
  const TemporaryUnfiledCount({super.key, required this.space});

  final ViewPB space;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ViewBloc(view: space)..add(const ViewEvent.initial()),
      child: BlocBuilder<ViewBloc, ViewState>(
        builder: (context, state) {
          final count = state.view.childViews.length;
          if (count == 0) {
            return const SizedBox.shrink();
          }
          return FlowyTooltip(
            message: LocaleKeys.space_unfiledCount.plural(
              count,
              namedArgs: {'count': '$count'},
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: FlowyText.regular(
                '($count)',
                // Parenthesised and at the name's own weight/colour, at the
                // user's request (2026-07-25) — the first version was 12pt
                // hintColor and read as too faint to notice. Still a plain
                // count, not a notification badge: no fill, no accent, no red.
                fontSize: 14.0,
                figmaLineHeight: 18.0,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}
