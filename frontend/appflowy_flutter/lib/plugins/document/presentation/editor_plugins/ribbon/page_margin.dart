// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 5).
//
// Per-page margins, implemented as per-page TEXT-COLUMN WIDTH presets.
//
// AppFlowy has no fixed paper size (a page is a text column centred in the
// window, not Letter/A4), so "margins" here means "how wide the text runs":
// wider margins = a narrower centred column. This is the Notion / Google-Docs
// page-width model, and the honest one for a web-style editor.
//
// Stored in `View.extra` per page like the other page properties; [absence of
// the key] = inherit the global width (Settings → Workspace slider), so
// untouched pages never shift. Only an explicit choice writes a width.
//
// The stored value is the column width in logical pixels (a double), within the
// same 480‥1920 range the global slider uses.

import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// Key under which the page's own column width lives inside `View.extra`.
const String kPageMarginExtKey = 'page_margin_width';

/// The four margin presets offered in the ribbon (Narrow / Normal / Wide / Full).
///
/// "Full width" is the app's default column width
/// ([EditorStyleCustomizer.maxDocumentWidth]), so it fills the sheet like today.
/// The other three are concrete reading-column widths, chosen (2026-07-24, r2)
/// as common best-practice measures rather than round guesses: ~700 is a focused
/// single-column read (about Notion's default), ~850 a comfortable default, 1000
/// a spacious column. They are spread deliberately below a typical sheet so the
/// four are visibly distinct — the first values (600/960/1400) had Wide and Full
/// collapsing to the same width because both exceeded the sheet, and Narrow read
/// as too tight.
///
/// Untouched pages don't shift regardless of these numbers — they carry no
/// attribute and inherit the global width — so these only matter once the user
/// opts in. On a very narrow window Wide can still clamp to Full; that is
/// inherent to having no fixed paper size.
enum MarginWidthPreset {
  narrow('Narrow', 700.0),
  normal('Normal', 850.0),
  wide('Wide', 1000.0),
  full('Full width', EditorStyleCustomizer.maxDocumentWidth);

  const MarginWidthPreset(this.label, this.width);

  final String label;

  /// The text-column width this preset sets, in logical pixels.
  final double width;
}

extension PageMarginViewExtension on ViewPB {
  /// This page's own column-width override, or null when it inherits the global
  /// width. Falls back rather than throwing on a non-document layout or an
  /// unparseable `extra`, matching the other `View.extra` getters.
  double? get pageMarginWidth {
    if (layout != ViewLayoutPB.Document) {
      return null;
    }
    try {
      if (extra.isEmpty) {
        return null;
      }
      final ext = jsonDecode(extra);
      if (ext is! Map) {
        return null;
      }
      final value = ext[kPageMarginExtKey];
      return value is num ? value.toDouble() : null;
    } catch (e) {
      Log.warn('failed to read page margin from view $id: $e');
      return null;
    }
  }
}

/// Persists [width] onto [view], preserving every other key in `extra`. A null
/// [width] clears the override, returning the page to the global width.
///
/// Reads the latest `extra` from the backend before the read-modify-write, like
/// `setPageThemeMode`.
Future<void> setPageMarginWidth(ViewPB view, double? width) async {
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
    (error) => Log.warn('failed to load view ${view.id} for margin: $error'),
  );

  if (width == null) {
    current.remove(kPageMarginExtKey);
  } else {
    current[kPageMarginExtKey] = width;
  }

  await ViewBackendService.updateView(
    viewId: view.id,
    extra: jsonEncode(current),
  );
}
