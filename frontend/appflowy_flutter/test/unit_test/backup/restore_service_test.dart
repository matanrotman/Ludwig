import 'package:appflowy/shared/backup/backup_service.dart';
import 'package:appflowy/shared/backup/restore_service.dart';
import 'package:appflowy/shared/backup/snapshot_manifest.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

/// The restore state machine, exercised on a MemoryFileSystem with every
/// effect injected. The invariant under test throughout: at every failure
/// point the live folder is either byte-identical to before or fully
/// restored — never in between.
void main() {
  const livePath = '/data/data_dev_test.server';
  const zipPath = '/drive/AppFlowy Backups/snapshots/snap.zip';
  final fixedNow = DateTime(2026, 7, 16, 12, 30, 45);
  const ts = '20260716-123045';

  late MemoryFileSystem fs;
  late List<String> calls;

  setUp(() {
    fs = MemoryFileSystem.test();
    calls = [];
    fs.directory(livePath).createSync(recursive: true);
    fs.file('$livePath/612287/collab_db/000004.log')
      ..createSync(recursive: true)
      ..writeAsStringSync('LIVE typed content');
    fs.file('$livePath/flowy-database.db')
      ..createSync(recursive: true)
      ..writeAsStringSync('LIVE sqlite');
    fs.directory('/drive/AppFlowy Backups/snapshots').createSync(
          recursive: true,
        );
    fs.file(zipPath).writeAsStringSync('fake zip bytes');
  });

  /// rel-path → contents for every file under [root], for byte-identical
  /// comparisons.
  Map<String, String> contentsOf(String root) {
    final result = <String, String>{};
    final dir = fs.directory(root);
    if (!dir.existsSync()) {
      return result;
    }
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        result[fs.path.relative(entity.path, from: root)] =
            entity.readAsStringSync();
      }
    }
    return result;
  }

  SnapshotManifest manifest({int? formatVersion, String? appVersion}) =>
      SnapshotManifest(
        formatVersion: formatVersion ?? SnapshotManifest.currentFormatVersion,
        appVersion: appVersion ?? '0.11.4',
        sourceFolderName: 'data_dev_test.server',
        createdAt: DateTime(2026, 7, 15),
        trigger: BackupTrigger.periodic,
        fileCount: 2,
        totalBytes: 100,
      );

  /// A fake engine extract: writes a known workspace shape into staging.
  Future<SnapshotManifest?> Function({
    required String zipPath,
    required String stagingDirPath,
  }) fakeExtract({
    SnapshotManifest? Function()? manifestBuilder,
    bool writeCollabDb = true,
    bool writeAnyFile = true,
  }) {
    return ({required String zipPath, required String stagingDirPath}) async {
      calls.add('extract');
      final staging = fs.directory(stagingDirPath);
      staging.createSync(recursive: true);
      if (writeCollabDb) {
        fs.file('$stagingDirPath/612287/collab_db/000004.log')
          ..createSync(recursive: true)
          ..writeAsStringSync('RESTORED typed content');
      }
      if (writeAnyFile) {
        fs.file('$stagingDirPath/flowy-database.db')
          ..createSync(recursive: true)
          ..writeAsStringSync('RESTORED sqlite');
      }
      return (manifestBuilder ?? manifest)();
    };
  }

  RestoreService service({
    Future<SnapshotManifest?> Function({
      required String zipPath,
      required String stagingDirPath,
    })? extract,
    List<BackupResult>? snapshotResults,
    RenameDirFn? renameDir,
    String appVersion = '0.11.4',
  }) {
    final pending = [
      ...?snapshotResults,
    ];
    return RestoreService(
      fileSystem: fs,
      resolveWorkspacePath: () async => livePath,
      pauseBackups: () async => calls.add('pause'),
      resumeBackups: () async => calls.add('resume'),
      takePreRestoreSnapshot: () async {
        calls.add('snapshot');
        if (pending.isNotEmpty) {
          return pending.removeAt(0);
        }
        return const BackupResult(
          BackupOutcome.snapshotCreated,
          snapshotName: 'AppFlowy-prerestore-v0.11.4-20260716-123000.zip',
        );
      },
      extract: extract ?? fakeExtract(),
      currentAppVersion: () => appVersion,
      renameDir: renameDir,
      now: () => fixedNow,
    );
  }

  Future<bool> neverAsked(String _) async {
    fail('confirmNewerAppVersion must not be called for same/older versions');
  }

  group('RestoreService happy path', () {
    test('swaps live folder for the snapshot and parks the original', () async {
      final restorer = service();
      final phases = <RestorePhase>[];
      restorer.progress.addListener(
        () => phases.add(restorer.progress.value.phase),
      );

      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );

      expect(result.ok, isTrue);
      // Live folder now holds exactly the extracted snapshot.
      expect(contentsOf(livePath), {
        '612287/collab_db/000004.log': 'RESTORED typed content',
        'flowy-database.db': 'RESTORED sqlite',
      });
      // The previous live data is parked, complete, at the reported path.
      expect(result.preRestoreDirPath, '$livePath.pre-restore-$ts');
      expect(contentsOf(result.preRestoreDirPath!), {
        '612287/collab_db/000004.log': 'LIVE typed content',
        'flowy-database.db': 'LIVE sqlite',
      });
      // Staging was renamed into place, not left behind.
      expect(
        fs.directory('$livePath.restore-staging-$ts').existsSync(),
        isFalse,
      );
      // Snapshot happens BEFORE pause (a paused service refuses all runs),
      // and resume always runs at the end.
      expect(calls, ['snapshot', 'pause', 'extract', 'resume']);
      // The machine walked every phase in order.
      expect(phases, [
        RestorePhase.confirmed,
        RestorePhase.preRestoreSnapshot,
        RestorePhase.extracting,
        RestorePhase.validating,
        RestorePhase.swapping,
        RestorePhase.awaitingRelaunch,
      ]);
    });

    test('retries once when the snapshot call coalesced into "noChanges"',
        () async {
      final restorer = service(
        snapshotResults: [
          const BackupResult(BackupOutcome.noChanges),
          const BackupResult(BackupOutcome.snapshotCreated),
        ],
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.ok, isTrue);
      expect(calls.where((c) => c == 'snapshot').length, 2);
    });
  });

  group('RestoreService aborts with live data untouched', () {
    late Map<String, String> before;

    setUp(() {
      before = contentsOf(livePath);
    });

    test('when the pre-restore snapshot fails (never even pauses)', () async {
      final restorer = service(
        snapshotResults: [
          const BackupResult(BackupOutcome.failed, error: 'disk full'),
        ],
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.ok, isFalse);
      expect(result.failure, RestoreFailure.preRestoreSnapshotFailed);
      expect(result.message, contains('disk full'));
      expect(contentsOf(livePath), before);
      expect(calls, ['snapshot']); // no pause, no extract, no resume
    });

    test('when the zip is corrupt (extract throws)', () async {
      final restorer = service(
        extract: ({required zipPath, required stagingDirPath}) async {
          calls.add('extract');
          throw const FormatException('bad zip');
        },
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.ok, isFalse);
      expect(result.failure, RestoreFailure.extractFailed);
      expect(contentsOf(livePath), before);
      // No staging or pre-restore artifacts survive the failure.
      final siblings =
          fs.directory('/data').listSync().map((e) => fs.path.basename(e.path));
      expect(siblings, ['data_dev_test.server']);
      expect(calls, ['snapshot', 'pause', 'extract', 'resume']);
    });

    test('when the snapshot has no manifest', () async {
      final restorer = service(
        extract: fakeExtract(manifestBuilder: () => null),
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.failure, RestoreFailure.manifestMissing);
      expect(contentsOf(livePath), before);
      expect(
        fs.directory('$livePath.restore-staging-$ts').existsSync(),
        isFalse,
      );
    });

    test('when the manifest declares a future format version', () async {
      final restorer = service(
        extract:
            fakeExtract(manifestBuilder: () => manifest(formatVersion: 99)),
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.failure, RestoreFailure.unsupportedFormat);
      expect(result.message, contains('v99'));
      expect(contentsOf(livePath), before);
      expect(
        fs.directory('$livePath.restore-staging-$ts').existsSync(),
        isFalse,
      );
    });

    test('when the snapshot has no collab_db anywhere', () async {
      final restorer = service(extract: fakeExtract(writeCollabDb: false));
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.failure, RestoreFailure.missingCollabDb);
      expect(contentsOf(livePath), before);
    });

    test('when the user declines a newer-app-version snapshot', () async {
      String? askedVersion;
      final restorer = service(
        extract:
            fakeExtract(manifestBuilder: () => manifest(appVersion: '9.9.9')),
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: (v) async {
          askedVersion = v;
          return false;
        },
      );
      expect(result.failure, RestoreFailure.declinedNewerVersion);
      expect(askedVersion, '9.9.9');
      expect(contentsOf(livePath), before);
      expect(
        fs.directory('$livePath.restore-staging-$ts').existsSync(),
        isFalse,
      );
    });

    test('but proceeds when the user accepts a newer-app-version snapshot',
        () async {
      final restorer = service(
        extract:
            fakeExtract(manifestBuilder: () => manifest(appVersion: '9.9.9')),
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: (_) async => true,
      );
      expect(result.ok, isTrue);
    });
  });

  group('RestoreService swap rollback', () {
    test('rename #2 failing rolls back; live folder is byte-identical',
        () async {
      final before = contentsOf(livePath);
      var renameCount = 0;
      final restorer = service(
        renameDir: (dir, newPath) async {
          renameCount += 1;
          // #1 = live -> pre-restore (allowed), #2 = staging -> live (fails),
          // #3 = the rollback (allowed).
          if (renameCount == 2) {
            throw const FileSystemException('rename refused');
          }
          await dir.rename(newPath);
        },
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.ok, isFalse);
      expect(result.failure, RestoreFailure.swapFailed);
      expect(renameCount, 3);
      expect(contentsOf(livePath), before);
      // Rollback consumed the pre-restore dir (renamed back); staging is
      // deleted: the parent holds ONLY the live folder again.
      final siblings =
          fs.directory('/data').listSync().map((e) => fs.path.basename(e.path));
      expect(siblings, ['data_dev_test.server']);
      expect(calls.last, 'resume');
    });

    test(
        'rename #2 AND rollback failing deletes nothing and reports where '
        'the data is', () async {
      var renameCount = 0;
      final restorer = service(
        renameDir: (dir, newPath) async {
          renameCount += 1;
          if (renameCount >= 2) {
            throw const FileSystemException('rename refused');
          }
          await dir.rename(newPath);
        },
      );
      final result = await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );
      expect(result.ok, isFalse);
      expect(result.failure, RestoreFailure.rollbackFailed);
      // The data survived, parked under the pre-restore name, and the result
      // says exactly where.
      expect(result.preRestoreDirPath, '$livePath.pre-restore-$ts');
      expect(contentsOf(result.preRestoreDirPath!), {
        '612287/collab_db/000004.log': 'LIVE typed content',
        'flowy-database.db': 'LIVE sqlite',
      });
      expect(result.message, contains('$livePath.pre-restore-$ts'));
      expect(result.message, contains(livePath));
      // NOTHING was deleted in this state — staging still exists too.
      expect(
        fs.directory('$livePath.restore-staging-$ts').existsSync(),
        isTrue,
      );
    });
  });

  group('RestoreService housekeeping', () {
    test('trims pre-restore dirs beyond the newest 2, at restore START',
        () async {
      for (final suffix in [
        '20260701-090000',
        '20260705-090000',
        '20260710-090000',
        '20260712-090000',
      ]) {
        fs.file('$livePath.pre-restore-$suffix/marker.txt')
          ..createSync(recursive: true)
          ..writeAsStringSync(suffix);
      }
      // Even a run that aborts at the snapshot phase has already trimmed.
      final restorer = service(
        snapshotResults: [const BackupResult(BackupOutcome.failed)],
      );
      await restorer.restore(
        zipPath: zipPath,
        confirmNewerAppVersion: neverAsked,
      );

      bool exists(String suffix) =>
          fs.directory('$livePath.pre-restore-$suffix').existsSync();
      expect(exists('20260712-090000'), isTrue);
      expect(exists('20260710-090000'), isTrue);
      expect(exists('20260705-090000'), isFalse);
      expect(exists('20260701-090000'), isFalse);
    });
  });

  group('isVersionNewer', () {
    test('orders plain x.y.z versions', () {
      expect(RestoreService.isVersionNewer('0.12.0', '0.11.4'), isTrue);
      expect(RestoreService.isVersionNewer('1.0.0', '0.11.4'), isTrue);
      expect(RestoreService.isVersionNewer('0.11.4', '0.11.4'), isFalse);
      expect(RestoreService.isVersionNewer('0.11.3', '0.11.4'), isFalse);
      expect(RestoreService.isVersionNewer('0.11.4.1', '0.11.4'), isTrue);
    });

    test('never blocks on unparsable versions', () {
      expect(RestoreService.isVersionNewer('unknown', '0.11.4'), isFalse);
      expect(RestoreService.isVersionNewer('', '0.11.4'), isFalse);
      expect(RestoreService.isVersionNewer('0.11.4-beta', '0.11.4'), isFalse);
      expect(RestoreService.isVersionNewer('0.12.0-beta', '0.11.4'), isTrue);
    });
  });
}
