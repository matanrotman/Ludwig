import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:appflowy/shared/backup/snapshot_exclusions.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Inputs for one snapshot, as plain values so the whole request can cross an
/// isolate boundary (`Isolate.run` — zipping on the UI thread janks, and this
/// runs mid-writing-session and on quit).
class SnapshotRequest {
  const SnapshotRequest({
    required this.sourceDirPath,
    required this.snapshotsDirPath,
    required this.fileName,
    required this.appVersion,
    required this.trigger,
    this.exclusions = const SnapshotExclusions(),
  });

  final String sourceDirPath;
  final String snapshotsDirPath;
  final String fileName;
  final String appVersion;
  final BackupTrigger trigger;

  /// What to leave out. Defaults to the standard policy (logs + derived search
  /// indexes); pass [SnapshotExclusions.none] for a bit-exact folder mirror.
  final SnapshotExclusions exclusions;
}

class SnapshotResult {
  const SnapshotResult({
    required this.zipPath,
    required this.fileCount,
    required this.totalBytes,
    required this.skippedFiles,
  });

  final String zipPath;
  final int fileCount;
  final int totalBytes;
  final List<String> skippedFiles;
}

class SnapshotEngineException implements Exception {
  SnapshotEngineException(this.message);
  final String message;
  @override
  String toString() => 'SnapshotEngineException: $message';
}

/// Creates one snapshot zip:
///   zip root = manifest.json + data/** (exact mirror of the source folder).
/// Written as `.<finalName>.tmp` INSIDE the snapshots dir, flushed, then
/// renamed — a same-directory rename is atomic on APFS and on the Drive
/// mount, so sync clients only ever see finished snapshots.
Future<SnapshotResult> createSnapshot(SnapshotRequest request) =>
    Isolate.run(() => _createSnapshotSync(request));

/// Extracts a snapshot's `data/**` into [stagingDirPath] (created fresh) and
/// returns its manifest. A corrupt zip throws HERE — before anything touches
/// live data. Returns null manifest only if the zip predates manifests.
Future<SnapshotManifest?> extractSnapshot({
  required String zipPath,
  required String stagingDirPath,
}) =>
    Isolate.run(() => _extractSnapshotSync(zipPath, stagingDirPath));

SnapshotResult _createSnapshotSync(SnapshotRequest request) {
  final source = io.Directory(request.sourceDirPath);
  if (!source.existsSync()) {
    throw SnapshotEngineException(
      'source folder does not exist: ${request.sourceDirPath}',
    );
  }

  final archive = Archive();
  final skipped = <String>[];
  var fileCount = 0;
  var totalBytes = 0;
  var excludedCount = 0;

  // No explicit directory entries: the archive package emits them in a form
  // Info-ZIP's `unzip -t` rejects ("invalid compressed data to inflate"),
  // which would break the manual-restore path. Extraction recreates parent
  // folders; a truly EMPTY directory is not preserved, which is fine — the
  // app recreates its cache/db folders on launch.
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    final zipPath = p.join('data', relative);
    if (entity is io.File) {
      // Deliberate omissions (logs, derived indexes) — recorded as a count in
      // the manifest, NOT in skippedFiles, which means "wanted but unreadable".
      if (request.exclusions.shouldExclude(relative)) {
        excludedCount += 1;
        continue;
      }
      try {
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(zipPath, bytes.length, bytes));
        fileCount += 1;
        totalBytes += bytes.length;
      } catch (_) {
        // A live database may drop a lock/tmp file between listing and read.
        // Record it in the manifest instead of failing the whole snapshot.
        skipped.add(relative);
      }
    }
  }

  if (fileCount == 0) {
    throw SnapshotEngineException(
      'nothing to back up in ${request.sourceDirPath}',
    );
  }

  final manifest = SnapshotManifest(
    formatVersion: SnapshotManifest.currentFormatVersion,
    appVersion: request.appVersion,
    sourceFolderName: p.basename(source.path),
    createdAt: DateTime.now(),
    trigger: request.trigger,
    fileCount: fileCount,
    totalBytes: totalBytes,
    skippedFiles: skipped,
    exclusionRules: request.exclusions.activeRuleNames,
    excludedFileCount: excludedCount,
  );
  final manifestBytes = utf8.encode(manifest.toJsonString());
  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );

  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    throw SnapshotEngineException('zip encoding produced no bytes');
  }

  final snapshotsDir = io.Directory(request.snapshotsDirPath);
  snapshotsDir.createSync(recursive: true);

  final tempPath = p.join(
    request.snapshotsDirPath,
    SnapshotRepository.tempNameFor(request.fileName),
  );
  final finalPath = p.join(request.snapshotsDirPath, request.fileName);

  final tempFile = io.File(tempPath);
  try {
    tempFile.writeAsBytesSync(zipBytes, flush: true);
    tempFile.renameSync(finalPath);
  } catch (e) {
    // Never leave a half-written temp behind.
    try {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    } catch (_) {}
    throw SnapshotEngineException('failed to write snapshot: $e');
  }

  return SnapshotResult(
    zipPath: finalPath,
    fileCount: fileCount,
    totalBytes: totalBytes,
    skippedFiles: skipped,
  );
}

SnapshotManifest? _extractSnapshotSync(String zipPath, String stagingDirPath) {
  final bytes = io.File(zipPath).readAsBytesSync();
  // Throws on a corrupt zip — the built-in integrity check of the restore.
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);

  final staging = io.Directory(stagingDirPath);
  if (staging.existsSync()) {
    staging.deleteSync(recursive: true);
  }
  staging.createSync(recursive: true);

  SnapshotManifest? manifest;
  var extractedFiles = 0;

  for (final file in archive) {
    if (file.name == 'manifest.json') {
      manifest = SnapshotManifest.fromJsonString(
        utf8.decode(file.content as List<int>, allowMalformed: true),
      );
      continue;
    }
    if (!p.isWithin('data', p.normalize(file.name)) &&
        p.normalize(file.name) != 'data') {
      continue; // Ignore anything outside data/ (and reject path traversal).
    }
    final relative = p.relative(p.normalize(file.name), from: 'data');
    final target = p.join(stagingDirPath, relative);
    if (!p.isWithin(stagingDirPath, target)) {
      continue; // Zip-slip guard.
    }
    if (file.isFile) {
      io.File(target)
        ..createSync(recursive: true)
        ..writeAsBytesSync(file.content as List<int>);
      extractedFiles += 1;
    } else {
      io.Directory(target).createSync(recursive: true);
    }
  }

  if (extractedFiles == 0) {
    throw SnapshotEngineException('snapshot contained no data files');
  }

  return manifest;
}
