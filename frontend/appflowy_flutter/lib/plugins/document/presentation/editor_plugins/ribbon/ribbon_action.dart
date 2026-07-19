// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// The action model behind every ribbon button.
//
// Why this exists rather than re-hosting `ToolbarItem.builder`: a ToolbarItem's
// builder returns the *entire finished button*, hardcoded to a floating-toolbar
// look and carrying its own tooltip with a literal shortcut string (see
// `custom_format_toolbar_items.dart`). The ribbon needs a uniform button and a
// tooltip whose shortcut reflects the user's *rebindable* keybinding, so it
// models the action separately and owns the rendering.

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Why a ribbon button is not currently usable.
enum RibbonDisabledReason {
  /// The capability does not exist in AppFlowy yet. Renders "coming soon".
  comingSoon,

  /// The action exists but cannot apply right now — typically because there is
  /// no cursor in the editor at all (focus is in the sidebar). Note a *collapsed*
  /// cursor is NOT this case: inline marks set a pending style and block actions
  /// apply to the current block.
  noTarget,
}

/// One button in the ribbon.
///
/// [onPressed] being null and [comingSoon] being true are different states:
/// a coming-soon button is a deliberate placeholder for a capability that does
/// not exist, and says so on hover.
@immutable
class RibbonAction {
  const RibbonAction({
    required this.id,
    required this.label,
    this.icon,
    this.shortcutCommandId,
    this.comingSoon = false,
    this.isEnabled,
    this.isHighlighted,
    this.onPressed,
    this.builder,
  }) : assert(
          comingSoon || onPressed != null || builder != null,
          'A ribbon action must either be comingSoon, or do something.',
        );

  /// Stable identifier, also used as the widget key and in tests.
  final String id;

  /// Human-readable name. Shown in the tooltip and, for wide buttons, inline.
  final String label;

  final FlowySvgData? icon;

  /// Id of the registered [CommandShortcutEvent] this action maps to, if any.
  /// The tooltip resolves the *current* binding through this, so a rebind in
  /// Settings → Shortcuts is reflected instead of a stale hardcoded string.
  final String? shortcutCommandId;

  /// True for capabilities that do not exist yet. Renders visibly disabled with
  /// a "coming soon" tooltip, so the ribbon shows the full intended shape.
  final bool comingSoon;

  /// Whether the action can apply given the current editor state. Defaults to
  /// "there is a selection" when omitted.
  final bool Function(EditorState editorState)? isEnabled;

  /// Whether the action is currently *active* (e.g. bold text is selected),
  /// so the button can render in a toggled-on state.
  final bool Function(EditorState editorState)? isHighlighted;

  final void Function(BuildContext context, EditorState editorState)? onPressed;

  /// Escape hatch for actions that are not a plain button — font pickers,
  /// colour pickers and the align dropdown open popovers. These still render
  /// inside the ribbon's group/caption layout, they just own their own control.
  final Widget Function(BuildContext context, EditorState editorState)? builder;

  bool get isPopover => builder != null;

  /// Resolves the button's state for the current editor.
  RibbonDisabledReason? disabledReason(EditorState editorState) {
    if (comingSoon) {
      return RibbonDisabledReason.comingSoon;
    }
    final enabled = isEnabled?.call(editorState) ??
        // Default: anything other than "no cursor at all" is fine.
        (editorState.selection != null);
    return enabled ? null : RibbonDisabledReason.noTarget;
  }
}

/// A titled cluster of buttons within a tab, rendered with its caption
/// underneath (the arrangement chosen at sign-off, 2026-07-19).
@immutable
class RibbonGroup {
  const RibbonGroup({
    required this.id,
    required this.caption,
    required this.actions,
  });

  final String id;

  /// Shown centred beneath the cluster, e.g. "Font", "Paragraph".
  final String caption;

  final List<RibbonAction> actions;
}

/// One tab's worth of groups.
@immutable
class RibbonTab {
  const RibbonTab({
    required this.id,
    required this.label,
    required this.groups,
  });

  final String id;
  final String label;
  final List<RibbonGroup> groups;
}
