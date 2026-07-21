import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarNewPageButton extends StatefulWidget {
  const SidebarNewPageButton({
    super.key,
  });

  @override
  State<SidebarNewPageButton> createState() => _SidebarNewPageButtonState();
}

class _SidebarNewPageButtonState extends State<SidebarNewPageButton> {
  @override
  void initState() {
    super.initState();
    createNewPageNotifier.addListener(_createNewPage);
  }

  @override
  void dispose() {
    createNewPageNotifier.removeListener(_createNewPage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: HomeSizes.newPageSectionHeight,
      child: FlowyButton(
        onTap: () async => _createNewPage(),
        leftIcon: const FlowySvg(
          FlowySvgs.new_app_m,
          blendMode: null,
        ),
        leftIconSize: const Size.square(24.0),
        margin: const EdgeInsets.only(left: 4.0),
        iconPadding: 8.0,
        text: FlowyText.regular(
          LocaleKeys.newPageText.tr(),
          lineHeight: 1.15,
        ),
      ),
    );
  }

  Future<void> _createNewPage() async {
    // if the workspace is collaborative, create the view in the private section by default.
    final section = context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn
        ? ViewSectionPB.Private
        : ViewSectionPB.Public;
    final spaceState = context.read<SpaceBloc>().state;
    if (spaceState.spaces.isNotEmpty) {
      // [fork:sidebar-improvements] Phase 4: with every space visible in the
      // sidebar, the new page goes to the space of the page currently open
      // (falling back to the bloc's current space, then the first space) —
      // created directly rather than via SpaceEvent.createPage, which can
      // only target the bloc's currentSpace.
      final target = await _resolveTargetSpace(spaceState);
      if (!mounted || target == null) {
        return;
      }
      final result = await ViewBackendService.createView(
        name: '',
        layoutType: ViewLayoutPB.Document,
        parentViewId: target.id,
        index: 0,
        openAfterCreate: true,
      );
      result.fold(
        (view) {
          // Reveal the target space so the new page is visible in the list.
          switchToSpaceNotifier.value = target;
          getIt<TabsBloc>().add(
            TabsEvent.openPlugin(plugin: view.plugin(), view: view),
          );
        },
        (error) => Log.error('SidebarNewPageButton createPage: $error'),
      );
    } else {
      context.read<SidebarSectionsBloc>().add(
            SidebarSectionsEvent.createRootViewInSection(
              name: '',
              viewSection: section,
              index: 0,
            ),
          );
    }
  }

  Future<ViewPB?> _resolveTargetSpace(SpaceState spaceState) async {
    final latestView = getIt<MenuSharedState>().latestOpenView;
    if (latestView != null) {
      final ancestors =
          await ViewBackendService.getViewAncestors(latestView.id);
      final space = ancestors.fold(
        (ancestors) =>
            ancestors.items.firstWhereOrNull((ancestor) => ancestor.isSpace),
        (_) => null,
      );
      if (space != null) {
        final match =
            spaceState.spaces.firstWhereOrNull((s) => s.id == space.id);
        if (match != null) {
          return match;
        }
      }
    }
    return spaceState.currentSpace ??
        (spaceState.spaces.isEmpty ? null : spaceState.spaces.first);
  }
}
