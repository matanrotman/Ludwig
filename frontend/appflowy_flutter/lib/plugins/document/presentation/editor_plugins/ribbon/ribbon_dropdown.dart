// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 3).
//
// A ribbon control that opens a short list of choices instead of firing a single
// action: Change Case, Line spacing, Paragraph spacing.
//
// Chosen over a numeric control at Phase 3 sign-off — nothing to type, no
// intermediate states, and it matches the align buttons already in the strip. A
// numeric "elevator" control is deliberately deferred to the font-size button so
// both can share one component rather than inventing it twice.

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

import 'ribbon_button.dart';

/// One row in a ribbon dropdown.
@immutable
class RibbonMenuEntry {
  const RibbonMenuEntry({
    required this.label,
    required this.onSelected,
    this.isSelected = false,
    this.isEnabled = true,
    this.disabledHint,
  });

  final String label;
  final VoidCallback onSelected;

  /// Renders with a check mark — the value currently in force.
  final bool isSelected;

  /// False for entries that would do nothing. Used by Change Case on unicase
  /// scripts (Hebrew, Arabic), where a transform is a genuine no-op and an
  /// enabled entry would look broken when pressing it changed nothing.
  final bool isEnabled;

  /// Shown on hover when disabled, so the entry explains itself.
  final String? disabledHint;
}

class RibbonDropdownButton extends StatefulWidget {
  const RibbonDropdownButton({
    super.key,
    required this.id,
    required this.label,
    required this.entriesBuilder,
    this.icon,
    this.isEnabled = true,
  });

  final String id;
  final String label;
  final FlowySvgData? icon;

  /// Built on open rather than passed in, so entries can reflect the editor
  /// state at the moment the menu is shown (which transform does anything, which
  /// value is currently in force).
  final List<RibbonMenuEntry> Function(BuildContext context) entriesBuilder;

  final bool isEnabled;

  @override
  State<RibbonDropdownButton> createState() => _RibbonDropdownButtonState();
}

class _RibbonDropdownButtonState extends State<RibbonDropdownButton> {
  final PopoverController _controller = PopoverController();
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isEnabled = widget.isEnabled;

    final iconColor = isEnabled
        ? theme.iconColorScheme.primary
        : theme.iconColorScheme.tertiary;

    Widget child = Container(
      height: kRibbonButtonSize,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 4.0),
      decoration: BoxDecoration(
        color: _isHovering && isEnabled
            ? theme.fillColorScheme.contentHover
            : null,
        borderRadius: BorderRadius.circular(theme.borderRadius.m),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null)
            FlowySvg(
              widget.icon!,
              size: const Size.square(18.0),
              color: iconColor,
            ),
          Icon(
            Icons.arrow_drop_down,
            size: 16.0,
            color: iconColor,
          ),
        ],
      ),
    );

    if (isEnabled) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: child,
      );
    }

    return FlowyTooltip(
      message: isEnabled
          ? widget.label
          : '${widget.label}\nPlace your cursor in the document first',
      preferBelow: true,
      child: AppFlowyPopover(
        controller: _controller,
        direction: PopoverDirection.bottomWithLeftAligned,
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 400),
        offset: const Offset(0, 4),
        triggerActions:
            isEnabled ? PopoverTriggerFlags.click : PopoverTriggerFlags.none,
        popupBuilder: (_) => _RibbonMenu(
          entries: widget.entriesBuilder(context),
          onDismiss: _controller.close,
        ),
        child: Semantics(
          label: widget.label,
          button: true,
          enabled: isEnabled,
          child: child,
        ),
      ),
    );
  }
}

class _RibbonMenu extends StatelessWidget {
  const _RibbonMenu({required this.entries, required this.onDismiss});

  final List<RibbonMenuEntry> entries;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          _RibbonMenuRow(
            entry: entry,
            onDismiss: onDismiss,
          ),
      ],
    );
  }
}

class _RibbonMenuRow extends StatefulWidget {
  const _RibbonMenuRow({required this.entry, required this.onDismiss});

  final RibbonMenuEntry entry;
  final VoidCallback onDismiss;

  @override
  State<_RibbonMenuRow> createState() => _RibbonMenuRowState();
}

class _RibbonMenuRowState extends State<_RibbonMenuRow> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final entry = widget.entry;

    Widget row = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8.0,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        color: _isHovering && entry.isEnabled
            ? theme.fillColorScheme.contentHover
            : null,
        borderRadius: BorderRadius.circular(theme.borderRadius.m),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18.0,
            child: entry.isSelected
                ? Icon(
                    Icons.check,
                    size: 14.0,
                    color: theme.iconColorScheme.primary,
                  )
                : null,
          ),
          Expanded(
            child: Text(
              entry.label,
              style: theme.textStyle.body.standard(
                color: entry.isEnabled
                    ? theme.textColorScheme.primary
                    : theme.textColorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );

    if (entry.isEnabled) {
      row = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: () {
            widget.onDismiss();
            entry.onSelected();
          },
          child: row,
        ),
      );
    } else if (entry.disabledHint != null) {
      row = FlowyTooltip(message: entry.disabledHint!, child: row);
    }

    return row;
  }
}
