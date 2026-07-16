import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/backup/backup_settings.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeyValueStorage implements KeyValueStorage {
  final Map<String, String> _map = {};

  @override
  Future<void> set(String key, String value) async => _map[key] = value;

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = _map[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => _map.remove(key);

  @override
  Future<void> clear() async => _map.clear();
}

void main() {
  group('BackupSettings / BackupStateRecord json', () {
    test('settings round-trip', () {
      const settings = BackupSettings(
        enabled: false,
        destinationPath: '/somewhere',
        intervalMinutes: 60,
      );
      final restored = BackupSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.enabled, isFalse);
      expect(restored.destinationPath, '/somewhere');
      expect(restored.intervalMinutes, 60);
    });

    test('state round-trip', () {
      final state = BackupStateRecord(
        lastRunAt: DateTime(2026, 7, 16, 12),
        lastResult: 'snapshotCreated',
        highWaterMtimeMs: 12345,
        highWaterFileCount: 67,
        lastSnapshotName: 'AppFlowy-backup-v1-20260716-120000.zip',
      );
      final restored = BackupStateRecord.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(restored.lastRunAt, DateTime(2026, 7, 16, 12));
      expect(restored.highWaterMtimeMs, 12345);
      expect(restored.highWaterFileCount, 67);
    });

    test('store defaults when nothing persisted or json corrupt', () async {
      final storage = _MemoryKeyValueStorage();
      final store = BackupSettingsStore(storage);
      final fresh = await store.loadSettings();
      expect(fresh.enabled, isTrue);
      expect(fresh.intervalMinutes, 30);
      expect(fresh.destinationPath, isNull);

      await storage.set('backupSettings', 'not json at all {');
      final corrupt = await store.loadSettings();
      expect(corrupt.enabled, isTrue);
    });
  });

  group('validateDestination', () {
    test('rejects a missing folder', () async {
      final fs = MemoryFileSystem.test();
      expect(
        await validateDestination(
          fs,
          destinationPath: '/absent',
          workspacePath: null,
        ),
        DestinationProblem.doesNotExist,
      );
    });

    test('rejects a destination inside the workspace (recursive zip)',
        () async {
      final fs = MemoryFileSystem.test();
      fs
          .directory('/data/data_dev_beta.appflowy.cloud/backups')
          .createSync(recursive: true);
      expect(
        await validateDestination(
          fs,
          destinationPath: '/data/data_dev_beta.appflowy.cloud/backups',
          workspacePath: '/data/data_dev_beta.appflowy.cloud',
        ),
        DestinationProblem.insideWorkspace,
      );
    });

    test('rejects a destination inside the parent data dir', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/data/other').createSync(recursive: true);
      expect(
        await validateDestination(
          fs,
          destinationPath: '/data/other',
          workspacePath: '/data/data_dev_beta.appflowy.cloud',
        ),
        DestinationProblem.insideWorkspace,
      );
    });

    test('accepts a writable outside folder', () async {
      final fs = MemoryFileSystem.test();
      fs.directory('/drive/My Drive/AppFlowy').createSync(recursive: true);
      expect(
        await validateDestination(
          fs,
          destinationPath: '/drive/My Drive/AppFlowy',
          workspacePath: '/data/data_dev_beta.appflowy.cloud',
        ),
        isNull,
      );
    });
  });
}
