import 'package:appflowy_editor/appflowy_editor.dart';

/// [fork:no-titles] Guarantees a freshly-loaded document has somewhere to type.
///
/// A document whose blocks cannot hold text — no blocks at all, or only blocks
/// like images and dividers — is completely unusable and gives no clue why. The
/// editor still draws a caret (its auto-focus falls back to a selection at path
/// `[0]` whether or not a node lives there) and the ribbon still reports a
/// selection, so the page looks perfectly normal and focused. But there is no
/// text node to attach the text input service to, so **every keystroke is
/// silently dropped, wherever you click**.
///
/// Reported 2026-07-29: "empty pages are dead no matter what". Unlike the
/// header-click bug in `document_cover_widget.dart`, this one cannot be worked
/// around by clicking somewhere else, because there is nowhere to click.
///
/// Ludwig makes this reachable in a way upstream AppFlowy is not: it retired
/// the page title, so a page with no editable block has no text field anywhere
/// on it. Upstream, the title always gave you somewhere to type.
///
/// Called on load rather than on save: this only touches documents that are
/// already broken, and does not write anything by itself — the paragraph is
/// persisted by the same transaction as the user's first keystroke, exactly as
/// it would be for a normal empty page.
///
/// Returns true when a paragraph was added, so callers can log it.
bool ensureDocumentIsEditable(Document document) {
  for (final child in document.root.children) {
    if (child.delta != null) {
      return false;
    }
  }

  // Append after any existing non-text blocks rather than inserting at [0], so
  // a page that legitimately opens with an image keeps that image first.
  final path = [document.root.children.length];
  return document.insert(path, [paragraphNode()]);
}
