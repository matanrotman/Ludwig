import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/create_space_popup.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [fork:sidebar-improvements] Phase 4: "New Space" as its own row directly
/// below "New Page" (the user's placement choice) — replacing the create
/// button that lived inside the retired space-switcher popover.
///
/// Icon is 16pt vs New Page's 24pt, so margins/padding are chosen to align
/// both rows' text: 4 + 24 + 8 = 8 + 16 + 12 = 36.
class SidebarNewSpaceButton extends StatelessWidget {
  const SidebarNewSpaceButton({super.key});

  @override
  Widget build(BuildContext context) {
    // No spaces means a workspace without the space concept — creating one
    // here isn't supported (matches the old popover, which only existed
    // when spaces did).
    if (context.watch<SpaceBloc>().state.spaces.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: HomeSizes.newPageSectionHeight,
      child: FlowyButton(
        onTap: () => _showCreateSpaceDialog(context),
        leftIcon: const FlowySvg(FlowySvgs.space_add_s),
        margin: const EdgeInsets.only(left: 8.0),
        iconPadding: 12.0,
        text: FlowyText.regular(
          LocaleKeys.space_createNewSpace.tr(),
          lineHeight: 1.15,
        ),
      ),
    );
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
}
