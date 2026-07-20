// [fork:page-surface] Sidecar module — per-page light/dark override.
//
// The app-wide theme (Settings → Appearance) drives the whole app: the
// layout AND, by default, every page. This adds a PER-PAGE override so the
// ribbon's Appearance toggle can make one page look light or dark on its
// own — the same rule the per-page text direction follows, so this mirrors
// `page_text_direction.dart` deliberately:
//   Settings = layout + default page look;  ribbon = this page's look.
//
// Stored in `View.extra` (per page), with [inherit] modelled as the
// ABSENCE of the key so untouched pages keep following the app-wide theme
// exactly as before. Kept out of upstream's `view_ext.dart` to stay
// merge-clean.

import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// Key under which the page's own light/dark override lives inside
/// `View.extra`'s JSON. Namespaced because `extra` is a shared blob.
const String kPageThemeModeExtKey = 'page_theme_mode';

/// The light/dark look a single page is pinned to.
///
/// [inherit] is *absence*, not a value: the key is removed entirely and the
/// page follows the app-wide theme (Settings → Appearance).
enum PageThemeMode {
  /// Follow the app-wide theme. Stored as the absence of the key.
  inherit,
  light,
  dark;

  /// The brightness this override forces, or null for [inherit].
  Brightness? get brightness => switch (this) {
        PageThemeMode.inherit => null,
        PageThemeMode.light => Brightness.light,
        PageThemeMode.dark => Brightness.dark,
      };

  static PageThemeMode fromStorage(Object? raw) => switch (raw) {
        'light' => PageThemeMode.light,
        'dark' => PageThemeMode.dark,
        _ => PageThemeMode.inherit,
      };

  String toStorage() => name;
}

extension PageThemeModeViewExtension on ViewPB {
  /// This page's own light/dark override, or [PageThemeMode.inherit] when
  /// unset. Falls back rather than throwing on a non-document layout or an
  /// unparseable `extra`, matching the other `View.extra` getters.
  PageThemeMode get pageThemeMode {
    if (layout != ViewLayoutPB.Document) {
      return PageThemeMode.inherit;
    }
    try {
      if (extra.isEmpty) {
        return PageThemeMode.inherit;
      }
      final ext = jsonDecode(extra);
      if (ext is! Map) {
        return PageThemeMode.inherit;
      }
      return PageThemeMode.fromStorage(ext[kPageThemeModeExtKey]);
    } catch (e) {
      Log.warn('failed to read page theme mode from view $id: $e');
      return PageThemeMode.inherit;
    }
  }
}

/// Persists [mode] onto [view], preserving every other key in `extra`.
///
/// Reads the latest `extra` from the backend (not the passed-in [view],
/// which may be stale) before the read-modify-write, exactly like
/// `setPageTextDirection`.
Future<void> setPageThemeMode(ViewPB view, PageThemeMode mode) async {
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
        Log.warn('unparseable extra on view ${view.id}, not writing: $e');
        current = {};
      }
    },
    (error) => Log.warn('failed to load view ${view.id} for theme: $error'),
  );

  if (mode == PageThemeMode.inherit) {
    current.remove(kPageThemeModeExtKey);
  } else {
    current[kPageThemeModeExtKey] = mode.toStorage();
  }

  await ViewBackendService.updateView(
    viewId: view.id,
    extra: jsonEncode(current),
  );
}
