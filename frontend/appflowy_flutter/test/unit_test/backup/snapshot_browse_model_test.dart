import 'package:appflowy/shared/backup/snapshot_browse_model.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    show ViewLayoutPB;
import 'package:appflowy_backend/protobuf/flowy-snapshot/entities.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

/// `specs/restore-redesign.md` Phase 1. These cover the decisions that would be
/// expensive to get wrong: what counts as missing (D6), what can be ticked (D4),
/// and how days are grouped (D3).
void main() {
  SnapshotViewPB view(
    String id, {
    required String parent,
    String name = '',
    bool isSpace = false,
    bool isFolder = false,
    int layout = 0, // ViewLayoutPB.Document
  }) =>
      SnapshotViewPB()
        ..id = id
        ..parentId = parent
        ..name = name.isEmpty ? id : name
        ..layout = Int64(layout)
        ..isSpace = isSpace
        ..isFolder = isFolder;

  SnapshotInfo snapshot(DateTime at) => SnapshotInfo(
        kind: SnapshotKind.backup,
        appVersion: '0.11.4',
        timestamp: at,
        fileName: 'AppFlowy-backup-v0.11.4-x.zip',
        sizeBytes: 1,
      );

  group('grouping snapshots by day (D3)', () {
    test('groups by local day, newest day first', () {
      final days = groupByDay([
        snapshot(DateTime(2026, 7, 24, 9, 0)),
        snapshot(DateTime(2026, 7, 26, 3, 8)),
        snapshot(DateTime(2026, 7, 26, 23, 5)),
        snapshot(DateTime(2026, 7, 25, 18, 43)),
      ]);

      expect(days.map((d) => d.date), [
        DateTime(2026, 7, 26),
        DateTime(2026, 7, 25),
        DateTime(2026, 7, 24),
      ]);
      expect(days.first.snapshots.length, 2);
    });

    test('newest snapshot within a day comes first', () {
      final days = groupByDay([
        snapshot(DateTime(2026, 7, 26, 3, 8)),
        snapshot(DateTime(2026, 7, 26, 23, 5)),
        snapshot(DateTime(2026, 7, 26, 14, 32)),
      ]);

      expect(
        days.single.snapshots.map((s) => s.timestamp.hour),
        [23, 14, 3],
        reason: 'the most recent snapshot of a day is the most likely choice',
      );
      expect(days.single.newest.timestamp.hour, 23);
    });

    test('an empty destination produces no days, not a crash', () {
      expect(groupByDay([]), isEmpty);
    });
  });

  group('building the tree', () {
    test('nests spaces, folders and pages by parent', () {
      final nodes = buildTree(
        workspaceId: 'w',
        views: [
          view('space', parent: 'w', isSpace: true),
          view('folder', parent: 'space', isFolder: true),
          view('page', parent: 'folder'),
        ],
        liveViewIds: {'space', 'folder', 'page'},
      );

      expect(nodes.single.id, 'space');
      expect(nodes.single.children.single.id, 'folder');
      expect(nodes.single.children.single.children.single.id, 'page');
    });

    test('a view whose parent is absent does not appear, and does not hang', () {
      final nodes = buildTree(
        workspaceId: 'w',
        views: [view('orphan', parent: 'a-parent-that-is-not-here')],
        liveViewIds: {},
      );
      expect(nodes, isEmpty);
    });

    test('a parent cycle terminates instead of hanging', () {
      // A malformed folder must not spin the browser forever — it is only being read.
      final nodes = buildTree(
        workspaceId: 'w',
        views: [
          view('a', parent: 'w'),
          view('b', parent: 'a'),
          view('a2', parent: 'b'),
        ],
        liveViewIds: {},
      );
      expect(countNodes(nodes), 3);
    });
  });

  group('what is missing (D6)', () {
    List<SnapshotNode> treeWithMissingPage() => buildTree(
          workspaceId: 'w',
          views: [
            view('space', parent: 'w', isSpace: true),
            view('kept', parent: 'space'),
            view('gone', parent: 'space'),
          ],
          // 'gone' is absent from the live workspace.
          liveViewIds: {'space', 'kept'},
        );

    test('marks views absent from the live workspace', () {
      final space = treeWithMissingPage().single;
      expect(space.isMissing, isFalse);
      expect(space.children.firstWhere((n) => n.id == 'kept').isMissing, isFalse);
      expect(space.children.firstWhere((n) => n.id == 'gone').isMissing, isTrue);
    });

    test('a container advertises that something inside it is gone', () {
      final space = treeWithMissingPage().single;
      expect(
        space.containsMissing,
        isTrue,
        reason: 'a collapsed space must still show that a page inside it is missing',
      );
    });

    test('the missing-only filter keeps containers on the path', () {
      final filtered = filterToMissing(treeWithMissingPage());

      expect(filtered.single.id, 'space',
          reason: 'the space is kept so the page appears where it belongs');
      expect(filtered.single.children.map((n) => n.id), ['gone']);
      expect(countNodes(filtered), 2);
    });

    test('the filter empties out when nothing is missing', () {
      final nodes = buildTree(
        workspaceId: 'w',
        views: [
          view('space', parent: 'w', isSpace: true),
          view('page', parent: 'space'),
        ],
        liveViewIds: {'space', 'page'},
      );
      expect(filterToMissing(nodes), isEmpty);
    });
  });

  group('what can be ticked (D4)', () {
    test('an ordinary document is restorable', () {
      final nodes = buildTree(
        workspaceId: 'w',
        views: [view('page', parent: 'w')],
        liveViewIds: {},
      );
      expect(nodes.single.isRestorable, isTrue);
    });

    test('spaces and folders are containers, never restorable pages', () {
      final nodes = buildTree(
        workspaceId: 'w',
        views: [
          view('space', parent: 'w', isSpace: true),
          view('folder', parent: 'w', isFolder: true),
        ],
        liveViewIds: {},
      );
      for (final node in nodes) {
        expect(node.isContainer, isTrue);
        expect(
          node.isRestorable,
          isFalse,
          reason: '${node.id} is structure, not a page',
        );
      }
    });

    test('a board is shown but cannot be ticked yet', () {
      final nodes = buildTree(
        workspaceId: 'w',
        views: [
          view('board', parent: 'w', layout: ViewLayoutPB.Board.value),
        ],
        liveViewIds: {},
      );
      expect(nodes.single.isRestorable, isFalse);
      expect(
        nodes.single.name,
        'board',
        reason: 'it must still be visible, so the structure makes sense',
      );
    });
  });
}
