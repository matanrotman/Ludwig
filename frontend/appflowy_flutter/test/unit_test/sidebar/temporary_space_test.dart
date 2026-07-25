import 'dart:convert';

import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fork:temp-space] Phase 1 rules — see `specs/temp-space.md`.
///
/// These are pure-function tests on purpose: the whole point of Phase 1 is
/// that the Temporary rules are decidable from the space list alone, with no
/// writes and no bloc, so they can be proven without the real macOS target.
/// (Anything visual or geometric still must not be trusted to headless tests —
/// see the verification rules in STATUS.md.)
ViewPB _space(String id, {String? name, bool? temporary}) {
  final view = ViewPB()
    ..id = id
    ..name = name ?? id
    ..layout = ViewLayoutPB.Document;
  final ext = <String, dynamic>{ViewExtKeys.isSpaceKey: true};
  if (temporary != null) {
    ext[ViewExtKeys.isTemporaryKey] = temporary;
  }
  view.extra = jsonEncode(ext);
  return view;
}

ViewPB _spaceWithRawExtra(String id, String extra) {
  return ViewPB()
    ..id = id
    ..name = id
    ..layout = ViewLayoutPB.Document
    ..extra = extra;
}

void main() {
  group('TemporarySpace.isFlagged', () {
    test('true only when the flag is explicitly true', () {
      expect(TemporarySpace.isFlagged(_space('a', temporary: true)), isTrue);
      expect(TemporarySpace.isFlagged(_space('a', temporary: false)), isFalse);
      expect(TemporarySpace.isFlagged(_space('a')), isFalse);
    });

    test('treats absent, empty and malformed extra as "no", never throws', () {
      expect(TemporarySpace.isFlagged(_spaceWithRawExtra('a', '')), isFalse);
      expect(
        TemporarySpace.isFlagged(_spaceWithRawExtra('a', 'not json at all')),
        isFalse,
      );
      // valid JSON, but not an object — extra is free-form and written by
      // several features, so this must degrade rather than blow up.
      final nonObject = _spaceWithRawExtra('a', '[1,2]');
      expect(TemporarySpace.isFlagged(nonObject), isFalse);

      final stringyFlag = _spaceWithRawExtra('a', '{"is_temporary":"yes"}');
      expect(
        TemporarySpace.isFlagged(stringyFlag),
        isFalse,
        reason: 'only a real boolean true counts',
      );
    });
  });

  group('TemporarySpace.resolve', () {
    test('returns null when there are no spaces', () {
      expect(TemporarySpace.resolve([]), isNull);
    });

    test('prefers the flagged space even when it is not first', () {
      final first = _space('first');
      final flagged = _space('flagged', temporary: true);
      expect(
        TemporarySpace.resolve([first, flagged])?.id,
        'flagged',
      );
    });

    test('falls back to the first space when none is flagged', () {
      // The Phase-1 bridge: nothing has written the flag yet, because writing
      // it is Phase 3's job (the only step allowed to touch real data).
      final spaces = [_space('first'), _space('second')];
      expect(TemporarySpace.resolve(spaces)?.id, 'first');
    });

    test('identity is by flag, never by the display name', () {
      // A fresh install names its first space "Shared"; this user's is called
      // "General". Matching either string would silently do nothing for
      // everybody else — so a space merely NAMED Temporary is not Temporary.
      final impostor = _space('impostor', name: 'Temporary');
      final flagged = _space('real', name: 'General', temporary: true);
      expect(TemporarySpace.resolve([impostor, flagged])?.id, 'real');
    });
  });

  group('TemporarySpace.sortedTemporaryFirst', () {
    test('moves Temporary to the front, keeping the order of the rest', () {
      final a = _space('a');
      final b = _space('b');
      final temporary = _space('t', temporary: true);
      final sorted = TemporarySpace.sortedTemporaryFirst([a, b, temporary]);
      expect(sorted.map((s) => s.id), ['t', 'a', 'b']);
    });

    test('is a no-op when Temporary is already first', () {
      final temporary = _space('t', temporary: true);
      final spaces = [temporary, _space('a')];
      expect(
        TemporarySpace.sortedTemporaryFirst(spaces).map((s) => s.id),
        ['t', 'a'],
      );
    });

    test('handles an empty list', () {
      expect(TemporarySpace.sortedTemporaryFirst([]), isEmpty);
    });

    test('does not mutate the input list', () {
      final spaces = [_space('a'), _space('t', temporary: true)];
      TemporarySpace.sortedTemporaryFirst(spaces);
      expect(
        spaces.map((s) => s.id),
        ['a', 't'],
        reason: 'the bloc state list must not be reordered in place',
      );
    });
  });

  group('the Temporary rules', () {
    final temporary = _space('t', temporary: true);
    final other = _space('other');
    final spaces = [other, temporary];

    test('Temporary cannot be renamed or deleted', () {
      expect(TemporarySpace.canRename(temporary, spaces), isFalse);
      expect(TemporarySpace.canDelete(temporary, spaces), isFalse);
    });

    test('every other space keeps both', () {
      expect(TemporarySpace.canRename(other, spaces), isTrue);
      expect(TemporarySpace.canDelete(other, spaces), isTrue);
    });

    test('Temporary stays flat — no folders inside it', () {
      expect(TemporarySpace.canContainFolders(temporary, spaces), isFalse);
      expect(TemporarySpace.canContainFolders(other, spaces), isTrue);
    });

    test('with a single unflagged space, that space IS Temporary', () {
      // The bridge again: a workspace that has never been migrated still has
      // exactly one landing place, so the rules must hold there too.
      final only = _space('only');
      expect(TemporarySpace.isTemporary(only, [only]), isTrue);
      expect(TemporarySpace.canDelete(only, [only]), isFalse);
    });
  });
}
