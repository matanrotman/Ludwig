import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    show ViewLayoutPB;
import 'package:appflowy_backend/protobuf/flowy-snapshot/entities.pb.dart';

import 'snapshot_repository.dart';

/// Pure logic behind the restore browser (`specs/restore-redesign.md` Phase 1).
///
/// Deliberately free of Flutter and of the backend: grouping snapshots by day,
/// turning a flat view list into a tree, and deciding what is missing are all
/// decisions worth testing directly rather than through a widget.

/// A day's worth of snapshots — decision D3: you pick a day, and a day opens to
/// every time it was backed up.
class SnapshotDay {
  const SnapshotDay({required this.date, required this.snapshots});

  /// Midnight of the day these snapshots were taken.
  final DateTime date;

  /// Newest first, so the most likely choice is the top one.
  final List<SnapshotInfo> snapshots;

  SnapshotInfo get newest => snapshots.first;
}

/// Groups snapshots into days, newest day first, newest snapshot first within a day.
///
/// Pre-restore snapshots are included: they are exactly the "I restored something and
/// want to see what was there before" case, which is the moment a person most needs
/// them. They are distinguishable by [SnapshotInfo.kind].
List<SnapshotDay> groupByDay(List<SnapshotInfo> snapshots) {
  final byDay = <DateTime, List<SnapshotInfo>>{};
  for (final snapshot in snapshots) {
    final local = snapshot.timestamp.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(snapshot);
  }

  final days = byDay.entries.map((entry) {
    final sorted = [...entry.value]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return SnapshotDay(date: entry.key, snapshots: sorted);
  }).toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  return days;
}

/// One row in the restore browser.
class SnapshotNode {
  SnapshotNode({
    required this.view,
    required this.children,
    required this.isMissing,
  });

  final SnapshotViewPB view;
  final List<SnapshotNode> children;

  /// True when this view existed in the snapshot but is absent from the live
  /// workspace — decision D6, and the reason most people open this screen.
  final bool isMissing;

  String get id => view.id;
  String get name => view.name;

  /// Spaces and folders are containers. A space is a Document-layout view flagged in
  /// `extra` and holds no document of its own, so it must never be treated as a page.
  bool get isContainer => view.isSpace || view.isFolder;

  /// Decision D4: only ordinary documents can be ticked in this phase. Containers are
  /// structure; other layouts (boards, grids, calendars) are shown but not restorable
  /// yet, because a database view owns data that lives elsewhere.
  bool get isRestorable =>
      !isContainer && view.layout.toInt() == ViewLayoutPB.Document.value;

  /// True when this node, or anything beneath it, is missing — so a collapsed branch
  /// can still advertise that something inside it is gone.
  bool get containsMissing =>
      isMissing || children.any((child) => child.containsMissing);
}

/// Builds the tree the browser draws.
///
/// [liveViewIds] is the set of view ids currently in the workspace; anything in the
/// snapshot and not in that set is marked missing. Ids are stable between a snapshot
/// and the live workspace (same workspace, never re-imported), which is what makes the
/// comparison meaningful — see `specs/restore-redesign.md` Phase 0.
List<SnapshotNode> buildTree({
  required String workspaceId,
  required List<SnapshotViewPB> views,
  required Set<String> liveViewIds,
}) {
  final byParent = <String, List<SnapshotViewPB>>{};
  for (final view in views) {
    byParent.putIfAbsent(view.parentId, () => []).add(view);
  }

  // Guard against a malformed folder pointing at itself, directly or in a cycle:
  // the browser must not hang on data it is only reading.
  final visited = <String>{};

  List<SnapshotNode> build(String parentId) {
    final children = byParent[parentId] ?? const [];
    return children
        .where((view) => visited.add(view.id))
        .map(
          (view) => SnapshotNode(
            view: view,
            children: build(view.id),
            isMissing: !liveViewIds.contains(view.id),
          ),
        )
        .toList();
  }

  return build(workspaceId);
}

/// Drops every branch with nothing missing in it — the "only show what's missing"
/// filter (D6). Containers are kept when something beneath them is missing, so a
/// recovered page still appears in the space and folder it belongs to rather than
/// floating at the root.
List<SnapshotNode> filterToMissing(List<SnapshotNode> nodes) {
  final kept = <SnapshotNode>[];
  for (final node in nodes) {
    if (!node.containsMissing) {
      continue;
    }
    kept.add(
      SnapshotNode(
        view: node.view,
        children: filterToMissing(node.children),
        isMissing: node.isMissing,
      ),
    );
  }
  return kept;
}

/// Counts every node in a tree, for the "N pages missing" summary.
int countNodes(List<SnapshotNode> nodes) =>
    nodes.fold(0, (sum, node) => sum + 1 + countNodes(node.children));
