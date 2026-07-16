import 'dart:async';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/snapshot_engine.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy/shared/backup/workspace_path_resolver.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:file/file.dart';
import 'package:flutter/foundation.dart';

/// Where a restore currently is. The order below IS the state machine:
///   idle → confirmed → preRestoreSnapshot → extracting → validating
///        → swapping → awaitingRelaunch, with `failed` reachable from any
/// working phase. No live data is touched before [swapping]; see [restore].
enum RestorePhase {
  idle,
  confirmed,
  preRestoreSnapshot,
  extracting,
  validating,
  swapping,
  awaitingRelaunch,
  failed,
}

/// Why a restore stopped. Everything except [rollbackFailed] leaves the live
/// workspace exactly as it was.
enum RestoreFailure {
  workspaceNotFound,
  preRestoreSnapshotFailed,
  extractFailed,
  manifestMissing,
  unsupportedFormat,
  missingCollabDb,
  nothingExtracted,
  declinedNewerVersion,
  swapFailed,

  /// The live folder was renamed away AND renaming it back failed — the only
  /// state that needs manual attention. [RestoreResult.preRestoreDirPath]
  /// holds the folder containing the user's data; nothing is deleted.
  rollbackFailed,
}

/// Published through [RestoreService.progress] for the UI's progress dialog.
class RestoreProgress {
  const RestoreProgress(this.phase, {this.failure, this.message});

  final RestorePhase phase;
  final RestoreFailure? failure;
  final String? message;
}

class RestoreResult {
  const RestoreResult.success({required this.preRestoreDirPath})
      : ok = true,
        failure = null,
        failedPhase = null,
        message = null;

  const RestoreResult.failed(
    this.failure,
    this.failedPhase, {
    this.message,
    this.preRestoreDirPath,
  }) : ok = false;

  final bool ok;
  final RestoreFailure? failure;
  final RestorePhase? failedPhase;
  final String? message;

  /// After success: the renamed-away previous live folder (kept on disk).
  /// After [RestoreFailure.rollbackFailed]: where the user's data actually is.
  final String? preRestoreDirPath;
}

typedef ExtractSnapshotFn = Future<SnapshotManifest?> Function({
  required String zipPath,
  required String stagingDirPath,
});

typedef RenameDirFn = Future<void> Function(Directory dir, String newPath);

/// Restores a snapshot zip over the live workspace folder.
///
/// The only code in the backup feature that can destroy data, so it is built
/// around one invariant: **at every failure point the live folder is either
/// untouched or already fully restored.** Concretely:
///   - nothing is mutated before the pre-restore snapshot succeeds;
///   - extraction goes into a sibling staging folder, never over live data;
///   - the swap is two renames; if the second fails the first is renamed
///     back (single-rename rollback), and the renamed-away previous live
///     folder is never deleted by the same run that created it.
///
/// One deliberate deviation from the spec's step order: the pre-restore
/// snapshot is taken BEFORE [BackupService.pause], not after — a paused
/// BackupService refuses every run including forced ones, and this feature
/// does not modify backup_service.dart. Safety is unchanged: pause() awaits
/// any in-flight run, and no mutation happens until after pause() returns.
///
/// All effects are injected so the machine is unit-testable on a
/// MemoryFileSystem with faked engine calls; [RestoreService.production]
/// wires the real ones. This class does no logging (keeps unit tests free of
/// the FFI-backed logger) — callers log the returned result.
class RestoreService {
  RestoreService({
    required this.fileSystem,
    required this.resolveWorkspacePath,
    required this.pauseBackups,
    required this.resumeBackups,
    required this.takePreRestoreSnapshot,
    required this.extract,
    required this.currentAppVersion,
    RenameDirFn? renameDir,
    DateTime Function()? now,
  })  : renameDir = renameDir ?? _defaultRenameDir,
        now = now ?? DateTime.now;

  /// The real wiring: local disk, the running [BackupService], the isolate
  /// zip engine, and the same workspace resolution the backup side uses.
  factory RestoreService.production() {
    final backupService = getIt<BackupService>();
    return RestoreService(
      fileSystem: BackupService.localFs,
      resolveWorkspacePath: _productionWorkspacePath,
      pauseBackups: backupService.pause,
      resumeBackups: backupService.resume,
      takePreRestoreSnapshot: () =>
          backupService.backupNow(trigger: BackupTrigger.preRestore),
      extract: extractSnapshot,
      currentAppVersion: () => ApplicationInfo.applicationVersion,
    );
  }

  final FileSystem fileSystem;
  final Future<String?> Function() resolveWorkspacePath;
  final Future<void> Function() pauseBackups;
  final Future<void> Function() resumeBackups;
  final Future<BackupResult> Function() takePreRestoreSnapshot;
  final ExtractSnapshotFn extract;
  final String Function() currentAppVersion;
  final RenameDirFn renameDir;
  final DateTime Function() now;

  /// How many renamed-away previous-live folders survive the start-of-restore
  /// housekeeping (plus the one this run is about to create).
  static const keepPreRestoreDirs = 2;

  final ValueNotifier<RestoreProgress> progress =
      ValueNotifier(const RestoreProgress(RestorePhase.idle));

  /// Runs the whole machine. [confirmNewerAppVersion] is awaited when the
  /// snapshot was written by a NEWER app than the one running (the risky
  /// direction); returning false aborts with live data untouched.
  Future<RestoreResult> restore({
    required String zipPath,
    required Future<bool> Function(String snapshotAppVersion)
        confirmNewerAppVersion,
  }) async {
    _publish(RestorePhase.confirmed);

    final livePath = await resolveWorkspacePath();
    if (livePath == null) {
      return _fail(
        RestoreFailure.workspaceNotFound,
        RestorePhase.confirmed,
        'could not locate the live workspace folder',
      );
    }
    final live = fileSystem.directory(livePath);
    final parentPath = live.parent.path;
    final liveName = fileSystem.path.basename(livePath);

    // Housekeeping runs at the START of a restore, never at the end, so a
    // failure can never destroy the fallback this run is about to create.
    await _trimPreRestoreDirs(parentPath, liveName);

    // Safety net #1: the current state gets its own snapshot first.
    _publish(RestorePhase.preRestoreSnapshot);
    var snapshot = await takePreRestoreSnapshot();
    if (snapshot.outcome == BackupOutcome.noChanges) {
      // A concurrent periodic run can coalesce with ours and answer
      // "no changes" without writing a pre-restore zip. It has finished by
      // now, so one retry is guaranteed to be our own forced run.
      snapshot = await takePreRestoreSnapshot();
    }
    if (snapshot.outcome != BackupOutcome.snapshotCreated) {
      return _fail(
        RestoreFailure.preRestoreSnapshotFailed,
        RestorePhase.preRestoreSnapshot,
        'pre-restore snapshot did not complete '
        '(${snapshot.outcome.name}${snapshot.error == null ? '' : ': ${snapshot.error}'})',
      );
    }

    // From here on no backup may run until we finish: the workspace folder
    // is about to be swapped underneath the service.
    await pauseBackups();
    var resumed = false;
    Future<void> resumeOnce() async {
      if (resumed) {
        return;
      }
      resumed = true;
      try {
        await resumeBackups();
      } catch (_) {
        // Never mask the restore's own outcome with a resume error.
      }
    }

    try {
      final ts = _formatTimestamp(now());
      final stagingPath =
          fileSystem.path.join(parentPath, '$liveName.restore-staging-$ts');

      // Extract into the sibling staging folder. A corrupt zip throws HERE —
      // live data untouched.
      _publish(RestorePhase.extracting);
      SnapshotManifest? manifest;
      try {
        manifest = await extract(zipPath: zipPath, stagingDirPath: stagingPath);
      } catch (e) {
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.extractFailed,
          RestorePhase.extracting,
          e.toString(),
        );
      }

      // Validate the staging folder before it may replace anything.
      _publish(RestorePhase.validating);
      if (manifest == null) {
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.manifestMissing,
          RestorePhase.validating,
          'snapshot has no manifest.json — cannot verify its format',
        );
      }
      if (manifest.formatVersion != SnapshotManifest.currentFormatVersion) {
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.unsupportedFormat,
          RestorePhase.validating,
          'snapshot format v${manifest.formatVersion} is not supported '
          '(this app understands v${SnapshotManifest.currentFormatVersion})',
        );
      }
      if (!await _containsDirNamed(stagingPath, 'collab_db')) {
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.missingCollabDb,
          RestorePhase.validating,
          'snapshot contains no collab_db folder — not a workspace snapshot',
        );
      }
      if (!await _containsAnyFile(stagingPath)) {
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.nothingExtracted,
          RestorePhase.validating,
          'nothing was extracted from the snapshot',
        );
      }
      if (isVersionNewer(manifest.appVersion, currentAppVersion())) {
        final proceed = await confirmNewerAppVersion(manifest.appVersion);
        if (!proceed) {
          await _deleteQuietly(stagingPath);
          return _fail(
            RestoreFailure.declinedNewerVersion,
            RestorePhase.validating,
            null,
          );
        }
      }

      // The swap. Rename #1 parks the live folder; rename #2 promotes
      // staging. If #2 fails, #1 is renamed back — at every point the live
      // name is either the original data or the fully-extracted snapshot.
      _publish(RestorePhase.swapping);
      final preRestorePath = _uniquePath(
        fileSystem.path.join(parentPath, '$liveName.pre-restore-$ts'),
      );
      try {
        await renameDir(live, preRestorePath);
      } catch (e) {
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.swapFailed,
          RestorePhase.swapping,
          'could not move the current data folder aside: $e',
        );
      }
      try {
        await renameDir(fileSystem.directory(stagingPath), livePath);
      } catch (e) {
        try {
          await renameDir(fileSystem.directory(preRestorePath), livePath);
        } catch (rollbackError) {
          // The one genuinely bad state. Delete NOTHING; tell the caller
          // exactly where the data is.
          return _fail(
            RestoreFailure.rollbackFailed,
            RestorePhase.swapping,
            'restore failed and rolling back also failed. Your data is '
            'intact in "$preRestorePath" but could not be moved back to '
            '"$livePath" ($rollbackError). Quit AppFlowy and rename the '
            'folder back by hand (see RESTORE.md).',
            preRestoreDirPath: preRestorePath,
          );
        }
        await _deleteQuietly(stagingPath);
        return _fail(
          RestoreFailure.swapFailed,
          RestorePhase.swapping,
          'could not move the restored data into place (rolled back, your '
          'data is unchanged): $e',
        );
      }

      // Done. The previous live folder stays on disk as the last-ditch
      // fallback; the next restore's housekeeping will eventually trim it.
      _publish(RestorePhase.awaitingRelaunch);
      return RestoreResult.success(preRestoreDirPath: preRestorePath);
    } finally {
      // The high-water mark is stale after a swap, so the next scheduled
      // tick correctly snapshots the restored state.
      await resumeOnce();
    }
  }

  /// `<liveName>.pre-restore-*` siblings beyond the newest
  /// [keepPreRestoreDirs] are deleted. Failures are ignored — housekeeping
  /// must never block a restore.
  Future<void> _trimPreRestoreDirs(String parentPath, String liveName) async {
    final prefix = '$liveName.pre-restore-';
    final names = <String>[];
    try {
      await for (final entity
          in fileSystem.directory(parentPath).list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = fileSystem.path.basename(entity.path);
        if (name.startsWith(prefix)) {
          names.add(name);
        }
      }
    } catch (_) {
      return;
    }
    // The timestamp suffix (yyyyMMdd-HHmmss) sorts lexicographically.
    names.sort((a, b) => b.compareTo(a));
    for (final name in names.skip(keepPreRestoreDirs)) {
      await _deleteQuietly(fileSystem.path.join(parentPath, name));
    }
  }

  Future<bool> _containsDirNamed(String rootPath, String dirName) async {
    try {
      await for (final entity in fileSystem
          .directory(rootPath)
          .list(recursive: true, followLinks: false)) {
        if (entity is Directory &&
            fileSystem.path.basename(entity.path) == dirName) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _containsAnyFile(String rootPath) async {
    try {
      await for (final entity in fileSystem
          .directory(rootPath)
          .list(recursive: true, followLinks: false)) {
        if (entity is File) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final dir = fileSystem.directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Collisions are practically impossible (second-resolution timestamp) but
  /// a rename onto an existing folder must never be attempted.
  String _uniquePath(String path) {
    var candidate = path;
    var suffix = 2;
    while (fileSystem.directory(candidate).existsSync() ||
        fileSystem.file(candidate).existsSync()) {
      candidate = '$path-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  void _publish(RestorePhase phase) {
    progress.value = RestoreProgress(phase);
  }

  RestoreResult _fail(
    RestoreFailure failure,
    RestorePhase phase,
    String? message, {
    String? preRestoreDirPath,
  }) {
    progress.value = RestoreProgress(
      RestorePhase.failed,
      failure: failure,
      message: message,
    );
    return RestoreResult.failed(
      failure,
      phase,
      message: message,
      preRestoreDirPath: preRestoreDirPath,
    );
  }

  static String _formatTimestamp(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${p2(t.month)}${p2(t.day)}-'
        '${p2(t.hour)}${p2(t.minute)}${p2(t.second)}';
  }

  /// True when [candidate] is a strictly newer x.y.z than [current].
  /// Unparsable segments count as 0, so 'unknown'/'' never blocks a restore.
  @visibleForTesting
  static bool isVersionNewer(String candidate, String current) {
    List<int> parse(String v) => v
        .split('.')
        .map((s) => int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0)
        .toList();
    final a = parse(candidate);
    final b = parse(current);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) {
        return x > y;
      }
    }
    return false;
  }

  static Future<void> _defaultRenameDir(Directory dir, String newPath) async {
    await dir.rename(newPath);
  }

  /// Same resolution the backup side performs: data root from
  /// ApplicationDataStorage, per-server suffix rules mirrored from Rust by
  /// [WorkspacePathResolver].
  static Future<String?> _productionWorkspacePath() async {
    final root = await getIt<ApplicationDataStorage>().getPath();
    String? baseUrl;
    try {
      baseUrl = getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url;
    } catch (_) {
      baseUrl = null; // Local-only mode has no cloud env registered.
    }
    final resolver = WorkspacePathResolver(
      BackupService.localFs,
      dataRootPath: root,
      cloudBaseUrl: baseUrl,
    );
    final dir = await resolver.resolve();
    return dir?.path;
  }
}
