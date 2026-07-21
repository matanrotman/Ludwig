import 'package:appflowy/features/shared_section/presentation/shared_section.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/favorites/favorite_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/sidebar_space_list.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

class SidebarSpace extends StatelessWidget {
  const SidebarSpace({
    super.key,
    this.isHoverEnabled = true,
    required this.userProfile,
  });

  final bool isHoverEnabled;
  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    final currentWorkspace =
        context.watch<UserWorkspaceBloc>().state.currentWorkspace;
    final currentWorkspaceId = currentWorkspace?.workspaceId ?? '';

    // only show spaces if the user role is member or owner
    final currentUserRole = currentWorkspace?.role;
    final shouldShowSpaces = [
      AFRolePB.Member,
      AFRolePB.Owner,
    ].contains(currentUserRole);

    return ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (_, __, ___) => Provider.value(
        value: userProfile,
        child: Column(
          children: [
            const VSpace(4.0),
            // favorite
            BlocBuilder<FavoriteBloc, FavoriteState>(
              builder: (context, state) {
                if (state.views.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: FavoriteFolder(
                    views: state.views.map((e) => e.item).toList(),
                  ),
                );
              },
            ),

            // shared
            if (FeatureFlag.sharedSection.isOn) ...[
              SharedSection(
                key: ValueKey(currentWorkspaceId),
                workspaceId: currentWorkspaceId,
              ),
            ],

            // spaces
            if (shouldShowSpaces) ...[
              // [fork:sidebar-improvements] Phase 4: every space stacked and
              // independently expandable, replacing the one-space-at-a-time
              // dropdown UI (_Space). See sidebar_space_list.dart.
              const SidebarSpaceList(),
            ],

            const VSpace(200),
          ],
        ),
      ),
    );
  }
}

// [fork:sidebar-improvements] Phase 4: the private _Space widget (one
// current space + switcher popover, plus the hotkey/space-follow listeners)
// was replaced by SidebarSpaceList, which renders every space and hosts
// those listeners itself.
