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
/// ## Identified by the flag, and only by the flag
///
/// Temporary is identified by the [ViewExtKeys.isTemporaryKey] flag in
/// `View.extra` — never by its display name. A fresh AppFlowy install names
/// its first space `Shared` (`space_bloc.dart`), and this user's was called
/// `General`; matching either string would be a hardcoded personal value that
/// silently does nothing for everybody else.
///
/// Phases 1–2 carried a bridge here: with nothing yet writing the flag,
/// [resolve] fell back to the workspace's first space so those phases could
/// ship without touching real data. **Phase 3's migration has since run and
/// written the flag, so the fallback is gone** (removed 2026-07-26, after
/// confirming `is_temporary":true` in the live folder). A workspace with no
/// flagged space now resolves to null, which is the honest answer — the
/// migration is idempotent and re-runs on the next launch to fix it.
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

  /// The workspace's Temporary space, or null if no space carries the flag.
  static ViewPB? resolve(List<ViewPB> spaces) =>
      spaces.firstWhereOrNull(isFlagged);

  /// Whether [space] is *the* Temporary space of this workspace.
  ///
  /// Takes the whole list rather than just the space so that "which one is
  /// Temporary" stays a single question answered in one place.
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
