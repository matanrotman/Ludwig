import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/sidebar_dock_side.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/rename_view/rename_view_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/page_folder.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/delete_with_children_dialog.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/double_click_detector.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/inline_rename_field.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/draggable_view_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/rename_view_popover.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef ViewItemOnSelected = void Function(BuildContext context, ViewPB view);
typedef ViewItemLeftIconBuilder = Widget Function(
  BuildContext context,
  ViewPB view,
);
typedef ViewItemRightIconsBuilder = List<Widget> Function(
  BuildContext context,
  ViewPB view,
);

enum IgnoreViewType { none, hide, disable }

class ViewItem extends StatelessWidget {
  const ViewItem({
    super.key,
    required this.view,
    this.parentView,
    required this.spaceType,
    required this.level,
    this.leftPadding = 10,
    required this.onSelected,
    this.onTertiarySelected,
    this.isFirstChild = false,
    this.isDraggable = true,
    required this.isFeedback,
    this.height = HomeSpaceViewSizes.viewHeight,
    this.isHoverEnabled = false,
    this.isPlaceholder = false,
    this.isHovered,
    this.shouldRenderChildren = true,
    this.leftIconBuilder,
    this.rightIconsBuilder,
    this.shouldLoadChildViews = true,
    this.isExpandedNotifier,
    this.extendBuilder,
    this.disableSelectedStatus,
    this.shouldIgnoreView,
    this.engagedInExpanding = false,
    this.enableRightClickContext = false,
  });

  final ViewPB view;
  final ViewPB? parentView;

  final FolderSpaceType spaceType;

  // indicate the level of the view item
  // used to calculate the left padding
  final int level;

  // the left padding of the view item for each level
  // the left padding of the each level = level * leftPadding
  final double leftPadding;

  // Selected by normal conventions
  final ViewItemOnSelected onSelected;

  // Selected by middle mouse button
  final ViewItemOnSelected? onTertiarySelected;

  // used for indicating the first child of the parent view, so that we can
  // add top border to the first child
  final bool isFirstChild;

  // it should be false when it's rendered as feedback widget inside DraggableItem
  final bool isDraggable;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final double height;

  final bool isHoverEnabled;

  // all the view movement depends on the [ViewItem] widget, so we have to add a
  // placeholder widget to receive the drop event when moving view across sections.
  final bool isPlaceholder;

  // used for control the expand/collapse icon
  final ValueNotifier<bool>? isHovered;

  // render the child views of the view
  final bool shouldRenderChildren;

  // custom the left icon widget, if it's null, the default expand/collapse icon will be used
  final ViewItemLeftIconBuilder? leftIconBuilder;

  // custom the right icon widget, if it's null, the default ... and + button will be used
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  final bool shouldLoadChildViews;
  final PropertyValueNotifier<bool>? isExpandedNotifier;

  final List<Widget> Function(ViewPB view)? extendBuilder;

  // disable the selected status of the view item
  final bool? disableSelectedStatus;

  // ignore the views when rendering the child views
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;

  /// Whether to add right-click to show the view action context menu
  ///
  final bool enableRightClickContext;

  /// to record the ViewBlock which is expanded or collapsed
  final bool engagedInExpanding;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ViewBloc(
        view: view,
        shouldLoadChildViews: shouldLoadChildViews,
        engagedInExpanding: engagedInExpanding,
      )..add(const ViewEvent.initial()),
      child: BlocConsumer<ViewBloc, ViewState>(
        listenWhen: (p, c) =>
            c.lastCreatedView != null &&
            p.lastCreatedView?.id != c.lastCreatedView!.id,
        listener: (context, state) =>
            context.read<TabsBloc>().openPlugin(state.lastCreatedView!),
        builder: (context, state) {
          // filter the child views that should be ignored
          List<ViewPB> childViews = state.view.childViews;
          if (shouldIgnoreView != null) {
            childViews = childViews
                .where((v) => shouldIgnoreView!(v) != IgnoreViewType.hide)
                .toList();
          }

          final Widget child = InnerViewItem(
            view: state.view,
            parentView: parentView,
            childViews: childViews,
            spaceType: spaceType,
            level: level,
            leftPadding: leftPadding,
            showActions: state.isEditing,
            enableRightClickContext: enableRightClickContext,
            isExpanded: state.isExpanded,
            disableSelectedStatus: disableSelectedStatus,
            onSelected: onSelected,
            onTertiarySelected: onTertiarySelected,
            isFirstChild: isFirstChild,
            isDraggable: isDraggable,
            isFeedback: isFeedback,
            height: height,
            isHoverEnabled: isHoverEnabled,
            isPlaceholder: isPlaceholder,
            isHovered: isHovered,
            shouldRenderChildren: shouldRenderChildren,
            leftIconBuilder: leftIconBuilder,
            rightIconsBuilder: rightIconsBuilder,
            isExpandedNotifier: isExpandedNotifier,
            extendBuilder: extendBuilder,
            shouldIgnoreView: shouldIgnoreView,
            engagedInExpanding: engagedInExpanding,
          );

          if (shouldIgnoreView?.call(view) == IgnoreViewType.disable) {
            return Opacity(
              opacity: 0.5,
              child: FlowyTooltip(
                message: LocaleKeys.space_cannotMovePageToDatabase.tr(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.forbidden,
                  child: IgnorePointer(child: child),
                ),
              ),
            );
          }

          return child;
        },
      ),
    );
  }
}

// TODO: We shouldn't have local global variables
bool _isDragging = false;

class InnerViewItem extends StatefulWidget {
  const InnerViewItem({
    super.key,
    required this.view,
    required this.parentView,
    required this.childViews,
    required this.spaceType,
    this.isDraggable = true,
    this.isExpanded = true,
    required this.level,
    required this.leftPadding,
    required this.showActions,
    this.enableRightClickContext = false,
    required this.onSelected,
    this.onTertiarySelected,
    this.isFirstChild = false,
    required this.isFeedback,
    required this.height,
    this.isHoverEnabled = true,
    this.isPlaceholder = false,
    this.isHovered,
    this.shouldRenderChildren = true,
    required this.leftIconBuilder,
    required this.rightIconsBuilder,
    this.isExpandedNotifier,
    required this.extendBuilder,
    this.disableSelectedStatus,
    this.engagedInExpanding = false,
    required this.shouldIgnoreView,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final List<ViewPB> childViews;
  final FolderSpaceType spaceType;

  final bool isDraggable;
  final bool isExpanded;
  final bool isFirstChild;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final int level;
  final double leftPadding;

  final bool showActions;
  final bool enableRightClickContext;
  final ViewItemOnSelected onSelected;
  final ViewItemOnSelected? onTertiarySelected;
  final double height;

  final bool isHoverEnabled;
  final bool isPlaceholder;
  final bool? disableSelectedStatus;
  final ValueNotifier<bool>? isHovered;
  final bool shouldRenderChildren;
  final ViewItemLeftIconBuilder? leftIconBuilder;
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  final PropertyValueNotifier<bool>? isExpandedNotifier;
  final List<Widget> Function(ViewPB view)? extendBuilder;
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;
  final bool engagedInExpanding;

  @override
  State<InnerViewItem> createState() => _InnerViewItemState();
}

class _InnerViewItemState extends State<InnerViewItem> {
  @override
  void initState() {
    super.initState();
    widget.isExpandedNotifier?.addListener(_collapseAllPages);
  }

  @override
  void dispose() {
    widget.isExpandedNotifier?.removeListener(_collapseAllPages);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (context, value, _) {
        final isSelected = value?.id == widget.view.id;
        return SingleInnerViewItem(
          view: widget.view,
          parentView: widget.parentView,
          level: widget.level,
          showActions: widget.showActions,
          enableRightClickContext: widget.enableRightClickContext,
          spaceType: widget.spaceType,
          onSelected: widget.onSelected,
          onTertiarySelected: widget.onTertiarySelected,
          isExpanded: widget.isExpanded,
          isDraggable: widget.isDraggable,
          leftPadding: widget.leftPadding,
          isFeedback: widget.isFeedback,
          height: widget.height,
          isPlaceholder: widget.isPlaceholder,
          isHovered: widget.isHovered,
          leftIconBuilder: widget.leftIconBuilder,
          rightIconsBuilder: widget.rightIconsBuilder,
          extendBuilder: widget.extendBuilder,
          disableSelectedStatus: widget.disableSelectedStatus,
          shouldIgnoreView: widget.shouldIgnoreView,
          isSelected: isSelected,
        );
      },
    );

    // if the view is expanded and has child views, render its child views
    if (widget.isExpanded &&
        widget.shouldRenderChildren &&
        widget.childViews.isNotEmpty) {
      final children = widget.childViews.map((childView) {
        return ViewItem(
          key: ValueKey('${widget.spaceType.name} ${childView.id}'),
          parentView: widget.view,
          spaceType: widget.spaceType,
          isFirstChild: childView.id == widget.childViews.first.id,
          view: childView,
          level: widget.level + 1,
          enableRightClickContext: widget.enableRightClickContext,
          onSelected: widget.onSelected,
          onTertiarySelected: widget.onTertiarySelected,
          isDraggable: widget.isDraggable,
          disableSelectedStatus: widget.disableSelectedStatus,
          leftPadding: widget.leftPadding,
          isFeedback: widget.isFeedback,
          isPlaceholder: widget.isPlaceholder,
          isHovered: widget.isHovered,
          leftIconBuilder: widget.leftIconBuilder,
          rightIconsBuilder: widget.rightIconsBuilder,
          extendBuilder: widget.extendBuilder,
          shouldIgnoreView: widget.shouldIgnoreView,
          engagedInExpanding: widget.engagedInExpanding,
        );
      }).toList();

      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [child, ...children],
      );
    }

    // wrap the child with DraggableItem if isDraggable is true
    if ((widget.isDraggable || widget.isPlaceholder) &&
        !isReferencedDatabaseView(widget.view, widget.parentView)) {
      child = DraggableViewItem(
        isFirstChild: widget.isFirstChild,
        view: widget.view,
        onDragging: (isDragging) => _isDragging = isDragging,
        onMove: widget.isPlaceholder
            ? (from, to) => moveViewCrossSpace(
                  context,
                  null,
                  widget.view,
                  widget.parentView,
                  widget.spaceType,
                  from,
                  to.parentViewId,
                )
            : null,
        feedback: (context) => Container(
          width: 250,
          decoration: BoxDecoration(
            color: Brightness.light == Theme.of(context).brightness
                ? Colors.white
                : Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ViewItem(
            view: widget.view,
            parentView: widget.parentView,
            spaceType: widget.spaceType,
            level: widget.level,
            onSelected: widget.onSelected,
            onTertiarySelected: widget.onTertiarySelected,
            isDraggable: false,
            leftPadding: widget.leftPadding,
            isFeedback: true,
            enableRightClickContext: widget.enableRightClickContext,
            leftIconBuilder: widget.leftIconBuilder,
            rightIconsBuilder: widget.rightIconsBuilder,
            extendBuilder: widget.extendBuilder,
            shouldIgnoreView: widget.shouldIgnoreView,
          ),
        ),
        child: child,
      );
    } else {
      // keep the same height of the DraggableItem
      child = Padding(
        padding: const EdgeInsets.only(top: kDraggableViewItemDividerHeight),
        child: child,
      );
    }

    return child;
  }

  void _collapseAllPages() {
    if (widget.isExpandedNotifier?.value == true) {
      context.read<ViewBloc>().add(const ViewEvent.collapseAllPages());
    }
  }
}

class SingleInnerViewItem extends StatefulWidget {
  const SingleInnerViewItem({
    super.key,
    required this.view,
    required this.parentView,
    required this.isExpanded,
    required this.level,
    required this.leftPadding,
    this.isDraggable = true,
    required this.spaceType,
    required this.showActions,
    this.enableRightClickContext = false,
    required this.onSelected,
    this.onTertiarySelected,
    required this.isFeedback,
    required this.height,
    this.isHoverEnabled = true,
    this.isPlaceholder = false,
    this.isHovered,
    required this.leftIconBuilder,
    required this.rightIconsBuilder,
    required this.extendBuilder,
    required this.disableSelectedStatus,
    required this.shouldIgnoreView,
    required this.isSelected,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final bool isExpanded;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final int level;
  final double leftPadding;

  final bool isDraggable;
  final bool showActions;
  final bool enableRightClickContext;
  final ViewItemOnSelected onSelected;
  final ViewItemOnSelected? onTertiarySelected;
  final FolderSpaceType spaceType;
  final double height;

  final bool isHoverEnabled;
  final bool isPlaceholder;
  final bool? disableSelectedStatus;
  final ValueNotifier<bool>? isHovered;
  final ViewItemLeftIconBuilder? leftIconBuilder;
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  final List<Widget> Function(ViewPB view)? extendBuilder;
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;
  final bool isSelected;

  @override
  State<SingleInnerViewItem> createState() => _SingleInnerViewItemState();
}

class _SingleInnerViewItemState extends State<SingleInnerViewItem> {
  final controller = PopoverController();
  final viewMoreActionController = PopoverController();

  bool isIconPickerOpened = false;

  final _doubleClickDetector = DoubleClickDetector();

  // [fork:sidebar-improvements] Phase 2: while true, the row's name text is
  // replaced by an InlineRenameField (thin frame, edits in place).
  bool _isRenaming = false;

  void _handleViewTap() {
    if (_isRenaming) {
      return;
    }
    if (_doubleClickDetector.isDoubleClick(DateTime.now())) {
      // Second click of a double-click: rename in place instead of
      // re-opening the view (the swallowed second click doubles as the old
      // click throttle).
      setState(() => _isRenaming = true);
      return;
    }
    widget.onSelected(context, widget.view);
  }

  void _commitRename(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && trimmed != widget.view.name) {
      context.read<ViewBloc>().add(ViewEvent.rename(trimmed));
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
    bool isSelected = widget.isSelected;

    if (widget.disableSelectedStatus == true) {
      isSelected = false;
    }

    if (widget.isPlaceholder) {
      return const SizedBox(height: 4, width: double.infinity);
    }

    if (widget.isFeedback || !widget.isHoverEnabled) {
      return _buildViewItem(
        false,
        !widget.isHoverEnabled ? isSelected : false,
      );
    }

    return FlowyHover(
      style: HoverStyle(hoverColor: Theme.of(context).colorScheme.secondary),
      resetHoverOnRebuild: widget.showActions || !isIconPickerOpened,
      buildWhenOnHover: () =>
          !widget.showActions && !_isDragging && !isIconPickerOpened,
      isSelected: () => widget.showActions || isSelected,
      builder: (_, onHover) => _buildViewItem(onHover, isSelected),
    );
  }

  Widget _buildViewItem(bool onHover, [bool isSelected = false]) {
    // [fork:folder] Signal 3 of the folder/page distinction: a folder's name
    // carries more weight than a page's, reinforcing "this is a heading for
    // what's below". Spaces are heavier still (semibold), so the sidebar reads
    // space > folder > page by weight alone.
    final name = widget.view.isFolder
        ? FlowyText.medium(
            widget.view.nameOrDefault,
            overflow: TextOverflow.ellipsis,
            fontSize: 14.0,
            figmaLineHeight: 18.0,
          )
        : FlowyText.regular(
            widget.view.nameOrDefault,
            overflow: TextOverflow.ellipsis,
            fontSize: 14.0,
            figmaLineHeight: 18.0,
          );
    final children = [
      const HSpace(2),
      // expand icon or placeholder
      widget.leftIconBuilder?.call(context, widget.view) ?? _buildLeftIcon(),
      const HSpace(2),
      // icon
      _buildViewIconButton(context),
      const HSpace(6),
      // title — swapped for an in-place editor while renaming
      Expanded(
        child: _isRenaming
            ? InlineRenameField(
                initialName: widget.view.nameOrDefault,
                onSubmitted: _commitRename,
                onDismissed: _stopRenaming,
              )
            : widget.extendBuilder != null
                ? Row(
                    children: [
                      Flexible(child: name),
                      ...widget.extendBuilder!(widget.view),
                    ],
                  )
                : name,
      ),
    ];

    // hover action
    if (widget.showActions || onHover) {
      if (widget.rightIconsBuilder != null) {
        children.addAll(widget.rightIconsBuilder!(context, widget.view));
      } else {
        // + button first, ··· last: the more-actions button must stay the
        // outermost icon (farthest from the view name) — see
        // specs/sidebar-improvements.md.
        // only support add button for document layout
        if (widget.view.layout == ViewLayoutPB.Document) {
          // + button
          children.add(_buildViewAddButton(context));
          children.add(const HSpace(8.0));
        }
        // ··· more action button
        children.add(
          _buildViewMoreActionButton(
            context,
            viewMoreActionController,
            (_) => FlowyTooltip(
              message: LocaleKeys.menuAppHeader_moreButtonToolTip.tr(),
              child: FlowyIconButton(
                width: 24,
                icon: const FlowySvg(FlowySvgs.workspace_three_dots_s),
                onPressed: viewMoreActionController.show,
              ),
            ),
          ),
        );
        children.add(const HSpace(4.0));
      }
    }

    final child = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _handleViewTap,
      onTertiaryTapDown: (_) =>
          widget.onTertiarySelected?.call(context, widget.view),
      child: SizedBox(
        height: widget.height,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: widget.level * widget.leftPadding,
          ),
          child: Listener(
            onPointerDown: (event) {
              if (event.buttons == kSecondaryMouseButton &&
                  widget.enableRightClickContext) {
                viewMoreActionController.showAt(
                  // We add some horizontal offset
                  event.position + const Offset(4, 0),
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(children: children),
          ),
        ),
      ),
    );

    if (isSelected) {
      final popoverController = getIt<RenameViewBloc>().state.controller;
      return AppFlowyPopover(
        controller: popoverController,
        triggerActions: PopoverTriggerFlags.none,
        offset: const Offset(0, 5),
        direction: sidebarPopoverDirection(
          context,
          context.watch<AppearanceSettingsCubit>().state.sidebarDockSide,
        ),
        popupBuilder: (_) => RenameViewPopover(
          view: widget.view,
          name: widget.view.name,
          emoji: widget.view.icon.toEmojiIconData(),
          popoverController: popoverController,
          showIconChanger: false,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _buildViewIconButton(BuildContext context) {
    final iconData = widget.view.icon.toEmojiIconData();
    final icon = iconData.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: iconData,
            emojiSize: 16.0,
            lineHeight: 18.0 / 16.0,
          )
        // [fork:folder] A folder's default icon is a plain monochrome folder
        // glyph at full strength — NOT the filled rounded-square badge tried
        // first, which read as "a coloured rectangle" next to emoji-bearing
        // pages (user feedback 2026-07-25). Full strength rather than the
        // pages' 0.6 opacity is deliberate: a container should sit slightly
        // forward of its contents. A user-chosen emoji still wins.
        : widget.view.isFolder
            ? FlowySvg(
                FlowySvgs.folder_m,
                size: const Size.square(16),
                // Contextual, not fixed: onSurface is light on a dark theme and
                // dark on a light one, so the glyph stays legible either way.
                color: Theme.of(context).colorScheme.onSurface,
              )
            : Opacity(opacity: 0.6, child: widget.view.defaultIcon());

    final Widget child = AppFlowyPopover(
      offset: const Offset(20, 0),
      controller: controller,
      direction: PopoverDirection.rightWithCenterAligned,
      constraints: BoxConstraints.loose(const Size(364, 356)),
      margin: const EdgeInsets.all(0),
      onClose: () => setState(() => isIconPickerOpened = false),
      child: GestureDetector(
        // prevent the tap event from being passed to the parent widget
        onTap: () {},
        child: FlowyTooltip(
          message: LocaleKeys.document_plugins_cover_changeIcon.tr(),
          child: SizedBox(width: 16.0, child: icon),
        ),
      ),
      popupBuilder: (context) {
        isIconPickerOpened = true;
        return FlowyIconEmojiPicker(
          initialType: iconData.type.toPickerTabType(),
          // [fork:folder] Folders get the icon set only (user decision
          // 2026-07-25), exactly like spaces. Signal 2 of the folder/page
          // distinction is "monochrome glyph vs colourful emoji" — allowing an
          // emoji on a folder would defeat it.
          tabs: widget.view.isFolder
              ? const [PickerTabType.icon]
              : const [
                  PickerTabType.emoji,
                  PickerTabType.icon,
                  PickerTabType.custom,
                ],
          documentId: widget.view.id,
          onSelectedEmoji: (r) {
            ViewBackendService.updateViewIcon(
              view: widget.view,
              viewIcon: r.data,
            );
            if (!r.keepOpen) controller.close();
          },
        );
      },
    );

    if (widget.view.isLocked) {
      return LockPageButtonWrapper(
        child: child,
      );
    }

    return child;
  }

  // > button or · button
  // show > if the view is expandable.
  // show · if the view can't contain child views.
  Widget _buildLeftIcon() {
    return ViewItemDefaultLeftIcon(
      view: widget.view,
      parentView: widget.parentView,
      isExpanded: widget.isExpanded,
      leftPadding: widget.leftPadding,
      isHovered: widget.isHovered,
    );
  }

  // + button
  Widget _buildViewAddButton(BuildContext context) {
    return FlowyTooltip(
      message: LocaleKeys.menuAppHeader_addPageTooltip.tr(),
      child: ViewAddButton(
        parentViewId: widget.view.id,
        onEditing: (value) =>
            context.read<ViewBloc>().add(ViewEvent.setIsEditing(value)),
        onSelected: _onSelected,
        // [fork:folder] Only a folder row offers "New folder" — folders nest in
        // spaces and in other folders, never under an ordinary page
        // (specs/folder.md). A folder can't exist inside Temporary, so any
        // folder row is already outside it and needs no further check.
        onCreateFolder: widget.view.isFolder ? _onCreateFolder : null,
      ),
    );
  }

  /// [fork:folder] Create a nested folder inside this folder.
  ///
  /// Goes straight through [PageFolder.create] rather than
  /// `ViewEvent.createView`, because the folder flag has to be written by a
  /// follow-up `updateView` — `createView` cannot set `View.extra`.
  Future<void> _onCreateFolder() async {
    final folder = await PageFolder.create(
      parentViewId: widget.view.id,
      name: LocaleKeys.sideBar_untitledFolder.tr(),
    );
    if (!mounted || folder == null) {
      return;
    }
    // Expand this folder so the new row is visible.
    context.read<ViewBloc>().add(const ViewEvent.setIsExpanded(true));
  }

  void _onSelected(
    PluginBuilder pluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) {
    final viewBloc = context.read<ViewBloc>();

    // the name of new document should be empty
    final viewName = ![ViewLayoutPB.Document, ViewLayoutPB.Chat]
            .contains(pluginBuilder.layoutType)
        ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
        : '';
    viewBloc.add(
      ViewEvent.createView(
        viewName,
        pluginBuilder.layoutType!,
        openAfterCreated: openAfterCreated,
        section: widget.spaceType.toViewSectionPB,
      ),
    );

    viewBloc.add(const ViewEvent.setIsExpanded(true));
  }

  // ··· more action button
  Widget _buildViewMoreActionButton(
    BuildContext context,
    PopoverController controller,
    Widget Function(PopoverController) buildChild,
  ) {
    return BlocProvider(
      create: (context) => SpaceBloc(
        userProfile: context.read<SpaceBloc>().userProfile,
        workspaceId: context.read<SpaceBloc>().workspaceId,
      )..add(const SpaceEvent.initial(openFirstPage: false)),
      child: ViewMoreActionPopover(
        view: widget.view,
        controller: controller,
        isExpanded: widget.isExpanded,
        spaceType: widget.spaceType,
        onEditing: (value) =>
            context.read<ViewBloc>().add(ViewEvent.setIsEditing(value)),
        buildChild: buildChild,
        onAction: (action, data) async {
          switch (action) {
            case ViewMoreActionType.favorite:
            case ViewMoreActionType.unFavorite:
              context
                  .read<FavoriteBloc>()
                  .add(FavoriteEvent.toggle(widget.view));
              break;
            case ViewMoreActionType.rename:
              unawaited(
                showAFTextFieldDialog(
                  context: context,
                  title: LocaleKeys.disclosureAction_rename.tr(),
                  initialValue: widget.view.nameOrDefault,
                  onConfirm: (newValue) {
                    context.read<ViewBloc>().add(ViewEvent.rename(newValue));
                  },
                  maxLength: 256,
                ),
              );
              break;
            case ViewMoreActionType.delete:
              // Deleting something that contains other pages asks first, and offers to
              // move the contents out instead. A page with nothing inside it is deleted
              // with no dialog, exactly as before. The published-page warning that used
              // to live here moved inside, so the two can be shown together rather than
              // one silently replacing the other. See specs/delete-and-trash.md.
              final viewBloc = context.read<ViewBloc>();
              await showDeleteViewDialog(
                context: context,
                view: widget.view,
                onDelete: () => viewBloc.add(const ViewEvent.delete()),
              );
              break;
            case ViewMoreActionType.duplicate:
              context.read<ViewBloc>().add(const ViewEvent.duplicate());
              break;
            case ViewMoreActionType.openInNewTab:
              context.read<TabsBloc>().openTab(widget.view);
              break;
            case ViewMoreActionType.collapseAllPages:
              context.read<ViewBloc>().add(const ViewEvent.collapseAllPages());
              break;
            case ViewMoreActionType.changeIcon:
              if (data is! SelectedEmojiIconResult) {
                return;
              }
              await ViewBackendService.updateViewIcon(
                view: widget.view,
                viewIcon: data.data,
              );
              break;
            case ViewMoreActionType.moveTo:
              final value = data;
              if (value is! (ViewPB, ViewPB)) {
                return;
              }
              final space = value.$1;
              final target = value.$2;
              moveViewCrossSpace(
                context,
                space,
                widget.view,
                widget.parentView,
                widget.spaceType,
                widget.view,
                target.id,
              );
            default:
              throw UnsupportedError('$action is not supported');
          }
        },
      ),
    );
  }
}

class _DotIconWidget extends StatelessWidget {
  const _DotIconWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).iconTheme.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// workaround: we should use view.isEndPoint or something to check if the view can contain child views. But currently, we don't have that field.
bool isReferencedDatabaseView(ViewPB view, ViewPB? parentView) {
  if (parentView == null) {
    return false;
  }
  return view.layout.isDatabaseView && parentView.layout.isDatabaseView;
}

void moveViewCrossSpace(
  BuildContext context,
  ViewPB? toSpace,
  ViewPB view,
  ViewPB? parentView,
  FolderSpaceType spaceType,
  ViewPB from,
  String toId,
) {
  if (isReferencedDatabaseView(view, parentView)) {
    return;
  }

  if (from.id == toId) {
    return;
  }

  final currentSpace = context.read<SpaceBloc>().state.currentSpace;
  if (currentSpace != null &&
      toSpace != null &&
      currentSpace.id != toSpace.id) {
    Log.info(
      'Move view(${from.name}) to another space(${toSpace.name}), unpublish the view',
    );
    context.read<ViewBloc>().add(const ViewEvent.unpublish(sync: false));

    switchToSpaceNotifier.value = toSpace;
  }

  context.read<ViewBloc>().add(ViewEvent.move(from, toId, null, null, null));
}

class ViewItemDefaultLeftIcon extends StatelessWidget {
  const ViewItemDefaultLeftIcon({
    super.key,
    required this.view,
    required this.parentView,
    required this.isExpanded,
    required this.leftPadding,
    required this.isHovered,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final bool isExpanded;
  final double leftPadding;
  final ValueNotifier<bool>? isHovered;

  @override
  Widget build(BuildContext context) {
    if (isReferencedDatabaseView(view, parentView)) {
      return const _DotIconWidget();
    }

    // [fork:folder] Signal 1, and the strongest: a folder ALWAYS shows its
    // disclosure caret, even when empty, because the caret is structural — it
    // says "things go inside me". Pages show one only when they actually have
    // children. Same convention as Finder, VS Code and Notion, so it needs no
    // learning, and it gives an empty folder something to show.
    if (context.read<ViewBloc>().state.view.childViews.isEmpty &&
        !view.isFolder) {
      return HSpace(leftPadding);
    }

    // The collapsed-state caret points toward where expanding reveals
    // more content, so it mirrors along with the sidebar's own
    // ambient Directionality (set once, at the sidebar root).
    final isRTL = Directionality.of(context) == ui.TextDirection.rtl;
    final child = FlowyHover(
      child: GestureDetector(
        child: Transform.flip(
          flipX: isRTL,
          child: FlowySvg(
            isExpanded
                ? FlowySvgs.view_item_expand_s
                : FlowySvgs.view_item_unexpand_s,
            size: const Size.square(16.0),
          ),
        ),
        onTap: () =>
            context.read<ViewBloc>().add(ViewEvent.setIsExpanded(!isExpanded)),
      ),
    );

    if (isHovered != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: isHovered!,
        builder: (_, isHovered, child) =>
            Opacity(opacity: isHovered ? 1.0 : 0.0, child: child),
        child: child,
      );
    }

    return child;
  }
}
