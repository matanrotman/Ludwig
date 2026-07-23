import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/manage_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_more_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/double_click_detector.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/inline_rename_field.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart' hide Icon;
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:sidebar-improvements] Phase 4 (specs/sidebar-improvements.md): the
/// header row of one space in the always-visible space list. Replaces
/// [SidebarSpaceHeader] on desktop — no switcher popover: the caret and a
/// click anywhere on the row toggle THIS space's page tree, double-click
/// renames in place, and the trailing hover icons follow the page rows'
/// convention (flex order, name-relative, ··· outermost, mirroring with the
/// ambient Directionality).
class SpaceListHeader extends StatefulWidget {
  const SpaceListHeader({
    super.key,
    required this.space,
    required this.isExpanded,
    required this.onToggle,
    required this.onAddPage,
    required this.onCreateNewSpace,
    required this.onCollapseAllPages,
  });

  final ViewPB space;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(ViewLayoutPB layout) onAddPage;
  final VoidCallback onCreateNewSpace;
  final VoidCallback onCollapseAllPages;

  @override
  State<SpaceListHeader> createState() => _SpaceListHeaderState();
}

class _SpaceListHeaderState extends State<SpaceListHeader> {
  final _doubleClickDetector = DoubleClickDetector();
  final _onEditing = ValueNotifier(false);
  bool _isRenaming = false;

  @override
  void dispose() {
    _onEditing.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_isRenaming) {
      return;
    }
    if (_doubleClickDetector.isDoubleClick(DateTime.now())) {
      // The first click of this double-click already toggled the space —
      // toggle back so renaming leaves the expansion as it was.
      widget.onToggle();
      setState(() => _isRenaming = true);
    } else {
      widget.onToggle();
    }
  }

  void _commitRename(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && trimmed != widget.space.name) {
      context
          .read<SpaceBloc>()
          .add(SpaceEvent.rename(space: widget.space, name: trimmed));
    }
    _stopRenaming();
  }

  void _stopRenaming() {
    if (mounted) {
      setState(() => _isRenaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HomeSizes.workspaceSectionHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: FlowyHover(
          style: HoverStyle(
            hoverColor: Theme.of(context).colorScheme.secondary,
          ),
          builder: (context, onHover) => ValueListenableBuilder(
            valueListenable: _onEditing,
            builder: (context, onEditing, _) =>
                _buildRow(context, onHover || onEditing),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, bool showActions) {
    final isRTL = Directionality.of(context) == ui.TextDirection.rtl;
    return Row(
      children: [
        const HSpace(4),
        // caret — sideways chevron when collapsed, flipped for RTL so it
        // points into the reading direction (same convention as the page
        // rows' expand caret).
        Transform.flip(
          flipX: !widget.isExpanded && isRTL,
          child: FlowySvg(
            widget.isExpanded
                ? FlowySvgs.workspace_drop_down_menu_show_s
                : FlowySvgs.workspace_drop_down_menu_hide_s,
          ),
        ),
        const HSpace(4),
        SpaceIcon(
          dimension: 22,
          space: widget.space,
          svgSize: 12,
          cornerRadius: 8.0,
        ),
        const HSpace(10),
        Expanded(
          child: _isRenaming
              ? InlineRenameField(
                  initialName: widget.space.name,
                  onSubmitted: _commitRename,
                  onDismissed: _stopRenaming,
                )
              : FlowyText.medium(
                  widget.space.name,
                  fontSize: 14.0,
                  figmaLineHeight: 18.0,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (showActions) ...[
          const HSpace(8.0),
          FlowyTooltip(
            message: LocaleKeys.sideBar_addAPage.tr(),
            child: ViewAddButton(
              parentViewId: widget.space.id,
              // Must feed the same notifier as SpaceMorePopup below: the
              // hover icons only exist while `showActions` is true, so an
              // unreported open popover dies the moment the pointer leaves
              // the row on its way to the menu — the button is removed from
              // the tree and takes its own popover with it. (User feedback
              // 2026-07-23: the "+" menu flashed and vanished; the "…" menu
              // was fine precisely because it wires this up.)
              onEditing: (value) => _onEditing.value = value,
              onSelected: (
                pluginBuilder,
                name,
                initialDataBytes,
                openAfterCreated,
                createNewView,
              ) {
                if (createNewView && pluginBuilder.layoutType != null) {
                  widget.onAddPage(pluginBuilder.layoutType!);
                }
              },
            ),
          ),
          const HSpace(8.0),
          // ··· stays outermost — farthest from the name (Phase 1's rule).
          SpaceMorePopup(
            space: widget.space,
            onEditing: (value) => _onEditing.value = value,
            onAction: _onAction,
          ),
        ],
        const HSpace(4.0),
      ],
    );
  }

  Future<void> _onAction(SpaceMoreActionType type, dynamic data) async {
    switch (type) {
      case SpaceMoreActionType.rename:
        // Same in-place rename as double-click — the dialog is retired.
        setState(() => _isRenaming = true);
        break;
      case SpaceMoreActionType.changeIcon:
        if (data is SelectedEmojiIconResult) {
          if (data.type == FlowyIconType.icon) {
            try {
              final iconsData = IconsData.fromJson(jsonDecode(data.emoji));
              context.read<SpaceBloc>().add(
                    SpaceEvent.changeIcon(
                      // Explicit target: with every space visible, actions
                      // must never fall back to the bloc's currentSpace.
                      space: widget.space,
                      icon: '${iconsData.groupName}/${iconsData.iconName}',
                      iconColor: iconsData.color,
                    ),
                  );
            } on FormatException catch (e) {
              context.read<SpaceBloc>().add(
                    SpaceEvent.changeIcon(space: widget.space, icon: ''),
                  );
              Log.warn('SpaceListHeader changeIcon error:$e');
            }
          }
        }
        break;
      case SpaceMoreActionType.manage:
        _showManageSpaceDialog(context);
        break;
      case SpaceMoreActionType.addNewSpace:
        widget.onCreateNewSpace();
        break;
      case SpaceMoreActionType.collapseAllPages:
        widget.onCollapseAllPages();
        break;
      case SpaceMoreActionType.delete:
        _showDeleteSpaceDialog(context);
        break;
      case SpaceMoreActionType.duplicate:
        context
            .read<SpaceBloc>()
            .add(SpaceEvent.duplicate(space: widget.space));
        break;
      case SpaceMoreActionType.divider:
        break;
    }
  }

  void _showManageSpaceDialog(BuildContext context) {
    final spaceBloc = context.read<SpaceBloc>();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: BlocProvider.value(
          value: spaceBloc,
          child: ManageSpacePopup(space: widget.space),
        ),
      ),
    );
  }

  void _showDeleteSpaceDialog(BuildContext context) {
    final spaceBloc = context.read<SpaceBloc>();
    showConfirmDeletionDialog(
      context: context,
      name: widget.space.name,
      description: LocaleKeys.space_deleteConfirmationDescription.tr(),
      onConfirm: () => spaceBloc.add(SpaceEvent.delete(widget.space)),
    );
  }
}
