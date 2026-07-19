import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:file/file.dart';

/// How densely snapshots are kept within one rung of the retention ladder.
enum RetentionGranularity {
  /// Keep every snapshot in this age range.
  all,

  /// Keep only the newest snapshot of each calendar day.
  daily,

  /// Keep only the newest snapshot of each 7-day bucket.
  weekly,

  /// Keep only the newest snapshot of each calendar month.
  monthly,
}

/// One rung: snapshots younger than [maxAge] are kept at [granularity].
class RetentionTier {
  const RetentionTier({required this.maxAge, required this.granularity});

  final Duration maxAge;
  final RetentionGranularity granularity;
}

/// Tiered ("grandfather-father-son") retention for the snapshot folder.
///
/// Chosen by the user 2026-07-19. The previous policy kept the newest 50
/// snapshots plus one per calendar day *forever*, which never expired anything
/// — roughly 550 MB/year and growing without bound. This one keeps dense
/// recent history and thins it with age, so a year of history costs a few tens
/// of megabytes and then holds steady:
///
///   * younger than 2 days  → keep everything (capped at [keepRecent])
///   * 2–30 days            → newest per day
///   * 30 days–6 months     → newest per week
///   * 6 months–1 year      → newest per month
///   * older than 1 year    → deleted
///
/// Pre-restore snapshots are exempt from all of the above and capped at the
/// newest [keepPreRestore] — they are the undo button for a restore, so their
/// value is recency, not history.
///
/// Deletes ONLY filenames produced by [SnapshotRepository]'s grammar — a
/// foreign file in the user's Drive folder is never touched, whatever it is
/// named.
class RetentionPruner {
  const RetentionPruner({
    this.tiers = defaultTiers,
    this.keepRecent = 50,
    this.keepPreRestore = 3,
  });

  static const List<RetentionTier> defaultTiers = [
    RetentionTier(
      maxAge: Duration(days: 2),
      granularity: RetentionGranularity.all,
    ),
    RetentionTier(
      maxAge: Duration(days: 30),
      granularity: RetentionGranularity.daily,
    ),
    RetentionTier(
      maxAge: Duration(days: 182),
      granularity: RetentionGranularity.weekly,
    ),
    RetentionTier(
      maxAge: Duration(days: 365),
      granularity: RetentionGranularity.monthly,
    ),
  ];

  final List<RetentionTier> tiers;

  /// Hard ceiling on how many snapshots the [RetentionGranularity.all] tier
  /// may keep outright. A burst of writing (a snapshot every 30 min) could
  /// otherwise put hundreds of files in the keep-everything window; beyond
  /// this count they fall through to daily granularity instead.
  final int keepRecent;

  final int keepPreRestore;

  /// Returns the file names that should be deleted. Pure policy — no IO, and
  /// [now] is injected rather than read from the clock — so it is trivially
  /// unit-testable at any point on the ladder.
  List<String> selectForDeletion(
    List<SnapshotInfo> snapshots, {
    required DateTime now,
  }) {
    final backups = snapshots
        .where((s) => s.kind == SnapshotKind.backup)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final preRestores = snapshots
        .where((s) => s.kind == SnapshotKind.preRestore)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final delete = <String>[];
    final seenBuckets = <String>{};

    for (var i = 0; i < backups.length; i++) {
      final s = backups[i];
      final age = now.difference(s.timestamp);

      // A timestamp in the future (clock skew, a hand-copied file) yields a
      // negative age and lands in the first tier — kept. Deliberate: never
      // delete something we can't confidently age.
      final tier = _tierFor(age);
      if (tier == null) {
        delete.add(s.fileName); // Older than the last rung.
        continue;
      }

      var granularity = tier.granularity;
      if (granularity == RetentionGranularity.all && i >= keepRecent) {
        granularity = RetentionGranularity.daily;
      }
      if (granularity == RetentionGranularity.all) {
        continue;
      }

      // Iterating newest-first means the first snapshot seen for a bucket is
      // that bucket's newest — it survives, the rest of the bucket goes.
      if (!seenBuckets.add(_bucketKey(granularity, s.timestamp))) {
        delete.add(s.fileName);
      }
    }

    for (var i = keepPreRestore; i < preRestores.length; i++) {
      delete.add(preRestores[i].fileName);
    }

    return delete;
  }

  RetentionTier? _tierFor(Duration age) {
    for (final tier in tiers) {
      if (age <= tier.maxAge) {
        return tier;
      }
    }
    return null;
  }

  /// Weekly buckets are counted off a fixed reference date rather than
  /// ISO week numbers — the exact boundary doesn't matter, only that the
  /// bucketing is stable and independent of when pruning happens to run.
  static final DateTime _weekEpoch = DateTime(2000);

  String _bucketKey(RetentionGranularity granularity, DateTime t) {
    switch (granularity) {
      case RetentionGranularity.daily:
        return 'd:${t.year}-${t.month}-${t.day}';
      case RetentionGranularity.weekly:
        final weeks = t.difference(_weekEpoch).inDays ~/ 7;
        return 'w:$weeks';
      case RetentionGranularity.monthly:
        return 'm:${t.year}-${t.month}';
      case RetentionGranularity.all:
        return 'a:${t.microsecondsSinceEpoch}';
    }
  }

  /// Applies the policy to the destination's snapshots folder.
  Future<int> prune(
    SnapshotRepository repository,
    String destination, {
    DateTime? now,
  }) async {
    final listing = await repository.list(destination);
    final doomed = selectForDeletion(listing, now: now ?? DateTime.now());
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
