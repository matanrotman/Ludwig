import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';

/// [fork:ephemeral-pad] Phase 1 — see `specs/ephemeral-pad.md`.
///
/// The app opens on nothing: a blank sheet and a cursor, with no sidebar row
/// for it. You write; later phases promote what you wrote into a real page.
///
/// ## ⚠️ The pad is a REAL PAGE, and that is the whole design
///
/// The obvious implementation is an in-memory buffer that becomes a page on
/// the first keystroke — which means **swapping the editor mid-keystroke**.
/// This fork has been bitten by that exact failure mode twice: `PageThemeScope`
/// changing the widget-tree shape remounted the editor and dropped keyboard
/// focus (session 4, reported as "the keyboard is disabled"), and the
/// in-document title re-seeding from a stale `ViewPB` produced session 11's
/// title bug and session 12's cover bug from one root cause.
///
/// So the pad is an ordinary page that already exists, carrying
/// [ViewExtKeys.isPadKey] in its `extra` and filtered out of the sidebar.
/// Promotion (Phase 2) will clear the flag — the page simply appears in
/// Temporary, where it already lived. Nothing remounts, because the editor was
/// always editing a real page.
///
/// ## Identity is the flag, never the name
///
/// Copied deliberately from `TemporarySpace`: a page merely *named* something
/// is not the pad. The flag is the only truth, and a malformed or absent
/// `extra` reads as "no" rather than throwing — `extra` is free-form JSON that
/// several independent features write into.
class EphemeralPad {
  const EphemeralPad._();

  /// The name stored for the pad view.
  ///
  /// Never shown: the pad is filtered out of the sidebar and renders without a
  /// title (D7). It exists so the row is identifiable if anything ever lists
  /// views raw — a debugging affordance, not user-facing copy, which is why it
  /// is deliberately not localized.
  static const storedName = 'Pad';

  /// Whether [view] is the pad.
  static bool isPad(ViewPB view) {
    try {
      if (view.extra.isEmpty) {
        return false;
      }
      final ext = jsonDecode(view.extra);
      if (ext is! Map) {
        return false;
      }
      return ext[ViewExtKeys.isPadKey] == true;
    } catch (_) {
      return false;
    }
  }

  /// The pad among [views], or null if none of them is it.
  static ViewPB? resolveIn(List<ViewPB> views) => views.firstWhereOrNull(isPad);

  /// [views] without the pad. The sidebar, the unfiled count and anything else
  /// that lists Temporary's contents goes through this.
  ///
  /// ## D12 — every surface that can reveal a page (the sweep)
  ///
  /// An un-promoted pad is not a page yet, so no surface may offer it as one.
  /// The filtering points are deliberately **not** in one place — each one is a
  /// different query — so they are listed here rather than rediscovered:
  ///
  /// | Surface | Where |
  /// |---|---|
  /// | Sidebar tree | `sidebar_space_list.dart` (`shouldIgnoreView`) |
  /// | Temporary's `(n)` | `temporary_unfiled_count.dart` |
  /// | Recent views | `cached_recent_service.dart` |
  /// | What opens on launch | `desktop_home_screen.dart` (`_switchToSpace`) |
  /// | Command palette results | `command_palette_bloc.dart` |
  /// | Sidebar + move-to search | `space_search_bloc.dart` |
  /// | Move-to tree | `move_page_menu.dart` |
  /// | Editor `@` page mention | `inline_page_reference.dart` |
  /// | Toolbar "link to page" | `link_search_text_field.dart` |
  /// | AI chat `@` mention | `chat_input_control_cubit.dart` |
  /// | Mobile page selector | `mobile_page_selector_sheet.dart` |
  /// | Mobile AI mention | `mention_page_bottom_sheet.dart` |
  ///
  /// **Deliberately NOT filtered**, so a later session doesn't "fix" them:
  /// the restore browser (`snapshot_browse_service.dart`) — a recovery tool
  /// that hides content is worse than useless; the settings data-repair tool;
  /// and reminders, which resolve one known id rather than offering a list.
  ///
  /// ## Why the filter is on the READ side, not the index
  ///
  /// The tempting fix for search is to stop indexing the pad. It is wrong:
  /// the local index stores document *content*, written when the document
  /// changes — and promotion changes only the view's name and `extra`. A pad
  /// excluded at index time would promote into a page whose contents are
  /// **permanently unsearchable** until the user happened to edit it again.
  /// Filtering results keeps one rule: the flag is absent, so it is a page, so
  /// it is findable — with no reindex and no Rust change.
  static List<ViewPB> withoutPad(List<ViewPB> views) =>
      views.where((view) => !isPad(view)).toList();

  /// [view]'s `extra` with the pad flag **merged** into whatever is there.
  ///
  /// Merging is not optional: `extra` also carries the page's direction, theme
  /// override, cover and margins. Replacing the map would silently strip them.
  static String mergedExtra(ViewPB view) =>
      jsonEncode(mergeMaps(_decode(view), {ViewExtKeys.isPadKey: true}));

  /// [view]'s `extra` as a map, treating anything unreadable as empty rather
  /// than throwing — it is free-form JSON written by several features.
  static Map<String, dynamic> _decode(ViewPB view) {
    try {
      if (view.extra.isNotEmpty) {
        final decoded = jsonDecode(view.extra);
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (error) {
      Log.warn('ephemeral-pad: unreadable extra on ${view.id}: $error');
    }
    return <String, dynamic>{};
  }

  /// [view]'s `extra` with the pad flag **removed**, everything else kept.
  static String extraWithoutFlag(ViewPB view) {
    final current = _decode(view);
    current.remove(ViewExtKeys.isPadKey);
    return current.isEmpty ? '' : jsonEncode(current);
  }

  /// Promote the pad to an ordinary page: clear the flag, name it after its
  /// first line (D6).
  ///
  /// The page is already in Temporary, so this is the whole of "becoming a
  /// page" — no content moves. Returns false if the write failed, so the
  /// caller can leave its own idea of the state alone and try again.
  static Future<bool> promote({
    required String viewId,
    required String name,
  }) async {
    // Re-read rather than trusting the `ViewPB` this page opened with: the
    // page's `extra` also carries its direction, theme and margins, and the
    // user may have changed any of them on the pad since. Merging into a stale
    // copy would silently revert them — the same stale-`ViewPB` trap that
    // produced session 11's title bug and session 12's cover bug.
    final current = await ViewBackendService.getView(viewId);
    final view = current.fold<ViewPB?>((view) => view, (error) {
      Log.error('ephemeral-pad: could not re-read the pad to promote: $error');
      return null;
    });
    if (view == null) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: viewId,
      name: name,
      // [fork:no-titles] The promoted page carries NO first-line tracking, and
      // that is deliberate rather than an omission.
      //
      // A brief version of this set the tracking flag here, reasoning that a
      // promoted pad had never been *deliberately* named. The user's "window in
      // time" rule (session 15) makes it unnecessary and wrong: the pad's own
      // promoter names the page from its first line for as long as you are on
      // it, and **navigating away closes the window** — which for the pad is the
      // very moment D10 already makes promotion permanent. Setting the flag here
      // would reopen a window that has just shut.
      extra: extraWithoutFlag(view),
    );
    return result.fold((_) => true, (error) {
      Log.error('ephemeral-pad: could not promote: $error');
      return false;
    });
  }

  /// Put the flag back after the page was emptied again (D10).
  ///
  /// Nothing is destroyed: it is the same view throughout, and only the flag
  /// and the name move. The sidebar row disappears because the row was only
  /// ever a consequence of the flag being absent.
  static Future<bool> demote({required ViewPB view}) async {
    final current = await ViewBackendService.getView(view.id);
    final fresh = current.fold<ViewPB?>((v) => v, (error) {
      Log.error('ephemeral-pad: could not re-read the page to demote: $error');
      return null;
    });
    if (fresh == null) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      name: storedName,
      extra: mergedExtra(fresh),
    );
    return result.fold((_) => true, (error) {
      Log.error('ephemeral-pad: could not demote: $error');
      return false;
    });
  }

  /// The pad for this workspace, creating it if it does not exist yet.
  ///
  /// Returns null if the pad could not be resolved or created — every caller
  /// must cope, because the pad is a convenience and never a precondition for
  /// the app starting.
  ///
  /// [temporary] is where the pad lives: it is an unfiled page like any other,
  /// so when Phase 2 promotes it, it is already in the right place and nothing
  /// has to move.
  static Future<ViewPB?> ensure({required ViewPB temporary}) async {
    final existing = await _find(temporary);
    if (existing != null) {
      return existing;
    }
    return _create(temporary);
  }

  /// Re-reads Temporary's children and looks for the flag.
  ///
  /// Deliberately re-fetches rather than trusting a `childViews` list handed in
  /// by a caller: those come from the sections fetch and go stale, and creating
  /// a second pad because the first was merely *not in a stale list* is exactly
  /// the orphan-accumulation this design exists to avoid.
  static Future<ViewPB?> _find(ViewPB temporary) async {
    final result = await ViewBackendService.getView(temporary.id);
    return result.fold(
      (parent) => resolveIn(parent.childViews),
      (error) {
        Log.error('ephemeral-pad: could not read Temporary: $error');
        return null;
      },
    );
  }

  static Future<ViewPB?> _create(ViewPB temporary) async {
    final created = await ViewBackendService.createView(
      name: storedName,
      layoutType: ViewLayoutPB.Document,
      parentViewId: temporary.id,
      index: 0,
    );
    final view = created.fold<ViewPB?>(
      (view) => view,
      (error) {
        Log.error('ephemeral-pad: could not create the pad: $error');
        return null;
      },
    );
    if (view == null) {
      return null;
    }

    // Flagging is a second call because `createView` takes no `extra`. Between
    // the two the page is briefly an ordinary unfiled page — visible in the
    // sidebar for that instant, and, worse, left behind as a stray "Pad" page
    // if the flag write fails. So a failed flag deletes it again rather than
    // leaking one page per launch.
    final extra = mergedExtra(view);
    final flagged = await ViewBackendService.updateView(
      viewId: view.id,
      extra: extra,
    );
    final ok = flagged.fold(
      (_) => true,
      (error) {
        Log.error('ephemeral-pad: could not flag the pad, removing it: $error');
        return false;
      },
    );
    if (!ok) {
      await ViewBackendService.deleteView(viewId: view.id);
      return null;
    }
    return view..extra = extra;
  }
}
