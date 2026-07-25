import 'dart:async';
import 'dart:io' as io;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/backup/backup_settings.dart';
import 'package:appflowy/shared/backup/change_detector.dart';
import 'package:appflowy/shared/backup/drive_mount_detector.dart';
import 'package:appflowy/shared/backup/retention_pruner.dart';
import 'package:appflowy/shared/backup/snapshot_engine.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy/shared/backup/workspace_path_resolver.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';

/// What a single backup run concluded.
enum BackupOutcome {
  snapshotCreated,
  noChanges,
  disabled,
  paused,
  noDestination,
  destinationInvalid,
  workspaceNotFound,
  failed,
}

class BackupResult {
  const BackupResult(this.outcome, {this.snapshotName, this.error});

  final BackupOutcome outcome;
  final String? snapshotName;
  final String? error;
}

/// Live status for the settings page.
class BackupStatus {
  const BackupStatus({
    this.lastRunAt,
    this.lastOutcome,
    this.lastSnapshotName,
    this.destination,
    this.destinationSource,
    this.running = false,
  });

  final DateTime? lastRunAt;
  final BackupOutcome? lastOutcome;
  final String? lastSnapshotName;
  final String? destination;
  final BackupDestinationSource? destinationSource;
  final bool running;
}

/// Orchestrates automatic workspace backups.
///
/// The constructor is inert — no timer, no IO — so resolving the singleton in
/// tests is harmless. [start] arms the periodic timer; every run funnels
/// through [backupNow], which coalesces concurrent calls into one in-flight
/// future (a timer tick during a quit-triggered run must never zip twice).
/// Failures land in [status] and the log; nothing escapes into the timer.
class BackupService {
  BackupService();

  static const localFs = LocalFileSystem();

  final ValueNotifier<BackupStatus> status =
      ValueNotifier(const BackupStatus());

  Timer? _timer;
  Future<BackupResult>? _inFlight;
  bool _paused = false;
  bool _started = false;

  BackupSettingsStore get _store =>
      BackupSettingsStore(getIt<KeyValueStorage>());

  bool get isPaused => _paused;

  /// Arms the timer according to persisted settings. Idempotent.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await _rearmTimer();
    await _refreshDestinationStatus();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    // Let an in-flight run finish; it holds no references back to the timer.
    await _inFlight;
  }

  /// Restore in progress: no snapshots may run (the workspace folder is
  /// about to be swapped underneath us).
  Future<void> pause() async {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    await _inFlight;
  }

  Future<void> resume() async {
    _paused = false;
    await _rearmTimer();
  }

  /// Called by settings when enabled/interval/destination change.
  Future<void> settingsChanged() async {
    await _rearmTimer();
    await _refreshDestinationStatus();
  }

  Future<void> _rearmTimer() async {
    _timer?.cancel();
    _timer = null;
    if (_paused) {
      return;
    }
    final settings = await _store.loadSettings();
    if (!settings.enabled) {
      return;
    }
    _timer = Timer.periodic(
      Duration(minutes: settings.intervalMinutes),
      (_) => unawaited(backupNow(trigger: BackupTrigger.periodic)),
    );
  }

  /// Runs one backup. Concurrent callers share the same in-flight future.
  Future<BackupResult> backupNow({required BackupTrigger trigger}) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final run = _run(trigger).whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<BackupResult> _run(BackupTrigger trigger) async {
    try {
      if (_paused) {
        return const BackupResult(BackupOutcome.paused);
      }
      final settings = await _store.loadSettings();
      // Manual and pre-restore runs proceed even when automatic backup is
      // off — the user asked for this one explicitly.
      final isForced = trigger == BackupTrigger.manual ||
          trigger == BackupTrigger.preRestore ||
          trigger == BackupTrigger.preMigration;
      if (!settings.enabled && !isForced) {
        return const BackupResult(BackupOutcome.disabled);
      }

      _publish(running: true);

      final workspace = await _resolveWorkspace();
      if (workspace == null) {
        return _finish(const BackupResult(BackupOutcome.workspaceNotFound));
      }

      final destination = await _resolveDestination(settings);
      if (destination == null) {
        return _finish(const BackupResult(BackupOutcome.noDestination));
      }
      // Auto-detected destinations (the `AppFlowy Backups` folder inside the
      // Drive mount) are created on first use. Manually picked folders must
      // already exist — validation failing on a typo is the protection.
      if (destination.source != BackupDestinationSource.manual) {
        try {
          await localFs.directory(destination.path).create(recursive: true);
        } catch (e) {
          Log.error('[Backup] cannot create destination: $e');
          return _finish(const BackupResult(BackupOutcome.destinationInvalid));
        }
      }
      final problem = await validateDestination(
        localFs,
        destinationPath: destination.path,
        workspacePath: workspace.path,
      );
      if (problem != null) {
        Log.error('[Backup] destination invalid ($problem): '
            '${destination.path}');
        return _finish(const BackupResult(BackupOutcome.destinationInvalid));
      }

      final detector = ChangeDetector(localFs);
      final signal = await detector.scan(workspace.path);
      final state = await _store.loadState();
      final stored = ChangeSignal(
        maxMtimeMillis: state.highWaterMtimeMs,
        fileCount: state.highWaterFileCount,
      );
      if (!isForced && !signal.differsFrom(stored)) {
        await _store.saveState(
          BackupStateRecord(
            lastRunAt: DateTime.now(),
            lastResult: BackupOutcome.noChanges.name,
            highWaterMtimeMs: state.highWaterMtimeMs,
            highWaterFileCount: state.highWaterFileCount,
            lastSnapshotName: state.lastSnapshotName,
          ),
        );
        return _finish(const BackupResult(BackupOutcome.noChanges));
      }

      final repository = SnapshotRepository(localFs);
      final fileName = SnapshotRepository.fileNameFor(
        kind: trigger == BackupTrigger.preRestore
            ? SnapshotKind.preRestore
            : SnapshotKind.backup,
        appVersion: ApplicationInfo.applicationVersion.isEmpty
            ? 'unknown'
            : ApplicationInfo.applicationVersion,
        timestamp: DateTime.now(),
      );

      final result = await createSnapshot(
        SnapshotRequest(
          sourceDirPath: workspace.path,
          snapshotsDirPath: repository.snapshotsDir(destination.path).path,
          fileName: fileName,
          appVersion: ApplicationInfo.applicationVersion,
          trigger: trigger,
        ),
      );
      Log.info('[Backup] snapshot created: ${result.zipPath} '
          '(${result.fileCount} files, ${result.totalBytes} bytes, '
          'skipped ${result.skippedFiles.length}, trigger ${trigger.name})');

      // High-water mark is persisted only after the rename succeeded.
      await _store.saveState(
        BackupStateRecord(
          lastRunAt: DateTime.now(),
          lastResult: BackupOutcome.snapshotCreated.name,
          highWaterMtimeMs: signal.maxMtimeMillis,
          highWaterFileCount: signal.fileCount,
          lastSnapshotName: fileName,
        ),
      );

      try {
        await const RetentionPruner().prune(repository, destination.path);
      } catch (e) {
        Log.error('[Backup] retention pruning failed: $e');
      }

      return _finish(
        BackupResult(BackupOutcome.snapshotCreated, snapshotName: fileName),
      );
    } catch (e, stackTrace) {
      Log.error('[Backup] run failed: $e\n$stackTrace');
      return _finish(
        BackupResult(BackupOutcome.failed, error: e.toString()),
      );
    }
  }

  Future<io.Directory?> _resolveWorkspace() async {
    try {
      final root = await getIt<ApplicationDataStorage>().getPath();
      String? baseUrl;
      try {
        baseUrl = getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url;
      } catch (_) {
        baseUrl = null; // Local-only mode has no cloud env registered.
      }
      final resolver = WorkspacePathResolver(
        localFs,
        dataRootPath: root,
        cloudBaseUrl: baseUrl,
      );
      final dir = await resolver.resolve();
      return dir == null ? null : io.Directory(dir.path);
    } catch (e) {
      Log.error('[Backup] workspace resolution failed: $e');
      return null;
    }
  }

  Future<DetectedDestination?> _resolveDestination(
    BackupSettings settings,
  ) async {
    final manual = settings.destinationPath;
    if (manual != null && manual.isNotEmpty) {
      return DetectedDestination(
        path: manual,
        source: BackupDestinationSource.manual,
      );
    }
    final home = io.Platform.environment['HOME'];
    if (home == null) {
      return null;
    }
    return DriveMountDetector(localFs, homePath: home).detect();
  }

  Future<void> _refreshDestinationStatus() async {
    final settings = await _store.loadSettings();
    final destination = await _resolveDestination(settings);
    final state = await _store.loadState();
    status.value = BackupStatus(
      lastRunAt: state.lastRunAt,
      lastOutcome: state.lastResult == null
          ? null
          : BackupOutcome.values.asNameMap()[state.lastResult],
      lastSnapshotName: state.lastSnapshotName,
      destination: destination?.path,
      destinationSource: destination?.source,
    );
  }

  void _publish({required bool running}) {
    status.value = BackupStatus(
      lastRunAt: status.value.lastRunAt,
      lastOutcome: status.value.lastOutcome,
      lastSnapshotName: status.value.lastSnapshotName,
      destination: status.value.destination,
      destinationSource: status.value.destinationSource,
      running: running,
    );
  }

  BackupResult _finish(BackupResult result) {
    unawaited(_refreshDestinationStatus());
    return result;
  }
}
