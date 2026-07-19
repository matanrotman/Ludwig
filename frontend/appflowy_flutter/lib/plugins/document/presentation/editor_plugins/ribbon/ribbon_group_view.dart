// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// One cluster of ribbon buttons with its caption underneath — the arrangement
// chosen at sign-off (2026-07-19) for legibility across the ~30-button Content
// tab. Uses logical (start/end) insets throughout so the strip mirrors in RTL
// without any left/right special-casing.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

import 'ribbon_action.dart';
import 'ribbon_button.dart';

class RibbonGroupView extends StatelessWidget {
  const RibbonGroupView({
    super.key,
    required this.group,
    required this.editorState,
    this.shortcuts,
    this.showDivider = true,
  });

  final RibbonGroup group;
  final EditorState editorState;
  final List<CommandShortcutEvent>? shortcuts;

  /// Trailing separator. Suppressed for the last group in a tab.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in group.actions)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 2.0),
                      child: action.isPopover
                          ? action.builder!(context, editorState)
                          : RibbonButton(
                              key: ValueKey(action.id),
                              action: action,
                              editorState: editorState,
                              shortcuts: shortcuts,
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 2.0),
              Text(
                group.caption,
                style: theme.textStyle.caption.standard(
                  color: theme.textColorScheme.tertiary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 4.0),
            child: VerticalDivider(
              width: 1.0,
              thickness: 1.0,
              color: theme.borderColorScheme.primary,
            ),
          ),
      ],
    );
  }
}
