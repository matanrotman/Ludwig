import 'dart:convert';

import 'package:appflowy/workspace/application/view/page_folder.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

/// [fork:folder] Phase 1 rules — see `specs/folder.md`.
ViewPB _view(String id, {Map<String, dynamic>? ext, List<ViewPB>? children}) {
  final view = ViewPB()
    ..id = id
    ..name = id
    ..layout = ViewLayoutPB.Document;
  if (ext != null) {
    view.extra = jsonEncode(ext);
  }
  if (children != null) {
    view.childViews.addAll(children);
  }
  return view;
}

ViewPB _page(String id) => _view(id);
ViewPB _folder(String id) => _view(id, ext: {ViewExtKeys.isFolderKey: true});
ViewPB _space(String id, {bool temporary = false}) => _view(id, ext: {
      ViewExtKeys.isSpaceKey: true,
      if (temporary) ViewExtKeys.isTemporaryKey: true,
    });

void main() {
  group('isFolder', () {
    test('true only for a view explicitly marked as one', () {
      expect(_folder('f').isFolder, isTrue);
      expect(_page('p').isFolder, isFalse);
      expect(_space('s').isFolder, isFalse);
    });

    test('EXPLICIT, never emergent — children do not make a folder', () {
      // Decision 2 of specs/capture-and-structure.md, and the guarantee most
      // worth locking down: a page must never restructure itself just because
      // something got nested under it.
      final parentWithKids = _view('p', children: [_page('c1'), _page('c2')]);
      expect(parentWithKids.childViews, hasLength(2));
      expect(parentWithKids.isFolder, isFalse);
    });

    test('unreadable extra means "no", never throws', () {
      for (final raw in ['', 'not json', '[1,2]', '{"is_folder":"yes"}']) {
        final view = ViewPB()
          ..id = 'v'
          ..extra = raw;
        expect(view.isFolder, isFalse, reason: 'extra was: $raw');
      }
    });
  });

  group('canCreateFolderIn', () {
    test('yes in an ordinary space', () {
      final temporary = _space('t', temporary: true);
      final work = _space('work');
      expect(
        PageFolder.canCreateFolderIn(parent: work, spaces: [temporary, work]),
        isTrue,
      );
    });

    test('NO in Temporary — the staging area stays flat', () {
      // Decision 4, and specs/temp-space.md Phase 5: this is the rule that
      // stops organising-inside-the-inbox from replacing filing out of it.
      final temporary = _space('t', temporary: true);
      final work = _space('work');
      expect(
        PageFolder.canCreateFolderIn(
          parent: temporary,
          spaces: [temporary, work],
        ),
        isFalse,
      );
    });

    test('YES in every space when none is flagged Temporary', () {
      // Phases 1–2 treated the first space as Temporary, so this rule bit it
      // too. That fallback is gone: with no flag there is no staging area to
      // keep flat, and blocking folders in a space chosen by position would be
      // a restriction resting on a guess.
      final first = _space('first');
      final second = _space('second');
      expect(
        PageFolder.canCreateFolderIn(parent: first, spaces: [first, second]),
        isTrue,
      );
      expect(
        PageFolder.canCreateFolderIn(parent: second, spaces: [first, second]),
        isTrue,
      );
    });

    test('yes inside another folder — folders nest freely', () {
      expect(
        PageFolder.canCreateFolderIn(parent: _folder('f'), spaces: []),
        isTrue,
      );
    });

    test('NO under an ordinary page', () {
      // Folders group pages within a space; hanging one off a page is a shape
      // that was never in scope (specs/folder.md goal 3). Keeping it out is
      // also what makes this check synchronous — no ancestor walk needed.
      expect(
        PageFolder.canCreateFolderIn(parent: _page('p'), spaces: []),
        isFalse,
      );
    });
  });

  group('markedExtra', () {
    test('adds the flag and preserves unrelated per-view settings', () {
      // extra also carries page direction, page theme, page colour, margins and
      // cover — none of which this feature may clobber.
      final view = _view('v', ext: {
        'text_direction': 'rtl',
        'page_theme_mode': 'dark',
        ViewExtKeys.coverKey: {'type': 1, 'value': 'x'},
      });
      final written =
          jsonDecode(PageFolder.markedExtra(view)) as Map<String, dynamic>;

      expect(written[ViewExtKeys.isFolderKey], isTrue);
      expect(written['text_direction'], 'rtl');
      expect(written['page_theme_mode'], 'dark');
      expect(written[ViewExtKeys.coverKey], {'type': 1, 'value': 'x'});
    });

    test('the result reads back as a folder', () {
      final marked = ViewPB()
        ..id = 'v'
        ..extra = PageFolder.markedExtra(_page('v'));
      expect(marked.isFolder, isTrue);
    });

    test('empty extra yields just the flag', () {
      final written = jsonDecode(PageFolder.markedExtra(_page('v')))
          as Map<String, dynamic>;
      expect(written, {ViewExtKeys.isFolderKey: true});
    });

    test('malformed extra is treated as empty rather than throwing', () {
      final broken = ViewPB()
        ..id = 'v'
        ..extra = 'not json';
      final written =
          jsonDecode(PageFolder.markedExtra(broken)) as Map<String, dynamic>;
      expect(written[ViewExtKeys.isFolderKey], isTrue);
    });
  });
}
