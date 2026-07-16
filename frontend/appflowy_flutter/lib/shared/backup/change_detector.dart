import 'package:file/file.dart';

/// The cheap "has anything changed since the last snapshot" signal:
/// the max modification time across the workspace folder plus a file count
/// (the count catches a pure deletion whose parent-dir mtime a filesystem
/// might not surface through this walk).
class ChangeSignal {
  const ChangeSignal({
    required this.maxMtimeMillis,
    required this.fileCount,
  });

  static const empty = ChangeSignal(maxMtimeMillis: 0, fileCount: 0);

  final int maxMtimeMillis;
  final int fileCount;

  bool differsFrom(ChangeSignal other) =>
      maxMtimeMillis != other.maxMtimeMillis || fileCount != other.fileCount;
}

/// Scans a workspace folder for the change signal.
///
/// Signal-only exclusions (the files are still INCLUDED in every zip — they
/// are just not allowed to *trigger* one):
/// - `log.*` — the app's own rotating logs at the workspace root churn even
///   while the user is idle, which would make every tick look like a change.
/// - `LOG` / `LOG.old.*` — RocksDB info logs, which stats-dump periodically.
///
/// Deliberately NOT excluded: RocksDB write-ahead logs (`000004.log` etc.) —
/// despite the `.log` suffix they carry the user's typed content and are
/// exactly the change we exist to detect. Hence prefix matching on basename,
/// never suffix matching.
class ChangeDetector {
  ChangeDetector(this.fileSystem);

  final FileSystem fileSystem;

  static final RegExp _signalExcluded = RegExp(r'^(log\.|LOG$|LOG\.old)');

  bool isExcludedFromSignal(String basename) =>
      _signalExcluded.hasMatch(basename);

  Future<ChangeSignal> scan(String rootPath) async {
    final root = fileSystem.directory(rootPath);
    if (!await root.exists()) {
      return ChangeSignal.empty;
    }

    var maxMtime = 0;
    var fileCount = 0;

    Future<void> walk(Directory dir) async {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (entity is File) {
          if (isExcludedFromSignal(name)) {
            continue;
          }
          fileCount += 1;
          try {
            final mtime = (await entity.lastModified()).millisecondsSinceEpoch;
            if (mtime > maxMtime) {
              maxMtime = mtime;
            }
          } catch (_) {
            // A file can vanish between listing and stat (live database);
            // it still counted, which is signal enough.
          }
        } else if (entity is Directory) {
          // Directory mtimes catch creations/deletions inside them.
          try {
            final mtime = (await entity.stat()).modified.millisecondsSinceEpoch;
            if (mtime > maxMtime) {
              maxMtime = mtime;
            }
          } catch (_) {}
          await walk(entity);
        }
      }
    }

    await walk(root);
    return ChangeSignal(maxMtimeMillis: maxMtime, fileCount: fileCount);
  }
}
