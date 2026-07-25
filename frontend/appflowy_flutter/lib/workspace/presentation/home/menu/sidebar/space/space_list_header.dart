import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/view/page_folder.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/manage_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_more_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/temporary_unfiled_count.dart';
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
    required this.onCreateFolder,
  });

  final ViewPB space;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(ViewLayoutPB layout) onAddPage;
  final VoidCallback onCreateNewSpace;
  final VoidCallback onCollapseAllPages;

  /// [fork:folder] Create a folder directly in this space.
  final VoidCallback onCreateFolder;

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

  /// [fork:temp-space] Is this row the workspace's Temporary space?
  ///
  /// Resolved against the whole space list, not the view alone, because
  /// identity is a property of the workspace — see [TemporarySpace]. Safe to
  /// `read` in build: this widget always sits inside the space list's
  /// `BlocBuilder<SpaceBloc>`, which rebuilds it when the spaces change.
  bool _isTemporary(BuildContext context) => TemporarySpace.isTemporary(
        widget.space,
        context.read<SpaceBloc>().state.spaces,
      );

  /// [fork:temp-space] Temporary's name is a product constant, not user data
  /// (it cannot be renamed), so it is *rendered* rather than read from the
  /// view. This is what lets Phase 1 write nothing at all to the user's data.
  ///
  /// Known and accepted Phase-1 gap: surfaces this doesn't cover — search
  /// results and the "Move to" picker — still show the stored name. Phase 3's
  /// migration aligns the stored name and closes it.
  String _displayName(BuildContext context) => _isTemporary(context)
      ? LocaleKeys.space_temporaryName.tr()
      : widget.space.name;

  void _handleTap() {
    if (_isRenaming) {
      return;
    }
    if (_doubleClickDetector.isDoubleClick(DateTime.now())) {
      // The first click of this double-click already toggled the space —
      // toggle back so renaming leaves the expansion as it was.
      widget.onToggle();
      // [fork:temp-space] Temporary can't be renamed, so a double-click is
      // just two toggles (net: nothing) instead of opening the rename field.
      if (_isTemporary(context)) {
        return;
      }
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

  /// [fork:folder] The space's own icon colour, faded, used to tint the whole
  /// header row (user request 2026-07-25: "let's try colouring the whole line of
  /// the space with the background colour and see how that works").
  ///
  /// This is the experiment that distinguishes a SPACE from a FOLDER now that
  /// folders also carry a filled rounded-square icon: the space gets a tinted
  /// band, the folder just gets the badge. Deliberately very low alpha — the row
  /// still has to read as a header, and the hover highlight has to remain
  /// visible on top of it.
  ///
  /// Returns null when the space has no colour, so untinted stays untinted.
  Color? _rowTint(BuildContext context) {
    final raw = widget.space.spaceIconColor;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return Color(int.parse(raw)).withValues(alpha: 0.12);
    } catch (error) {
      Log.warn('SpaceListHeader: unparseable space icon colour "$raw": $error');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: HomeSizes.workspaceSectionHeight,
      color: _rowTint(context),
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
        // [fork:folder] Clicking the icon opens the icon + colour picker
        // directly (user request 2026-07-25) — the same thing the "…" menu's
        // "Change icon" does, without the menu trip. Wrapped in its own tap
        // handler so the click doesn't also toggle the space open/closed.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SpaceIconPopup(
            space: widget.space,
            icon: widget.space.spaceIcon,
            iconColor: widget.space.spaceIconColor,
            cornerRadius: 8.0,
            onIconChanged: (icon, color) => context.read<SpaceBloc>().add(
                  SpaceEvent.changeIcon(
                    space: widget.space,
                    icon: icon,
                    iconColor: color,
                  ),
                ),
          ),
        ),
        const HSpace(10),
        Expanded(
          child: _isRenaming
              ? InlineRenameField(
                  initialName: widget.space.name,
                  onSubmitted: _commitRename,
                  onDismissed: _stopRenaming,
                )
              // [fork:temp-space] Phase 4: the count sits INSIDE the expanded
              // slot, immediately after the name — "Temporary (3)", mirroring
              // to "(3) Temporary" in RTL off the ambient Directionality.
              //
              // It was previously a sibling of this Expanded, which pushed it to
              // the far edge of the row, visibly detached from the name (user
              // feedback 2026-07-25). `Flexible` on the text keeps a long space
              // name ellipsizing rather than squeezing the count out.
              : Row(
                  children: [
                    Flexible(
                      child: FlowyText.semibold(
                        _displayName(context),
                        fontSize: 14.0,
                        figmaLineHeight: 18.0,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isTemporary(context))
                      TemporaryUnfiledCount(space: widget.space),
                  ],
                ),
        ),
        if (showActions) ...[
          const HSpace(8.0),
          FlowyTooltip(
            message: LocaleKeys.sideBar_addAPage.tr(),
            child: ViewAddButton(
              parentViewId: widget.space.id,
              // [fork:folder] null on Temporary — decision 4, the staging area
              // stays flat. Passing null is what hides the entry entirely.
              onCreateFolder: PageFolder.canCreateFolderIn(
                parent: widget.space,
                spaces: context.read<SpaceBloc>().state.spaces,
              )
                  ? widget.onCreateFolder
                  : null,
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
        // [fork:temp-space] belt-and-braces: the menu entry is already
        // disabled for Temporary, so this should be unreachable.
        if (_isTemporary(context)) {
          break;
        }
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
