import 'package:appflowy/workspace/application/pad/pad_content.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

Document _document(List<Node> children) =>
    Document(root: pageNode(children: children));

Node _text(String text) => paragraphNode(text: text);

/// `specs/ephemeral-pad.md` Phase 2 — D2 (what counts as writing) and D6 (what
/// the page gets called). These are the rules that decide whether Temporary
/// fills up with junk, so they are worth pinning precisely.
void main() {
  group('PadContent.hasRealContent', () {
    test('an empty pad is not content', () {
      expect(PadContent.hasRealContent(_document([_text('')])), isFalse);
      expect(PadContent.hasRealContent(_document([])), isFalse);
    });

    test('whitespace alone is not content (D2)', () {
      // Pressing space or return while thinking must not create a page.
      for (final blank in [' ', '   ', '\t', ' ']) {
        expect(
          PadContent.hasRealContent(_document([_text(blank)])),
          isFalse,
          reason: 'whitespace ${blank.codeUnits} should not promote',
        );
      }
      expect(
        PadContent.hasRealContent(_document([_text(''), _text('  ')])),
        isFalse,
        reason: 'several blank lines are still nothing written',
      );
    });

    test('one real character is content', () {
      expect(PadContent.hasRealContent(_document([_text('a')])), isTrue);
      expect(PadContent.hasRealContent(_document([_text('  a  ')])), isTrue);
    });

    test('content on a later line counts', () {
      // Return, return, then start writing — the earlier blank lines must not
      // hide the fact that something was written.
      expect(
        PadContent.hasRealContent(
          _document([_text(''), _text(''), _text('here')]),
        ),
        isTrue,
      );
    });

    test('a block with no text at all is content', () {
      // An image or a divider has no "whitespace" to be empty of. Putting one
      // on the pad is unambiguously writing.
      expect(
        PadContent.hasRealContent(_document([dividerNode()])),
        isTrue,
      );
    });

    test('Hebrew counts, like any other script', () {
      expect(PadContent.hasRealContent(_document([_text('שלום')])), isTrue);
    });
  });

  group('PadContent.nameFrom', () {
    test('names the page after its first line (D6)', () {
      expect(
        PadContent.nameFrom(_document([_text('Buy milk'), _text('and eggs')])),
        'Buy milk',
      );
    });

    test('skips leading blank lines', () {
      expect(
        PadContent.nameFrom(_document([_text(''), _text('  '), _text('Real')])),
        'Real',
      );
    });

    test('returns empty when there is nothing to name it after', () {
      // The caller must then leave the name alone rather than write a blank
      // over it.
      expect(PadContent.nameFrom(_document([_text('   ')])), '');
      expect(PadContent.nameFrom(_document([])), '');
    });

    test('trims and collapses internal whitespace', () {
      expect(
        PadContent.nameFrom(_document([_text('  a   b\tc  ')])),
        'a b c',
      );
    });

    test('keeps Hebrew intact', () {
      expect(
        PadContent.nameFrom(_document([_text('זהו עמוד ניסיוני')])),
        'זהו עמוד ניסיוני',
      );
    });

    test('truncates a long first line on a word boundary', () {
      final long = 'word ' * 40;
      final name = PadContent.nameFrom(_document([_text(long)]));

      expect(name.length, lessThanOrEqualTo(PadContent.nameLimit));
      expect(name.endsWith('word'), isTrue, reason: 'cut between words');
      expect(name.trim(), name, reason: 'no trailing space');
    });

    test('truncates hard when there is no word boundary to cut on', () {
      final name = PadContent.nameFrom(_document([_text('x' * 200)]));
      expect(name.length, PadContent.nameLimit);
    });
  });
}
