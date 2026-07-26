import 'dart:convert';

import 'package:appflowy/workspace/application/naming/first_line_naming.dart';
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

/// `specs/no-titles.md`. These cover the parts that would be expensive — or
/// destructive — to get wrong.
///
/// The one that matters most is the **polarity** group. The flag means "this
/// page has no deliberate name yet", so its absence must mean "leave this page's
/// name alone". Inverted, the first launch after shipping renames the user's
/// entire workspace to whatever each page happens to open with. Every page that
/// predates the feature has no `extra` at all, which is why the plain
/// `ViewPB()` cases below are the real subject.
void main() {
  group('polarity — the safety property', () {
    test('a page with no extra does NOT track (every pre-existing page)', () {
      expect(FirstLineNaming.tracksFirstLine(ViewPB()), isFalse);
      expect(FirstLineNaming.tracksFirstLine(_view('p')), isFalse);
    });

    test('a page carrying other settings but no flag does NOT track', () {
      // A page someone set to RTL and gave a cover, before this feature existed.
      final view = _view('p', ext: {
        'page_text_direction': 'rtl',
        'cover': 'x',
      },);
      expect(FirstLineNaming.tracksFirstLine(view), isFalse);
    });

    test('only an explicit true counts', () {
      expect(
        FirstLineNaming.tracksFirstLine(
          _view('p', ext: {ViewExtKeys.tracksFirstLineKey: true}),
        ),
        isTrue,
      );
      expect(
        FirstLineNaming.tracksFirstLine(
          _view('p', ext: {ViewExtKeys.tracksFirstLineKey: false}),
        ),
        isFalse,
      );
      // A string is not a flag — `extra` is written by several features and a
      // coerced truthy value would silently arm tracking.
      expect(
        FirstLineNaming.tracksFirstLine(
          _view('p', ext: {ViewExtKeys.tracksFirstLineKey: 'true'}),
        ),
        isFalse,
      );
    });

    test('unreadable extra reads as "leave this page alone", never throws', () {
      expect(FirstLineNaming.tracksFirstLine(_view('p', raw: 'not json')),
          isFalse,);
      expect(
          FirstLineNaming.tracksFirstLine(_view('p', raw: '[1,2,3]')), isFalse,);
    });
  });

  group('initialExtra — what a new page starts with', () {
    test('a page created with it tracks', () {
      final created = ViewPB()
        ..id = 'new'
        ..extra = FirstLineNaming.initialExtra;
      expect(FirstLineNaming.tracksFirstLine(created), isTrue);
    });
  });

  group('mergedExtra', () {
    test('adds the flag without destroying what is already there', () {
      final view = _view('p', ext: {
        'page_text_direction': 'rtl',
        'page_theme_mode': 'dark',
      },);
      final merged = jsonDecode(FirstLineNaming.mergedExtra(view)) as Map;

      expect(merged[ViewExtKeys.tracksFirstLineKey], isTrue);
      expect(merged['page_text_direction'], 'rtl');
      expect(merged['page_theme_mode'], 'dark');
    });
  });

  group('extraWithoutFlag — what renaming clears', () {
    test('drops only the flag and keeps the page settings', () {
      final view = _view('p', ext: {
        ViewExtKeys.tracksFirstLineKey: true,
        'page_text_direction': 'rtl',
        'cover': 'blue',
      },);
      final after = jsonDecode(FirstLineNaming.extraWithoutFlag(view)) as Map;

      expect(after.containsKey(ViewExtKeys.tracksFirstLineKey), isFalse);
      expect(after['page_text_direction'], 'rtl');
      expect(after['cover'], 'blue');
    });

    test('a page with nothing else set ends up with an empty extra', () {
      final view = _view('p', ext: {ViewExtKeys.tracksFirstLineKey: true});
      expect(FirstLineNaming.extraWithoutFlag(view), '');
    });

    test('UNREADABLE extra is returned untouched, not rebuilt', () {
      // The destructive version decodes to {}, removes nothing, and writes ''
      // back — erasing the page's direction, theme, cover and margins to remove
      // a flag that was not even there. Bail rather than clobber.
      const malformed = '{"page_text_direction":"rtl",';
      final view = _view('p', raw: malformed);
      expect(FirstLineNaming.extraWithoutFlag(view), malformed);
    });

    test('an already-empty extra stays empty', () {
      expect(FirstLineNaming.extraWithoutFlag(ViewPB()), '');
    });
  });

  group('the one rule, end to end', () {
    test('created → tracks; renamed → detached, and stays detached', () {
      final page = ViewPB()
        ..id = 'p'
        ..extra = FirstLineNaming.initialExtra;
      expect(FirstLineNaming.tracksFirstLine(page), isTrue);

      // Renaming clears the flag.
      final renamed = ViewPB()
        ..id = 'p'
        ..extra = FirstLineNaming.extraWithoutFlag(page);
      expect(FirstLineNaming.tracksFirstLine(renamed), isFalse);

      // And nothing turns it back on: there is no opt-in action anywhere, so a
      // detached page can only be renamed again by hand (Q1/Q4, one-way).
      expect(FirstLineNaming.tracksFirstLine(renamed), isFalse);
    });

    test('leaving the page freezes the name — the window is your first visit',
        () {
      // The user's rule (session 15): *"a page title is a window in time. You
      // can change it while you're inside for the first time, and then it
      // sticks."* Closing the window is exactly clearing the flag, so a first
      // line edited months later is body text and renames nothing.
      final page = ViewPB()
        ..id = 'p'
        ..extra = FirstLineNaming.initialExtra;
      expect(FirstLineNaming.tracksFirstLine(page), isTrue);

      final left = ViewPB()
        ..id = 'p'
        ..extra = FirstLineNaming.extraWithoutFlag(page);

      expect(FirstLineNaming.tracksFirstLine(left), isFalse);
    });

    test('closing the window keeps everything else about the page', () {
      final page = _view('p', ext: {
        ViewExtKeys.tracksFirstLineKey: true,
        'page_text_direction': 'rtl',
        'page_theme_mode': 'dark',
      },);

      final after = jsonDecode(FirstLineNaming.extraWithoutFlag(page)) as Map;

      expect(after.containsKey(ViewExtKeys.tracksFirstLineKey), isFalse);
      expect(after['page_text_direction'], 'rtl');
      expect(after['page_theme_mode'], 'dark');
    });
  });
}
