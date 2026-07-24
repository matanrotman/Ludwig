// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md.
//
// The one button widget every ribbon action renders through, so the strip looks
// uniform and every tooltip follows the same "name + live shortcut" rule.

// `Path` here must be dart:ui's, not appflowy_editor's node-path typedef of the
// same name — hence the prefix.
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';

import 'keep_editor_focus.dart';
import 'ribbon_action.dart';
import 'ribbon_shortcuts.dart';

/// Size of a standard ribbon button. Kept in one place so groups can lay out
/// against a known metric rather than guessing.
const double kRibbonButtonSize = 30.0;

class RibbonButton extends StatefulWidget {
  const RibbonButton({
    super.key,
    required this.action,
    required this.editorState,
    this.shortcuts,
  });

  final RibbonAction action;
  final EditorState editorState;

  /// The live shortcut list to resolve tooltips against. Falls back to the
  /// editor's global defaults when not supplied.
  final List<CommandShortcutEvent>? shortcuts;

  @override
  State<RibbonButton> createState() => _RibbonButtonState();
}

class _RibbonButtonState extends State<RibbonButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final action = widget.action;
    final disabledReason = action.disabledReason(widget.editorState);
    final isDisabled = disabledReason != null;
    final isHighlighted = !isDisabled &&
        (action.isHighlightedInContext?.call(context, widget.editorState) ??
            action.isHighlighted?.call(widget.editorState) ??
            false);

    final Color iconColor;
    if (isDisabled) {
      iconColor = theme.iconColorScheme.tertiary;
    } else {
      iconColor = theme.iconColorScheme.primary;
    }

    final Color? background;
    if (isHighlighted) {
      background = theme.fillColorScheme.themeSelect;
    } else if (_isHovering && !isDisabled) {
      background = theme.fillColorScheme.contentHover;
    } else {
      background = null;
    }

    Widget child = Container(
      width: kRibbonButtonSize,
      height: kRibbonButtonSize,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(theme.borderRadius.m),
      ),
      alignment: Alignment.center,
      child: action.icon != null
          ? FlowySvg(
              action.icon!,
              size: const Size.square(18.0),
              color: iconColor,
            )
          : _PlaceholderGlyph(color: iconColor),
    );

    if (!isDisabled) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          // Hold the editor's selection across the tap (and return focus to the
          // editor afterwards) — otherwise a focus-stealing tap wipes the
          // selection the action needs. See keep_editor_focus.dart.
          onTap: () => runKeepingEditorFocus(
            () => action.onPressed?.call(context, widget.editorState),
          ),
          child: child,
        ),
      );
    }

    return FlowyTooltip(
      message: _tooltipMessage(disabledReason),
      preferBelow: true,
      child: Semantics(
        label: action.label,
        button: true,
        enabled: !isDisabled,
        child: child,
      ),
    );
  }

  String _tooltipMessage(RibbonDisabledReason? reason) {
    final action = widget.action;
    if (reason == RibbonDisabledReason.comingSoon) {
      // Deliberately explicit: these buttons exist to show the ribbon's full
      // intended shape, and must explain themselves rather than look broken.
      return '${action.label}\nComing soon';
    }

    final shortcut = action.shortcutCommandId == null
        ? null
        : resolveShortcutLabel(
            action.shortcutCommandId!,
            shortcuts: widget.shortcuts,
          );

    final buffer = StringBuffer(action.label);
    if (shortcut != null) {
      buffer.write('  $shortcut');
    }
    if (reason == RibbonDisabledReason.noTarget) {
      buffer.write('\nPlace your cursor in the document first');
    }
    return buffer.toString();
  }
}

/// Stand-in for actions that have no icon yet.
///
/// One shared glyph for every icon-less action, rather than the action's first
/// letter: a row of unrelated initials ("F H F F", "S M P") reads as noise or
/// as broken icons, whereas a single repeated dashed outline reads as "nothing
/// here yet" — which is exactly what these coming-soon buttons are. Swap an
/// action to a real [FlowySvg] and this disappears for it automatically.
class _PlaceholderGlyph extends StatelessWidget {
  const _PlaceholderGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(14.0),
        painter: _DashedSquarePainter(color: color),
      );
}

class _DashedSquarePainter extends CustomPainter {
  const _DashedSquarePainter({required this.color});

  final Color color;

  static const double _dash = 2.5;
  static const double _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final path = ui.Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(2.0),
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + _dash),
          paint,
        );
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSquarePainter oldDelegate) =>
      oldDelegate.color != color;
}
