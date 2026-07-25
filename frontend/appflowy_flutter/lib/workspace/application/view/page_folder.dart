import 'dart:convert';

import 'package:appflowy/workspace/application/sidebar/space/temporary_space.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';

/// [fork:folder] Phase 1 — see `specs/folder.md` and the binding decisions in
/// `specs/capture-and-structure.md`.
///
/// A folder is a container that lives inside a space, holds pages and other
/// folders, and can itself hold writing. Per decision 1 of the model there is
/// only **one** container concept: a space *is* a top-level folder. So a folder
/// is marked exactly the way a space is — a flag in `View.extra` — and needs no
/// new backend entity, no protobuf change and no Rust change.
///
/// ## Naming
///
/// "Folder" is the user-facing word. In code this is `PageFolder`, because
/// `lib/…/sidebar/folder/` is already taken by upstream's pre-spaces name for
/// sidebar *sections*, and `Container` is unusable as a prefix in Flutter. The
/// stored key is plain `is_folder` — `View.extra` is a data namespace where
/// nothing collides.
///
/// ## Explicit, never emergent
///
/// Decision 2 of the model: nesting a page under another page does **not**
/// create a folder. `ViewExtension.isFolder` (in `view_ext.dart`, alongside
/// `isSpace`) is true only for a view someone deliberately created as one. That
/// is why the flag exists at all rather than inferring "has children".
class PageFolder {
  const PageFolder._();

  /// Whether a new folder may be created directly inside [parent].
  ///
  /// Two rules, both from the model rather than from convenience:
  ///
  /// - **Folders nest inside spaces and inside other folders — not inside
  ///   ordinary pages.** A folder groups pages within a space; hanging one off
  ///   a page is a different shape that was never in scope (`specs/folder.md`
  ///   goal 3). This also happens to make the check synchronous, since it needs
  ///   no ancestor walk.
  /// - **Never inside Temporary.** Decision 4: the staging area is deliberately
  ///   flat, so that organising inside it can't quietly replace filing out of
  ///   it. Delegates to [TemporarySpace.canContainFolders] so the rule lives in
  ///   one place. Note this is also `specs/temp-space.md` Phase 5 — the rule was
  ///   written and tested there and had nothing to enforce against until now.
  ///
  /// A folder can never itself be inside Temporary (that is what the first call
  /// prevents), so a folder parent needs no further check.
  static bool canCreateFolderIn({
    required ViewPB parent,
    required List<ViewPB> spaces,
  }) {
    if (parent.isSpace) {
      return TemporarySpace.canContainFolders(parent, spaces);
    }
    return parent.isFolder;
  }

  /// [view]'s `extra` with the folder flag added, **merged** into whatever is
  /// already there.
  ///
  /// Merging matters for the same reason it does in the Temporary migration:
  /// `extra` carries unrelated per-view settings this feature must not clobber
  /// (page direction, page theme, page colour, margins, cover). Uses the same
  /// `mergeMaps` convention as `SpaceBloc.update`.
  static String markedExtra(ViewPB view) {
    var current = <String, dynamic>{};
    try {
      if (view.extra.isNotEmpty) {
        final decoded = jsonDecode(view.extra);
        if (decoded is Map<String, dynamic>) {
          current = decoded;
        }
      }
    } catch (error) {
      Log.warn('folder: unreadable extra on ${view.id}: $error');
    }
    return jsonEncode(mergeMaps(current, {ViewExtKeys.isFolderKey: true}));
  }

  /// Creates a folder inside [parentViewId] and returns it, or null on failure.
  ///
  /// Two steps by necessity: `createView`'s `ext` parameter feeds the backend's
  /// `meta`, **not** `View.extra`, so the flag has to be written by a follow-up
  /// `updateView`. A folder is a `Document` view — exactly like a space — which
  /// is what will let it hold writing in Phase 2.
  ///
  /// If the second step fails the view still exists, as an ordinary page. That
  /// is the deliberate failure mode: a stray empty page is recoverable and
  /// visible, whereas a half-marked container would not be.
  static Future<ViewPB?> create({
    required String parentViewId,
    required String name,
  }) async {
    final created = await ViewBackendService.createView(
      name: name,
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      index: 0,
    );
    final view = created.fold<ViewPB?>(
      (view) => view,
      (error) {
        Log.error('folder: create failed: $error');
        return null;
      },
    );
    if (view == null) {
      return null;
    }
    final marked = await ViewBackendService.updateView(
      viewId: view.id,
      extra: markedExtra(view),
    );
    return marked.fold<ViewPB?>(
      (updated) => updated,
      (error) {
        Log.error(
          'folder: created ${view.id} but marking it as a folder failed, '
          'it remains an ordinary page: $error',
        );
        return null;
      },
    );
  }
}
