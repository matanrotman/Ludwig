import 'package:appflowy_editor/appflowy_editor.dart';

/// [fork:no-titles] Where the caret should land when the page header is
/// clicked — see `specs/no-titles.md` and `DocumentCoverWidget`.
///
/// Ludwig retired the in-document title, but kept the vertical space it
/// occupied. That leaves a tall blank band at the top of every page which used
/// to be a text field you could click into. A click there must now put you on
/// the document's first line instead, or the click does nothing useful and
/// (before this) actively destroyed the caret.
///
/// Split out of the widget so the choice of line is testable on its own: the
/// widget itself cannot be mounted in a unit test, because its `initState`
/// starts a `ViewListener` that needs the Rust backend.
///
/// Returns `null` when there is nowhere sensible to put a caret, in which case
/// the caller should leave the selection alone rather than clearing it.
Position? headerClickCaretPosition(Document document) {
  final children = document.root.children;

  for (final child in children) {
    // `delta != null` is the test for "this block holds text". A page can open
    // with an image, divider, table or database view on top, and none of those
    // can hold a caret — putting one there would select the block instead of
    // starting you typing, which is not what clicking the top of a page means.
    if (child.delta != null) {
      return Position(path: child.path);
    }
  }

  return null;
}
