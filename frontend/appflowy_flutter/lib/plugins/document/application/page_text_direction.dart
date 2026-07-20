// [fork:rtl] Sidecar module — per-page text direction. See specs/ribbon-menu.md
// (Phase 2) and specs/rtl-support.md.
//
// Direction was already resolved *per document* by the editor; it was merely
// persisted in one global preference
// (`KVKeys.kDocumentAppearanceDefaultTextDirection`), so every page shared one
// setting. This module adds per-page storage in `View.extra` and leaves the
// global preference in place as the fallback for pages that have never been set
// — so existing pages keep behaving exactly as before until touched.
//
// Deliberately kept out of `view_ext.dart`: that file is upstream's and edits to
// it cost a merge conflict every release. Everything here is additive.

import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// Key under which the page's own direction lives inside `View.extra`'s JSON.
///
/// Namespaced rather than a bare `direction` because `extra` is a shared,
/// whole-string-replaced blob: an unprefixed key risks colliding with something
/// upstream adds later.
const String kPageTextDirectionExtKey = 'page_text_direction';

/// The direction a single page is pinned to.
///
/// [inherit] is *absence*, not a value: the key is removed entirely, and the
/// page falls back to the global default. Keeping this distinct from [auto]
/// matters — `auto` is a real per-page choice ("detect from what I type here"),
/// whereas `inherit` means "whatever the app-wide setting says."
enum PageTextDirection {
  /// Follow the app-wide default. Stored as the absence of the key.
  inherit,

  /// Detect per block from the text typed into it.
  auto,

  ltr,
  rtl;

  /// The string the editor expects in `EditorStyle.defaultTextDirection`, or
  /// null to defer to the global default.
  String? get editorValue => switch (this) {
        PageTextDirection.inherit => null,
        PageTextDirection.auto => 'auto',
        PageTextDirection.ltr => 'ltr',
        PageTextDirection.rtl => 'rtl',
      };

  static PageTextDirection fromStorage(Object? raw) => switch (raw) {
        'auto' => PageTextDirection.auto,
        'ltr' => PageTextDirection.ltr,
        'rtl' => PageTextDirection.rtl,
        _ => PageTextDirection.inherit,
      };
}

extension PageTextDirectionViewExtension on ViewPB {
  /// This page's own direction, or [PageTextDirection.inherit] when unset.
  ///
  /// Mirrors the defensive shape of the existing `View.extra` getters
  /// (`view_ext.dart`'s `lineHeightLayout`, `fontLayout`): non-document layouts
  /// and unparseable `extra` both fall back rather than throw, because `extra`
  /// is free-form JSON written by several unrelated features.
  PageTextDirection get pageTextDirection {
    if (layout != ViewLayoutPB.Document) {
      return PageTextDirection.inherit;
    }
    try {
      if (extra.isEmpty) {
        return PageTextDirection.inherit;
      }
      final ext = jsonDecode(extra);
      if (ext is! Map) {
        return PageTextDirection.inherit;
      }
      return PageTextDirection.fromStorage(ext[kPageTextDirectionExtKey]);
    } catch (e) {
      Log.warn('failed to read page text direction from view $id: $e');
      return PageTextDirection.inherit;
    }
  }
}

/// Persists [direction] onto [view], preserving every other key in `extra`.
///
/// `ViewBackendService.updateView` replaces `extra` wholesale, so this has to
/// read-modify-write. It reads from the **backend**, not from the passed-in
/// [view], on purpose: a stale in-memory `ViewPB` would silently drop keys that
/// another feature (cover, font, pin state) wrote in the meantime. This is the
/// bug `document_page_style_bloc.dart:127` still has.
Future<void> setPageTextDirection(
  ViewPB view,
  PageTextDirection direction,
) async {
  if (view.id.isEmpty) {
    return;
  }

  Map<String, dynamic> current = {};
  final latest = await ViewBackendService.getView(view.id);
  latest.fold(
    (v) {
      if (v.extra.isEmpty) return;
      try {
        final decoded = jsonDecode(v.extra);
        if (decoded is Map) {
          current = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        // A corrupt blob is not worth losing the user's direction over, but it
        // IS worth not silently overwriting whatever else was in there — so
        // bail rather than clobber.
        Log.warn('unparseable extra on view ${view.id}, not writing: $e');
        current = {};
      }
    },
    (error) => Log.warn('failed to load view ${view.id} for direction: $error'),
  );

  if (direction == PageTextDirection.inherit) {
    current.remove(kPageTextDirectionExtKey);
  } else {
    current[kPageTextDirectionExtKey] = direction.editorValue;
  }

  await ViewBackendService.updateView(
    viewId: view.id,
    extra: jsonEncode(current),
  );
}
