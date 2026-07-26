import 'dart:async';

import 'package:appflowy/workspace/application/pad/ephemeral_pad.dart';
import 'package:appflowy/workspace/application/pad/pad_content.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';

/// [fork:ephemeral-pad] Phase 2 — the pad becomes a page when you write in it.
/// See `specs/ephemeral-pad.md`.
///
/// Watches the pad's own editor and, on the first real character (D2), clears
/// the pad flag and names the page after its first line (D6). The page was
/// already sitting in Temporary, so it simply appears there — **no content
/// moves and nothing remounts**, which is the entire reason the pad is a real
/// page rather than a buffer.
///
/// ## Promotion is provisional (D10)
///
/// Empty it again while you are still on it and it demotes: the flag comes
/// back, the sidebar row goes away, and no empty page is left behind. Nothing
/// is destroyed either way — it is the same view throughout, and only the flag
/// moves. Promotion becomes permanent by navigating away, which needs no code:
/// the next time this page opens, it opens as an ordinary page.
///
/// ## What deliberately does NOT happen here
///
/// **A fresh pad is not created on promotion.** `EphemeralPad.ensure` already
/// creates one when nothing carries the flag, so the next request for the pad
/// makes it (D3). Creating one here would leave a stray blank page behind
/// every time a promotion was undone by demotion.
class EphemeralPadPromoter extends StatefulWidget {
  const EphemeralPadPromoter({
    super.key,
    required this.view,
    required this.editorState,
    required this.child,
  });

  /// The pad's view, as it was when this page opened.
  final ViewPB view;
  final EditorState editorState;
  final Widget child;

  @override
  State<EphemeralPadPromoter> createState() => _EphemeralPadPromoterState();
}

class _EphemeralPadPromoterState extends State<EphemeralPadPromoter> {
  StreamSubscription<EditorTransactionValue>? _subscription;
  Timer? _debounce;

  /// Mirrors what has been written to the backend, so an unchanged keystroke
  /// costs nothing. Starts as "still the pad".
  bool _promoted = false;
  String _name = '';

  /// One write at a time: keystrokes arrive far faster than a backend round
  /// trip, and two overlapping updates to the same view can land out of order.
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    // Once on mount, before any editing: a pad can legitimately open with
    // content already in it — quit inside the debounce window below, or a pad
    // written before promotion existed. Nothing but a transaction would ever
    // reconcile that, and it would sit there permanently invisible. A genuinely
    // empty pad costs nothing here, because the state already agrees.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_sync());
      }
    });
    _subscription = widget.editorState.transactionStream.listen((_) {
      // Debounced because this fires per keystroke. The delay is only ever a
      // delay in the sidebar catching up — the document itself is saved by the
      // editor regardless, so nothing you type is ever waiting on this.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _sync);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _sync() async {
    if (_writing || !mounted) {
      return;
    }
    final document = widget.editorState.document;
    final shouldPromote = PadContent.hasRealContent(document);
    final name = shouldPromote ? PadContent.nameFrom(document) : '';

    if (shouldPromote == _promoted && name == _name) {
      return;
    }

    _writing = true;
    try {
      final ok = shouldPromote
          ? await EphemeralPad.promote(viewId: widget.view.id, name: name)
          : await EphemeralPad.demote(view: widget.view);
      if (ok) {
        _promoted = shouldPromote;
        _name = name;
      }
    } finally {
      _writing = false;
    }

    // A keystroke may have landed while the write was in flight; the debounce
    // timer that would have caught it was skipped by the `_writing` guard.
    if (mounted && _debounce?.isActive != true) {
      final document = widget.editorState.document;
      if (PadContent.hasRealContent(document) != _promoted) {
        unawaited(_sync());
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
