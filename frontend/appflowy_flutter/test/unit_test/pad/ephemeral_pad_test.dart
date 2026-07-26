import 'dart:convert';

import 'package:appflowy/workspace/application/pad/ephemeral_pad.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _view(String id, {Map<String, dynamic>? ext, String raw = ''}) {
  final view = ViewPB()
    ..id = id
    ..name = id;
  if (ext != null) {
    view.extra = jsonEncode(ext);
  } else if (raw.isNotEmpty) {
    view.extra = raw;
  }
  return view;
}

ViewPB _pad(String id, {Map<String, dynamic> extra = const {}}) =>
    _view(id, ext: {...extra, ViewExtKeys.isPadKey: true});

/// `specs/ephemeral-pad.md` Phase 1. These cover the parts that would be
/// expensive to get wrong: identity is the flag (never the name), the flag
/// merges rather than replaces, and everything that lists Temporary's contents
/// can drop the pad without dropping anything else.
void main() {
  group('EphemeralPad.isPad', () {
    test('true only when the flag is explicitly true', () {
      expect(EphemeralPad.isPad(_pad('p')), isTrue);
      expect(EphemeralPad.isPad(_view('a')), isFalse);
      expect(
        EphemeralPad.isPad(_view('b', ext: {ViewExtKeys.isPadKey: false})),
        isFalse,
      );
      expect(
        EphemeralPad.isPad(_view('c', ext: {ViewExtKeys.isPadKey: 'true'})),
        isFalse,
        reason: 'the string "true" is not the boolean true',
      );
    });

    test('treats absent, empty and malformed extra as "no", never throws', () {
      // `extra` is free-form JSON written by several independent features, so
      // anything unreadable must read as "not the pad" rather than blow up the
      // sidebar it is filtering.
      expect(EphemeralPad.isPad(_view('a')), isFalse);
      expect(EphemeralPad.isPad(_view('b', raw: 'not json')), isFalse);
      expect(EphemeralPad.isPad(_view('c', raw: '[1,2,3]')), isFalse);
      expect(EphemeralPad.isPad(_view('d', raw: '"a string"')), isFalse);
    });

    test('identity is the flag, never the name', () {
      // The same lesson TemporarySpace learned: a page merely CALLED Pad is
      // not the pad, or every user with a page of that name loses it from
      // their sidebar.
      final impostor = _view('impostor')..name = EphemeralPad.storedName;
      expect(EphemeralPad.isPad(impostor), isFalse);
    });
  });

  group('EphemeralPad.resolveIn / withoutPad', () {
    test('finds the pad wherever it sits in the list', () {
      final pad = _pad('pad');
      final views = [_view('a'), pad, _view('b')];
      expect(EphemeralPad.resolveIn(views)?.id, 'pad');
    });

    test('resolves to null when nothing is flagged', () {
      expect(EphemeralPad.resolveIn([_view('a'), _view('b')]), isNull);
      expect(EphemeralPad.resolveIn([]), isNull);
    });

    test('withoutPad drops the pad and keeps the order of the rest', () {
      final views = [_view('a'), _pad('pad'), _view('b'), _view('c')];
      expect(
        EphemeralPad.withoutPad(views).map((v) => v.id),
        ['a', 'b', 'c'],
      );
    });

    test('withoutPad is a no-op when there is no pad', () {
      final views = [_view('a'), _view('b')];
      expect(EphemeralPad.withoutPad(views).map((v) => v.id), ['a', 'b']);
    });
  });

  group('EphemeralPad.mergedExtra', () {
    test('adds the flag without destroying what is already there', () {
      // A page's `extra` also carries its direction, theme override, cover and
      // margins. Replacing the map would silently strip every one of them.
      final view = _view(
        'v',
        ext: {
          'text_direction': 'rtl',
          'page_theme_mode': 'dark',
          ViewExtKeys.coverKey: {'type': 1, 'value': 'x'},
        },
      );

      final written =
          jsonDecode(EphemeralPad.mergedExtra(view)) as Map<String, dynamic>;

      expect(written[ViewExtKeys.isPadKey], isTrue);
      expect(written['text_direction'], 'rtl');
      expect(written['page_theme_mode'], 'dark');
      expect(written[ViewExtKeys.coverKey], {'type': 1, 'value': 'x'});
    });

    test('produces a flagged view from empty or unreadable extra', () {
      for (final view in [_view('a'), _view('b', raw: 'not json')]) {
        final flagged = _view(view.id)..extra = EphemeralPad.mergedExtra(view);
        expect(EphemeralPad.isPad(flagged), isTrue);
      }
    });
  });

  group('EphemeralPad.extraWithoutFlag (promotion)', () {
    test('drops only the flag and keeps the look you gave the pad (D11)', () {
      // The page you just promoted keeps its colour, theme and margins —
      // it is the same view, and the look is part of what you wrote.
      final pad = _pad(
        'p',
        extra: {
          'text_direction': 'rtl',
          'page_theme_mode': 'dark',
          'page_margin_width': 850,
        },
      );

      final written = jsonDecode(EphemeralPad.extraWithoutFlag(pad))
          as Map<String, dynamic>;

      expect(written.containsKey(ViewExtKeys.isPadKey), isFalse);
      expect(written['text_direction'], 'rtl');
      expect(written['page_theme_mode'], 'dark');
      expect(written['page_margin_width'], 850);
    });

    test('a pad with nothing else set promotes to an empty extra', () {
      // Not the string "{}": an empty `extra` is how every ordinary page with
      // no per-page settings looks, and promotion should leave one of those.
      expect(EphemeralPad.extraWithoutFlag(_pad('p')), '');
    });

    test('round-trips: flag, promote, and the view is no longer the pad', () {
      final view = _view('v', ext: {'text_direction': 'rtl'});
      final flagged = _view('v')..extra = EphemeralPad.mergedExtra(view);
      expect(EphemeralPad.isPad(flagged), isTrue);

      final promoted = _view('v')..extra = EphemeralPad.extraWithoutFlag(flagged);
      expect(EphemeralPad.isPad(promoted), isFalse);
      expect(
        (jsonDecode(promoted.extra) as Map)['text_direction'],
        'rtl',
        reason: 'the page keeps its direction across the round trip',
      );
    });
  });
}
