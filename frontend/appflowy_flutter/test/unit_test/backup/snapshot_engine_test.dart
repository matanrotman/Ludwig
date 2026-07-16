import 'dart:io' as io;

import 'package:appflowy/shared/backup/snapshot_engine.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:appflowy/shared/backup/snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Real temp dirs, not MemoryFileSystem: the engine runs in Isolate.run and
// exercises the actual atomic-rename semantics.
void main() {
  late io.Directory sandbox;

  setUp(() async {
    sandbox = await io.Directory.systemTemp.createTemp('backup_engine_test');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<io.Directory> makeWorkspace() async {
    final ws = io.Directory(p.join(sandbox.path, 'data_dev_test.server'));
    final collab = io.Directory(p.join(ws.path, '612287', 'collab_db'));
    await collab.create(recursive: true);
    await io.File(p.join(collab.path, '000004.log'))
        .writeAsString('typed content');
    await io.File(p.join(collab.path, 'CURRENT')).writeAsString('MANIFEST');
    await io.File(p.join(ws.path, 'flowy-database.db')).writeAsString('sqlite');
    await io.File(p.join(ws.path, 'log.2026-07-16')).writeAsString('applog');
    return ws;
  }

  SnapshotRequest request(io.Directory ws, {BackupTrigger? trigger}) =>
      SnapshotRequest(
        sourceDirPath: ws.path,
        snapshotsDirPath: p.join(sandbox.path, 'dest', 'snapshots'),
        fileName: SnapshotRepository.fileNameFor(
          kind: SnapshotKind.backup,
          appVersion: '0.11.4',
          timestamp: DateTime(2026, 7, 16, 12),
        ),
        appVersion: '0.11.4',
        trigger: trigger ?? BackupTrigger.manual,
      );

  test('snapshot -> no temp orphan -> extract -> deep compare', () async {
    final ws = await makeWorkspace();
    final result = await createSnapshot(request(ws));

    // Zip landed under its final name; no `.tmp` left behind.
    expect(await io.File(result.zipPath).exists(), isTrue);
    final leftovers = io.Directory(p.dirname(result.zipPath))
        .listSync()
        .where((e) => e.path.endsWith('.tmp'));
    expect(leftovers, isEmpty);
    // Log files are INCLUDED in the zip (signal-only exclusion elsewhere).
    expect(result.fileCount, 4);
    expect(result.skippedFiles, isEmpty);

    // Extract and compare every file byte-for-byte.
    final staging = p.join(sandbox.path, 'staging');
    final manifest = await extractSnapshot(
      zipPath: result.zipPath,
      stagingDirPath: staging,
    );
    expect(manifest, isNotNull);
    expect(manifest!.formatVersion, SnapshotManifest.currentFormatVersion);
    expect(manifest.sourceFolderName, 'data_dev_test.server');
    expect(manifest.fileCount, 4);

    for (final entity in ws.listSync(recursive: true)) {
      if (entity is! io.File) continue;
      final rel = p.relative(entity.path, from: ws.path);
      final restored = io.File(p.join(staging, rel));
      expect(await restored.exists(), isTrue, reason: '$rel missing');
      expect(
        await restored.readAsBytes(),
        await entity.readAsBytes(),
        reason: '$rel differs',
      );
    }
  });

  test('zip passes the system unzip -t (manual-restore path)', () async {
    // Regression: the archive package's explicit directory entries make
    // Info-ZIP report "invalid compressed data to inflate" (found live,
    // 2026-07-16). RESTORE.md tells a human to use standard tools, so the
    // zips must satisfy them.
    final ws = await makeWorkspace();
    final result = await createSnapshot(request(ws));
    final probe = await io.Process.run('unzip', ['-t', result.zipPath]);
    expect(
      probe.exitCode,
      0,
      reason: 'unzip -t rejected the snapshot:\n${probe.stdout}',
    );
  });

  test('corrupt zip fails cleanly, staging is not half-populated', () async {
    final zipPath = p.join(sandbox.path, 'corrupt.zip');
    await io.File(zipPath).writeAsString('this is not a zip');
    final staging = p.join(sandbox.path, 'staging');

    await expectLater(
      extractSnapshot(zipPath: zipPath, stagingDirPath: staging),
      throwsA(anything),
    );
  });

  test('empty source refuses to snapshot', () async {
    final empty = io.Directory(p.join(sandbox.path, 'empty'));
    await empty.create();
    await expectLater(
      createSnapshot(
        SnapshotRequest(
          sourceDirPath: empty.path,
          snapshotsDirPath: p.join(sandbox.path, 'dest', 'snapshots'),
          fileName: 'AppFlowy-backup-v1-20260716-120000.zip',
          appVersion: '1',
          trigger: BackupTrigger.manual,
        ),
      ),
      throwsA(isA<SnapshotEngineException>()),
    );
  });

  test('missing source refuses to snapshot', () async {
    await expectLater(
      createSnapshot(
        SnapshotRequest(
          sourceDirPath: p.join(sandbox.path, 'absent'),
          snapshotsDirPath: p.join(sandbox.path, 'dest', 'snapshots'),
          fileName: 'AppFlowy-backup-v1-20260716-120000.zip',
          appVersion: '1',
          trigger: BackupTrigger.quit,
        ),
      ),
      throwsA(isA<SnapshotEngineException>()),
    );
  });
}
