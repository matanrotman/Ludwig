import 'dart:async';

import 'package:appflowy/shared/backup/snapshot_browse_bloc.dart';
import 'package:appflowy/shared/backup/snapshot_browse_model.dart';
import 'package:appflowy/shared/backup/snapshot_browse_service.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-snapshot/entities.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:file/memory.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

/// `specs/restore-redesign.md` Phase 2 — the read-only preview (D5).
///
/// These cover the two ways a preview can lie about what you are looking at:
/// showing one page's content under another page's name, and carrying a preview
/// across from a different backup. Both are worse than showing nothing, because
/// the entire purpose of this screen is deciding *which version* you want.
///
/// The rendering itself (the real editor, read-only) is not covered here — it
/// needs the app's theme and appearance cubits, and "does an RTL page preview
/// RTL" is a question for the real target, not a fake font. That is the live
/// check in the spec.
void main() {
  SnapshotViewPB view(
    String id, {
    required String parent,
    bool isSpace = false,
    int layout = 0, // ViewLayoutPB.Document
  }) =>
      SnapshotViewPB()
        ..id = id
        ..parentId = parent
        ..name = id
        ..layout = Int64(layout)
        ..isSpace = isSpace
        ..isFolder = false
        ..extra = ''
        ..icon = '';

  SnapshotNode node(SnapshotViewPB v) =>
      SnapshotNode(view: v, children: const [], isMissing: false);

  DocumentDataPB documentFor(String id) => DocumentDataPB()..pageId = id;

  SnapshotInfo snapshot(String fileName) => SnapshotInfo(
        kind: SnapshotKind.backup,
        appVersion: '0.11.4',
        timestamp: DateTime(2026, 7, 26, 3, 8),
        fileName: fileName,
        sizeBytes: 1,
      );

  /// A service that answers from memory, with per-view control over *when*.
  ///
  /// The delay is the point: a real snapshot read unzips an archive, so two
  /// clicks in quick succession genuinely can return out of order.
  late _FakeService service;
  late SnapshotBrowseBloc bloc;

  setUp(() {
    service = _FakeService();
    bloc = SnapshotBrowseBloc(
      destinationPath: '/backups',
      repository: SnapshotRepository(MemoryFileSystem()),
      service: service,
    );
  });

  tearDown(() async => bloc.close());

  Future<void> openSnapshot(String fileName, List<SnapshotViewPB> views) async {
    service.tree = SnapshotTreePB()
      ..workspaceId = 'w'
      ..views.addAll(views);
    await bloc.open(snapshot(fileName));
  }

  test('a container has nothing to preview, and says so by showing nothing',
      () async {
    final space = view('space', parent: 'w', isSpace: true);
    await openSnapshot('a.zip', [space]);

    await bloc.preview(node(space));

    expect(bloc.state.previewNode, isNull);
    expect(bloc.state.preview, isNull);
    // Not merely empty — it must never have asked. A space holds no document,
    // and "couldn't read this page" about a space would be a lie.
    expect(service.requestedViewIds, isEmpty);
  });

  test('previewing a page reads it out of the open snapshot', () async {
    final page = view('page-1', parent: 'w');
    await openSnapshot('a.zip', [page]);
    service.documents['page-1'] = documentFor('page-1');

    await bloc.preview(node(page));

    expect(bloc.state.previewNode?.id, 'page-1');
    expect(bloc.state.preview?.pageId, 'page-1');
    expect(bloc.state.isLoadingPreview, isFalse);
    expect(service.requestedZipPaths.single, contains('a.zip'));
  });

  test('a slow first click never overwrites a faster second one', () async {
    final slow = view('slow', parent: 'w');
    final quick = view('quick', parent: 'w');
    await openSnapshot('a.zip', [slow, quick]);
    service.documents['slow'] = documentFor('slow');
    service.documents['quick'] = documentFor('quick');
    service.gate['slow'] = Completer<void>();

    final slowRead = bloc.preview(node(slow));
    await bloc.preview(node(quick));
    // The first read lands last — the ordering a real unzip can produce.
    service.gate['slow']!.complete();
    await slowRead;

    expect(bloc.state.previewNode?.id, 'quick');
    expect(
      bloc.state.preview?.pageId,
      'quick',
      reason: 'the late result for "slow" must not paint itself under the '
          'name of the page the user actually clicked',
    );
  });

  test('opening another backup drops the preview from the previous one',
      () async {
    final page = view('page-1', parent: 'w');
    await openSnapshot('a.zip', [page]);
    service.documents['page-1'] = documentFor('page-1');
    await bloc.preview(node(page));
    expect(bloc.state.preview, isNotNull);

    await openSnapshot('b.zip', [page]);

    expect(bloc.state.previewNode, isNull);
    expect(bloc.state.preview, isNull);
  });

  test('a page that cannot be read fails the preview, not the tree', () async {
    final good = view('good', parent: 'w');
    final broken = view('broken', parent: 'w');
    await openSnapshot('a.zip', [good, broken]);
    // `broken` is absent from `documents`, so the fake fails it.

    await bloc.preview(node(broken));

    expect(bloc.state.previewError, isNotNull);
    expect(bloc.state.isLoadingPreview, isFalse);
    expect(
      bloc.state.tree, isNotEmpty,
      reason: 'one unreadable page must not blank out a tree that is still '
          'perfectly readable — the rest of the backup is still browsable',
    );
    expect(bloc.state.error, isNull);
  });

  test('closing the preview leaves the tree and the open backup alone',
      () async {
    final page = view('page-1', parent: 'w');
    await openSnapshot('a.zip', [page]);
    service.documents['page-1'] = documentFor('page-1');
    await bloc.preview(node(page));

    bloc.closePreview();

    expect(bloc.state.previewNode, isNull);
    expect(bloc.state.preview, isNull);
    expect(bloc.state.selected?.fileName, 'a.zip');
    expect(bloc.state.tree, isNotEmpty);
  });
}

class _FakeService implements SnapshotBrowseService {
  SnapshotTreePB tree = SnapshotTreePB();
  final Map<String, DocumentDataPB> documents = {};

  /// Holds a given view's read open until completed, to force an out-of-order
  /// return.
  final Map<String, Completer<void>> gate = {};

  final List<String> requestedViewIds = [];
  final List<String> requestedZipPaths = [];

  @override
  Future<FlowyResult<SnapshotTreePB, FlowyError>> readTree(String zipPath) async =>
      FlowySuccess(tree);

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> readDocument(
    String zipPath,
    String viewId,
  ) async {
    requestedViewIds.add(viewId);
    requestedZipPaths.add(zipPath);
    await gate[viewId]?.future;
    final document = documents[viewId];
    if (document == null) {
      return FlowyFailure(FlowyError()..msg = 'no such document');
    }
    return FlowySuccess(document);
  }

  /// Every view is present, so nothing reads as missing and the tests stay
  /// about the preview.
  @override
  Future<Set<String>?> liveViewIds() async =>
      tree.views.map((v) => v.id).toSet();
}
