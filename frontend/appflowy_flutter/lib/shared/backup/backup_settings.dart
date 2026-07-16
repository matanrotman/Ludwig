import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:file/file.dart';

/// User-facing backup preferences. `destinationPath == null` means
/// "auto-detect the Google Drive mount".
class BackupSettings {
  const BackupSettings({
    this.enabled = true,
    this.destinationPath,
    this.intervalMinutes = 30,
  });

  static const allowedIntervals = [15, 30, 60];

  final bool enabled;
  final String? destinationPath;
  final int intervalMinutes;

  BackupSettings copyWith({
    bool? enabled,
    String? destinationPath,
    bool clearDestination = false,
    int? intervalMinutes,
  }) =>
      BackupSettings(
        enabled: enabled ?? this.enabled,
        destinationPath:
            clearDestination ? null : (destinationPath ?? this.destinationPath),
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'destinationPath': destinationPath,
        'intervalMinutes': intervalMinutes,
      };

  static BackupSettings fromJson(Map<String, dynamic> json) => BackupSettings(
        enabled: json['enabled'] as bool? ?? true,
        destinationPath: json['destinationPath'] as String?,
        intervalMinutes: json['intervalMinutes'] as int? ?? 30,
      );
}

/// Internal bookkeeping between runs (never shown raw to the user).
/// The high-water mark is persisted only AFTER a snapshot's atomic rename
/// succeeds, so a failed run can never mask a change.
class BackupStateRecord {
  const BackupStateRecord({
    this.lastRunAt,
    this.lastResult,
    this.highWaterMtimeMs = 0,
    this.highWaterFileCount = 0,
    this.lastSnapshotName,
  });

  final DateTime? lastRunAt;
  final String? lastResult;
  final int highWaterMtimeMs;
  final int highWaterFileCount;
  final String? lastSnapshotName;

  Map<String, dynamic> toJson() => {
        'lastRunAt': lastRunAt?.toIso8601String(),
        'lastResult': lastResult,
        'highWaterMtimeMs': highWaterMtimeMs,
        'highWaterFileCount': highWaterFileCount,
        'lastSnapshotName': lastSnapshotName,
      };

  static BackupStateRecord fromJson(Map<String, dynamic> json) =>
      BackupStateRecord(
        lastRunAt: json['lastRunAt'] != null
            ? DateTime.tryParse(json['lastRunAt'] as String)
            : null,
        lastResult: json['lastResult'] as String?,
        highWaterMtimeMs: json['highWaterMtimeMs'] as int? ?? 0,
        highWaterFileCount: json['highWaterFileCount'] as int? ?? 0,
        lastSnapshotName: json['lastSnapshotName'] as String?,
      );
}

/// KeyValueStorage-backed persistence for the two records above.
class BackupSettingsStore {
  BackupSettingsStore(this._storage);

  final KeyValueStorage _storage;

  Future<BackupSettings> loadSettings() async {
    final settings = await _storage.getWithFormat<BackupSettings?>(
      KVKeys.backupSettings,
      (value) {
        try {
          return BackupSettings.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          );
        } catch (_) {
          return null;
        }
      },
    );
    return settings ?? const BackupSettings();
  }

  Future<void> saveSettings(BackupSettings settings) =>
      _storage.set(KVKeys.backupSettings, jsonEncode(settings.toJson()));

  Future<BackupStateRecord> loadState() async {
    final state = await _storage.getWithFormat<BackupStateRecord?>(
      KVKeys.backupState,
      (value) {
        try {
          return BackupStateRecord.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          );
        } catch (_) {
          return null;
        }
      },
    );
    return state ?? const BackupStateRecord();
  }

  Future<void> saveState(BackupStateRecord state) =>
      _storage.set(KVKeys.backupState, jsonEncode(state.toJson()));
}

/// Why a destination was rejected — surfaced verbatim in settings.
enum DestinationProblem {
  doesNotExist,
  notWritable,
  insideWorkspace,
}

/// Validates a backup destination:
/// - must exist,
/// - must accept a probe write (catches read-only mounts and vanished
///   Drive folders),
/// - must not live inside the workspace/data folder (a snapshot that
///   contains the growing snapshot folder would recursively zip itself).
Future<DestinationProblem?> validateDestination(
  FileSystem fileSystem, {
  required String destinationPath,
  required String? workspacePath,
}) async {
  final dest = fileSystem.directory(destinationPath);
  if (!await dest.exists()) {
    return DestinationProblem.doesNotExist;
  }

  if (workspacePath != null) {
    final destCanonical = fileSystem.path.canonicalize(destinationPath);
    final dataDirCanonical =
        fileSystem.path.canonicalize(fileSystem.path.dirname(workspacePath));
    final workspaceCanonical = fileSystem.path.canonicalize(workspacePath);
    if (fileSystem.path.isWithin(workspaceCanonical, destCanonical) ||
        destCanonical == workspaceCanonical ||
        fileSystem.path.isWithin(dataDirCanonical, destCanonical) ||
        destCanonical == dataDirCanonical) {
      return DestinationProblem.insideWorkspace;
    }
  }

  try {
    final probe = dest.childFile('.appflowy-backup-probe');
    await probe.writeAsString('probe', flush: true);
    await probe.delete();
  } catch (_) {
    return DestinationProblem.notWritable;
  }

  return null;
}
