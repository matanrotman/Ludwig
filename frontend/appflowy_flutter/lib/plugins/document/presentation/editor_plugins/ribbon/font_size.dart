// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 5).
//
// Font size — the "elevator" control: a type-in box flanked by two carets
// (▼ decrease on the leading side, ▲ increase on the trailing side). This is the
// reusable numeric control Phase 3 deliberately deferred to here so it would be
// built once, not twice.
//
// No editor-fork change is needed. The fork already DEFINES and RENDERS the
// attribute — `AppFlowyRichTextKeys.fontSize` ('font_size'), read as a double off
// each text span and applied as `TextStyle(fontSize:)` — nothing in the *app*
// ever wrote it (audit 2026-07-19). So this is "write the inline attribute the
// fork already reads," the exact shape the font-family / colour pickers use:
//   * range selected  -> editorState.formatDelta(selection, {font_size: v})
//   * bare caret       -> editorState.updateToggledStyle(font_size, v)  (pending)
//
// The value is a raw number, not "pt": AppFlowy's font_size is logical pixels, so
// labelling it "pt" would be a lie. Shown unitless. font_size is already in
// `clearableInlineAttributes` (text_transforms.dart), so "Clear formatting"
// resets it to the default — the agreed way back.

import 'dart:async';

import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'keep_editor_focus.dart';
import 'ribbon_button.dart';
import 'text_transforms.dart';

/// Bounds the box accepts, by typing or by stepping (signed off 2026-07-24:
/// range 8‥96, ▲▼ step ±1).
const double kMinFontSize = 8.0;
const double kMaxFontSize = 96.0;

/// Fallback baseline when the app's configured default cannot be read. Matches
/// `kDocumentAppearanceFontSize`'s default (document_appearance_cubit.dart).
const double kDefaultBodyFontSize = 16.0;

/// The inline attribute key. Re-exported so the tests and the tab wiring do not
/// each reach into appflowy_editor for the same string.
const String kFontSizeAttribute = 'font_size';

/// The size the box shows for text that carries no size of its own — the app's
/// configured default body size.
///
/// Note this reads `DocumentAppearanceCubit.state.fontSize`, which is the
/// user-set default (16 unless changed in Settings). Per-span sizes written here
/// are absolute and override it. A textScaleFactor other than 1 (unusual on
/// desktop) would make the *rendered* default differ slightly, but the stored
/// baseline number is what the control is about.
double defaultFontSizeOf(BuildContext context) {
  try {
    return context.read<DocumentAppearanceCubit>().state.fontSize;
  } catch (_) {
    return kDefaultBodyFontSize;
  }
}

/// The font size currently in force for the target text, or null when the
/// selection MIXES sizes (Word-style blank box).
///
/// Resolution order mirrors the mark buttons:
///   1. a pending size (`toggledStyle`) set for the next typed character;
///   2. otherwise the size across the effective selection — every covered text
///      run compared, with an unstyled run counting as [defaultSize]. All equal
///      -> that number; any disagreement -> null.
double? currentFontSize(EditorState editorState, double defaultSize) {
  final pending = editorState.toggledStyle[kFontSizeAttribute];
  if (pending is num) {
    return pending.toDouble();
  }

  final selection = effectiveSelection(editorState);
  if (selection == null) {
    return defaultSize;
  }
  final normalized = selection.normalized;
  final nodes = editorState.getNodesInSelection(normalized);
  if (nodes.isEmpty) {
    return defaultSize;
  }

  double? seen;
  var sawAny = false;
  for (final node in nodes) {
    final delta = node.delta;
    if (delta == null) {
      continue;
    }
    final start =
        node.path.equals(normalized.start.path) ? normalized.start.offset : 0;
    final end = node.path.equals(normalized.end.path)
        ? normalized.end.offset
        : delta.length;
    if (start >= end) {
      continue;
    }

    var offset = 0;
    for (final op in delta) {
      if (op is! TextInsert) {
        offset += op.length;
        continue;
      }
      final opStart = offset;
      final opEnd = offset + op.length;
      offset = opEnd;
      // Only runs overlapping the target range count.
      if (opEnd <= start || opStart >= end) {
        continue;
      }
      final raw = op.attributes?[kFontSizeAttribute];
      final size = raw is num ? raw.toDouble() : defaultSize;
      if (!sawAny) {
        seen = size;
        sawAny = true;
      } else if (seen != size) {
        return null; // mixed
      }
    }
  }
  return sawAny ? seen : defaultSize;
}

/// Applies [size] (clamped) to the target text: to the given [selection] when
/// supplied (the type-in box captures it before focus moves), otherwise to the
/// live selection. A collapsed target sets a pending size for the next typed
/// character, matching how Bold behaves from a bare caret.
Future<void> applyFontSize(
  EditorState editorState,
  double size, {
  Selection? selection,
}) async {
  final target = selection ?? editorState.selection;
  if (target == null) {
    return;
  }
  final clamped = size.clamp(kMinFontSize, kMaxFontSize).toDouble();
  if (target.isCollapsed) {
    editorState.updateToggledStyle(kFontSizeAttribute, clamped);
  } else {
    await editorState.formatDelta(target, {kFontSizeAttribute: clamped});
  }
}

/// Formats a size for the box: whole numbers show without a trailing ".0"
/// (16, not 16.0); a half step shows as "16.5".
String formatFontSize(double size) {
  return size == size.roundToDouble()
      ? size.toInt().toString()
      : size.toString();
}

/// The elevator control itself. Rebuilt on every selection change (the ribbon
/// wraps the groups row in a `ValueListenableBuilder<Selection?>`), so the box
/// tracks the cursor.
class RibbonFontSizeControl extends StatefulWidget {
  const RibbonFontSizeControl({
    super.key,
    required this.editorState,
  });

  final EditorState editorState;

  @override
  State<RibbonFontSizeControl> createState() => _RibbonFontSizeControlState();
}

class _RibbonFontSizeControlState extends State<RibbonFontSizeControl> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// The editor selection captured the instant the box is pressed — BEFORE
  /// focus moves off the editor. We write to this captured value so the size
  /// still applies even though the field now holds focus.
  Selection? _capturedSelection;

  /// Whether we are currently holding [keepEditorFocusNotifier] up for this
  /// field. Paired increase/decrease, guarded so a pointer-down + focus-gain
  /// can't double-count.
  bool _holdingFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    // Never leave the notifier raised if the control is torn down mid-edit.
    if (_holdingFocus) {
      keepEditorFocusNotifier.decrease();
    }
    super.dispose();
  }

  bool get _hasTarget => widget.editorState.selection != null;

  /// Called on pointer-down, which fires BEFORE the tap moves focus to the
  /// field. Raising the notifier here — not in the focus listener — is the
  /// whole fix: by the time the focus listener runs, the editor's keyboard
  /// service has already nulled the selection (and disabled this box). Capturing
  /// and holding first keeps the selection alive.
  void _beginHold() {
    if (_holdingFocus || widget.editorState.selection == null) {
      return;
    }
    _capturedSelection = widget.editorState.selection;
    keepEditorFocusNotifier.increase();
    _holdingFocus = true;
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Pointer-down already captured the selection and raised the notifier;
      // this covers focus arriving another way (keyboard traversal).
      _beginHold();
      // Select-all so the user can just type a replacement.
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _commit();
      _capturedSelection = null;
      if (_holdingFocus) {
        keepEditorFocusNotifier.decrease();
        _holdingFocus = false;
      }
    }
  }

  Future<void> _commit() async {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      return; // leave the text; build() will restore it on the next rebuild
    }
    await applyFontSize(
      widget.editorState,
      parsed,
      selection: _capturedSelection,
    );
  }

  void _step(double delta) {
    final base =
        currentFontSize(widget.editorState, defaultFontSizeOf(context)) ??
            defaultFontSizeOf(context);
    final next = (base + delta).clamp(kMinFontSize, kMaxFontSize).toDouble();
    // A caret tap steals focus like any button; hold the selection across it and
    // hand focus back to the editor afterwards.
    runKeepingEditorFocus(() => unawaited(applyFontSize(widget.editorState, next)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final isEnabled = _hasTarget;

    final size = isEnabled
        ? currentFontSize(widget.editorState, defaultFontSizeOf(context))
        : null;

    // Don't fight the user while they type; only sync the box from the document
    // when it isn't focused.
    if (!_focusNode.hasFocus) {
      _controller.text = size == null ? '' : formatFontSize(size);
    }

    final foreground = isEnabled
        ? theme.textColorScheme.primary
        : theme.textColorScheme.tertiary;
    final iconColor = isEnabled
        ? theme.iconColorScheme.primary
        : theme.iconColorScheme.tertiary;

    return FlowyTooltip(
      message: isEnabled
          ? 'Font size'
          : 'Font size\nPlace your cursor in the document first',
      preferBelow: true,
      child: Container(
        height: kRibbonButtonSize,
        decoration: BoxDecoration(
          border: Border.all(color: theme.borderColorScheme.primary),
          borderRadius: BorderRadius.circular(theme.borderRadius.m),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CaretButton(
              icon: Icons.keyboard_arrow_down,
              color: iconColor,
              isEnabled: isEnabled,
              onTap: () => _step(-1),
            ),
            SizedBox(
              width: 30.0,
              // Raise the keep-focus notifier on pointer-down, before the tap
              // moves focus off the editor — see _beginHold.
              child: Listener(
                onPointerDown: (_) => _beginHold(),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: isEnabled,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                  ],
                  onSubmitted: (_) {
                    // Commit and hand focus back to the editor.
                    _focusNode.unfocus();
                  },
                  style: theme.textStyle.body.standard(color: foreground),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            _CaretButton(
              icon: Icons.keyboard_arrow_up,
              color: iconColor,
              isEnabled: isEnabled,
              onTap: () => _step(1),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two step carets.
class _CaretButton extends StatelessWidget {
  const _CaretButton({
    required this.icon,
    required this.color,
    required this.isEnabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget child = SizedBox(
      width: 20.0,
      height: kRibbonButtonSize,
      child: Icon(icon, size: 16.0, color: color),
    );
    if (isEnabled) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: child),
      );
    }
    return child;
  }
}
