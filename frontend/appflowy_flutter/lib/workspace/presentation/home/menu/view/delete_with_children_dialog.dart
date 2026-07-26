import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/move_to/move_page_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Ask-first deletion for anything that contains other pages.
///
/// Why this exists: deleting a container used to remove everything inside it with no warning
/// and no visible trace — the contents were not listed in the trash, so a delete looked
/// unrecoverable even when it wasn't, and a *permanent* delete genuinely stranded them. The
/// data half of that is fixed in the Rust core (`flowy-folder`'s `delete_trash`); this is the
/// half that stops it being a surprise in the first place.
///
/// Design decisions and their reasoning live in `specs/delete-and-trash.md`. The ones that
/// shape this file:
///  - the count is of **every** nested page at any depth, never just the direct children,
///    because an understated number is exactly how the original loss happened;
///  - there is deliberately **no "don't ask again"** — that option is how someone re-creates
///    silent loss for themselves later;
///  - a page with nothing inside it is deleted with no dialog at all, so the common case
///    gains no friction.
enum DeleteChoice { deleteEverything, moveThemElsewhere }

/// Runs the whole delete interaction for [view].
///
/// Calls [onDelete] once the user has committed to deleting — either immediately (nothing
/// inside), or after they chose "delete everything", or after the contents were successfully
/// moved somewhere else. If the user cancels, or a rescue-move fails, [onDelete] is never
/// called and nothing is deleted.
Future<void> showDeleteViewDialog({
  required BuildContext context,
  required ViewPB view,
  required VoidCallback onDelete,
}) async {
  // Both of these hit the backend, so gather them before touching the UI.
  final descendants = await ViewBackendService.getAllChildViews(view);
  final (containsPublishedPage, _) =
      await ViewBackendService.containPublishedPage(view);

  if (!context.mounted) {
    return;
  }

  // Nothing inside: keep the existing behaviour exactly, including the published-page
  // warning that already guarded this path.
  if (descendants.isEmpty) {
    if (containsPublishedPage) {
      await showConfirmDeletionDialog(
        context: context,
        name: view.name,
        description: LocaleKeys.publish_containsPublishedPage.tr(),
        onConfirm: onDelete,
      );
    } else {
      onDelete();
    }
    return;
  }

  final choice = await showDialog<DeleteChoice>(
    context: context,
    builder: (_) => DeleteWithChildrenDialog(
      view: view,
      descendantCount: descendants.length,
      containsPublishedPage: containsPublishedPage,
      // "Move to" is server-workspace only upstream, so the rescue route is offered only
      // where it actually works. Local workspaces still get Cancel / Delete everything.
      canMoveElsewhere: _canMoveElsewhere(context),
    ),
  );

  if (choice == null || !context.mounted) {
    return;
  }

  switch (choice) {
    case DeleteChoice.deleteEverything:
      onDelete();
    case DeleteChoice.moveThemElsewhere:
      final moved = await _moveChildrenElsewhere(context: context, view: view);
      // Only delete once the contents are safely out. If the move failed we must NOT
      // fall through to deleting — that would destroy exactly what the user was rescuing.
      if (moved && context.mounted) {
        onDelete();
      }
  }
}

bool _canMoveElsewhere(BuildContext context) {
  final spaceBloc = context.read<SpaceBloc?>();
  if (spaceBloc == null) {
    return false;
  }
  return spaceBloc.userProfile.workspaceType == WorkspaceTypePB.ServerW;
}

/// Opens the existing Move to picker and re-parents each DIRECT child of [view] to the
/// chosen destination. Each child brings its own sub-pages along, so one destination is
/// enough to rescue the whole branch.
///
/// Returns true only if every child was moved.
Future<bool> _moveChildrenElsewhere({
  required BuildContext context,
  required ViewPB view,
}) async {
  final spaceBloc = context.read<SpaceBloc>();
  final target = await showDialog<ViewPB>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: spaceBloc,
      child: _MoveChildrenPickerDialog(view: view),
    ),
  );

  if (target == null || !context.mounted) {
    return false;
  }

  final childrenResult =
      await ViewBackendService.getChildViews(viewId: view.id);
  final children = childrenResult.fold(
    (children) => children,
    (_) => <ViewPB>[],
  );

  var allMoved = true;
  for (final child in children) {
    final result = await ViewBackendService.moveViewV2(
      viewId: child.id,
      newParentId: target.id,
      prevViewId: null,
    );
    result.onFailure((_) => allMoved = false);
  }

  if (!allMoved && context.mounted) {
    showToastNotification(
      message: LocaleKeys.deleteWithChildren_moveFailed.tr(),
      type: ToastificationType.error,
    );
  }

  return allMoved;
}

class DeleteWithChildrenDialog extends StatelessWidget {
  const DeleteWithChildrenDialog({
    super.key,
    required this.view,
    required this.descendantCount,
    required this.containsPublishedPage,
    required this.canMoveElsewhere,
  });

  final ViewPB view;
  final int descendantCount;
  final bool containsPublishedPage;
  final bool canMoveElsewhere;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // Escape cancels. Enter deliberately does nothing: this dialog has two opposite
    // commitments and no safe default, so there is no key that "just confirms".
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Container(
            // Wide enough for all three buttons on one row (user's call,
            // 2026-07-26). At 460 they wrapped, stranding the destructive one
            // alone on a second line. The Wrap below stays as a safety net for
            // translations longer than English or Hebrew.
            width: 640,
            padding: EdgeInsets.all(theme.spacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.deleteWithChildren_title.tr(
                    args: [view.nameOrDefault],
                  ),
                  style: theme.textStyle.heading4.prominent(
                    color: theme.textColorScheme.primary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                VSpace(theme.spacing.l),
                Text(
                  _describeContents(),
                  style: theme.textStyle.body.standard(
                    color: theme.textColorScheme.primary,
                  ),
                  maxLines: 4,
                ),
                VSpace(theme.spacing.xxl),
                _buildButtons(context, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _describeContents() {
    final count = descendantCount == 1
        ? LocaleKeys.deleteWithChildren_countOne.tr()
        : LocaleKeys.deleteWithChildren_countMany
            .tr(args: ['$descendantCount']);
    // Both warnings can be true at once; the published one must not silently replace
    // the count, which is the number that matters most.
    if (!containsPublishedPage) {
      return count;
    }
    return '$count ${LocaleKeys.deleteWithChildren_alsoPublished.tr()}';
  }

  Widget _buildButtons(BuildContext context, AppFlowyThemeData theme) {
    // Wrap rather than Row: three labelled buttons is already close to the dialog's
    // width in English, and translations vary a lot in length — Hebrew and German
    // both push past it. Wrapping onto a second line is far better than an overflow
    // stripe, and costs nothing when they do fit.
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12.0,
      runSpacing: 8.0,
      children: [
        AFOutlinedTextButton.normal(
          text: LocaleKeys.button_cancel.tr(),
          textStyle: theme.textStyle.body.standard(
            color: theme.textColorScheme.primary,
          ),
          onTap: () => Navigator.of(context).pop(),
        ),
        if (canMoveElsewhere)
          AFOutlinedTextButton.normal(
            text: LocaleKeys.deleteWithChildren_moveThemElsewhere.tr(),
            textStyle: theme.textStyle.body.standard(
              color: theme.textColorScheme.primary,
            ),
            onTap: () =>
                Navigator.of(context).pop(DeleteChoice.moveThemElsewhere),
          ),
        // Outlined with red text rather than a solid red fill: all three
        // choices are equally legitimate here, so the destructive one is
        // *marked*, not shouted. A filled red button reads as "this is what
        // you came to do", which is exactly the wrong suggestion in a dialog
        // whose whole purpose is to slow that down.
        AFOutlinedTextButton.destructive(
          text: LocaleKeys.deleteWithChildren_deleteEverything.tr(),
          onTap: () =>
              Navigator.of(context).pop(DeleteChoice.deleteEverything),
        ),
      ],
    );
  }
}

/// Thin wrapper that presents the existing [MovePageMenu] as a dialog and pops the chosen
/// destination. Reused rather than reimplemented so the picker keeps behaving exactly like
/// the "Move to" action elsewhere in the sidebar.
class _MoveChildrenPickerDialog extends StatelessWidget {
  const _MoveChildrenPickerDialog({required this.view});

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Container(
        width: 400,
        height: 460,
        padding: EdgeInsets.all(theme.spacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.deleteWithChildren_movePickerTitle.tr(
                args: [view.nameOrDefault],
              ),
              style: theme.textStyle.heading4.prominent(
                color: theme.textColorScheme.primary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            VSpace(theme.spacing.l),
            Expanded(
              child: MovePageMenu(
                sourceView: view,
                onSelected: (_, target) => Navigator.of(context).pop(target),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
