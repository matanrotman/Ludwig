import 'dart:async';

import 'package:appflowy/workspace/application/naming/first_line_naming.dart';
import 'package:appflowy/workspace/application/pad/pad_content.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

/// [fork:no-titles] Phase 1 — a page with no deliberate name is named by its
/// first line. See `specs/no-titles.md`.
///
/// Mounted only for pages carrying [ViewExtKeys.tracksFirstLineKey], and it
/// renders its child unchanged, so a page that has been named deliberately
/// carries none of this.
///
/// ## This is the pad's promoter with the promotion taken out
///
/// `EphemeralPadPromoter` already solved the hard parts — debounce a
/// per-keystroke stream, keep exactly one write in flight, reconcile once on
/// mount for a page that opened with content already in it — and it has been
/// live-verified. The shape is deliberately copied rather than shared: the
/// promoter also moves a flag and can *demote*, which this must never do, and
/// merging them would put a branch inside the one loop that must stay simple.
/// `specs/no-titles.md` Phase 5 is where unifying them belongs, once the pad's
/// frozen-appearance machinery goes away.
///
/// ## It never runs on the pad
///
/// The pad is named by the promoter, which also renames it back to its stored
/// name when emptied (D10). Two namers on one page would fight: the promoter
/// would demote and this would immediately rename it back from the first line.
/// The guard is at the mount site in `document_page.dart` — `isPad` wins.
class FirstLineNamer extends StatefulWidget {
  const FirstLineNamer({
    super.key,
    required this.view,
    required this.editorState,
    required this.child,
  });

  /// The page's view, kept **live** by the caller.
  ///
  /// Deliberately not the frozen open-time copy the rest of the page uses: this
  /// widget has to notice a rename the moment it happens (see `_sync`). Updating
  /// the prop cannot remount anything — same widget, same type, same position —
  /// so the live value costs nothing here while it would cost a remount if the
  /// *appearance* were driven from it.
  final ViewPB view;
  final EditorState editorState;
  final Widget child;

  @override
  State<FirstLineNamer> createState() => _FirstLineNamerState();
}

class _FirstLineNamerState extends State<FirstLineNamer> {
  StreamSubscription<EditorTransactionValue>? _subscription;
  Timer? _debounce;

  /// Mirrors what has been written to the backend, so an unchanged keystroke
  /// costs nothing. Seeded from the name the page opened with, because that is
  /// already what the backend holds.
  late String _name = widget.view.name;

  /// One write at a time: keystrokes arrive far faster than a backend round
  /// trip, and two overlapping updates to the same view can land out of order.
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    // Once on mount, before any editing. A tracking page can legitimately open
    // with a name that no longer matches its first line — the app was quit
    // inside the debounce window below, or the page was written before this
    // feature existed. Without this, nothing but a fresh keystroke would ever
    // reconcile it. A page that already agrees costs nothing here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_sync());
      }
    });
    _subscription = widget.editorState.transactionStream.listen((_) {
      // Debounced because this fires per keystroke. The delay is only ever a
      // delay in the sidebar catching up — the document itself is saved by the
      // editor regardless, so nothing typed is ever waiting on this.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _sync);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    // [fork:no-titles] **Leaving the page closes the naming window.** The name
    // a page picked up from its first line is fixed the moment you navigate
    // away, and from then on only an explicit rename changes it.
    //
    // The user's framing (session 15): *"a page title is a window in time. You
    // can change it while you're inside for the first time, and then it sticks."*
    // Editing a first line months later must not silently rename the page —
    // that line is body text by then, not a title.
    //
    // This is the same rule the pad already lives by: promotion becomes
    // permanent by navigating away (`specs/ephemeral-pad.md` D10). Both surfaces
    // now share one sentence — the window is your first visit.
    //
    // Fire-and-forget: nothing is waiting on it, and if the app is quitting hard
    // enough that it does not land, the page simply gets one more naming visit.
    // The name itself is already correct either way, so the failure is invisible.
    if (FirstLineNaming.tracksFirstLine(widget.view)) {
      unawaited(FirstLineNaming.closeNamingWindow(view: widget.view));
    }
    super.dispose();
  }

  Future<void> _sync() async {
    if (_writing || !mounted) {
      return;
    }

    // ⚠️ Read LIVE, from the current [view] prop — not from a value captured at
    // mount. Renaming the page clears the flag while this widget is still on
    // screen, and a captured value would leave it happily renaming the page back
    // from its first line on the very next keystroke. That is exactly what the
    // user saw: "renamed it, then edited the first line, and it went back."
    //
    // Reading it live is safe precisely because it is read *here* and not in
    // `build`: nothing about the widget tree depends on it, so the flag can
    // change mid-visit without anything remounting. The page's *appearance*
    // still uses the frozen value at the mount site, so the title box does not
    // pop in mid-keystroke.
    if (!FirstLineNaming.tracksFirstLine(widget.view)) {
      return;
    }

    // Truncation happens here, at the moment the name is WRITTEN — which is why
    // nothing downstream needs a length rule of its own. The sidebar row, the
    // breadcrumb, `@`-mentions, tab labels and search results all read
    // `view.name`, so they all get the short form for free. `view.name` is read
    // in 72 files; giving each of them its own cut would have been the sweep
    // this avoids entirely.
    final name = PadContent.nameFrom(widget.editorState.document);

    // An empty document leaves the name ALONE rather than blanking it. Select
    // all and delete, and the row keeps saying what the page was called until
    // something is typed again — a page that loses its name mid-edit looks like
    // a page that has been lost.
    if (name.isEmpty || name == _name) {
      return;
    }

    _writing = true;
    try {
      final ok = await FirstLineNaming.updateDraftName(
        viewId: widget.view.id,
        name: name,
      );
      if (ok) {
        _name = name;
      }
    } finally {
      _writing = false;
    }

    // A keystroke may have landed while the write was in flight; the debounce
    // timer that would have caught it was skipped by the `_writing` guard.
    if (mounted && _debounce?.isActive != true) {
      final latest = PadContent.nameFrom(widget.editorState.document);
      if (latest.isNotEmpty && latest != _name) {
        unawaited(_sync());
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
