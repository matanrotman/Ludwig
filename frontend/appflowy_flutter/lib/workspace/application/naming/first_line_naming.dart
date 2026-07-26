import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';

/// [fork:no-titles] The whole feature in one rule — see `specs/no-titles.md`.
///
/// > **Every page either has a deliberate name or it doesn't. If it doesn't,
/// > its first line names it. Setting a name is one-way.**
///
/// That single sentence is the entire model, and it is worth resisting any
/// change that needs a second one.
///
/// ## Why there is no migration, and no "old page" concept
///
/// Pages that predate this feature are **not** a second kind of page. They have
/// all already been named — the title box is where their names came from — so
/// they simply fall on the "has a deliberate name" side of the one rule, and
/// nothing has to detect, convert or special-case them. `tracksFirstLine` is
/// false for them because the flag is absent, which is exactly right.
///
/// ## ⚠️ The polarity is the safety property
///
/// The flag marks "no deliberate name yet", set at creation. If it meant "has
/// been named", its absence would mean *track my first line* — and every page
/// already in the workspace would be renamed to whatever it happens to open
/// with, on the first launch after shipping. See [ViewExtKeys.tracksFirstLineKey].
///
/// ## Identity is the flag, never a comparison
///
/// Never infer this state by checking whether the name equals the first line.
/// A comparison silently re-arms itself the moment either one is edited, which
/// is the failure this rule exists to prevent. Same lesson as `TemporarySpace`
/// (identify by flag, never by name) and [EphemeralPad].
class FirstLineNaming {
  const FirstLineNaming._();

  /// Whether [view]'s name should follow its first line.
  ///
  /// A malformed or absent `extra` reads as "no" rather than throwing — `extra`
  /// is free-form JSON that several independent features write into, and the
  /// safe answer for an unreadable one is "leave this page's name alone".
  static bool tracksFirstLine(ViewPB view) {
    try {
      if (view.extra.isEmpty) {
        return false;
      }
      final ext = jsonDecode(view.extra);
      if (ext is! Map) {
        return false;
      }
      return ext[ViewExtKeys.tracksFirstLineKey] == true;
    } catch (_) {
      return false;
    }
  }

  /// The `extra` a newly created page starts with: tracking, and nothing else.
  ///
  /// Passed at creation rather than written afterwards, so there is no window
  /// in which a page exists un-flagged — and no second call that can fail and
  /// leave one stranded.
  static String get initialExtra =>
      jsonEncode({ViewExtKeys.tracksFirstLineKey: true});

  /// [view]'s `extra` with the tracking flag **merged** into whatever is there.
  ///
  /// Merging is not optional: `extra` also carries the page's direction, theme
  /// override, cover and margins. Replacing the map would silently strip them.
  static String mergedExtra(ViewPB view) => jsonEncode(
        mergeMaps(_decode(view), {ViewExtKeys.tracksFirstLineKey: true}),
      );

  /// [view]'s `extra` with the tracking flag removed, everything else kept.
  ///
  /// **An unreadable `extra` is returned untouched, not rebuilt.** Decoding a
  /// malformed blob yields an empty map, and writing that back would erase the
  /// page's direction, theme, cover and margins to remove a flag that was not
  /// even there. Bail rather than clobber — the same rule
  /// `page_text_direction.dart` follows, for the same reason.
  static String extraWithoutFlag(ViewPB view) {
    if (view.extra.isEmpty) {
      return '';
    }
    final current = _decodeOrNull(view);
    if (current == null) {
      return view.extra;
    }
    current.remove(ViewExtKeys.tracksFirstLineKey);
    return current.isEmpty ? '' : jsonEncode(current);
  }

  static Map<String, dynamic> _decode(ViewPB view) =>
      _decodeOrNull(view) ?? <String, dynamic>{};

  /// Null when `extra` is present but cannot be read, so callers can tell
  /// "empty" apart from "do not touch this".
  static Map<String, dynamic>? _decodeOrNull(ViewPB view) {
    try {
      if (view.extra.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(view.extra);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (error) {
      Log.warn('no-titles: unreadable extra on ${view.id}: $error');
    }
    return null;
  }

  /// Update a tracking page's name to follow its first line.
  ///
  /// Only the name is written — `extra` is deliberately untouched, so this can
  /// never disturb the page's direction, theme, cover or margins, and cannot
  /// race the read-modify-write those settings do.
  static Future<bool> updateDraftName({
    required String viewId,
    required String name,
  }) async {
    final result = await ViewBackendService.updateView(
      viewId: viewId,
      name: name,
    );
    return result.fold((_) => true, (error) {
      Log.error('no-titles: could not update the draft name: $error');
      return false;
    });
  }

  /// Fix [view]'s name where it stands: stop tracking, keep the name.
  ///
  /// Called when the page is navigated away from — the naming window is your
  /// first visit, and leaving closes it. Unlike [setDeliberateName] this writes
  /// no name: whatever the first line already put there is the name, and it is
  /// simply frozen.
  ///
  /// Re-reads before writing for the usual reason — a stale `ViewPB` would drop
  /// whatever another feature wrote into `extra` since the page opened.
  static Future<bool> closeNamingWindow({required ViewPB view}) async {
    final current = await ViewBackendService.getView(view.id);
    final fresh = current.fold<ViewPB?>((v) => v, (error) {
      Log.error('no-titles: could not re-read the view to freeze it: $error');
      return null;
    });
    if (fresh == null || !tracksFirstLine(fresh)) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: extraWithoutFlag(fresh),
    );
    return result.fold((_) => true, (error) {
      Log.error('no-titles: could not close the naming window: $error');
      return false;
    });
  }

  /// Give [viewId] a **deliberate** name, permanently detaching it from its
  /// first line.
  ///
  /// This is one-way by design (Q1): there is no action anywhere that turns
  /// tracking back on, including for a page the user converted by hand. What is
  /// lost is the automatic tracking, never the ability to name the page — a
  /// detached page can still be renamed to anything, including its own first
  /// line.
  ///
  /// Re-reads the view before writing rather than trusting the caller's copy:
  /// a stale `ViewPB` would drop whatever another feature wrote into `extra`
  /// since the page opened. That exact staleness produced session 11's title bug
  /// and session 12's cover bug from one root cause.
  /// Safe to call on anything — spaces, folders, databases, already-named pages.
  /// When the flag is absent this writes **only the name**, on exactly the path
  /// renaming took before this feature existed, so nothing that never tracked
  /// gets its `extra` rewritten as a side effect of being renamed.
  static Future<bool> setDeliberateName({
    required String viewId,
    required String name,
  }) async {
    // Re-read rather than trusting the caller's copy. A stale `ViewPB` would
    // drop whatever another feature wrote into `extra` since the page opened —
    // the trap that produced session 11's title bug and session 12's cover bug
    // from one root cause. It also decides correctly whether the flag is there
    // at all, which a stale copy could get wrong in the direction that matters:
    // a page left tracking would rename itself back on the next keystroke, and
    // the rename would look as though it had simply been ignored.
    final current = await ViewBackendService.getView(viewId);
    final view = current.fold<ViewPB?>((view) => view, (error) {
      Log.error('no-titles: could not re-read the view to rename: $error');
      return null;
    });

    final result = await ViewBackendService.updateView(
      viewId: viewId,
      name: name,
      extra:
          view != null && tracksFirstLine(view) ? extraWithoutFlag(view) : null,
    );
    return result.fold((_) => true, (error) {
      Log.error('no-titles: could not set a deliberate name: $error');
      return false;
    });
  }
}
