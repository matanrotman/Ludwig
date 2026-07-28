import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart'
    show determineTextDirection;
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

  /// Breathing room between the frame and the sidebar's trailing wall. The
  /// field lives in an [Expanded], so without this the frame runs flush into
  /// the sidebar edge (user feedback 2026-07-23). Deliberately *directional*:
  /// the sidebar can be docked either side, so this must follow the ambient
  /// reading direction rather than pick a hardcoded left/right.
  static const double trailingMargin = 8.0;

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

/// Which modifier a platform uses for word-at-a-time caret movement.
enum _Modifier { alt, control }

class _InlineRenameFieldState extends State<InlineRenameField> {
  late final TextEditingController controller;
  final focusNode = FocusNode();

  // Set once a commit/cancel has run, so the focus-loss listener can't
  // fire a second outcome (Escape drops focus while unmounting).
  bool done = false;

  /// Closes the window in which focus loss is read as a steal. A timer rather
  /// than a wall-clock comparison so the behaviour is drivable in tests — with
  /// `DateTime.now()` the window cannot be advanced by `tester.pump`.
  Timer? _graceTimer;
  bool _graceOver = false;

  /// How many times focus has been reclaimed from a steal. Bounded so a
  /// pathological competitor cannot produce an infinite focus ping-pong.
  int _reclaims = 0;

  /// A rename is opened by DOUBLE-clicking a sidebar row, and the FIRST of
  /// those clicks already opened the page (see [DoubleClickDetector] — single
  /// tap must stay immediate, so it cannot wait on a disambiguation window).
  /// The document editor therefore mounts *after* this field autofocuses, and
  /// then asks for focus itself — on macOS via an explicitly DELAYED request
  /// (`cover_title.dart`, `Durations.short4`), which lands right on top of us.
  /// The field lost focus, `_onFocusChanged` read that as a click-away, and
  /// committed instantly: the box appeared and vanished.
  ///
  /// Grace window generously longer than that delay, to also cover the page
  /// load that precedes it.
  static const Duration _focusGrace = Duration(milliseconds: 900);
  static const int _maxReclaims = 3;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
    _detected = determineTextDirection(widget.initialName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName.length,
    );
    _graceTimer = Timer(_focusGrace, () => _graceOver = true);
    focusNode.addListener(_onFocusChanged);
    controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    focusNode.removeListener(_onFocusChanged);
    controller.removeListener(_onTextChanged);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  /// The field re-reads its direction as the text changes, matching the
  /// editor's own per-block auto-direction. It matters here because the name
  /// starts fully selected: the first keystroke replaces everything, so
  /// renaming a Hebrew page to an English one (or the reverse) has to flip
  /// alignment *and* arrow behaviour immediately rather than stay stuck on
  /// whatever the old name was.
  void _onTextChanged() {
    if (determineTextDirection(controller.text) != _detected) {
      setState(() => _detected = determineTextDirection(controller.text));
    }
  }

  TextDirection? _detected;

  void _onFocusChanged() {
    if (focusNode.hasFocus) {
      return;
    }
    if (_isFocusSteal()) {
      _reclaims += 1;
      // Take it back on the next frame: whatever grabbed focus is mid-build,
      // and requesting synchronously inside its own notification loses again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!done && mounted && !focusNode.hasFocus) {
          focusNode.requestFocus();
        }
      });
      return;
    }
    _finish(commit: true);
  }

  /// Whether losing focus just now was something else grabbing it rather than
  /// the user leaving.
  ///
  /// The distinction is available without guessing: a real click-away arrives
  /// as a pointer-down, and [TapRegion.onTapOutside] already commits on those
  /// — including clicks on sidebar chrome that take no focus at all, which is
  /// why it was added in the first place. So focus that disappears with no
  /// pointer event, moments after the box opened, was taken programmatically.
  ///
  /// Deliberately time-bounded rather than permanent: after the window, focus
  /// loss commits exactly as before, so Tab-away and every other ordinary exit
  /// keep working. [done] means a commit or cancel already ran.
  bool _isFocusSteal() {
    if (done || !mounted || _reclaims >= _maxReclaims) {
      return false;
    }
    return !_graceOver;
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

  /// Flutter moves the caret in *logical* order: ArrowLeft always steps to the
  /// previous character in the string. In RTL text the previous character is
  /// drawn to the RIGHT, so the caret walks the opposite way from the arrow the
  /// user pressed (measured, not assumed — from offset 4 in `שלום עולם`,
  /// ArrowLeft gave 3 and ArrowRight gave 5). Setting `textDirection` alone does
  /// NOT change this. Remapping the intents here swaps `forward` so the caret
  /// follows the key visually.
  ///
  /// Scope, deliberately: character and word movement, plain and shift-extended.
  /// Cmd+Arrow (logical line start/end) is left alone — for a one-line field its
  /// "correct" RTL behaviour is genuinely debatable and native apps disagree.
  /// Also note this is a whole-field flip, right for a page name in one script;
  /// truly mixed bidi names would need per-run visual resolution, which is a far
  /// bigger job than a sidebar rename warrants.
  Map<ShortcutActivator, Intent> get _visualArrowShortcuts => {
        for (final shift in [false, true]) ...{
          SingleActivator(LogicalKeyboardKey.arrowLeft, shift: shift):
              ExtendSelectionByCharacterIntent(
            forward: true,
            collapseSelection: !shift,
          ),
          SingleActivator(LogicalKeyboardKey.arrowRight, shift: shift):
              ExtendSelectionByCharacterIntent(
            forward: false,
            collapseSelection: !shift,
          ),
          // Word jumps: Option on macOS, Control elsewhere. Mapping both is
          // harmless — only one is ever produced on a given platform.
          for (final wordModifier in [_Modifier.alt, _Modifier.control]) ...{
            SingleActivator(
              LogicalKeyboardKey.arrowLeft,
              shift: shift,
              alt: wordModifier == _Modifier.alt,
              control: wordModifier == _Modifier.control,
            ): ExtendSelectionToNextWordBoundaryIntent(
              forward: true,
              collapseSelection: !shift,
            ),
            SingleActivator(
              LogicalKeyboardKey.arrowRight,
              shift: shift,
              alt: wordModifier == _Modifier.alt,
              control: wordModifier == _Modifier.control,
            ): ExtendSelectionToNextWordBoundaryIntent(
              forward: false,
              collapseSelection: !shift,
            ),
          },
        },
      };

  @override
  Widget build(BuildContext context) {
    final direction = _detected ?? Directionality.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: _frameColor(Theme.of(context))),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        end: InlineRenameField.trailingMargin,
      ),
      child: TapRegion(
        // Focus loss alone does NOT catch every click-away: clicking sidebar
        // chrome or empty space doesn't move focus, so no focus event fired and
        // the edit was silently dropped (user feedback 2026-07-23 — "doesn't
        // save the first one, doesn't save the second one, saves the third
        // one"; the third click happened to land on something focusable).
        // TapRegion fires on any pointer-down outside this field regardless of
        // whether the target takes focus. [_finish]'s `done` guard keeps this
        // and the focus listener from producing two outcomes.
        onTapOutside: (_) => _finish(commit: true),
        // A nearer [Shortcuts] wins over the app-level
        // DefaultTextEditingShortcuts, so this replaces the logical arrow
        // bindings for RTL names only — LTR names keep stock behaviour.
        child: Shortcuts(
          shortcuts: direction == TextDirection.rtl
              ? _visualArrowShortcuts
              : const <ShortcutActivator, Intent>{},
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
              textDirection: direction,
              textAlign: direction == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
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
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }
}
