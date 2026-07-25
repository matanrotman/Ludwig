import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';

/// [fork:temp-space] Phase 1 — see `specs/temp-space.md` and the binding
/// decisions in `specs/capture-and-structure.md`.
///
/// Temporary is the one permanent staging space that every page created
/// without a stated destination lands in, so that starting a page never
/// requires deciding where it belongs. It is deliberately not an ordinary
/// space: it cannot be renamed, cannot be deleted, always sorts first, and
/// (from Phase 5) cannot contain folders.
///
/// Everything in this file is a **pure function over the space list** — no
/// writes, no bloc, no localization — so the rules are unit-testable and so
/// Phase 1 cannot touch the user's data.
///
/// ## ⚠️ The Phase-1 bridge, and why it exists
///
/// Temporary is identified by the [ViewExtKeys.isTemporaryKey] flag in
/// `View.extra` — never by its display name. A fresh AppFlowy install names
/// its first space `Shared` (`space_bloc.dart`), and this user's is called
/// `General`; matching either string would be a hardcoded personal value that
/// silently does nothing for everybody else.
///
/// Nothing has written that flag yet: writing it is Phase 3's job, because
/// Phase 3 is the only step allowed to touch real data (and must take a
/// backup snapshot first). Until then [resolve] falls back to **the first
/// space in the workspace's own order**, read-only.
///
/// Consequence to be aware of while the bridge is in place: whichever space
/// happens to be first is treated as Temporary — it loses Rename/Delete and
/// receives new pages. That is reversible in one line and writes nothing, but
/// it does mean the fallback is a *bridge*, not the design. When Phase 3 lands
/// and the flag is written, delete the fallback branch and let [resolve]
/// return null when no space is flagged.
class TemporarySpace {
  const TemporarySpace._();

  /// Whether this space carries the Temporary flag in `View.extra`.
  ///
  /// Mirrors the shape of `ViewExtension.isSpace` deliberately: `extra` is
  /// free-form JSON written by several features, so a malformed or absent
  /// value must read as "no", never throw.
  static bool isFlagged(ViewPB space) {
    try {
      if (space.extra.isEmpty) {
        return false;
      }
      final ext = jsonDecode(space.extra);
      if (ext is! Map) {
        return false;
      }
      return ext[ViewExtKeys.isTemporaryKey] == true;
    } catch (_) {
      return false;
    }
  }

  /// The workspace's Temporary space, or null if there are no spaces at all.
  ///
  /// Prefers the flagged space; falls back to the first space (see the
  /// Phase-1 bridge note on the class).
  static ViewPB? resolve(List<ViewPB> spaces) {
    if (spaces.isEmpty) {
      return null;
    }
    return spaces.firstWhereOrNull(isFlagged) ?? spaces.first;
  }

  /// Whether [space] is *the* Temporary space of this workspace.
  ///
  /// Takes the whole list rather than just the space because identity is
  /// resolved against the workspace (the flag may not be written yet).
  static bool isTemporary(ViewPB space, List<ViewPB> spaces) =>
      resolve(spaces)?.id == space.id;

  /// [spaces] with Temporary moved to the front, every other space keeping
  /// the user's own order. Never mutates the input.
  static List<ViewPB> sortedTemporaryFirst(List<ViewPB> spaces) {
    final temporary = resolve(spaces);
    if (temporary == null ||
        spaces.isEmpty ||
        spaces.first.id == temporary.id) {
      return spaces;
    }
    return [
      temporary,
      ...spaces.where((space) => space.id != temporary.id),
    ];
  }

  /// Temporary's name is a product constant, not user data (user decision,
  /// 2026-07-25). Renaming is refused rather than hidden, so the row explains
  /// itself instead of looking broken.
  static bool canRename(ViewPB space, List<ViewPB> spaces) =>
      !isTemporary(space, spaces);

  /// Temporary is permanent — deleting it would leave unallocated pages with
  /// nowhere to land.
  static bool canDelete(ViewPB space, List<ViewPB> spaces) =>
      !isTemporary(space, spaces);

  /// Decision 4 of the model: the staging area is deliberately flat, so that
  /// organising inside it can't quietly replace filing out of it.
  ///
  /// Nothing enforces this yet — folders don't exist. Wired up in Phase 5,
  /// once `specs/folder.md` Phase 1 has landed.
  static bool canContainFolders(ViewPB space, List<ViewPB> spaces) =>
      !isTemporary(space, spaces);
}
