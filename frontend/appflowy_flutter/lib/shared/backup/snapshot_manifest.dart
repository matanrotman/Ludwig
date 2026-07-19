import 'dart:convert';

/// What triggered a snapshot. Recorded in the manifest so a restore (or a
/// human reading RESTORE.md) can tell how a given snapshot came to exist.
enum BackupTrigger {
  periodic,
  quit,
  manual,
  catchUp,
  preRestore;

  static BackupTrigger fromName(String? name) =>
      BackupTrigger.values.asNameMap()[name] ?? BackupTrigger.manual;
}

/// The `manifest.json` written at the root of every snapshot zip.
///
/// `formatVersion` gates restore: a restore refuses formats it doesn't know.
/// `sourceFolderName` preserves the workspace folder's exact name (e.g.
/// `data_dev_beta.appflowy.cloud`) so a restore on a fresh machine can
/// reconstruct the right target even when the local config differs.
class SnapshotManifest {
  const SnapshotManifest({
    required this.formatVersion,
    required this.appVersion,
    required this.sourceFolderName,
    required this.createdAt,
    required this.trigger,
    required this.fileCount,
    required this.totalBytes,
    this.platform = 'macos',
    this.skippedFiles = const [],
    this.exclusionRules = const [],
    this.excludedFileCount = 0,
  });

  static const int currentFormatVersion = 1;

  final int formatVersion;
  final String appVersion;
  final String sourceFolderName;
  final DateTime createdAt;
  final BackupTrigger trigger;
  final int fileCount;
  final int totalBytes;
  final String platform;

  /// Relative paths that could not be read while zipping (a live database may
  /// drop a lock file mid-walk). Recorded rather than failing the snapshot.
  final List<String> skippedFiles;

  /// Which [SnapshotExclusions] rules were active — e.g. `['logs',
  /// 'searchIndexes']`. Present so a human reading manifest.json can tell that
  /// those files are absent BY DESIGN, not lost. Distinct from [skippedFiles],
  /// which means "wanted but unreadable".
  final List<String> exclusionRules;

  /// How many files those rules left out.
  final int excludedFileCount;

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'appVersion': appVersion,
        'sourceFolderName': sourceFolderName,
        'createdAt': createdAt.toIso8601String(),
        'trigger': trigger.name,
        'fileCount': fileCount,
        'totalBytes': totalBytes,
        'platform': platform,
        'skippedFiles': skippedFiles,
        'exclusionRules': exclusionRules,
        'excludedFileCount': excludedFileCount,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static SnapshotManifest? fromJsonString(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      return SnapshotManifest(
        formatVersion: json['formatVersion'] as int,
        appVersion: json['appVersion'] as String,
        sourceFolderName: json['sourceFolderName'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        trigger: BackupTrigger.fromName(json['trigger'] as String?),
        fileCount: json['fileCount'] as int,
        totalBytes: json['totalBytes'] as int,
        platform: json['platform'] as String? ?? 'macos',
        skippedFiles: (json['skippedFiles'] as List<dynamic>? ?? [])
            .cast<String>()
            .toList(),
        // Additive since 2026-07-19; absent in older snapshots, which were
        // taken with no exclusions at all. formatVersion stays 1 — an old
        // build reading a new manifest simply ignores these keys.
        exclusionRules: (json['exclusionRules'] as List<dynamic>? ?? [])
            .cast<String>()
            .toList(),
        excludedFileCount: json['excludedFileCount'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
