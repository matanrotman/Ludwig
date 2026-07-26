import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/pad/ephemeral_pad.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/page_folder.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/create_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_drop_target.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_list_header.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show PropertyValueNotifier;
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:sidebar-improvements] Phase 4 (specs/sidebar-improvements.md): every
/// space stacked in the sidebar, each independently expandable with its own
/// caret — replacing the one-space-at-a-time dropdown UI.
///
/// Design notes (why this is app-side only, no SpaceBloc changes):
/// - Expansion state lives here, persisted read-modify-write to the same
///   [KVKeys.expandedViews] map the bloc used — but writing explicit `false`
///   on collapse, so collapsed spaces survive restarts (the bloc's own
///   writer removed the key on collapse, which reads back as expanded).
/// - Page creation goes straight through [ViewBackendService] with an
///   explicit parent space, because [SpaceEvent.createPage] can only target
///   the bloc's currentSpace.
/// - [SpaceEvent.open] is deliberately NOT dispatched when a page in
///   another space is opened (its side effect opens that space's first
///   page, which would hijack cross-space navigation) — the space-follow
///   notifier now just expands the space so the open page is visible.
/// - ⌘/Ctrl+O keeps its meaning ("open the next space's first page") by
///   still dispatching [SpaceEvent.switchToNextSpace].
class SidebarSpaceList extends StatefulWidget {
  const SidebarSpaceList({super.key});

  @override
  State<SidebarSpaceList> createState() => _SidebarSpaceListState();
}

class _SidebarSpaceListState extends State<SidebarSpaceList> {
  /// spaceId → expanded; absent = expanded (the historical default).
  final Map<String, bool> _expanded = {};

  /// Per-space collapse-all-pages triggers (consumed by [SpacePages]).
  final Map<String, PropertyValueNotifier<bool>> _collapseAll = {};

  final ValueNotifier<bool> _pagesHovered = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    unawaited(_loadExpansion());
    switchToTheNextSpace.addListener(_switchToNextSpace);
    switchToSpaceNotifier.addListener(_revealSpace);
  }

  @override
  void dispose() {
    switchToTheNextSpace.removeListener(_switchToNextSpace);
    switchToSpaceNotifier.removeListener(_revealSpace);
    for (final notifier in _collapseAll.values) {
      notifier.dispose();
    }
    _pagesHovered.dispose();
    super.dispose();
  }

  bool _isExpanded(ViewPB space) => _expanded[space.id] ?? true;

  PropertyValueNotifier<bool> _collapseNotifier(String spaceId) =>
      _collapseAll.putIfAbsent(spaceId, () => PropertyValueNotifier(false));

  Future<void> _loadExpansion() async {
    final raw = await getIt<KeyValueStorage>().get(KVKeys.expandedViews);
    if (raw == null || !mounted) {
      return;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        for (final entry in map.entries) {
          if (entry.value is bool) {
            _expanded[entry.key] = entry.value as bool;
          }
        }
      });
    } on FormatException catch (e) {
      Log.warn('SidebarSpaceList: unreadable expandedViews map: $e');
    }
  }

  Future<void> _persistExpansion() async {
    final storage = getIt<KeyValueStorage>();
    final raw = await storage.get(KVKeys.expandedViews);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        // overwrite an unreadable map
      }
    }
    map.addAll(_expanded);
    await storage.set(KVKeys.expandedViews, jsonEncode(map));
  }

  void _toggle(ViewPB space) {
    setState(() => _expanded[space.id] = !_isExpanded(space));
    unawaited(_persistExpansion());
  }

  void _reveal(ViewPB space) {
    if (_isExpanded(space)) {
      return;
    }
    setState(() => _expanded[space.id] = true);
    unawaited(_persistExpansion());
  }

  /// The open page's space changed (page opened via favorites, search,
  /// another space…): make sure that space's tree is visible.
  void _revealSpace() {
    final space = switchToSpaceNotifier.value;
    if (space == null || !mounted) {
      return;
    }
    _reveal(space);
  }

  void _switchToNextSpace() {
    if (!mounted) {
      return;
    }
    context.read<SpaceBloc>().add(const SpaceEvent.switchToNextSpace());
  }

  Future<void> _createPage(ViewPB space, ViewLayoutPB layout) async {
    final result = await ViewBackendService.createView(
      name: '',
      layoutType: layout,
      parentViewId: space.id,
      index: 0,
      openAfterCreate: true,
    );
    if (!mounted) {
      return;
    }
    result.fold(
      (view) {
        _reveal(space);
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(plugin: view.plugin(), view: view),
        );
      },
      (error) => Log.error('SidebarSpaceList createPage: $error'),
    );
  }

  /// [fork:folder] Create a folder inside [parent] — see specs/folder.md.
  ///
  /// Unlike [_createPage] this does NOT open the new folder: in Phase 1 a
  /// folder has no page of its own yet (clicking it just expands, exactly as a
  /// space does). It reveals the parent so the new row is visible instead.
  Future<void> _createFolder(ViewPB parent) async {
    final folder = await PageFolder.create(
      parentViewId: parent.id,
      name: LocaleKeys.sideBar_untitledFolder.tr(),
    );
    if (!mounted || folder == null) {
      return;
    }
    _reveal(parent);
  }

  void _showCreateSpaceDialog(BuildContext context) {
    final spaceBloc = context.read<SpaceBloc>();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: BlocProvider.value(
          value: spaceBloc,
          child: const CreateSpacePopup(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentWorkspace =
        context.watch<UserWorkspaceBloc>().state.currentWorkspace;
    return BlocBuilder<SpaceBloc, SpaceState>(
      builder: (context, state) {
        if (state.spaces.isEmpty) {
          return const SizedBox.shrink();
        }
        // [fork:temp-space] Temporary always sorts first (specs/temp-space.md);
        // every other space keeps the user's own order.
        final spaces = TemporarySpace.sortedTemporaryFirst(state.spaces);
        return Column(
          children: [
            for (final space in spaces) ...[
              // [fork:sidebar] The header doubles as a drop target so a page
              // can be dragged onto a space to move it there.
              SpaceDropTarget(
                space: space,
                child: SpaceListHeader(
                  key: ValueKey('space_header_${space.id}'),
                  space: space,
                  isExpanded: _isExpanded(space),
                  onToggle: () => _toggle(space),
                  onAddPage: (layout) => unawaited(_createPage(space, layout)),
                  onCreateFolder: () => unawaited(_createFolder(space)),
                  onCreateNewSpace: () => _showCreateSpaceDialog(context),
                  onCollapseAllPages: () =>
                      _collapseNotifier(space.id).value = true,
                ),
              ),
              if (_isExpanded(space))
                MouseRegion(
                  onEnter: (_) => _pagesHovered.value = true,
                  onExit: (_) => _pagesHovered.value = false,
                  child: SpacePages(
                    key: ValueKey(
                      Object.hashAll([
                        currentWorkspace?.workspaceId ?? '',
                        space.id,
                      ]),
                    ),
                    isExpandedNotifier: _collapseNotifier(space.id),
                    space: space,
                    isHovered: _pagesHovered,
                    // [fork:ephemeral-pad] The pad is a real page living in
                    // Temporary, and this is what keeps it off the sidebar —
                    // see specs/ephemeral-pad.md. Applied to every space, not
                    // just Temporary: cheap, and it means a pad that somehow
                    // ends up elsewhere still can't show up as a stray row.
                    shouldIgnoreView: (view) => EphemeralPad.isPad(view)
                        ? IgnoreViewType.hide
                        : IgnoreViewType.none,
                    onSelected: (context, view) {
                      if (HardwareKeyboard.instance.isControlPressed) {
                        context.read<TabsBloc>().openTab(view);
                      }
                      context.read<TabsBloc>().openPlugin(view);
                    },
                    onTertiarySelected: (context, view) =>
                        context.read<TabsBloc>().openTab(view),
                  ),
                ),
              // [fork:folder] A hairline between spaces. Deliberately a real
              // 1px rule with almost no padding around it (user feedback
              // 2026-07-25: the first version, a FlowyDivider sandwiched
              // between two VSpace(4), "sat too high" and ate vertical space).
              // Omitted after the last space so the list doesn't end on a rule.
              const VSpace(4.0),
              if (space.id != spaces.last.id)
                Divider(
                  height: 1.0,
                  thickness: 1.0,
                  indent: 8.0,
                  endIndent: 8.0,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
            ],
          ],
        );
      },
    );
  }
}
