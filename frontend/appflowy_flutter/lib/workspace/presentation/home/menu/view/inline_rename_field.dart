import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [fork:sidebar-improvements] In-place rename for sidebar rows (Phase 2,
/// specs/sidebar-improvements.md): the name's text is replaced by this
/// field, framed by a thin border inside the row — no popover, no dialog.
///
/// Conventions (Finder-style): the current name starts fully selected;
/// Enter commits, Escape cancels, and clicking anywhere else (focus loss)
/// commits.
class InlineRenameField extends StatefulWidget {
  const InlineRenameField({
    super.key,
    required this.initialName,
    required this.onSubmitted,
    required this.onDismissed,
    this.fontSize = 14.0,
  });

  final String initialName;
  final double fontSize;

  /// Called with the edited text when the user commits (Enter/focus loss).
  /// The caller decides whether the value warrants an actual rename.
  final ValueChanged<String> onSubmitted;

  /// Called when the user cancels with Escape; no rename should happen.
  final VoidCallback onDismissed;

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  late final TextEditingController controller;
  final focusNode = FocusNode();

  // Set once a commit/cancel has run, so the focus-loss listener can't
  // fire a second outcome (Escape drops focus while unmounting).
  bool done = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName.length,
    );
    focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!focusNode.hasFocus) {
      _finish(commit: true);
    }
  }

  void _finish({required bool commit}) {
    if (done) {
      return;
    }
    done = true;
    if (commit) {
      widget.onSubmitted(controller.text);
    } else {
      widget.onDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: _frameColor(Theme.of(context))),
    );
    return TapRegion(
      // Focus loss alone does NOT catch every click-away: clicking sidebar
      // chrome or empty space doesn't move focus, so no focus event fired and
      // the edit was silently dropped (user feedback 2026-07-23 — "doesn't
      // save the first one, doesn't save the second one, saves the third
      // one"; the third click happened to land on something focusable).
      // TapRegion fires on any pointer-down outside this field regardless of
      // whether the target takes focus. [_finish]'s `done` guard keeps this
      // and the focus listener from producing two outcomes.
      onTapOutside: (_) => _finish(commit: true),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _finish(commit: false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          maxLength: 256,
          style: TextStyle(fontSize: widget.fontSize),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            enabledBorder: border,
            focusedBorder: border,
          ),
          onSubmitted: (_) => _finish(commit: true),
        ),
      ),
    );
  }

  /// A quiet outline rather than an accent colour: the frame is one shade
  /// *away* from the surface it sits on — brighter than the sidebar in dark
  /// mode, darker in light mode (user feedback 2026-07-23; the previous
  /// `colorScheme.primary` read as a loud blue). Derived from the theme's own
  /// surface so it tracks any theme, including a page-level override.
  Color _frameColor(ThemeData theme) {
    final hsl = HSLColor.fromColor(theme.colorScheme.surface);
    final delta = theme.brightness == Brightness.dark ? 0.30 : -0.30;
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
        .toColor();
  }
}
