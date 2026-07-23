// [fork:ribbon] Sidecar module — see specs/ribbon-menu.md (Phase 3).
//
// Per-paragraph line height and paragraph spacing.
//
// Why per paragraph and not per page (user decision, 2026-07-23: "per content
// because it affects each paragraph, not the entire page"): this is deliberately
// UNLIKE the per-page text direction and per-page theme, which live in
// `View.extra`. Those describe the page; this describes a block. Stored as block
// attributes on the node, so the spacing travels with the paragraph when it is
// moved, split or merged.
//
// No editor-fork change is needed for any of this. Both seams the values feed
// already receive the node:
//   * `BlockComponentConfiguration.padding`   — EdgeInsets Function(Node)
//   * `BlockComponentConfiguration.textStyle` — BlockComponentTextStyleBuilder,
//                                               also (Node, {TextSpan})
// The app supplies both in `editor_configuration.dart`; desktop previously
// returned hardcoded constants there while mobile already read a bloc, which is
// the whole reason these looked "missing" rather than "broken".

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Block attribute holding a paragraph's line height multiplier.
///
/// Namespaced rather than a bare `line_height` because these keys share a
/// namespace with the editor's own and with anything upstream adds later.
const String blockComponentLineHeight = 'appflowy_line_height';

/// Block attribute holding extra space *below* a paragraph, in logical pixels.
const String blockComponentSpaceAfter = 'appflowy_space_after';

/// Desktop's previous hardcoded values, now the defaults when a block carries no
/// attribute of its own. Keeping the exact old numbers means every existing
/// document renders byte-identically until the user changes something.
const double kDefaultLineHeight = 1.4; // was editor_style.dart:243
const double kDefaultBlockVerticalPadding = 5.0; // was editor_configuration.dart

/// A named line-height choice, matching the preset-dropdown decision at
/// sign-off (a numeric "elevator" control is deferred to the font-size button so
/// both can share one component rather than inventing it twice).
enum LineSpacingPreset {
  compact('Compact', 1.15),
  single('Single', kDefaultLineHeight),
  oneAndAHalf('1.5 lines', kDefaultLineHeight * 1.5),
  double$('Double', kDefaultLineHeight * 2);

  const LineSpacingPreset(this.label, this.multiplier);

  final String label;

  /// The value written to [blockComponentLineHeight].
  ///
  /// These are NOT the plain 1.0 / 1.5 / 2.0 a word processor shows, and that is
  /// deliberate: AppFlowy's "single spacing" baseline is **1.4**, not 1.0. So
  /// `single` is pinned to [kDefaultLineHeight] — choosing it on an untouched
  /// paragraph must be a no-op, not a visible jump — and the others are scaled
  /// off that baseline. Matching Word's visual *result* matters more than
  /// matching its numbers.
  final double multiplier;
}

/// Extra space after a paragraph.
enum ParagraphSpacingPreset {
  none('None', 0.0),
  small('Small', 6.0),
  medium('Medium', 12.0),
  large('Large', 20.0);

  const ParagraphSpacingPreset(this.label, this.pixels);

  final String label;
  final double pixels;
}

/// Reads a block's line height, falling back to the desktop default.
double lineHeightOf(Node node) {
  final value = node.attributes[blockComponentLineHeight];
  return value is num ? value.toDouble() : kDefaultLineHeight;
}

/// Reads a block's extra trailing space. Zero when unset.
double spaceAfterOf(Node node) {
  final value = node.attributes[blockComponentSpaceAfter];
  return value is num ? value.toDouble() : 0.0;
}

/// The desktop vertical padding for [node], including any paragraph spacing.
///
/// The base 5.0 is preserved on both edges so nothing shifts for untouched
/// documents; paragraph spacing is added *below* only, which is what "space
/// after a paragraph" means and avoids doubling the gap between two spaced
/// paragraphs.
EdgeInsets desktopBlockPadding(Node node) => EdgeInsets.only(
      top: kDefaultBlockVerticalPadding,
      bottom: kDefaultBlockVerticalPadding + spaceAfterOf(node),
    );

/// The per-node text style carrying that block's line height.
///
/// Only `height` is set: [TextStyle.combine] in the editor copies each field
/// from the incoming style, and Flutter's `copyWith` treats null as "keep", so
/// every other property of the resolved style survives untouched.
TextStyle lineHeightTextStyle(Node node) =>
    TextStyle(height: lineHeightOf(node));

/// Writes [value] to [key] on every block the selection touches, or removes the
/// attribute when [value] is null (returning the block to the default).
///
/// ⚠️ The null case must be written as an explicit `key: null`, NOT by dropping
/// the key from the map. Attribute updates are *composed*, delta-style
/// (`composeAttributes`), so an omitted key means "leave it as it was" and a
/// null value means "remove it". Building a map without the key silently
/// merges the old value straight back — caught by a test here.
Future<void> setBlockSpacingAttribute(
  EditorState editorState,
  String key,
  double? value,
) async {
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }
  await editorState.updateNode(
    selection,
    (node) => node.copyWith(
      attributes: {...node.attributes, key: value},
    ),
  );
}

/// Whether every block in the selection already carries [value] for [key].
bool blockSpacingIs(EditorState editorState, String key, double value) {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }
  final nodes = editorState.getNodesInSelection(selection);
  if (nodes.isEmpty) {
    return false;
  }
  return nodes.every((node) {
    final raw = node.attributes[key];
    final resolved = raw is num
        ? raw.toDouble()
        : (key == blockComponentLineHeight ? kDefaultLineHeight : 0.0);
    return resolved == value;
  });
}
