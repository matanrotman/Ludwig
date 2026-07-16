import 'package:appflowy/shared/backup/retention_pruner.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SnapshotInfo backup(DateTime t) => SnapshotRepository.parse(
        SnapshotRepository.fileNameFor(
          kind: SnapshotKind.backup,
          appVersion: '0.11.4',
          timestamp: t,
        ),
      )!;

  SnapshotInfo preRestore(DateTime t) => SnapshotRepository.parse(
        SnapshotRepository.fileNameFor(
          kind: SnapshotKind.preRestore,
          appVersion: '0.11.4',
          timestamp: t,
        ),
      )!;

  group('RetentionPruner.selectForDeletion', () {
    test('keeps everything when under the recent cap', () {
      final snapshots = List.generate(
        30,
        (i) => backup(DateTime(2026, 7).add(Duration(hours: i))),
      );
      expect(const RetentionPruner().selectForDeletion(snapshots), isEmpty);
    });

    test('seed 120 across 30 days -> newest 50 plus one per older day', () {
      // 4 snapshots per day for 30 days = 120.
      final snapshots = <SnapshotInfo>[];
      for (var day = 1; day <= 30; day++) {
        for (var run = 0; run < 4; run++) {
          snapshots.add(backup(DateTime(2026, 7, day, 6 + run * 4)));
        }
      }
      final doomed = const RetentionPruner().selectForDeletion(snapshots);

      // Newest 50 = days 30..19 fully (48) + 2 of day 18. Beyond the cap,
      // each day keeps its newest remaining snapshot: day 18 keeps 1 more
      // (deliberately conservative on the boundary day), days 17..1 keep 1
      // each. Survivors = 50 + 1 + 17 = 68.
      final survivors = snapshots.length - doomed.length;
      expect(survivors, 68);

      // Structural assertions that don't depend on arithmetic subtleties:
      // no deleted name is among the newest 50,
      final sorted = snapshots.map((s) => s.fileName).toList()..sort();
      final newest50 = sorted.reversed.take(50).toSet();
      expect(doomed.toSet().intersection(newest50), isEmpty);
      // and every older day retains at least one snapshot.
      final survivorNames =
          snapshots.map((s) => s.fileName).toSet().difference(doomed.toSet());
      for (var day = 1; day <= 30; day++) {
        final dayToken = '202607${day.toString().padLeft(2, '0')}';
        expect(
          survivorNames.any((n) => n.contains(dayToken)),
          isTrue,
          reason: 'day $day lost all snapshots',
        );
      }
    });

    test('pre-restore snapshots capped separately at 3', () {
      final snapshots = [
        for (var i = 0; i < 5; i++)
          preRestore(DateTime(2026, 7, 10 + i, 12)),
        for (var i = 0; i < 5; i++) backup(DateTime(2026, 7, 10 + i, 13)),
      ];
      final doomed = const RetentionPruner().selectForDeletion(snapshots);
      expect(doomed, hasLength(2));
      expect(doomed.every((n) => n.contains('prerestore')), isTrue);
      // The two OLDEST pre-restores die.
      expect(doomed, contains(predicate<String>((n) => n.contains('20260710'))));
      expect(doomed, contains(predicate<String>((n) => n.contains('20260711'))));
    });
  });

  group('RetentionPruner.prune (filesystem)', () {
    test('deletes only grammar-matching files; foreign files untouched',
        () async {
      final fs = MemoryFileSystem.test();
      final repo = SnapshotRepository(fs);
      final dir = repo.snapshotsDir('/dest');
      await dir.create(recursive: true);

      // 60 backups, one per day -> newest 50 kept outright, the 10 older are
      // each their day's only snapshot -> all survive too. Then 60 same-day
      // extras to force deletions.
      for (var i = 0; i < 60; i++) {
        final name = SnapshotRepository.fileNameFor(
          kind: SnapshotKind.backup,
          appVersion: '1.0.0',
          timestamp: DateTime(2026, 5, 1, 8).add(Duration(days: i ~/ 2, minutes: i)),
        );
        await dir.childFile(name).writeAsString('zip');
      }
      await dir.childFile('my-vacation-photos.zip').writeAsString('precious');
      await dir.childFile('.AppFlowy-backup-v1-x.zip.tmp').writeAsString('tmp');

      await const RetentionPruner().prune(repo, '/dest');

      expect(await dir.childFile('my-vacation-photos.zip').exists(), isTrue);
      expect(
        await dir.childFile('.AppFlowy-backup-v1-x.zip.tmp').exists(),
        isTrue,
        reason: 'pruner must not race the engine over temp files',
      );
      final remaining = (await repo.list('/dest')).length;
      expect(remaining, lessThan(60));
      expect(remaining, greaterThanOrEqualTo(50));
    });
  });
}
