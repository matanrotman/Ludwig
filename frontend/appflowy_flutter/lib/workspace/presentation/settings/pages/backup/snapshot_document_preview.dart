import 'dart:convert';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/page_text_direction.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-snapshot/entities.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One page out of a backup, rendered read-only (`specs/restore-redesign.md` D5).
///
/// ## Why this is the real editor and not a lighter renderer
///
/// The user chose it (session 14), and the reason holds up: the question this
/// screen answers is "is this the version I want?" — which you cannot answer from
/// a plain-text approximation. Tables, callouts, colours, headings and above all
/// **reading direction** are exactly the things that tell two versions of a page
/// apart. A second renderer would also drift from the first the moment anything
/// new is added to the editor, and drift in a *recovery* tool is the kind that
/// costs someone their writing.
///
/// The cost is a second [AppFlowyEditor] mounted inside the dialog. It is
/// bounded: one page at a time, no document listener, no collab, no save path.
///
/// ## Read-only, three ways
///
/// 1. `editable: false` on both the editor and the block builders — no caret,
///    no typing, no block handles.
/// 2. **Nothing is wired to write.** There is no `DocumentBloc`, no
///    `documentService`, no transaction listener. The `EditorState` here is
///    built from bytes and thrown away when you click another page; even if a
///    character somehow reached it, there is no code path from this widget to
///    the snapshot or to the live workspace.
/// 3. The snapshot itself is read through a read transaction on the Rust side,
///    against a copy unzipped into the OS temp area — never the live data folder.
class SnapshotDocumentPreview extends StatefulWidget {
  const SnapshotDocumentPreview({
    super.key,
    required this.view,
    required this.data,
  });

  /// The snapshot's view row, for its per-page settings — chiefly direction,
  /// which lives on the folder side rather than in the document.
  final SnapshotViewPB view;

  final DocumentDataPB data;

  @override
  State<SnapshotDocumentPreview> createState() =>
      _SnapshotDocumentPreviewState();
}

class _SnapshotDocumentPreviewState extends State<SnapshotDocumentPreview> {
  EditorState? _editorState;
  EditorScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(SnapshotDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different page, or the same page from a different backup: rebuild from
    // scratch rather than mutating the live EditorState, which is the only way
    // to be sure no content from the previous page survives into this one.
    if (oldWidget.view.id != widget.view.id || oldWidget.data != widget.data) {
      _dispose();
      _build();
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _build() {
    final document = widget.data.toDocument();
    if (document == null) {
      Log.error('[snapshot-preview] could not decode ${widget.view.id}');
      return;
    }
    final editorState = EditorState(document: document);
    _editorState = editorState;
    _scrollController = EditorScrollController(editorState: editorState);
  }

  void _dispose() {
    _scrollController?.dispose();
    _editorState?.dispose();
    _scrollController = null;
    _editorState = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final editorState = _editorState;
    final scrollController = _scrollController;
    if (editorState == null || scrollController == null) {
      return Text(
        'This page is in the backup, but its contents could not be read.',
        style: theme.textStyle.body.standard(
          color: theme.textColorScheme.secondary,
        ),
      );
    }

    // Built here rather than in initState because it reads theme and the
    // appearance cubits off the context — the same reason `ai_markdown_text.dart`
    // builds its customizer in build().
    final styleCustomizer = EditorStyleCustomizer(
      context: context,
      padding: EdgeInsets.zero,
      editorState: editorState,
      // The page's own direction travels with the folder entry, not the
      // document, so an RTL page previews RTL instead of falling back to the
      // app default. Getting this wrong would make every Hebrew page in a backup
      // look subtly wrong and read as corruption.
      pageTextDirection: _pageTextDirection(widget.view.extra),
    );

    final editorStyle = styleCustomizer.style().copyWith(
          // No caret: there is nothing to type into, and a blinking cursor in a
          // backup invites exactly the attempt this screen must not accept.
          cursorColor: Colors.transparent,
          cursorWidth: 0,
        );

    // Some block components read `SharedEditorContext` (sub-pages ask it whether
    // they are inside a database row). The live page creates one per document;
    // the preview needs its own rather than reaching for the open page's.
    return Provider(
      create: (_) => SharedEditorContext(),
      dispose: (_, SharedEditorContext shared) => shared.dispose(),
      child: AppFlowyEditor(
        editorState: editorState,
        editable: false,
        editorStyle: editorStyle,
        editorScrollController: scrollController,
        // (`autoFocus` defaults to false, which is what a preview wants — the
        // dialog's own focus must not jump into a backup.)
        blockComponentBuilders: _previewBuilders(context, editorState, styleCustomizer),
        // Deliberately empty: every shortcut and character handler in this app
        // exists to *change* a document. Passing none means there is no keystroke
        // that can mutate what is on screen, independently of `editable`.
        characterShortcutEvents: const [],
        commandShortcutEvents: const [],
        contextMenuItems: const [],
        disableAutoScroll: true,
      ),
    );
  }
}

/// Block types that cannot be drawn from a snapshot, and why each one is a
/// **correctness** decision rather than a shortcut.
///
/// These components are built against the *live* app: they read
/// `DocumentBloc.state.userProfilePB` (images), the document id (files), or
/// otherwise assume an open, editable document. In a preview there is no
/// `DocumentBloc` — providing one would mean opening the live page, which is
/// precisely what this screen must never do.
///
/// **And even if they built, they would lie.** A local image is stored as a path
/// into the live data folder, so rendering it here would show you *today's*
/// picture inside yesterday's backup — the single most misleading thing this
/// screen could do. Saying "an image was here" is the honest answer until
/// Phase 3 can extract the snapshot's own copy.
const _unrenderableInPreview = {
  ImageBlockKeys.type: 'An image was here.',
  MultiImageBlockKeys.type: 'Images were here.',
  FileBlockKeys.type: 'A file was attached here.',
  SubPageBlockKeys.type: 'A page was embedded here.',
  AiWriterBlockKeys.type: 'An AI drafting block was here.',
};

Map<String, BlockComponentBuilder> _previewBuilders(
  BuildContext context,
  EditorState editorState,
  EditorStyleCustomizer styleCustomizer,
) {
  final builders = buildBlockComponentBuilders(
    context: context,
    editorState: editorState,
    styleCustomizer: styleCustomizer,
    editable: false,
  );
  for (final entry in _unrenderableInPreview.entries) {
    if (builders.containsKey(entry.key)) {
      builders[entry.key] = _PlaceholderBlockBuilder(entry.value);
    }
  }
  return builders;
}

/// Stands in for a block the preview can't honestly draw, saying what was there.
///
/// It reports the block's presence rather than hiding it: a paragraph missing
/// from a preview reads as "this backup doesn't have it", which on a recovery
/// screen is the wrong conclusion to invite.
class _PlaceholderBlockBuilder extends BlockComponentBuilder {
  _PlaceholderBlockBuilder(this.label);

  final String label;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    return _PlaceholderBlock(
      key: blockComponentContext.node.key,
      node: blockComponentContext.node,
      configuration: configuration,
      label: label,
    );
  }
}

class _PlaceholderBlock extends BlockComponentStatelessWidget {
  const _PlaceholderBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.fillColorScheme.contentHover,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textStyle.caption.standard(
          color: theme.textColorScheme.secondary,
        ),
      ),
    );
  }
}

/// The page's own direction out of a snapshot row's raw `extra`.
///
/// The live app reads this through an extension on `ViewPB`; a snapshot row is a
/// different type carrying the same JSON, so the parse is repeated here rather
/// than faking a `ViewPB`. Unreadable `extra` falls back to the app default,
/// matching `page_text_direction.dart` — it is free-form JSON that several
/// features write into, and a backup is the last place to start throwing.
String? _pageTextDirection(String extra) {
  if (extra.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(extra);
    if (decoded is! Map) {
      return null;
    }
    return PageTextDirection.fromStorage(decoded[kPageTextDirectionExtKey])
        .editorValue;
  } catch (e) {
    Log.warn('[snapshot-preview] unreadable extra: $e');
    return null;
  }
}
