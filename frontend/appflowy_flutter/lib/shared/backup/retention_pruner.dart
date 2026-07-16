import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:file/file.dart';

/// Retention policy for the snapshot folder:
/// - regular backups: keep the newest [keepRecent] outright, and beyond those
///   keep the newest snapshot of each calendar day (local time);
/// - pre-restore snapshots: exempt from the count above, capped at the newest
///   [keepPreRestore].
///
/// Deletes ONLY filenames produced by [SnapshotRepository]'s grammar — a
/// foreign file in the user's Drive folder is never touched, whatever it is
/// named.
class RetentionPruner {
  const RetentionPruner({
    this.keepRecent = 50,
    this.keepPreRestore = 3,
  });

  final int keepRecent;
  final int keepPreRestore;

  /// Returns the file names that should be deleted for the given listing.
  /// Pure policy — no IO — so it is trivially unit-testable.
  List<String> selectForDeletion(List<SnapshotInfo> snapshots) {
    final backups = snapshots
        .where((s) => s.kind == SnapshotKind.backup)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final preRestores = snapshots
        .where((s) => s.kind == SnapshotKind.preRestore)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final delete = <String>[];

    // Backups beyond the newest [keepRecent]: keep newest-per-day.
    final seenDays = <String>{};
    for (var i = keepRecent; i < backups.length; i++) {
      final s = backups[i];
      final day = '${s.timestamp.year}-${s.timestamp.month}-${s.timestamp.day}';
      if (!seenDays.add(day)) {
        delete.add(s.fileName);
      }
    }

    for (var i = keepPreRestore; i < preRestores.length; i++) {
      delete.add(preRestores[i].fileName);
    }

    return delete;
  }

  /// Applies the policy to the destination's snapshots folder.
  Future<int> prune(SnapshotRepository repository, String destination) async {
    final listing = await repository.list(destination);
    final doomed = selectForDeletion(listing);
    final dir = repository.snapshotsDir(destination);
    var deleted = 0;
    for (final name in doomed) {
      try {
        final File file = dir.childFile(name);
        if (await file.exists()) {
          await file.delete();
          deleted += 1;
        }
      } catch (_) {
        // A file Drive is mid-syncing may refuse deletion; next run retries.
      }
    }
    return deleted;
  }
}
