import 'package:path/path.dart' as p;

/// What a snapshot deliberately leaves out.
///
/// Decided 2026-07-19 after measuring a real snapshot: ~49% of the raw bytes
/// in every backup were log files and ~7% were derived search indexes. Neither
/// is needed to recover a single word of the user's writing — the content
/// lives in `collab_db` and the sqlite databases, which are never excluded.
///
/// Two rules, both opt-out-able so a future settings toggle (or a user who
/// wants a bit-exact folder mirror) can turn them off without touching the
/// engine:
///
///  * [excludeLogs] — AppFlowy's own diagnostic logs plus RocksDB's `LOG`
///    files. On this fork these grow ~1 MB/day on their own because the dead
///    cloud-sync loop retries every 15s forever (see STATUS.md), so they
///    inflate every future snapshot even during a week of no writing.
///  * [excludeSearchIndexes] — the `indexes/` trees and `vector.db`. These are
///    derived from the content and are rebuilt by the app; a restore may have
///    briefly slower search while that happens, but nothing is lost.
///
/// Matching is on path SEGMENTS and file basenames, never on substrings, so a
/// user file that merely contains "log" or "indexes" in its name (`catalog.md`,
/// `indexes-of-refraction.md`) can never be caught by these rules.
class SnapshotExclusions {
  const SnapshotExclusions({
    this.excludeLogs = true,
    this.excludeSearchIndexes = true,
  });

  /// Keeps everything — a bit-exact mirror of the source folder.
  static const SnapshotExclusions none = SnapshotExclusions(
    excludeLogs: false,
    excludeSearchIndexes: false,
  );

  final bool excludeLogs;
  final bool excludeSearchIndexes;

  /// Short stable identifiers for the active rules. Recorded in the snapshot's
  /// manifest so a human reading it later can tell that these files were left
  /// out ON PURPOSE rather than lost.
  List<String> get activeRuleNames => [
        if (excludeLogs) 'logs',
        if (excludeSearchIndexes) 'searchIndexes',
      ];

  /// [relativePath] is relative to the workspace data folder, e.g.
  /// `612287731153768448/collab_db/LOG` or `log.sync.2026-07-17-21`.
  bool shouldExclude(String relativePath) {
    final segments = p.split(p.normalize(relativePath));
    if (segments.isEmpty) {
      return false;
    }
    final name = segments.last;

    if (excludeLogs) {
      // AppFlowy's own logs: `log.2026-07-17`, `log.sync.2026-07-17-21`.
      if (name.startsWith('log.')) {
        return true;
      }
      // RocksDB's operational log and its rotations: `LOG`, `LOG.old.<n>`.
      if (name == 'LOG' || name.startsWith('LOG.old.')) {
        return true;
      }
    }

    if (excludeSearchIndexes) {
      if (segments.contains('indexes')) {
        return true;
      }
      if (name == 'vector.db') {
        return true;
      }
    }

    return false;
  }
}
