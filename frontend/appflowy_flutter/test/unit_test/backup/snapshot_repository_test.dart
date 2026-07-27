import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filename grammar', () {
    test('round-trips a backup name', () {
      final t = DateTime(2026, 7, 16, 12, 4, 9);
      final name = SnapshotRepository.fileNameFor(
        kind: SnapshotKind.backup,
        appVersion: '0.11.4',
        timestamp: t,
      );
      expect(name, 'Ludwig-backup-v0.11.4-20260716-120409.zip');
      final parsed = SnapshotRepository.parse(name)!;
      expect(parsed.kind, SnapshotKind.backup);
      expect(parsed.appVersion, '0.11.4');
      expect(parsed.timestamp, t);
    });

    // The Ludwig rename (2026-07-27) changed the prefix new snapshots are
    // written with. Every snapshot taken before it carries `AppFlowy-`, and
    // they are real backups of real writing -- if the reader stopped
    // recognising them the restore browser and the pruner would go silently
    // blind to the whole existing set. See specs/distribution.md.
    test('still reads pre-rename AppFlowy- snapshots', () {
      final parsed =
          SnapshotRepository.parse('AppFlowy-backup-v0.11.4-20260716-120409.zip');
      expect(parsed, isNotNull);
      expect(parsed!.kind, SnapshotKind.backup);
      expect(parsed.appVersion, '0.11.4');
      expect(parsed.timestamp, DateTime(2026, 7, 16, 12, 4, 9));

      final pre = SnapshotRepository.parse(
        'AppFlowy-prerestore-v0.11.4-20260719-015952.zip',
      );
      expect(pre, isNotNull);
      expect(pre!.kind, SnapshotKind.preRestore);
    });

    test('writes the Ludwig prefix, never the old one', () {
      for (final kind in SnapshotKind.values) {
        final name = SnapshotRepository.fileNameFor(
          kind: kind,
          appVersion: '0.11.4',
          timestamp: DateTime(2026, 7, 27, 9),
        );
        expect(name, startsWith('Ludwig-'));
        expect(name, isNot(startsWith('AppFlowy-')));
      }
    });

    test('a foreign prefix is still rejected', () {
      expect(
        SnapshotRepository.parse('Notion-backup-v1.0-20260716-120409.zip'),
        isNull,
        reason: 'the pruner deletes what this grammar matches -- it must stay strict',
      );
    });

    test('round-trips a pre-restore name', () {
      final name = SnapshotRepository.fileNameFor(
        kind: SnapshotKind.preRestore,
        appVersion: '1.0.0-beta',
        timestamp: DateTime(2026, 1, 2, 3, 4, 5),
      );
      final parsed = SnapshotRepository.parse(name)!;
      expect(parsed.kind, SnapshotKind.preRestore);
      expect(parsed.appVersion, '1.0.0-beta');
    });

    test('rejects foreign names', () {
      expect(SnapshotRepository.parse('holiday.zip'), isNull);
      expect(SnapshotRepository.parse('AppFlowy-backup.zip'), isNull);
      expect(
        SnapshotRepository.parse('.AppFlowy-backup-v1-20260716-120409.zip.tmp'),
        isNull,
        reason: 'in-progress temp files must never parse as snapshots',
      );
    });
  });

  group('list', () {
    test('sorts newest first and tolerates foreign files', () async {
      final fs = MemoryFileSystem.test();
      final repo = SnapshotRepository(fs);
      final dir = repo.snapshotsDir('/dest');
      await dir.create(recursive: true);

      final older = SnapshotRepository.fileNameFor(
        kind: SnapshotKind.backup,
        appVersion: '1',
        timestamp: DateTime(2026, 7, 15, 10),
      );
      final newer = SnapshotRepository.fileNameFor(
        kind: SnapshotKind.backup,
        appVersion: '1',
        timestamp: DateTime(2026, 7, 16, 10),
      );
      await dir.childFile(older).writeAsString('aa');
      await dir.childFile(newer).writeAsString('bbbb');
      await dir.childFile('random.txt').writeAsString('ignore me');

      final list = await repo.list('/dest');
      expect(list, hasLength(2));
      expect(list.first.fileName, newer);
      expect(list.first.sizeBytes, 4);
    });

    test('missing folder lists empty', () async {
      final repo = SnapshotRepository(MemoryFileSystem.test());
      expect(await repo.list('/absent'), isEmpty);
    });
  });
}
