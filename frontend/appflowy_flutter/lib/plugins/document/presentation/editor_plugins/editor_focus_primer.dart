import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

/// [fork:no-titles] Makes a freshly-opened page actually accept typing.
///
/// The bug (reported 2026-07-29 as "the keyboard stopped working", measured
/// 2026-07-29 with a key probe): open a page, type — nothing happens. Click on
/// any line, type again — it works from then on. Everything that usually
/// explains this was ruled out by measurement at the moment of the dead
/// keystroke:
///
/// ```
/// KEY key=S primaryFocus=keyboard service primaryHasFocus=true
///     keepEditorFocus=0 editable=true selection=[0],0 extraInfo=null
///     blocks=1[paragraph] anyTextBlock=true      ← and the offset never moved
/// ```
///
/// So the editor holds the keyboard, the selection is valid, the page is
/// editable, and there is a real paragraph to type into. What is missing is the
/// *text input service*: the editor's keyboard service attaches it from the
/// selection-changed notification, and the selection the editor's own auto-focus
/// sets at mount does not produce a usable attach — it runs in a post-frame
/// callback before the block components can answer for their text. A selection
/// placed later by a click does, which is exactly why clicking a line "fixes"
/// the page.
///
/// The fix re-asserts the selection once, shortly after the page has settled.
/// It re-asserts **the current selection**, so the caret does not move and a
/// click that happened in the meantime is preserved — the only effect is the
/// notification, which is what attaches the input. The null in between is
/// required: `selectionNotifier` is a ValueNotifier and `Selection` has value
/// equality, so re-setting an identical selection notifies nobody.
///
/// Deliberately a one-shot: it exists to cover the mount race, not to police
/// the selection for the life of the page.
class EditorFocusPrimer extends StatefulWidget {
  const EditorFocusPrimer({
    super.key,
    required this.editorState,
    required this.child,
  });

  final EditorState editorState;
  final Widget child;

  @override
  State<EditorFocusPrimer> createState() => _EditorFocusPrimerState();
}

class _EditorFocusPrimerState extends State<EditorFocusPrimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // One frame is not enough: the block components register what the input
    // service needs during and after their own first layout. A short delay is
    // invisible to the user and is the difference between a page that types and
    // one that silently ignores you.
    _timer = Timer(const Duration(milliseconds: 250), _prime);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _prime() {
    if (!mounted) {
      return;
    }

    final editorState = widget.editorState;
    if (editorState.isDisposed || !editorState.editable) {
      return;
    }

    final selection = editorState.selection;
    if (selection == null) {
      // Nothing to re-assert. A page with no selection is not the broken case:
      // the user has somewhere to click, and clicking works.
      return;
    }

    editorState.selection = null;
    editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
