import 'package:appflowy/shared/backup/snapshot_exclusions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const exclusions = SnapshotExclusions();

  group('excludes diagnostic logs', () {
    test('AppFlowy log files', () {
      expect(exclusions.shouldExclude('log.2026-07-17'), isTrue);
      expect(exclusions.shouldExclude('log.sync.2026-07-17-21'), isTrue);
    });

    test('RocksDB operational logs and their rotations', () {
      expect(exclusions.shouldExclude('612287731153768448/collab_db/LOG'), isTrue);
      expect(
        exclusions.shouldExclude('612287731153768448/collab_db/LOG.old.1784199569667823'),
        isTrue,
      );
    });
  });

  group('excludes derived search indexes', () {
    test('the indexes tree at any depth', () {
      expect(
        exclusions.shouldExclude(
          '612287731153768448/indexes/30b63f55/documents/9045eb21.store',
        ),
        isTrue,
      );
    });

    test('vector.db', () {
      expect(exclusions.shouldExclude('vector.db'), isTrue);
    });
  });

  group('never excludes real content', () {
    test('collab_db data files survive', () {
      expect(
        exclusions.shouldExclude('612287731153768448/collab_db/000316.sst'),
        isFalse,
      );
      expect(
        exclusions.shouldExclude('612287731153768448/collab_db/000047.log'),
        isFalse,
        reason: 'a RocksDB write-ahead log is DATA — only LOG/LOG.old are not',
      );
    });

    test('sqlite databases and collab_db_history survive', () {
      expect(
        exclusions.shouldExclude('612287731153768448/flowy-database.db'),
        isFalse,
      );
      expect(
        exclusions.shouldExclude(
          '612287731153768448/collab_db_history/collab_db_20260716.zip',
        ),
        isFalse,
        reason: 'the second independent safety net is deliberately kept',
      );
    });

    test('user files that merely CONTAIN a rule word are safe', () {
      // The whole reason matching is on segments and basenames, not substrings.
      expect(exclusions.shouldExclude('catalog.md'), isFalse);
      expect(exclusions.shouldExclude('my-indexes-of-refraction.md'), isFalse);
      expect(exclusions.shouldExclude('notes/backlog.txt'), isFalse);
      expect(exclusions.shouldExclude('travel-blog.md'), isFalse);
      expect(exclusions.shouldExclude('LOGISTICS.md'), isFalse);
    });
  });

  group('rules are individually opt-out-able', () {
    test('SnapshotExclusions.none keeps a bit-exact mirror', () {
      expect(SnapshotExclusions.none.shouldExclude('log.2026-07-17'), isFalse);
      expect(SnapshotExclusions.none.shouldExclude('vector.db'), isFalse);
      expect(SnapshotExclusions.none.activeRuleNames, isEmpty);
    });

    test('logs can be dropped while indexes are kept', () {
      const logsOnly = SnapshotExclusions(excludeSearchIndexes: false);
      expect(logsOnly.shouldExclude('log.2026-07-17'), isTrue);
      expect(logsOnly.shouldExclude('vector.db'), isFalse);
      expect(logsOnly.activeRuleNames, ['logs']);
    });

    test('the default records both rules for the manifest', () {
      expect(exclusions.activeRuleNames, ['logs', 'searchIndexes']);
    });
  });
}
