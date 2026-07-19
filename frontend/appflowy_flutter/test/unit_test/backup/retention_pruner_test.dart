import 'package:appflowy/shared/backup/retention_pruner.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fixed "now" so every age below is exact and the suite never depends on
  // the wall clock.
  final now = DateTime(2026, 7, 19, 12);

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

  /// A snapshot aged [days] days (plus [hours]) before [now].
  SnapshotInfo aged(int days, {int hours = 0}) =>
      backup(now.subtract(Duration(days: days, hours: hours)));

  List<String> prune(List<SnapshotInfo> s) =>
      const RetentionPruner().selectForDeletion(s, now: now);

  group('tier 1 — keep everything younger than 2 days', () {
    test('a burst of 20 snapshots in 36 hours is kept intact', () {
      final snapshots = [
        for (var h = 0; h < 20; h++) aged(0, hours: h),
      ];
      expect(prune(snapshots), isEmpty);
    });

    test('the keepRecent cap demotes the excess to daily', () {
      // 80 snapshots inside the 2-day window, an hour apart. The newest 50 are
      // kept outright; the rest fall through to daily granularity, so they
      // collapse to at most one per calendar day.
      final snapshots = [
        for (var h = 0; h < 80; h++) aged(0, hours: h),
      ];
      final survivors = snapshots.length - prune(snapshots).length;
      expect(survivors, greaterThanOrEqualTo(50));
      expect(
        survivors,
        lessThan(80),
        reason: 'the cap must actually thin the tail of the burst',
      );
    });
  });

  group('tier 2 — one per day between 2 and 30 days', () {
    test('4 snapshots a day for 8 days collapse to one per day', () {
      final snapshots = <SnapshotInfo>[];
      for (var day = 3; day <= 10; day++) {
        // Hour offsets stay small so all four land on the SAME calendar day
        // (now is 12:00, so a 15-hour offset would cross midnight).
        for (var run = 0; run < 4; run++) {
          snapshots.add(aged(day, hours: run));
        }
      }
      expect(snapshots, hasLength(32));

      final doomed = prune(snapshots).toSet();
      final survivors =
          snapshots.where((s) => !doomed.contains(s.fileName)).toList();

      expect(survivors, hasLength(8), reason: 'one per calendar day');
      // And every day is represented — no day loses all its snapshots.
      final days = survivors
          .map((s) => '${s.timestamp.year}-${s.timestamp.month}-${s.timestamp.day}')
          .toSet();
      expect(days, hasLength(8));
    });
  });

  group('tier 3 — one per week between 30 days and 6 months', () {
    test('daily snapshots across ~7 weeks collapse to roughly one a week', () {
      final snapshots = [
        for (var day = 40; day <= 90; day++) aged(day),
      ];
      expect(snapshots, hasLength(51));

      final survivors = snapshots.length - prune(snapshots).length;
      // 51 days spans 7-9 week buckets depending on where the boundaries fall.
      expect(survivors, inInclusiveRange(7, 9));
    });
  });

  group('tier 4 — one per month between 6 months and a year', () {
    test('snapshots across ~5 months collapse to one per calendar month', () {
      final snapshots = [
        for (var day = 200; day <= 350; day += 5) aged(day),
      ];
      final doomed = prune(snapshots).toSet();
      final survivors =
          snapshots.where((s) => !doomed.contains(s.fileName)).toList();

      final months =
          survivors.map((s) => '${s.timestamp.year}-${s.timestamp.month}').toSet();
      expect(
        months,
        hasLength(survivors.length),
        reason: 'at most one survivor per calendar month',
      );
      expect(survivors.length, inInclusiveRange(5, 7));
    });
  });

  group('beyond the ladder', () {
    test('anything older than a year is deleted', () {
      final old = aged(400);
      final alsoOld = aged(1000);
      final recent = aged(1);
      final doomed = prune([old, alsoOld, recent]);
      expect(doomed, containsAll([old.fileName, alsoOld.fileName]));
      expect(doomed, isNot(contains(recent.fileName)));
    });

    test('a future-dated snapshot is kept, never deleted', () {
      // Clock skew or a hand-copied file: age is negative. We must not delete
      // something we cannot confidently age.
      final future = backup(now.add(const Duration(days: 3)));
      expect(prune([future]), isEmpty);
    });
  });

  group('pre-restore snapshots', () {
    test('capped at 3 and exempt from the age ladder', () {
      final snapshots = [
        // Five pre-restores, all far older than a year — the cap, not the
        // ladder, decides their fate.
        for (var i = 0; i < 5; i++) preRestore(now.subtract(Duration(days: 400 + i))),
        aged(1),
      ];
      final doomed = prune(snapshots);

      expect(doomed, hasLength(2));
      expect(doomed.every((n) => n.contains('prerestore')), isTrue);
      // The two OLDEST pre-restores die.
      final survivingPreRestores = 5 - doomed.length;
      expect(survivingPreRestores, 3);
    });
  });

  group('RetentionPruner.prune (filesystem)', () {
    test('deletes only grammar-matching files; foreign files untouched',
        () async {
      final fs = MemoryFileSystem.test();
      final repo = SnapshotRepository(fs);
      final dir = repo.snapshotsDir('/dest');
      await dir.create(recursive: true);

      // 60 snapshots, 4 per day going back 15 days — well inside the daily
      // tier, so they must thin to roughly one per day.
      for (var i = 0; i < 60; i++) {
        final name = SnapshotRepository.fileNameFor(
          kind: SnapshotKind.backup,
          appVersion: '1.0.0',
          timestamp: now.subtract(Duration(days: 3 + i ~/ 4, hours: i % 4)),
        );
        await dir.childFile(name).writeAsString('zip');
      }
      await dir.childFile('my-vacation-photos.zip').writeAsString('precious');
      await dir.childFile('.AppFlowy-backup-v1-x.zip.tmp').writeAsString('tmp');

      await const RetentionPruner().prune(repo, '/dest', now: now);

      expect(await dir.childFile('my-vacation-photos.zip').exists(), isTrue);
      expect(
        await dir.childFile('.AppFlowy-backup-v1-x.zip.tmp').exists(),
        isTrue,
        reason: 'pruner must not race the engine over temp files',
      );
      final remaining = (await repo.list('/dest')).length;
      expect(remaining, lessThan(60), reason: 'daily tier must have thinned');
      expect(remaining, greaterThan(10), reason: 'one per day must survive');
    });
  });
}
