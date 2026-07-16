import 'package:appflowy/shared/backup/change_detector.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChangeDetector signal exclusions', () {
    final detector = ChangeDetector(MemoryFileSystem.test());

    test('app rotating logs are excluded', () {
      expect(detector.isExcludedFromSignal('log.2026-07-16'), isTrue);
      expect(detector.isExcludedFromSignal('log.sync.2026-07-15-18'), isTrue);
    });

    test('RocksDB info logs are excluded', () {
      expect(detector.isExcludedFromSignal('LOG'), isTrue);
      expect(detector.isExcludedFromSignal('LOG.old.1752530421'), isTrue);
    });

    test('RocksDB write-ahead logs MUST count (they carry typed content)', () {
      expect(detector.isExcludedFromSignal('000004.log'), isFalse);
      expect(detector.isExcludedFromSignal('000123.log'), isFalse);
    });

    test('ordinary data files count', () {
      expect(detector.isExcludedFromSignal('MANIFEST-000005'), isFalse);
      expect(detector.isExcludedFromSignal('flowy-database.db'), isFalse);
      expect(detector.isExcludedFromSignal('CURRENT'), isFalse);
    });
  });

  group('ChangeDetector.scan', () {
    test('excluded files change neither mtime nor count', () async {
      final fs = MemoryFileSystem.test();
      final detector = ChangeDetector(fs);
      final root = fs.directory('/ws')..createSync();

      root.childFile('data.bin').writeAsStringSync('v1');
      final before = await detector.scan('/ws');

      // Touch only an excluded file, newer than everything else.
      final log = root.childFile('log.2026-07-16')..writeAsStringSync('spam');
      log.setLastModifiedSync(DateTime(2030));
      final after = await detector.scan('/ws');

      expect(after.differsFrom(before), isFalse);
    });

    test('a WAL write is detected', () async {
      final fs = MemoryFileSystem.test();
      final detector = ChangeDetector(fs);
      final collab = fs.directory('/ws/uid/collab_db')
        ..createSync(recursive: true);
      collab.childFile('000004.log').writeAsStringSync('v1');
      final before = await detector.scan('/ws');

      collab.childFile('000004.log')
        ..writeAsStringSync('v1 + typed text')
        ..setLastModifiedSync(DateTime(2031));
      final after = await detector.scan('/ws');

      expect(after.differsFrom(before), isTrue);
    });

    test('pure deletion is detected via file count', () async {
      final fs = MemoryFileSystem.test();
      final detector = ChangeDetector(fs);
      final root = fs.directory('/ws')..createSync();
      root.childFile('a.bin').writeAsStringSync('a');
      root.childFile('b.bin').writeAsStringSync('b');
      final before = await detector.scan('/ws');

      root.childFile('b.bin').deleteSync();
      final after = await detector.scan('/ws');

      expect(after.differsFrom(before), isTrue);
      expect(after.fileCount, before.fileCount - 1);
    });

    test('missing root yields the empty signal', () async {
      final detector = ChangeDetector(MemoryFileSystem.test());
      final signal = await detector.scan('/nope');
      expect(signal.differsFrom(ChangeSignal.empty), isFalse);
    });
  });
}
