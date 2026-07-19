// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// The ribbon itself: a tabbed formatting strip pinned above the document.
//
// Pinned, not scrolling — it is mounted as a sibling above the editor in
// `document_page.dart`, deliberately NOT via the editor's `header:` parameter,
// which scrolls away with the document.

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'application/ribbon_settings_cubit.dart';
import 'ribbon_action.dart';
import 'ribbon_collapse_command.dart';
import 'ribbon_group_view.dart';
import 'ribbon_shortcuts.dart';

/// Height of the tab bar row. The groups row sizes to its content.
const double _kTabBarHeight = 30.0;

class RibbonMenu extends StatelessWidget {
  const RibbonMenu({
    super.key,
    required this.editorState,
    required this.tabs,
    this.shortcuts,
  });

  final EditorState editorState;
  final List<RibbonTab> tabs;
  final List<CommandShortcutEvent>? shortcuts;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = AppFlowyTheme.of(context);

    // The ribbon is deliberately ALWAYS left-to-right, like Word's — and like
    // the sidebar, it belongs to the application frame rather than to the page.
    // Even though its buttons act on the current page, flipping the whole strip
    // when a page's direction changes would move every control under the user's
    // hands. Decided with the user 2026-07-19; see specs/ribbon-menu.md.
    //
    // Note this is NOT the same question as the document's own margins, which
    // DO follow the page (see `EditorStyleCustomizer.documentPaddingFor`).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: BlocBuilder<RibbonSettingsCubit, RibbonSettingsState>(
        builder: (context, settings) {
          // Avoid flashing the expanded default before the stored state loads.
          if (!settings.isLoaded) {
            return const SizedBox.shrink();
          }

          final activeTab = tabs.firstWhere(
            (t) => t.id == settings.activeTabId,
            orElse: () => tabs.first,
          );

          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surfaceColorScheme.primary,
              border: Border(
                bottom: BorderSide(color: theme.borderColorScheme.primary),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RibbonTabBar(
                  tabs: tabs,
                  activeTabId: activeTab.id,
                  isCollapsed: settings.isCollapsed,
                ),
                // Rebuilding the groups on every selection change is what keeps
                // button enabled/highlighted states honest as the cursor moves.
                if (!settings.isCollapsed)
                  ValueListenableBuilder<Selection?>(
                    valueListenable: editorState.selectionNotifier,
                    builder: (context, _, __) => _RibbonGroupsRow(
                      tab: activeTab,
                      editorState: editorState,
                      shortcuts: shortcuts,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RibbonGroupsRow extends StatelessWidget {
  const _RibbonGroupsRow({
    required this.tab,
    required this.editorState,
    this.shortcuts,
  });

  final RibbonTab tab;
  final EditorState editorState;
  final List<CommandShortcutEvent>? shortcuts;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8.0,
        vertical: 6.0,
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < tab.groups.length; i++)
              RibbonGroupView(
                key: ValueKey(tab.groups[i].id),
                group: tab.groups[i],
                editorState: editorState,
                shortcuts: shortcuts,
                showDivider: i != tab.groups.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _RibbonTabBar extends StatelessWidget {
  const _RibbonTabBar({
    required this.tabs,
    required this.activeTabId,
    required this.isCollapsed,
  });

  final List<RibbonTab> tabs;
  final String activeTabId;
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return SizedBox(
      height: _kTabBarHeight,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(start: 8.0),
              children: [
                for (final tab in tabs)
                  _RibbonTabLabel(
                    tab: tab,
                    isActive: tab.id == activeTabId,
                    isCollapsed: isCollapsed,
                  ),
              ],
            ),
          ),
          _CollapseChevron(isCollapsed: isCollapsed),
          SizedBox(width: theme.spacing.s),
        ],
      ),
    );
  }
}

class _RibbonTabLabel extends StatelessWidget {
  const _RibbonTabLabel({
    required this.tab,
    required this.isActive,
    required this.isCollapsed,
  });

  final RibbonTab tab;
  final bool isActive;
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return GestureDetector(
      onTap: () {
        final cubit = context.read<RibbonSettingsCubit>();
        // Clicking the tab you are already on, while collapsed, expands —
        // matching how Word's collapsed ribbon behaves.
        if (isActive && isCollapsed) {
          cubit.setCollapsed(false);
        } else {
          cubit.setActiveTab(tab.id);
          if (isCollapsed) {
            cubit.setCollapsed(false);
          }
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2.0,
                color: isActive && !isCollapsed
                    ? theme.borderColorScheme.themeThick
                    : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            tab.label,
            style: theme.textStyle.body.standard(
              color: isActive
                  ? theme.textColorScheme.primary
                  : theme.textColorScheme.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapseChevron extends StatelessWidget {
  const _CollapseChevron({required this.isCollapsed});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    // Same rule as every ribbon button: show the binding that is actually in
    // force, not a hardcoded one.
    final shortcut = resolveShortcutLabel(kToggleRibbonCommandId);
    final label = isCollapsed ? 'Expand the ribbon' : 'Collapse the ribbon';

    return FlowyTooltip(
      message: shortcut == null ? label : '$label  $shortcut',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.read<RibbonSettingsCubit>().toggleCollapsed(),
          child: SizedBox(
            width: 28.0,
            height: 28.0,
            child: Center(
              child: FlowySvg(
                isCollapsed ? FlowySvgs.arrow_down_s : FlowySvgs.arrow_up_s,
                size: const Size.square(16.0),
                color: theme.iconColorScheme.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
