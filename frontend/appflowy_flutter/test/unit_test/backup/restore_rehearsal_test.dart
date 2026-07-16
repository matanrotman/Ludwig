import 'dart:io' as io;

import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/restore_service.dart';
import 'package:appflowy/shared/backup/snapshot_engine.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:appflowy/shared/backup/workspace_path_resolver.dart';
import 'package:file/local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Stage 4's gate rehearsal (specs/google-drive-backup.md): a full restore
/// round-trip on a REAL filesystem against a SCRATCH data tree — real zip
/// engine (isolates), real APFS renames, the real RestoreService — with only
/// the app singletons replaced (the pre-restore snapshot calls the real
/// engine directly instead of going through BackupService/getIt).
///
/// Never touches any live data folder (2026-07-13 incident rule): everything
/// lives under a systemTemp sandbox.
void main() {
  const localFs = LocalFileSystem();
  late io.Directory sandbox;

  setUp(() async {
    sandbox = await io.Directory.systemTemp.createTemp('restore_rehearsal');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<void> writeTree(String root, Map<String, String> files) async {
    for (final entry in files.entries) {
      final file = io.File(p.join(root, entry.key));
      await file.create(recursive: true);
      await file.writeAsString(entry.value);
    }
  }

  Future<Map<String, String>> readTree(String root) async {
    final result = <String, String>{};
    final dir = io.Directory(root);
    if (!await dir.exists()) {
      return result;
    }
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is io.File) {
        result[p.relative(entity.path, from: root)] =
            await entity.readAsString();
      }
    }
    return result;
  }

  test(
      'rehearsal: snapshot yesterday -> keep typing -> restore the snapshot '
      '-> relaunch resolution finds the restored folder', () async {
    // A scratch "data root" shaped like the real one: parent dir + suffixed
    // workspace folder, exactly what WorkspacePathResolver expects.
    final dataRoot = p.join(sandbox.path, 'appflowy', 'data_dev');
    final workspacePath = '${dataRoot}_scratch.server';
    const yesterdaysWork = {
      '612287/collab_db/000004.log': 'the novel, as of yesterday',
      '612287/collab_db/CURRENT': 'MANIFEST-000001',
      'flowy-database.db': 'sqlite as of yesterday',
    };
    await writeTree(workspacePath, yesterdaysWork);

    final destination = p.join(sandbox.path, 'drive', 'AppFlowy Backups');
    final snapshotsDir = p.join(destination, 'snapshots');

    // "Yesterday's" snapshot, made by the real engine.
    final yesterdayZip = await createSnapshot(
      SnapshotRequest(
        sourceDirPath: workspacePath,
        snapshotsDirPath: snapshotsDir,
        fileName: SnapshotRepository.fileNameFor(
          kind: SnapshotKind.backup,
          appVersion: '0.11.4',
          timestamp: DateTime(2026, 7, 15, 21),
        ),
        appVersion: '0.11.4',
        trigger: BackupTrigger.periodic,
      ),
    );

    // "Today": more typing happens after that snapshot.
    await writeTree(workspacePath, {
      '612287/collab_db/000004.log': 'the novel, overwritten by a bad day',
      'new-note.md': 'today-only file that the restore must move aside',
    });
    final todaysContent = await readTree(workspacePath);

    // The real service, with the pre-restore snapshot wired straight to the
    // real engine (BackupService needs getIt; the zip mechanics are what
    // this rehearsal must prove).
    var paused = false;
    final service = RestoreService(
      fileSystem: localFs,
      resolveWorkspacePath: () async => workspacePath,
      pauseBackups: () async => paused = true,
      resumeBackups: () async => paused = false,
      takePreRestoreSnapshot: () async {
        final name = SnapshotRepository.fileNameFor(
          kind: SnapshotKind.preRestore,
          appVersion: '0.11.4',
          timestamp: DateTime(2026, 7, 16, 12),
        );
        await createSnapshot(
          SnapshotRequest(
            sourceDirPath: workspacePath,
            snapshotsDirPath: snapshotsDir,
            fileName: name,
            appVersion: '0.11.4',
            trigger: BackupTrigger.preRestore,
          ),
        );
        return BackupResult(
          BackupOutcome.snapshotCreated,
          snapshotName: name,
        );
      },
      extract: extractSnapshot,
      currentAppVersion: () => '0.11.4',
    );

    final result = await service.restore(
      zipPath: yesterdayZip.zipPath,
      confirmNewerAppVersion: (_) async =>
          fail('same-version snapshot must not ask'),
    );

    // The restore succeeded and the machine ended awaiting relaunch.
    expect(result.ok, isTrue, reason: result.message ?? '');
    expect(service.progress.value.phase, RestorePhase.awaitingRelaunch);
    expect(paused, isFalse, reason: 'backups must be resumed afterwards');

    // The live folder is byte-identical to yesterday's snapshot again.
    expect(await readTree(workspacePath), yesterdaysWork);

    // Safety net #1: today's state was zipped before anything changed, and
    // the zip is genuinely restorable (extract + compare).
    final preRestoreZips = io.Directory(snapshotsDir)
        .listSync()
        .whereType<io.File>()
        .where((f) => p.basename(f.path).startsWith('AppFlowy-prerestore-'))
        .toList();
    expect(preRestoreZips, hasLength(1));
    final checkDir = p.join(sandbox.path, 'prerestore-check');
    final manifest = await extractSnapshot(
      zipPath: preRestoreZips.single.path,
      stagingDirPath: checkDir,
    );
    expect(manifest, isNotNull);
    expect(manifest!.formatVersion, SnapshotManifest.currentFormatVersion);
    expect(await readTree(checkDir), todaysContent);

    // Safety net #2: today's folder is parked on disk, complete, untouched.
    expect(result.preRestoreDirPath, isNotNull);
    expect(await readTree(result.preRestoreDirPath!), todaysContent);

    // No staging leftovers anywhere.
    final parentNames = io.Directory(p.dirname(workspacePath))
        .listSync()
        .map((e) => p.basename(e.path));
    expect(
      parentNames.where((n) => n.contains('.restore-staging-')),
      isEmpty,
    );

    // "Including the relaunch": startup re-resolves the workspace via
    // WorkspacePathResolver (same call backup_task/startup wiring uses).
    // Against the scratch tree it must pick the restored folder — and never
    // the parked pre-restore one.
    final resolved = await WorkspacePathResolver(
      localFs,
      dataRootPath: dataRoot,
      cloudBaseUrl: 'https://scratch.server',
    ).resolve();
    expect(resolved?.path, workspacePath);
  });

  test('rehearsal: a truncated zip aborts with the scratch tree untouched',
      () async {
    final dataRoot = p.join(sandbox.path, 'appflowy', 'data_dev');
    final workspacePath = '${dataRoot}_scratch.server';
    const content = {
      '612287/collab_db/000004.log': 'typed content',
    };
    await writeTree(workspacePath, content);

    final snapshotsDir = p.join(sandbox.path, 'drive', 'snapshots');
    final zip = await createSnapshot(
      SnapshotRequest(
        sourceDirPath: workspacePath,
        snapshotsDirPath: snapshotsDir,
        fileName: SnapshotRepository.fileNameFor(
          kind: SnapshotKind.backup,
          appVersion: '0.11.4',
          timestamp: DateTime(2026, 7, 15, 21),
        ),
        appVersion: '0.11.4',
        trigger: BackupTrigger.periodic,
      ),
    );
    // Truncate the zip to simulate a half-synced/damaged Drive file.
    final bytes = await io.File(zip.zipPath).readAsBytes();
    await io.File(zip.zipPath)
        .writeAsBytes(bytes.sublist(0, bytes.length ~/ 2), flush: true);

    final service = RestoreService(
      fileSystem: localFs,
      resolveWorkspacePath: () async => workspacePath,
      pauseBackups: () async {},
      resumeBackups: () async {},
      takePreRestoreSnapshot: () async => const BackupResult(
        BackupOutcome.snapshotCreated,
        snapshotName: 'fake',
      ),
      extract: extractSnapshot,
      currentAppVersion: () => '0.11.4',
    );

    final result = await service.restore(
      zipPath: zip.zipPath,
      confirmNewerAppVersion: (_) async => true,
    );

    expect(result.ok, isFalse);
    expect(result.failure, RestoreFailure.extractFailed);
    expect(await readTree(workspacePath), content);
    final parentNames = io.Directory(p.dirname(workspacePath))
        .listSync()
        .map((e) => p.basename(e.path));
    expect(parentNames.toList(), [p.basename(workspacePath)]);
  });
}
