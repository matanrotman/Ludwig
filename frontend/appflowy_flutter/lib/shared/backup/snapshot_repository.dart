import 'package:file/file.dart';

/// The two kinds of snapshot this feature writes.
enum SnapshotKind { backup, preRestore }

/// A parsed snapshot filename plus cheap file metadata.
///
/// Listing reads directory entries only (names + sizes) — metadata stays
/// locally available even when Google Drive's streaming mode has evicted the
/// file contents to the cloud.
class SnapshotInfo {
  const SnapshotInfo({
    required this.kind,
    required this.appVersion,
    required this.timestamp,
    required this.fileName,
    required this.sizeBytes,
  });

  final SnapshotKind kind;
  final String appVersion;
  final DateTime timestamp;
  final String fileName;
  final int sizeBytes;
}

/// Filename grammar and listing for the snapshot destination folder.
///
/// Grammar (sortable, greppable, version-stamped):
///   `Ludwig-backup-v<version>-<yyyyMMdd-HHmmss>.zip`
///   `Ludwig-prerestore-v<version>-<yyyyMMdd-HHmmss>.zip`
/// In-progress writes use a dot-prefixed temp name (`.<finalName>.tmp`) and
/// are renamed into place only when complete, so a name matching this grammar
/// is by construction a finished snapshot.
///
/// ⚠️ The READER accepts `AppFlowy-` as well, and must keep doing so. Every
/// snapshot taken before the Ludwig rename carries the old prefix, and they
/// are real backups of the user's real writing. Narrowing this regex to
/// `Ludwig-` alone would make the restore browser, "Find something you lost"
/// and the retention pruner all silently blind to them -- the backups would
/// still be on disk, and nothing in the app would admit they existed.
/// The WRITER emits `Ludwig-` only; the two prefixes coexist by design and
/// old snapshots are deliberately NOT renamed on disk (renaming files inside
/// a proven backup set to make them tidier is a bad trade).
///
/// Everything here is strict-match: the pruner deletes ONLY names this
/// grammar produces, so foreign files in the user's Drive folder are never
/// touched.
class SnapshotRepository {
  SnapshotRepository(this.fileSystem);

  final FileSystem fileSystem;

  static const snapshotsSubfolder = 'snapshots';

  /// The prefix new snapshots are written with.
  static const _writePrefix = 'Ludwig';

  static final RegExp _nameGrammar = RegExp(
    r'^(?:Ludwig|AppFlowy)-(backup|prerestore)-v(.+)-(\d{8})-(\d{6})\.zip$',
  );

  static String tempNameFor(String finalName) => '.$finalName.tmp';

  static String fileNameFor({
    required SnapshotKind kind,
    required String appVersion,
    required DateTime timestamp,
  }) {
    final kindLabel = switch (kind) {
      SnapshotKind.backup => 'backup',
      SnapshotKind.preRestore => 'prerestore',
    };
    final ts = _formatTimestamp(timestamp);
    return '$_writePrefix-$kindLabel-v$appVersion-$ts.zip';
  }

  static String _formatTimestamp(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${p2(t.month)}${p2(t.day)}-'
        '${p2(t.hour)}${p2(t.minute)}${p2(t.second)}';
  }

  /// Parses a filename; returns null for anything not matching the grammar.
  static SnapshotInfo? parse(String fileName, {int sizeBytes = 0}) {
    final match = _nameGrammar.firstMatch(fileName);
    if (match == null) {
      return null;
    }
    final date = match.group(3)!;
    final time = match.group(4)!;
    final timestamp = DateTime(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(4, 6)),
      int.parse(date.substring(6, 8)),
      int.parse(time.substring(0, 2)),
      int.parse(time.substring(2, 4)),
      int.parse(time.substring(4, 6)),
    );
    return SnapshotInfo(
      kind: match.group(1) == 'backup'
          ? SnapshotKind.backup
          : SnapshotKind.preRestore,
      appVersion: match.group(2)!,
      timestamp: timestamp,
      fileName: fileName,
      sizeBytes: sizeBytes,
    );
  }

  /// The `snapshots/` directory under the user's chosen destination.
  Directory snapshotsDir(String destinationPath) =>
      fileSystem.directory(destinationPath).childDirectory(snapshotsSubfolder);

  /// Lists finished snapshots, newest first. Tolerates foreign files.
  Future<List<SnapshotInfo>> list(String destinationPath) async {
    final dir = snapshotsDir(destinationPath);
    if (!await dir.exists()) {
      return [];
    }
    final result = <SnapshotInfo>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      int size;
      try {
        size = await entity.length();
      } catch (_) {
        size = 0;
      }
      final info = parse(entity.basename, sizeBytes: size);
      if (info != null) {
        result.add(info);
      }
    }
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }
}
