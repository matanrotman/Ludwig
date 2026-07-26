import 'package:appflowy_editor/appflowy_editor.dart';

/// [fork:ephemeral-pad] D2 and D6 — what counts as writing, and what the page
/// gets called. See `specs/ephemeral-pad.md`.
///
/// Pure functions over a [Document] so the rules are unit-testable without an
/// editor, a backend or a running app. Everything that decides *when* the pad
/// promotes lives here; the wiring lives in the promoter widget.
class PadContent {
  const PadContent._();

  /// How much of the first line becomes the page name.
  ///
  /// Long enough for a real sentence, short enough that the sidebar row is not
  /// a wall of text. The full first line stays in the document either way —
  /// this only bounds the *name*.
  static const nameLimit = 60;

  /// Whether [document] holds anything that should turn the pad into a page.
  ///
  /// **Whitespace does not count** (D2): pressing space or return while
  /// thinking must not fill Temporary with junk pages. Anything that is not a
  /// plain text block — an image, a divider, a table — does count, because
  /// there is no such thing as "whitespace" for those.
  static bool hasRealContent(Document document) {
    for (final node in document.root.children) {
      final delta = node.delta;
      if (delta == null) {
        // A block with no text at all: an image, a divider, a table. Putting
        // one on the pad is unambiguously writing.
        return true;
      }
      if (delta.toPlainText().trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// The page name for [document] — its first non-empty line, Apple Notes style
  /// (D6).
  ///
  /// Returns an empty string when there is nothing to name it after, so the
  /// caller can leave the name alone rather than write a blank over it.
  static String nameFrom(Document document) {
    for (final node in document.root.children) {
      final text = node.delta?.toPlainText().trim() ?? '';
      if (text.isEmpty) {
        continue;
      }
      // Collapse any internal runs of whitespace: a name is one line, and a
      // pasted first line can carry tabs or double spaces.
      final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
      return collapsed.length <= nameLimit
          ? collapsed
          // Cut on a word boundary when there is one reasonably near the
          // limit, so the row doesn't end mid-word for the sake of 6 letters.
          : _truncate(collapsed);
    }
    return '';
  }

  static String _truncate(String text) {
    final cut = text.substring(0, nameLimit);
    final lastSpace = cut.lastIndexOf(' ');
    return lastSpace > nameLimit * 0.6
        ? cut.substring(0, lastSpace)
        : cut.trimRight();
  }
}
